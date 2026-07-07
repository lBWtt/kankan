// 这个文件是干什么的：封装项目相关的后端接口调用（当前只有 GET /projects 列表）。
// 它对应产品里的什么功能：看看 feed 拉真数据。
// 如果它出错了：feed 拉不到真项目（会被 remoteProjectsProvider 转成错误态）。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../../core/pagination/page.dart';
import '../../domain/models/models.dart';
import '../dto/project_card_dto.dart';

class ProjectsApi {
  final Dio _dio;
  ProjectsApi(this._dio);

  /// GET /projects → 已发布项目卡片列表。
  /// 后端返回信封 {items:[...]} 或裸数组，两种都兼容。
  Future<List<Project>> list({int limit = 30}) async {
    try {
      final resp = await _dio.get<dynamic>(
        '/projects',
        queryParameters: {'page_size': limit},
      );
      final data = resp.data;
      final Object? rawItems = data is Map<dynamic, dynamic>
          ? (data['items'] ?? data['data'] ?? const <dynamic>[])
          : (data ?? const <dynamic>[]);
      final items = rawItems is List ? rawItems : const <dynamic>[];
      return items
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => projectFromCardJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /users/{id}/projects → TA 的作品（仅 published，游客可读）。
  /// 用于个人主页「项目」Tab 远程化；返回 Page 信封 {items:[...]}。
  Future<List<Project>> byUser(String userId, {int limit = 30}) async {
    try {
      final resp = await _dio.get<dynamic>(
        '/users/$userId/projects',
        queryParameters: {'page_size': limit},
      );
      final data = resp.data;
      final Object? rawItems = data is Map<dynamic, dynamic>
          ? (data['items'] ?? data['data'] ?? const <dynamic>[])
          : (data ?? const <dynamic>[]);
      final items = rawItems is List ? rawItems : const <dynamic>[];
      return items
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => projectFromCardJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /projects（游标分页）→ 项目卡片分页。
  /// 后端返回 {items, next_cursor, has_more}；无游标时 hasMore 按 items.length>=limit 推断。
  /// 后端契约参数是 page_size + cursor（见 backend/api/v1/projects.py），不是 limit。
  Future<Page<Project>> listPaged({int limit = 20, String? cursor}) async {
    try {
      final qp = <String, dynamic>{'page_size': limit};
      if (cursor != null && cursor.isNotEmpty) qp['cursor'] = cursor;
      final resp = await _dio.get<dynamic>('/projects', queryParameters: qp);
      final data = resp.data;
      final Object? rawItems = data is Map<dynamic, dynamic>
          ? (data['items'] ?? data['data'] ?? const <dynamic>[])
          : (data ?? const <dynamic>[]);
      final items = rawItems is List ? rawItems : const <dynamic>[];
      final projects = items
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => projectFromCardJson(Map<String, dynamic>.from(m)))
          .toList();
      String? nextCursor;
      bool hasMore;
      if (data is Map) {
        final nc = data['next_cursor'];
        nextCursor = nc is String && nc.isNotEmpty ? nc : null;
        final hm = data['has_more'];
        hasMore = hm is bool ? hm : projects.length >= limit;
      } else {
        hasMore = projects.length >= limit;
      }
      return Page<Project>(
          items: projects, nextCursor: nextCursor, hasMore: hasMore);
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// POST /projects → 发布项目（需登录，走 v2 字段）。
  /// 成功返回后端 ProjectDetail 映射的 Project（含真 uuid）。
  /// 准入不过后端回 409 PUBLISH_GATE_FAILED；AppException 透出给 UI 提示。
  Future<Project> create(Map<String, dynamic> body) async {
    try {
      final resp = await _dio.post<dynamic>('/projects', data: body);
      final data = resp.data;
      if (data is Map) {
        return projectFromDetailJson(Map<String, dynamic>.from(data));
      }
      throw const AppException(code: 'UNKNOWN', message: '发布返回格式异常');
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// DELETE /projects/{id} → 软删自己的项目（需登录，own-only，后端 status=deleted）。
  /// 404/403 等经 AppException 透出。
  Future<void> delete(String id) async {
    try {
      await _dio.delete<dynamic>('/projects/$id');
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /projects/{id} → 单个项目详情（比卡片多 intro/author/media/counts）。
  Future<Project?> detail(String id) async {
    try {
      final resp = await _dio.get<dynamic>('/projects/$id');
      final data = resp.data;
      if (data is Map) {
        return projectFromDetailJson(Map<String, dynamic>.from(data));
      }
      return null;
    } on DioException catch (e) {
      // 404 → 该 id 后端没有（可能是 mock id 误入）→ 返回 null 让上层兜底,不抛。
      if (e.response?.statusCode == 404) return null;
      throw AppException.fromDio(e);
    }
  }
}

final projectsApiProvider = Provider<ProjectsApi>(
  (ref) => ProjectsApi(ref.watch(dioProvider)),
);
