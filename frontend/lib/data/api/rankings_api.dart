// 这个文件是干什么的：封装榜单接口 GET /rankings（当前接项目周热门榜）。
// 它对应产品里的什么功能：榜单页「项目榜」真数据（埋点→hot_score→真热度排序）。
// 如果它出错了：项目榜拉不到真榜（会被 provider 转成错误态，可重试）。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../../domain/models/models.dart';
import '../dto/project_card_dto.dart';

class RankingsApi {
  final Dio _dio;
  RankingsApi(this._dio);

  /// 本周热门项目榜。返回按名次排好的项目（items[].project 是卡片形状）。
  /// type 固定 weekly_hot（latest/today_pick 后续按需加）。
  Future<List<Project>> weeklyHot({int limit = 50}) async {
    try {
      final resp = await _dio.get<dynamic>(
        '/rankings',
        queryParameters: {'type': 'weekly_hot', 'limit': limit},
      );
      final data = resp.data;
      final raw = data is Map ? (data['items'] ?? const <dynamic>[]) : const <dynamic>[];
      final items = raw is List ? raw : const <dynamic>[];
      final out = <Project>[];
      for (final m in items.whereType<Map<dynamic, dynamic>>()) {
        final proj = m['project'];
        if (proj is Map) {
          out.add(projectFromCardJson(Map<String, dynamic>.from(proj)));
        }
      }
      return out;
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}

final rankingsApiProvider = Provider<RankingsApi>(
  (ref) => RankingsApi(ref.watch(dioProvider)),
);

/// 项目周热门榜（真数据，AsyncValue：loading→骨架/错误→重试/data→名次列表）。
final remoteWeeklyHotProvider =
    FutureProvider.autoDispose<List<Project>>((ref) async {
  return ref.watch(rankingsApiProvider).weeklyHot(limit: 50);
});
