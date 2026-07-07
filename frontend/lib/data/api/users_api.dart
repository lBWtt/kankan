// 这个文件是干什么的：封装用户「读」接口 —— GET /me 计数、GET /users/{id} 公开资料、
// GET /users/{id}/followers|following 列表。
// 它对应产品里的什么功能：me / profile 头部的关注/粉丝数 + 关注/粉丝列表屏（真计数 + 真列表）。
// 如果它出错了：计数显旧值或 0、列表显错误态（调用方用 RemoteError 可重试）。
//
// 边界：关注「写」通路（POST/DELETE /users/{id}/follow）在 interactions_api.dart，
// 这里只做读显示。关注按钮选中态走 appState.followedUserIds（Claude 已双轨），本文件不碰。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../../domain/models/models.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/auth_provider.dart';
import '../remote_user_cache.dart';

/// 远程用户公开资料（GET /users/{id} 返回字段子集，前端读显示用）。
///
/// 比 KkUser 多 published_project_count / following_count / follower_count /
/// is_followed_by_me——这些是后端聚合的「他人视角」字段，前端 KkUser 不存。
class UserPublic {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? bio;
  final int projectCount;
  final int followingCount;
  final int followerCount;
  final bool isFollowedByMe;

  const UserPublic({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.bio,
    this.projectCount = 0,
    this.followingCount = 0,
    this.followerCount = 0,
    this.isFollowedByMe = false,
  });
}

/// 「我的」四联计数（GET /me：关注/粉丝/收藏/获赞）。
class MyCounts {
  final int following;
  final int follower;
  final int favorites; // 我收藏的项目数
  final int receivedLikes; // 我的内容获赞总数（项目反应 + 动态点赞）
  const MyCounts(
    this.following,
    this.follower, {
    this.favorites = 0,
    this.receivedLikes = 0,
  });
}

/// 一次分页用户列表拉取的结果：用户列表 + 下一页游标 + hasMore。
/// 后端返回 {items, next_cursor, has_more}；无游标时 hasMore 按 users.length>=limit 推断
/// （与 posts_api._parsePage 启发式一致）。
class UserPage {
  final List<KkUser> users;
  final String? nextCursor;
  final bool hasMore;
  const UserPage({
    required this.users,
    required this.nextCursor,
    required this.hasMore,
  });
}

class UsersApi {
  final Dio _dio;
  UsersApi(this._dio);

  /// GET /me → 我的关注/粉丝计数。需登录（后端 auth_required）。
  /// 调用方（myCountsProvider）在未登录 / 非 useRemote 时不调本方法。
  Future<MyCounts> myCounts() async {
    try {
      final resp = await _dio.get<dynamic>('/me');
      final data = resp.data;
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        return MyCounts(
          _readInt(m['following_count']),
          _readInt(m['follower_count']),
          favorites: _readInt(m['favorite_count']),
          receivedLikes: _readInt(m['received_like_count']),
        );
      }
      throw const AppException(code: 'UNKNOWN', message: '/me 返回格式异常');
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /users/{id} → 远程用户公开资料（昵称/头像/简介/计数/是否已关注）。
  /// 游客可读。顺带 cacheRemoteUser 让 userByIdProvider 兜底也能查到这位远程用户。
  Future<UserPublic> userPublic(String id) async {
    try {
      final resp = await _dio.get<dynamic>('/users/$id');
      final data = resp.data;
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        final uid = m['id'].toString();
        final nick = (m['nickname'] ?? '').toString();
        // 顺带缓存：profile_screen 头像、follows_screen 行头像都能用 userByIdProvider 查到。
        cacheRemoteUser(KkUser(
          id: uid,
          name: nick.isNotEmpty ? nick : uid,
          avatar: m['avatar_url'] as String?,
          bio: m['bio'] as String?,
        ));
        return UserPublic(
          id: uid,
          nickname: nick,
          avatarUrl: m['avatar_url'] as String?,
          bio: m['bio'] as String?,
          projectCount: _readInt(m['published_project_count']),
          followingCount: _readInt(m['following_count']),
          followerCount: _readInt(m['follower_count']),
          isFollowedByMe: m['is_followed_by_me'] == true,
        );
      }
      throw const AppException(code: 'UNKNOWN', message: '用户资料格式异常');
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /users/{id}/followers → 粉丝列表（UserBrief → KkUser，顺带缓存）。
  /// 游标分页：[cursor]=null 拉首页；非 null 拉下一页。
  /// 后端返回 { items:[UserBrief], next_cursor, has_more } 或裸数组，两种都兼容。
  /// 无 next_cursor/has_more 时：hasMore = users.length >= limit（启发式，与 posts_api 一致）。
  Future<UserPage> followers(String id, {int limit = 20, String? cursor}) async {
    try {
      final qp = <String, dynamic>{'page_size': limit};
      if (cursor != null && cursor.isNotEmpty) qp['cursor'] = cursor;
      final resp =
          await _dio.get<dynamic>('/users/$id/followers', queryParameters: qp);
      return _parseUserPage(resp.data, limit);
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// GET /users/{id}/following → 关注列表（UserBrief → KkUser，顺带缓存）。
  /// 游标分页语义同 [followers]。
  Future<UserPage> following(String id, {int limit = 20, String? cursor}) async {
    try {
      final qp = <String, dynamic>{'page_size': limit};
      if (cursor != null && cursor.isNotEmpty) qp['cursor'] = cursor;
      final resp =
          await _dio.get<dynamic>('/users/$id/following', queryParameters: qp);
      return _parseUserPage(resp.data, limit);
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }

  /// 解析 { items:[UserBrief], next_cursor, has_more } 或裸数组 → List<KkUser>。
  /// UserBrief = { id, nickname, avatar_url, role } → KkUser(id/name=nickname/avatar=avatar_url)。
  /// role 暂不存（前端 KkUser 无此字段，Phase 5 加角色徽章时再扩）。
  List<KkUser> _parseUsers(dynamic data) {
    final raw = data is Map
        ? (data['items'] ?? const <dynamic>[])
        : (data ?? const <dynamic>[]);
    final items = raw is List ? raw : const <dynamic>[];
    final out = <KkUser>[];
    for (final m in items.whereType<Map<dynamic, dynamic>>()) {
      final j = Map<String, dynamic>.from(m);
      final id = j['id'].toString();
      if (id.isEmpty) continue;
      final nick = (j['nickname'] ?? '').toString();
      final user = KkUser(
        id: id,
        name: nick.isNotEmpty ? nick : id,
        avatar: j['avatar_url'] as String?,
      );
      cacheRemoteUser(user);
      out.add(user);
    }
    return out;
  }

  /// 解析分页信封 {items, next_cursor, has_more} 或裸数组 → [UserPage]。
  /// 无 next_cursor/has_more 时：hasMore = users.length >= limit（启发式）。
  UserPage _parseUserPage(dynamic data, int limit) {
    final users = _parseUsers(data);
    String? nextCursor;
    bool hasMore;
    if (data is Map) {
      final nc = data['next_cursor'];
      nextCursor = nc is String && nc.isNotEmpty ? nc : null;
      final hm = data['has_more'];
      hasMore = hm is bool ? hm : users.length >= limit;
    } else {
      hasMore = users.length >= limit;
    }
    return UserPage(
      users: users,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  int _readInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}

final usersApiProvider = Provider<UsersApi>(
  (ref) => UsersApi(ref.watch(dioProvider)),
);

/// 我的四联计数（GET /me：关注/粉丝/收藏/获赞）。
/// 仅登录 + useRemote 时拉真数据，否则返回 null（调用方走 mock 兜底）。
/// watch followedUserIds.length / savedProjectIds.length：关注-取关、收藏-取消后
/// 本地状态变 → provider 重建 → 重拉 /me，我的 following_count / favorite_count 自动刷新。
final myCountsProvider = FutureProvider<MyCounts?>((ref) async {
  ref.watch(appStateProvider.select(
      (s) => (s.followedUserIds.length, s.savedProjectIds.length)));
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn || !AppConfig.useRemote) return null;
  return ref.watch(usersApiProvider).myCounts();
});

/// 远程用户公开资料（GET /users/{id}）。
/// 仅 useRemote + 真后端 id（UUID）时拉，否则返回 null（调用方走 mock）。
/// watch followedUserIds.contains(id)：我关注/取关该用户 → ta 的 follower_count
/// + is_followed_by_me 变，provider 重建重拉。
final remoteUserPublicProvider =
    FutureProvider.autoDispose.family<UserPublic?, String>((ref, id) async {
  ref.watch(appStateProvider.select((s) => s.followedUserIds.contains(id)));
  if (!AppConfig.useRemote) return null;
  return ref.watch(usersApiProvider).userPublic(id);
});

/// 远程用户粉丝列表（GET /users/{id}/followers，首页 cursor=null）。
/// watch followedUserIds.contains(id)：我关注/取关该用户 → 我从 ta 的粉丝列表
/// 加入/退出，provider 重建重拉。
/// P0-1 收口：本 provider 仅给 follows_screen Tab 计数等「快取首页长度」场景用；
/// 列表体无限滚动改用 paginatedFollowersProvider（同源 cursor=null 首页 + 后续页）。
final remoteFollowersProvider =
    FutureProvider.autoDispose.family<List<KkUser>, String>((ref, id) async {
  ref.watch(appStateProvider.select((s) => s.followedUserIds.contains(id)));
  final page = await ref.watch(usersApiProvider).followers(id);
  return page.users;
});

/// 远程用户关注列表（GET /users/{id}/following，首页 cursor=null）。
/// 若 id 是当前登录用户，watch followedUserIds.length：我关注/取关别人 → 我的
/// following 列表变，provider 重建重拉。他人 following 列表与本地状态无关，不订阅。
final remoteFollowingProvider =
    FutureProvider.autoDispose.family<List<KkUser>, String>((ref, id) async {
  final myId = ref.watch(authProvider).currentUser?.id;
  if (myId != null && myId == id) {
    ref.watch(appStateProvider.select((s) => s.followedUserIds.length));
  }
  final page = await ref.watch(usersApiProvider).following(id);
  return page.users;
});
