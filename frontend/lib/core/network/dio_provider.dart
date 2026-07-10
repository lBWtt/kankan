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
///   - 收到 401：用 refresh_token 静默换一对新令牌并重试原请求一次。
///
/// 刷新是「单飞」的（并发 401 共享同一个刷新 Future）——后端 refresh 是一次性轮换
/// （jti 消费即废），页面加载常有多个鉴权请求同时过期：若各自刷新，第一个消费掉 jti 后
/// 其余必 401，旧实现会在此时清令牌把刚续上期的用户踢下线。单飞 + 「发现令牌已被
/// 别人换新就直接重试」两道保险堵死这个随机掉登录。
///
/// 只有 refresh 被后端明确 401 拒绝才判会话死亡（expireSession 清令牌 + 通知 UI 登出）；
/// 网络抖动/5xx 不清令牌，原 401 冒泡，下次请求还有机会续。
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

  // 单飞刷新：非 null = 正在刷，后来者 await 同一个 Future。
  Future<bool>? refreshing;

  Future<bool> doRefresh() async {
    final oldRefresh = store.refreshToken;
    if (oldRefresh == null || oldRefresh.isEmpty) return false;
    // 用裸 Dio 换令牌，避免走本拦截器造成递归；用完 close 释放其连接池，防长跑泄漏。
    final bare = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
    try {
      final r = await bare.post<dynamic>(
        '/auth/refresh',
        data: {'refresh_token': oldRefresh},
      );
      final data = r.data;
      if (data is Map &&
          data['access_token'] != null &&
          data['refresh_token'] != null) {
        store.set(
          access: data['access_token'].toString(),
          refresh: data['refresh_token'].toString(),
        );
        return true;
      }
      return false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // 后端确认 refresh 已废（过期/已轮换/伪造）→ 会话真死了，清令牌并通知 UI 登出。
        store.expireSession();
      }
      // 网络错/超时/5xx：令牌不动，本轮失败但不判死。
      return false;
    } catch (_) {
      return false;
    } finally {
      bare.close();
    }
  }

  Future<bool> refreshTokens() =>
      refreshing ??= doRefresh().whenComplete(() => refreshing = null);

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = store.accessToken;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final is401 = e.response?.statusCode == 401;
        final alreadyRetried = e.requestOptions.extra['__retried'] == true;
        final isAuthCall =
            e.requestOptions.path.contains('/auth/'); // 登录/刷新自身 401 不套刷新
        if (!is401 || alreadyRetried || isAuthCall) {
          return handler.next(e);
        }

        // 保险 1：本请求带的令牌已经不是当前令牌（并发请求刚刷新过）→ 不再刷，直接重试。
        final sentAuth = e.requestOptions.headers['Authorization'];
        final current = store.accessToken;
        var ok = current != null &&
            current.isNotEmpty &&
            sentAuth != 'Bearer $current';

        // 保险 2：单飞刷新——并发 401 等同一个 Future，只有一次真正的 /auth/refresh。
        if (!ok) {
          if (!(store.refreshToken?.isNotEmpty ?? false)) {
            return handler.next(e);
          }
          ok = await refreshTokens();
        }
        if (!ok || !(store.accessToken?.isNotEmpty ?? false)) {
          return handler.next(e); // 刷新失败：原 401 冒泡（UI 弹登录）
        }

        // 重试原请求（带新令牌 + 标记，防二次刷新死循环）。裸 Dio 防拦截器递归，用完 close 防泄漏。
        final bare = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
        try {
          final opts = e.requestOptions;
          opts.headers['Authorization'] = 'Bearer ${store.accessToken}';
          opts.extra['__retried'] = true;
          final clone = await bare.fetch<dynamic>(opts);
          return handler.resolve(clone);
        } catch (_) {
          // 重试自身失败（含 FormData 不可复用等）：原 401 冒泡，不再纠缠。
          return handler.next(e);
        } finally {
          bare.close();
        }
      },
    ),
  );

  return dio;
});
