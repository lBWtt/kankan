// 这个文件是干什么的：封装登录三件套接口——发验证码、验证码登录、刷新令牌。
// 它对应产品里的什么功能：登录页发码/登录；令牌过期时后台静默换新。
// 如果它出错了：发不出验证码、登录不上，或令牌过期后掉线无法续期。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../dto/auth_dto.dart';

/// 判断输入是邮箱还是手机号（含 '@' 视为邮箱）。后端还会再校验格式。
String detectIdentifierType(String identifier) =>
    identifier.contains('@') ? 'email' : 'phone';

class AuthApi {
  final Dio _dio;
  AuthApi(this._dio);

  /// POST /auth/send-code — 发送验证码。频控 429 由 AppException 透出给 UI 提示。
  Future<void> sendCode(String identifier) async {
    try {
      await _dio.post<dynamic>(
        '/auth/send-code',
        data: {
          'identifier_type': detectIdentifierType(identifier),
          'identifier': identifier,
        },
      );
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// POST /auth/login — 验证码登录（未注册自动注册）。
  /// [anonClientId] 带上则后端把游客的「想看怎么做」记录归并到账号（主信号不丢）。
  Future<LoginResult> login(
    String identifier,
    String code, {
    String? anonClientId,
  }) async {
    try {
      final resp = await _dio.post<dynamic>(
        '/auth/login',
        data: {
          'identifier_type': detectIdentifierType(identifier),
          'identifier': identifier,
          'code': code,
          if (anonClientId != null) 'anon_client_id': anonClientId,
        },
      );
      final data = resp.data;
      if (data is Map) {
        return loginResultFromJson(Map<String, dynamic>.from(data));
      }
      throw const AppException(code: 'UNKNOWN', message: '登录返回格式异常');
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(dioProvider)),
);
