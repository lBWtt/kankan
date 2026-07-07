// 这个文件是干什么的：封装埋点上报接口 POST /events（批量行为事件）。
// 它对应产品里的什么功能：dashboard 主信号漏斗（曝光→点开→想看怎么做）+ hot_score 浏览权重。
// 如果它出错了：用户无感（埋点绝不阻断 UX）；漏斗数据断流。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';

class EventsApi {
  final Dio _dio;
  EventsApi(this._dio);

  /// 批量上报事件（1-50 条/批，游客可用）。best-effort：任何错误静默吞掉，绝不影响 UX。
  Future<void> sendBatch(
    List<Map<String, dynamic>> events, {
    String? anonClientId,
  }) async {
    if (events.isEmpty) return;
    try {
      await _dio.post<dynamic>('/events', data: {
        'events': events,
        'client_info': {
          if (anonClientId != null) 'anon_client_id': anonClientId,
          'platform': 'web',
        },
      });
    } on DioException {
      // 埋点失败不重试不报错（best-effort，不该因遥测抖动影响用户）。
    }
  }
}

final eventsApiProvider = Provider<EventsApi>(
  (ref) => EventsApi(ref.watch(dioProvider)),
);
