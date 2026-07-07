// 这个文件是干什么的：封装媒体上传接口 POST /media（发布项目的图/视频真上云）。
// 它对应产品里的什么功能：发布页传的图/视频，登录后真上传后端拿 media_id。
// 如果它出错了：发布的项目没有封面图（media_ids 空，项目仍能发，只是缺图）。
//
// 后端只信文件真实魔数（V8 字节头校验），不信声明的 Content-Type。所以这里从字节头
// 自己推断类型，保证声明与内容一致，必过后端校验。
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';

/// 从字节头推断 content-type（与后端 media._magic_matches 对齐）。识别不了返回 null。
String? detectMediaContentType(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return 'image/png';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 && // R
      b[1] == 0x49 && // I
      b[2] == 0x46 && // F
      b[3] == 0x46 && // F
      b[8] == 0x57 && // W
      b[9] == 0x45 && // E
      b[10] == 0x42 && // B
      b[11] == 0x50) {
    // P
    return 'image/webp';
  }
  // mp4：ISO BMFF，第 4-8 字节是 'ftyp'
  if (b.length >= 8 &&
      b[4] == 0x66 && // f
      b[5] == 0x74 && // t
      b[6] == 0x79 && // y
      b[7] == 0x70) {
    // p
    return 'video/mp4';
  }
  return null;
}

String _extForType(String contentType) {
  switch (contentType) {
    case 'image/jpeg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'video/mp4':
      return 'mp4';
    default:
      return 'bin';
  }
}

class MediaApi {
  final Dio _dio;
  MediaApi(this._dio);

  /// 上传一份媒体字节。返回后端 media id（填进 POST /projects 的 media_ids）。
  /// 类型从字节头推断；识别不了（非 jpg/png/webp/mp4）抛 AppException，调用方跳过该张。
  Future<String> upload(Uint8List bytes) async {
    final contentType = detectMediaContentType(bytes);
    if (contentType == null) {
      throw const AppException(
        code: 'VALIDATION_FAILED',
        message: '不支持的媒体格式（仅 jpg/png/webp/mp4）',
      );
    }
    final filename = 'upload.${_extForType(contentType)}';
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType.parse(contentType),
        ),
      });
      final resp = await _dio.post<dynamic>('/media', data: form);
      final data = resp.data;
      if (data is Map && data['id'] != null) {
        return data['id'].toString();
      }
      throw const AppException(code: 'UNKNOWN', message: '上传返回格式异常');
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}

final mediaApiProvider = Provider<MediaApi>(
  (ref) => MediaApi(ref.watch(dioProvider)),
);
