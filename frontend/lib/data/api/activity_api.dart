import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../../domain/models/models.dart';

class ActivityStatsData {
  final int publishCount;
  final int receivedLikeCount;
  final int favoriteCount;
  const ActivityStatsData(this.publishCount, this.receivedLikeCount, this.favoriteCount);
}

class ActivityEventData {
  final String type;
  final String text;
  final int createdAtMs;
  final String? targetId;
  const ActivityEventData(this.type, this.text, this.createdAtMs, this.targetId);
}

class ActivityData {
  final ActivityStatsData stats;
  final List<HeatmapCell> cells;
  final List<ActivityEventData> events;
  const ActivityData(this.stats, this.cells, this.events);
}

class ActivityApi {
  final Dio _dio;
  ActivityApi(this._dio);

  Future<ActivityData> mine() async {
    try {
      final response = await _dio.get<dynamic>('/me/activity');
      final map = Map<String, dynamic>.from(response.data as Map);
      final stats = Map<String, dynamic>.from(map['stats'] as Map);
      final cells = (map['days'] as List? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((raw) {
            final item = Map<String, dynamic>.from(raw);
            return HeatmapCell(
              dateMs: DateTime.parse(item['date'].toString()).millisecondsSinceEpoch,
              level: (item['level'] as num?)?.toInt() ?? 0,
            );
          }).toList();
      final events = (map['events'] as List? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((raw) {
            final item = Map<String, dynamic>.from(raw);
            return ActivityEventData(
              item['type'].toString(),
              item['text'].toString(),
              DateTime.parse(item['created_at'].toString()).millisecondsSinceEpoch,
              item['target_id']?.toString(),
            );
          }).toList();
      return ActivityData(
        ActivityStatsData(
          (stats['publish_count'] as num?)?.toInt() ?? 0,
          (stats['received_like_count'] as num?)?.toInt() ?? 0,
          (stats['favorite_count'] as num?)?.toInt() ?? 0,
        ),
        cells,
        events,
      );
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}

final activityApiProvider = Provider<ActivityApi>((ref) => ActivityApi(ref.watch(dioProvider)));
final myActivityProvider = FutureProvider.autoDispose<ActivityData>(
  (ref) => ref.watch(activityApiProvider).mine(),
);
