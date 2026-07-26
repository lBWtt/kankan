// 这个文件是干什么的：封装通知中心的读接口——拉通知列表、标记单条已读。
// 它对应产品里的什么功能：通知中心页、tab 角标红点（远端模式下的真实数据源）。
// 如果它出错了：通知中心空白或红点消不掉（调用方降级到空列表，不崩）。
//
// 后端契约（type 是内容/系统模型：daily_pick/clue_update/content_status/system/… ，
// 与前端社交 5 类不同）：GET /notifications → {items:[{id,type,title,body,project_id,is_read,created_at}]}；
// PATCH /notifications/{id}/read。映射成前端 NotificationItem：无 actor 的内容通知按「系统样式」渲染，
// title+body 合成一行主文案，project_id 作为落点（clue_update 跳实现线索页，其余跳详情页）。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../../domain/models/models.dart';

class NotificationsApi {
  final Dio _dio;
  NotificationsApi(this._dio);

  /// GET /notifications → 通知列表（需登录）。映射成前端 NotificationItem。
  Future<List<NotificationItem>> list() async {
    try {
      final resp = await _dio.get<dynamic>(
        '/notifications',
        queryParameters: {'page_size': 50},
      );
      final data = resp.data;
      final raw = data is Map ? (data['items'] ?? const <dynamic>[]) : const <dynamic>[];
      final items = raw is List ? raw : const <dynamic>[];
      return items
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => _fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// PATCH /notifications/{id}/read → 标记已读（幂等）。
  Future<void> markRead(String id) async {
    try {
      await _dio.patch<dynamic>('/notifications/$id/read');
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  NotificationItem _fromJson(Map<String, dynamic> m) {
    final title = (m['title'] ?? '').toString();
    final body = m['body']?.toString();
    // title 为主，body 补充（去重、去空）。内容通知无 actor，走系统样式单行展示。
    final line = <String>[
      if (title.isNotEmpty) title,
      if (body != null && body.isNotEmpty && body != title) body,
    ].join('：');
    final createdMs =
        DateTime.tryParse(m['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch;
    // 深链落点：优先项目详情，其次动态详情；都无但有 actor（关注类）→ 由 _handleTap 跳触发者主页。
    final projectId = m['project_id']?.toString();
    final postId = m['post_id']?.toString();
    String? targetId;
    String? hostType;
    if (projectId != null && projectId.isNotEmpty) {
      targetId = projectId;
      hostType = 'project';
    } else if (postId != null && postId.isNotEmpty) {
      targetId = postId;
      hostType = 'post';
    }
    final actorId = m['actor_user_id']?.toString();
    return NotificationItem(
      id: m['id'].toString(),
      type: (m['type'] ?? 'system').toString(),
      actorId: (actorId != null && actorId.isNotEmpty) ? actorId : null,
      targetId: targetId,
      hostType: hostType,
      preview: line.isEmpty ? null : line,
      read: m['is_read'] == true,
      createdAtMs: createdMs,
    );
  }
}

final notificationsApiProvider = Provider<NotificationsApi>(
  (ref) => NotificationsApi(ref.watch(dioProvider)),
);
