// 这个文件是干什么的：封装动态接口（流/发/看/删/赞）+ 把后端 PostOut 映射成前端 Post。
// 它对应产品里的什么功能：发现页动态流、发动态、动态详情、动态点赞。
// 如果它出错了：动态流拉不到/发不出/看不到/赞不动（经 AppException 透出）。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../../domain/models/models.dart';
import '../remote_user_cache.dart';

/// 后端相对媒体 URL（/uploads/xxx）拼后端 origin；绝对 URL 原样（同 project_card_dto）。
String _resolveUrl(String url) {
  if (url.isEmpty || url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  var origin = AppConfig.apiBaseUrl;
  final i = origin.indexOf('/api/');
  if (i > 0) origin = origin.substring(0, i);
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}

int _parseMs(dynamic iso) {
  if (iso is String && iso.isNotEmpty) {
    final dt = DateTime.tryParse(iso);
    if (dt != null) return dt.millisecondsSinceEpoch;
  }
  return DateTime.now().millisecondsSinceEpoch;
}

/// 后端 PostOut → 前端 Post。is_liked 收集进 [likedIds]；likes 存「不含我」基数
/// （前端 post_card/detail 显示 likes + isLiked，后端 like_count 含我，减掉我这一票）。
Post _postFromJson(Map<String, dynamic> j, Set<String> likedIds) {
  final id = j['id'].toString();
  if (j['is_liked'] == true) likedIds.add(id);
  final author = j['author'];
  String authorId = '';
  if (author is Map) {
    authorId = author['id']?.toString() ?? '';
    if (authorId.isNotEmpty) {
      final nick = author['nickname']?.toString();
      cacheRemoteUser(KkUser(
        id: authorId,
        name: (nick != null && nick.isNotEmpty) ? nick : authorId,
        avatar: author['avatar_url']?.toString(),
      ));
    }
  }
  final media = <MediaItem>[];
  final rawMedia = j['media'];
  if (rawMedia is List) {
    for (final m in rawMedia.whereType<Map<dynamic, dynamic>>()) {
      final url = m['url']?.toString();
      if (url != null && url.isNotEmpty) {
        media.add(MediaItem(
          type: m['type']?.toString() == 'video' ? 'video' : 'image',
          url: _resolveUrl(url),
          poster: m['poster'] != null ? _resolveUrl(m['poster'].toString()) : null,
        ));
      }
    }
  }
  final tags = (j['tags'] is List)
      ? (j['tags'] as List).map((e) => e.toString()).toList()
      : const <String>[];
  final rawLikes = j['likes'];
  final total = rawLikes is int ? rawLikes : int.tryParse('$rawLikes') ?? 0;
  final baseLikes = j['is_liked'] == true ? (total - 1).clamp(0, total) : total;
  final cc = j['comment_count'];
  return Post(
    id: id,
    content: (j['content'] ?? '').toString(),
    authorId: authorId,
    media: media,
    tags: tags,
    quoteProjectId: j['quote_project_id']?.toString(),
    likes: baseLikes,
    commentCount: cc is int ? cc : int.tryParse('$cc') ?? 0,
    createdAtMs: _parseMs(j['created_at']),
  );
}

/// 一次动态列表拉取：动态列表 + 我已赞的动态 id 集合。
class PostList {
  final List<Post> posts;
  final Set<String> likedIds;
  const PostList(this.posts, this.likedIds);
}

/// 分页动态结果：动态列表 + 已赞集合 + 下一页游标 + hasMore。
/// 后端返回 {items, next_cursor, has_more}；无游标时 hasMore 按 items.length>=limit 推断。
class PostPage {
  final List<Post> posts;
  final Set<String> likedIds;
  final String? nextCursor;
  final bool hasMore;
  const PostPage(this.posts, this.likedIds, this.nextCursor, this.hasMore);
}

class PostsApi {
  final Dio _dio;
  PostsApi(this._dio);

  /// GET /posts → 动态流 + 已赞集合（首页，无分页）。保留给非 feed 调用方。
  Future<PostList> list({int limit = 30}) async {
    try {
      final resp = await _dio.get<dynamic>('/posts', queryParameters: {'page_size': limit});
      return _parseList(resp.data);
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /posts（游标分页）→ 动态流 + 已赞集合 + nextCursor + hasMore。
  /// [cursor]=null 拉首页；非 null 拉下一页。后端不认 cursor 时返回首页，
  /// 前端去重 + hasMore 启发式兜底（见 PaginatedNotifier.loadMore）。
  Future<PostPage> listPaged({int limit = 20, String? cursor}) async {
    try {
      final qp = <String, dynamic>{'page_size': limit};
      if (cursor != null && cursor.isNotEmpty) qp['cursor'] = cursor;
      final resp = await _dio.get<dynamic>('/posts', queryParameters: qp);
      return _parsePaged(resp.data, limit);
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /users/{id}/posts → ta 的动态（首页，无分页）。
  Future<PostList> byUser(String userId, {int limit = 30}) async {
    try {
      final resp = await _dio.get<dynamic>('/users/$userId/posts', queryParameters: {'page_size': limit});
      return _parseList(resp.data);
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /users/{id}/posts（游标分页）→ ta 的动态分页。
  Future<PostPage> byUserPaged(String userId, {int limit = 20, String? cursor}) async {
    try {
      final qp = <String, dynamic>{'page_size': limit};
      if (cursor != null && cursor.isNotEmpty) qp['cursor'] = cursor;
      final resp = await _dio.get<dynamic>('/users/$userId/posts', queryParameters: qp);
      return _parsePaged(resp.data, limit);
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  PostList _parseList(dynamic data) {
    final raw = data is Map ? (data['items'] ?? const <dynamic>[]) : const <dynamic>[];
    final items = raw is List ? raw : const <dynamic>[];
    final liked = <String>{};
    final posts = items
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => _postFromJson(Map<String, dynamic>.from(m), liked))
        .toList();
    return PostList(posts, liked);
  }

  /// 解析分页信封 {items, next_cursor, has_more} + 已赞集合。
  /// 无 next_cursor/has_more 时：hasMore = posts.length >= limit（启发式）。
  PostPage _parsePaged(dynamic data, int limit) {
    final raw = data is Map ? (data['items'] ?? const <dynamic>[]) : const <dynamic>[];
    final items = raw is List ? raw : const <dynamic>[];
    final liked = <String>{};
    final posts = items
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => _postFromJson(Map<String, dynamic>.from(m), liked))
        .toList();
    String? nextCursor;
    bool hasMore;
    if (data is Map) {
      final nc = data['next_cursor'];
      nextCursor = nc is String && nc.isNotEmpty ? nc : null;
      final hm = data['has_more'];
      hasMore = hm is bool ? hm : posts.length >= limit;
    } else {
      hasMore = posts.length >= limit;
    }
    return PostPage(posts, liked, nextCursor, hasMore);
  }

  /// GET /posts/{id} → 动态详情。404→null。
  Future<({Post? post, bool isLiked})> detail(String id) async {
    try {
      final resp = await _dio.get<dynamic>('/posts/$id');
      final data = resp.data;
      if (data is Map) {
        final liked = <String>{};
        final p = _postFromJson(Map<String, dynamic>.from(data), liked);
        return (post: p, isLiked: liked.contains(id));
      }
      return (post: null, isLiked: false);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return (post: null, isLiked: false);
      throw AppException.fromDio(e);
    }
  }

  /// POST /posts → 发动态。返回真 Post（真 uuid）。
  Future<Post> create(Map<String, dynamic> body) async {
    try {
      final resp = await _dio.post<dynamic>('/posts', data: body);
      final data = resp.data;
      if (data is Map) {
        return _postFromJson(Map<String, dynamic>.from(data), <String>{});
      }
      throw const AppException(code: 'UNKNOWN', message: '发动态返回格式异常');
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// 动态点赞 / 取消。on=true→POST，false→DELETE，幂等。
  Future<void> setLike(String id, bool on) async {
    try {
      if (on) {
        await _dio.post<dynamic>('/posts/$id/like');
      } else {
        await _dio.delete<dynamic>('/posts/$id/like');
      }
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// DELETE /posts/{id}（仅本人）。
  Future<void> delete(String id) async {
    try {
      await _dio.delete<dynamic>('/posts/$id');
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}

final postsApiProvider = Provider<PostsApi>((ref) => PostsApi(ref.watch(dioProvider)));
