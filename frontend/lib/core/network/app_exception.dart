// 这个文件是干什么的：把后端错误信封 {code,message,details} 和网络异常收敛成一个类型。
// 它对应产品里的什么功能：接口报错时 UI 只认这一个异常（"连不上"/"需登录"/校验失败）。
// 如果它出错了：报错以原始 DioException 冒泡，文案难看且无法区分登录拦截。
import 'package:dio/dio.dart';

/// App 统一异常。后端非 2xx 一律 {code,message,details}（见 backend/app/core/errors.py）。
class AppException implements Exception {
  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;

  const AppException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details,
  });

  bool get isAuthRequired => code == 'AUTH_REQUIRED' || statusCode == 401;

  /// 从 DioException 收敛。有后端信封用信封，否则按网络层给兜底文案。
  factory AppException.fromDio(DioException e) {
    final resp = e.response;
    final data = resp?.data;
    if (data is Map && data['code'] != null) {
      return AppException(
        code: data['code'].toString(),
        message: (data['message'] ?? '请求失败').toString(),
        statusCode: resp?.statusCode,
        details: data['details'] is Map
            ? Map<String, dynamic>.from(data['details'] as Map)
            : null,
      );
    }
    // 无信封：连不上 / 超时 / 其它
    final isConn = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout;
    return AppException(
      code: isConn ? 'NETWORK_ERROR' : 'UNKNOWN',
      message: isConn ? '连不上服务器' : '请求失败',
      statusCode: resp?.statusCode,
    );
  }

  @override
  String toString() => 'AppException($code, $message)';
}
