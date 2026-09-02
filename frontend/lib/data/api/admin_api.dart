// 这个文件是干什么的：封装后台审核相关接口（GET /admin/candidates 队列、详情、
//   approve/discard/park、PATCH 编辑）。只在管理员构建（AppConfig.adminBuild）下用到。
// 它对应产品里的什么功能：你在模拟器/后台上刷「待审队列」、点通过/不推荐/暂存/编辑。
// 如果它出错了：审核页拉不到候选或操作失败（AppException 透出给 UI 提示）。
//
// 隔离：本文件只被 features/admin/* 引用，而那些又只在 adminBuild 分支里挂载，
//   消费端构建时整片被 tree-shake，不进公开包。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../../providers/auth_provider.dart';

/// 候选媒体一项（图/视频）。url 已补成可加载的绝对地址。
class AdminMedia {
  final String url;
  final String mediaType; // image | video
  const AdminMedia({required this.url, required this.mediaType});

  bool get isVideo => mediaType == 'video';
}

/// 一条候选（列表 + 详情共用；详情字段列表接口可能为空）。
class AdminCandidate {
  final String id;
  final String status;
  final String? title;
  final String? tagline;
  final String? summary;
  final String? description;
  final String? category;
  final String? sourcePlatform;
  final String? coverMediaUrl;
  final int? score;
  final List<String> riskFlags;
  final List<String> tools;
  final List<String> domains;
  final List<String> tags;
  final String? aiImplementationHint;
  final String? sourceUrl;
  final String? originalAuthorName;
  final String? originalAuthorUrl;
  final String? riskNote;
  final List<AdminMedia> media;
  final Map<String, dynamic>? scores; // scores_json：五维分 + composite
  final String? projectId;

  const AdminCandidate({
    required this.id,
    required this.status,
    this.title,
    this.tagline,
    this.summary,
    this.description,
    this.category,
    this.sourcePlatform,
    this.coverMediaUrl,
    this.score,
    this.riskFlags = const [],
    this.tools = const [],
    this.domains = const [],
    this.tags = const [],
    this.aiImplementationHint,
    this.sourceUrl,
    this.originalAuthorName,
    this.originalAuthorUrl,
    this.riskNote,
    this.media = const [],
    this.scores,
    this.projectId,
  });

  String? get resolvedCover =>
      coverMediaUrl == null ? null : AppConfig.resolveMedia(coverMediaUrl!);

  static List<String> _strList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const <String>[];

  /// tags_json / media_json 兼容：直接列表 或 {items:[...]} / {tags:[...]}。
  static List<dynamic> _unwrap(dynamic v, String key) {
    if (v is List) return v;
    if (v is Map && v[key] is List) return v[key] as List;
    return const [];
  }

  factory AdminCandidate.fromJson(Map<String, dynamic> j) {
    final rawMedia = _unwrap(j['media_json'], 'items');
    final media = <AdminMedia>[];
    for (final m in rawMedia) {
      if (m is Map && m['url'] != null) {
        final url = m['url'].toString();
        media.add(AdminMedia(
          url: AppConfig.resolveMedia(url),
          mediaType: (m['media_type'] ?? 'image').toString(),
        ));
      }
    }
    final tagsRaw = _unwrap(j['tags_json'], 'tags');
    return AdminCandidate(
      id: j['id'].toString(),
      status: (j['status'] ?? '').toString(),
      title: j['title'] as String?,
      tagline: j['tagline'] as String?,
      summary: j['summary'] as String?,
      description: j['description'] as String?,
      category: j['category'] as String?,
      sourcePlatform: j['source_platform'] as String?,
      coverMediaUrl: j['cover_media_url'] as String?,
      score: j['ai_curation_score'] is int
          ? j['ai_curation_score'] as int
          : (j['ai_curation_score'] is num
              ? (j['ai_curation_score'] as num).toInt()
              : null),
      riskFlags: _strList(j['risk_flags']),
      tools: _strList(j['tools']),
      domains: _strList(j['domains']),
      tags: tagsRaw.map((e) => e.toString()).toList(),
      aiImplementationHint: j['ai_implementation_hint'] as String?,
      sourceUrl: j['source_url'] as String?,
      originalAuthorName: j['original_author_name'] as String?,
      originalAuthorUrl: j['original_author_url'] as String?,
      riskNote: j['risk_note'] as String?,
      media: media,
      scores: j['scores_json'] is Map
          ? Map<String, dynamic>.from(j['scores_json'] as Map)
          : null,
      projectId: j['project_id']?.toString(),
    );
  }
}

class AdminApi {
  final Dio _dio;
  AdminApi(this._dio);

  /// GET /admin/candidates?status=&sort_by=score → 待审队列（默认待审、分数降序）。
  Future<List<AdminCandidate>> listCandidates({
    String status = 'pending_review',
    int limit = 50,
  }) async {
    try {
      final resp = await _dio.get<dynamic>(
        '/admin/candidates',
        queryParameters: {
          if (status.isNotEmpty) 'status': status,
          'page_size': limit,
        },
      );
      final data = resp.data;
      final rawItems = data is Map
          ? (data['items'] ?? const <dynamic>[])
          : (data ?? const <dynamic>[]);
      final items = rawItems is List ? rawItems : const <dynamic>[];
      final list = items
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => AdminCandidate.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      // 后端按入池时间排；队列里我们让高分先看（分数降序，无分排后）。
      list.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
      return list;
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /admin/candidates/{id} → 候选详情（含媒体/简介/五维分/风控）。
  Future<AdminCandidate> detail(String id) async {
    try {
      final resp = await _dio.get<dynamic>('/admin/candidates/$id');
      return AdminCandidate.fromJson(
          Map<String, dynamic>.from(resp.data as Map));
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// POST /admin/candidates/{id}/approve → 通过并发布（含媒体转存）。
  /// 返回 (新项目 id, 实际派到的马甲昵称)——让审核员知道发布后作者显示成谁。
  /// 准入不满足抛 AppException(code=PUBLISH_GATE_FAILED, details.problems=[...])。
  Future<({String projectId, String? personaName})> approve(String id) async {
    try {
      final resp = await _dio.post<dynamic>('/admin/candidates/$id/approve');
      final data = resp.data;
      if (data is Map) {
        return (
          projectId: data['project_id']?.toString() ?? '',
          personaName: data['persona_name']?.toString(),
        );
      }
      return (projectId: '', personaName: null);
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// POST /admin/candidates/{id}/discard → 不推荐（→discarded）。
  Future<void> discard(String id, {String? reason}) async {
    try {
      await _dio.post<dynamic>(
        '/admin/candidates/$id/discard',
        data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
      );
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// POST /admin/candidates/{id}/park → 暂存（→parked）。
  Future<void> park(String id) async {
    try {
      await _dio.post<dynamic>('/admin/candidates/$id/park');
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// PATCH /admin/candidates/{id} → 人工编辑候选文案字段（保存后状态自动→edited）。
  Future<AdminCandidate> patch(String id, Map<String, dynamic> body) async {
    try {
      final resp =
          await _dio.patch<dynamic>('/admin/candidates/$id', data: body);
      return AdminCandidate.fromJson(
          Map<String, dynamic>.from(resp.data as Map));
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}

final adminApiProvider =
    Provider<AdminApi>((ref) => AdminApi(ref.watch(dioProvider)));

/// 待审队列（默认 pending_review）。审核动作后 ref.invalidate 刷新。
/// watch 登录态：常驻的悬浮球会一直持有本 provider，登录/登出时若不重拉，
/// 会卡在登录前的 401 缓存里（要手动「重试」）。依赖 isLoggedIn 让登录后自动刷新。
final adminQueueProvider =
    FutureProvider.autoDispose<List<AdminCandidate>>((ref) async {
  ref.watch(authProvider.select((s) => s.isLoggedIn));
  return ref.watch(adminApiProvider).listCandidates();
});

/// 单条候选详情。
final adminCandidateProvider =
    FutureProvider.autoDispose.family<AdminCandidate, String>((ref, id) async {
  return ref.watch(adminApiProvider).detail(id);
});
