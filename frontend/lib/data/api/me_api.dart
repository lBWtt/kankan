// 这个文件是干什么的：封装「我的资料」的写接口——PATCH /me 改昵称/简介。
// 它对应产品里的什么功能：编辑资料页保存按钮（远端模式下真落库）。
// 如果它出错了：保存失败会如实提示（不伪装成已保存）。
//
// 传昵称/简介 + 关注领域（内容类型）：后端已加 content_type 轴（interest_content_types），
// 前端 UI 词表（ai_image/web/app…）与它 1:1，直接 PATCH /me 即可落库，不再 422。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';

class MeApi {
  final Dio _dio;
  MeApi(this._dio);

  /// PATCH /me — 只传想改的字段（后端 exclude_unset：不传的字段不动）。
  /// 需登录。返回后端最新资料 JSON（调用方按需取用）。
  Future<Map<String, dynamic>> updateProfile({
    String? nickname,
    String? bio,
    List<String>? interestContentTypes,
  }) async {
    try {
      final resp = await _dio.patch<dynamic>(
        '/me',
        data: {
          if (nickname != null) 'nickname': nickname,
          // bio 传空串 = 清空（后端对 bio 允许 null/空语义）。
          if (bio != null) 'bio': bio,
          // 关注领域（内容类型）：与后端 content_type 轴 1:1，直接落库。
          if (interestContentTypes != null)
            'interest_content_types': interestContentTypes,
        },
      );
      final data = resp.data;
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}

final meApiProvider = Provider<MeApi>((ref) => MeApi(ref.watch(dioProvider)));
