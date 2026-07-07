// 这个文件是干什么的：提供全局唯一 Dio 实例（配好 baseUrl / 超时 / 请求头 + 鉴权拦截器）。
// 它对应产品里的什么功能：所有走后端的接口调用都用这个 client；登录后自动带身份、令牌过期自动续期。
// 如果它出错了：全站真数据接口失效，或登录后写操作仍报「需登录」。
//
// 说明：不碰 dart:io（web 编译不支持）。浏览器对 127.0.0.1 默认不走系统代理，
// web 端无需处理代理；移动/桌面端若被系统代理干扰，再加平台条件导入的 adapter。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/token_store.dart';
import '../config/app_config.dart';

/// 全局 Dio。带鉴权拦截器：
///   - 请求前：已登录则自动加 `Authorization: Bearer <access>`。
///   - 收到 401：用 refresh_token 静默换一对新令牌并重试原请求一次；
///     换令牌也失败 → 清登录态，让 401 原样冒泡（UI 弹登录）。
final dioProvider = Provider<Dio>((ref) {
  final store = ref.watch(tokenStoreProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final token = store.accessToken;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (e, handler) async {
      final path = e.requestOptions.path;
      final is401 = e.response?.statusCode == 401;
      final alreadyRetried = e.requestOptions.extra['__retried'] == true;
      final isAuthCall = path.contains('/auth/'); // 登录/刷新自身 401 不再套刷新
      if (is401 &&
          !alreadyRetried &&
          !isAuthCall &&
          (store.refreshToken?.isNotEmpty ?? false)) {
        try {
          // 用裸 Dio 换令牌，避免走本拦截器造成递归。
          final bare = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
          final r = await bare.post<dynamic>(
            '/auth/refresh',
            data: {'refresh_token': store.refreshToken},
          );
          final data = r.data;
          if (data is Map &&
              data['access_token'] != null &&
              data['refresh_token'] != null) {
            store.set(
              access: data['access_token'].toString(),
              refresh: data['refresh_token'].toString(),
            );
            // 重试原请求（带新令牌 + 标记，防二次刷新死循环）。
            final opts = e.requestOptions;
            opts.headers['Authorization'] = 'Bearer ${store.accessToken}';
            opts.extra['__retried'] = true;
            final clone = await bare.fetch<dynamic>(opts);
            return handler.resolve(clone);
          }
        } catch (_) {
          // 刷新失败：令牌已废，清掉登录态，让原 401 冒泡。
        }
        store.clear();
      }
      handler.next(e);
    },
  ),);

  return dio;
});
