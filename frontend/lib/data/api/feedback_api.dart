// 这个文件是干什么的：封装意见反馈提交接口 POST /feedback。
// 它对应产品里的什么功能：设置页「反馈 Bug / 建议」——真提交进后端反馈箱（不再只复制模板）。
// 如果它出错了：抛 AppException，调用方提示失败（不静默）。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';

class FeedbackApi {
  final Dio _dio;
  FeedbackApi(this._dio);

  /// 提交反馈（游客也可提；登录态后端自动带 user_id）。
  Future<void> submit({
    required String category, // bug / suggestion / other
    required String content,
    String? contact,
    String? appVersion,
    String? platform,
    String? deviceInfo,
    String? sourcePage,
    String? errorCode,
  }) async {
    try {
      await _dio.post<dynamic>(
        '/feedback',
        data: {
          'category': category,
          'content': content,
          if (contact != null && contact.isNotEmpty) 'contact': contact,
          if (appVersion != null) 'app_version': appVersion,
          if (platform != null) 'platform': platform,
          if (deviceInfo != null) 'device_info': deviceInfo,
          if (sourcePage != null && sourcePage.isNotEmpty)
            'source_page': sourcePage,
          if (errorCode != null && errorCode.isNotEmpty)
            'error_code': errorCode,
        },
      );
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}

final feedbackApiProvider = Provider<FeedbackApi>(
  (ref) => FeedbackApi(ref.watch(dioProvider)),
);
