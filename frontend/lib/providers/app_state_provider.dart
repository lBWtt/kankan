import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/local_store.dart';
import '../core/utils/backend_id.dart';
import '../data/api/comments_api.dart';
import '../data/api/interactions_api.dart';
import '../data/api/posts_api.dart';
import '../data/seed/mock_seed.dart';
import '../domain/models/models.dart';
import 'app_state_data.dart';
import 'auth_provider.dart';

// P0-2 持久化：AppStateData 抽到 app_state_data.dart（破 LocalStore 循环 import）。
// 这里 export 透出，所有 `import 'app_state_provider.dart'` 的既有代码无需改。
export 'app_state_data.dart';

/// 全局 AppState Notifier（手动，无 codegen）。
///
/// P0-2 持久化：build() 时从 [LocalStore.loadMerged] 读回用户可变切片（我拿走的 /
/// 浏览历史 / 最近搜索 / 偏好 / 游客点赞收藏关注 / 通知未读 / 不感兴趣），并入 mock 种子。
/// 用 [ref.listenSelf] 在每次 state 变化时自动落盘——所有 setter 无需手动调 persist。
///
/// 合并语义（见 [LocalStore.loadMerged]）：
///   - 首启（无 kv_* key）→ 全用 seed（mock 演示数据）。
///   - 用户互动后 → 该片用 persisted；清空也会持久化（空集合），不会被 seed 塞回。
class AppStateNotifier extends Notifier<AppStateData> {
  @override
  AppStateData build() {
    // P0-2：每次 state 变化自动落盘。Riverpod 3.x 移除了 ref.listenSelf，改为
    // 覆盖下方的 `set state` —— 所有 setter 走 `state = ...` 即自动持久化。
    // 首启基线由本 build 末尾的 persist(merged) 固化。

    // 读通路:登录态变化时同步后端收藏。
    //   游客→登录:拉 /me/favorites 回填收藏心(退出重登收藏还在)。
    //   登录→登出:移除后端来的收藏(UUID id),保留 mock 演示收藏(短 id)。
    ref.listen(authProvider, (prev, next) {
      final was = prev?.isLoggedIn ?? false;
      if (!was && next.isLoggedIn) {
        _loadFavoritesFromBackend();
        _loadFollowingFromBackend(next.currentUser?.id);
      } else if (was && !next.isLoggedIn) {
        _dropBackendFavorites();
        _dropBackendFollows();
      }
    });

    // P0-2：从本地读回用户可变 state，并入 mock 种子。
    final merged =
        ref.read(localStoreProvider).loadMerged(AppStateData.initial());

    // 恢复的登录态（web 刷新后 auth 从 prefs 恢复）：ref.listen 不会为初始值触发，
    // 这里主动拉一次后端收藏/关注，让收藏心/关注态亮回来。
    final restored = ref.read(authProvider);
    if (restored.isLoggedIn) {
      _loadFavoritesFromBackend();
      _loadFollowingFromBackend(restored.currentUser?.id);
    }

    // 固化首启基线（让后续「未写过」判断有据可依）。
    ref.read(localStoreProvider).persist(merged);

    return merged;
  }

  // P0-2：覆盖 state setter，每次赋值后落盘（替代 Riverpod 3.x 已移除的 listenSelf）。
  @override
  set state(AppStateData value) {
    super.state = value;
    ref.read(localStoreProvider).persist(value);
  }

  /// 登录后拉后端收藏,并入 savedProjectIds(mock 演示收藏一并保留)。失败静默。
  Future<void> _loadFavoritesFromBackend() async {
    try {
      final ids = await ref.read(interactionsApiProvider).listFavoriteIds();
      if (ids.isEmpty) return;
      final next = Set<String>.from(state.savedProjectIds)..addAll(ids);
      state = state.copyWith(savedProjectIds: next);
    } catch (_) {
      // 拉取失败:保持现状,不影响本地演示收藏
    }
  }

  /// 登出:从 savedProjectIds 移除后端项目(UUID),保留 mock 演示收藏。
  void _dropBackendFavorites() {
    final next = state.savedProjectIds
        .where((id) => !looksLikeBackendId(id))
        .toSet();
    if (next.length != state.savedProjectIds.length) {
      state = state.copyWith(savedProjectIds: next);
    }
  }

  /// 登录后拉「我关注的人」并入 followedUserIds(关注按钮显真态)。失败静默。
  Future<void> _loadFollowingFromBackend(String? myId) async {
    if (myId == null || !looksLikeBackendId(myId)) return;
    try {
      final ids = await ref.read(interactionsApiProvider).listFollowingIds(myId);
      if (ids.isEmpty) return;
      final next = Set<String>.from(state.followedUserIds)..addAll(ids);
      state = state.copyWith(followedUserIds: next);
    } catch (_) {
      // 拉取失败:保持现状
    }
  }

  /// 登出:从 followedUserIds 移除后端用户(UUID),保留 mock 演示关注(短 id)。
  void _dropBackendFollows() {
    final next = state.followedUserIds
        .where((id) => !looksLikeBackendId(id))
        .toSet();
    if (next.length != state.followedUserIds.length) {
      state = state.copyWith(followedUserIds: next);
    }
  }

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  // ── 偏好设置(真生效 + 持久化)──
  void setFontScale(String scale) =>
      state = state.copyWith(fontScale: scale);
  void setPaperTexture(bool on) =>
      state = state.copyWith(paperTexture: on);
  void setDndEnabled(bool on) => state = state.copyWith(dndEnabled: on);
  void setBannerImage(String url) =>
      state = state.copyWith(bannerImageUrl: url);

  void setTabIndex(int i) => state = state.copyWith(currentTabIndex: i);

  /// F-3:更新 'me' 用户资料(写入内存 mockUsers)。
  /// 调用方(如 profile_edit _save)调用后应 ref.invalidate(userByIdProvider('me'))
  /// 让 profile / me 等屏重建显示新值。
  /// domains 暂不持久化(KkUser 无 interests 字段,Phase 5 加字段后接)。
  void updateProfile({required String name, String? bio}) {
    final i = mockUsers.indexWhere((u) => u.id == 'me');
    if (i >= 0) {
      mockUsers[i] = mockUsers[i].copyWith(
        name: name,
        bio: bio ?? mockUsers[i].bio,
      );
    }
  }

  // ── 点赞 ──
  bool isLiked(String id) => state.likedItemIds.contains(id);

  void toggleLike(String id) {
    final next = Set<String>.from(state.likedItemIds);
    if (!next.add(id)) next.remove(id);
    state = state.copyWith(likedItemIds: next);
  }

  /// 评论点赞（双轨）：乐观 toggle likedItemIds；登录 + 真后端评论(UUID)→ 同步后端、失败回滚。
  /// mock 评论(短 id)本地即真源。comment_thread 的点赞按钮走这个（统一 mock/remote，
  /// P0-1 收口：远程 likedIds 由 paginated_comments_provider.fetchPage mergeLikedIds 并入，
  /// 本方法只负责 toggle + 后端同步）。
  void toggleCommentLike(String commentId) {
    final wasLiked = state.likedItemIds.contains(commentId);
    final next = Set<String>.from(state.likedItemIds);
    if (wasLiked) {
      next.remove(commentId);
    } else {
      next.add(commentId);
    }
    state = state.copyWith(likedItemIds: next);
    _syncCommentLike(commentId, on: !wasLiked);
  }

  Future<void> _syncCommentLike(String commentId, {required bool on}) async {
    if (!ref.read(authProvider).isLoggedIn) return;
    if (!looksLikeBackendId(commentId)) return;
    try {
      await ref.read(commentsApiProvider).setLike(commentId, on);
    } catch (_) {
      final revert = Set<String>.from(state.likedItemIds);
      if (on) {
        revert.remove(commentId);
      } else {
        revert.add(commentId);
      }
      state = state.copyWith(likedItemIds: revert);
    }
  }

  /// 动态点赞（双轨）：乐观 toggle likedItemIds；登录 + 真后端动态(UUID)→ 同步后端、失败回滚。
  /// mock 动态(短 id)本地即真源。post_card/post_detail 的点赞按钮走这个（不走 toggleLike）。
  void togglePostLike(String postId) {
    final wasLiked = state.likedItemIds.contains(postId);
    final next = Set<String>.from(state.likedItemIds);
    if (wasLiked) {
      next.remove(postId);
    } else {
      next.add(postId);
    }
    state = state.copyWith(likedItemIds: next);
    _syncPostLike(postId, on: !wasLiked);
  }

  Future<void> _syncPostLike(String postId, {required bool on}) async {
    if (!ref.read(authProvider).isLoggedIn) return;
    if (!looksLikeBackendId(postId)) return;
    try {
      await ref.read(postsApiProvider).setLike(postId, on);
    } catch (_) {
      final revert = Set<String>.from(state.likedItemIds);
      if (on) {
        revert.remove(postId);
      } else {
        revert.add(postId);
      }
      state = state.copyWith(likedItemIds: revert);
    }
  }

  /// 把后端返回「我已赞」的 id 并入 likedItemIds（远程动态流/详情加载后点亮心）。
  void mergeLikedIds(Set<String> ids) {
    if (ids.isEmpty) return;
    final next = Set<String>.from(state.likedItemIds)..addAll(ids);
    if (next.length != state.likedItemIds.length) {
      state = state.copyWith(likedItemIds: next);
    }
  }

  // ── 收藏 ──
  bool isSaved(String projectId) =>
      state.savedProjectIds.contains(projectId);

  void toggleSave(String projectId) {
    final wasSaved = state.savedProjectIds.contains(projectId);
    final next = Set<String>.from(state.savedProjectIds);
    if (wasSaved) {
      next.remove(projectId);
    } else {
      next.add(projectId);
    }
    state = state.copyWith(savedProjectIds: next); // 乐观更新，UI 立即响应
    _syncFavorite(projectId, on: !wasSaved); // 后端同步（仅登录 + 真后端项目）
  }

  /// 收藏落库：登录 + 真后端项目（UUID）才发请求；失败回滚本地，保持与后端一致。
  /// mock 项目（短 id 如 'p1'）本地即真源，不碰后端（发了也会 404）。
  Future<void> _syncFavorite(String projectId, {required bool on}) async {
    if (!ref.read(authProvider).isLoggedIn) return;
    if (!looksLikeBackendId(projectId)) return;
    try {
      await ref.read(interactionsApiProvider).setFavorite(projectId, on);
    } catch (_) {
      // 落库失败：撤回乐观更新（此刻 state 可能已被其它操作改动，按幂等增删处理）
      final revert = Set<String>.from(state.savedProjectIds);
      if (on) {
        revert.remove(projectId);
      } else {
        revert.add(projectId);
      }
      state = state.copyWith(savedProjectIds: revert);
    }
  }

  // ── 关注 ──
  bool isFollowing(String userId) =>
      state.followedUserIds.contains(userId);

  void toggleFollow(String userId) {
    final wasFollowing = state.followedUserIds.contains(userId);
    final next = Set<String>.from(state.followedUserIds);
    if (wasFollowing) {
      next.remove(userId);
    } else {
      next.add(userId);
    }
    state = state.copyWith(followedUserIds: next); // 乐观更新
    _syncFollow(userId, on: !wasFollowing);
  }

  /// 关注落库:登录 + 真后端用户(UUID)才发请求;失败回滚本地保持一致。
  /// mock 用户(短 id 如 'chen')本地即真源,不碰后端。
  Future<void> _syncFollow(String userId, {required bool on}) async {
    if (!ref.read(authProvider).isLoggedIn) return;
    if (!looksLikeBackendId(userId)) return;
    try {
      await ref.read(interactionsApiProvider).setFollow(userId, on);
    } catch (_) {
      final revert = Set<String>.from(state.followedUserIds);
      if (on) {
        revert.remove(userId);
      } else {
        revert.add(userId);
      }
      state = state.copyWith(followedUserIds: revert);
    }
  }

  // ── 我拿走的(HANDOFF §6.3)──
  void addTakeaway(SavedTakeaway t) {
    final next = List<SavedTakeaway>.from(state.savedTakeaways);
    next.removeWhere((x) => x.id == t.id);
    next.insert(0, t);
    state = state.copyWith(savedTakeaways: next);
  }

  void removeTakeaway(String id) {
    final next = List<SavedTakeaway>.from(state.savedTakeaways)
      ..removeWhere((x) => x.id == id);
    state = state.copyWith(savedTakeaways: next);
  }

  // ── 浏览历史 ──
  void recordBrowse(String projectId) {
    final next = List<String>.from(state.browseHistory)
      ..remove(projectId)
      ..insert(0, projectId);
    if (next.length > 50) next.removeRange(50, next.length);
    state = state.copyWith(browseHistory: next);
  }

  /// 清空浏览历史(「我的」页最近看过的「清空」按钮)。
  void clearBrowseHistory() {
    state = state.copyWith(browseHistory: const []);
  }

  // ── 通知未读(HANDOFF §6.8)──
  void markNotifRead(String id) {
    final next = Set<String>.from(state.unreadNotifIds)..remove(id);
    state = state.copyWith(unreadNotifIds: next);
  }

  void markAllNotifRead() {
    state = state.copyWith(unreadNotifIds: const {});
  }

  // ── 最近搜索词(Map<String, int> 时间戳)──
  /// 加入一条搜索:刷新时间戳(天然去重)。超过 12 条时淘汰最旧。
  void addRecentSearch(String q) {
    final s = q.trim();
    if (s.isEmpty) return;
    final next = Map<String, int>.from(state.recentSearchesMap);
    next[s] = DateTime.now().millisecondsSinceEpoch;
    // 容量上限 12:超出则按时间戳升序(最旧在前)批量淘汰
    if (next.length > 12) {
      final sorted = next.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final excess = sorted.length - 12;
      for (var i = 0; i < excess; i++) {
        next.remove(sorted[i].key);
      }
    }
    state = state.copyWith(recentSearchesMap: next);
  }

  void removeRecentSearch(String q) {
    final next = Map<String, int>.from(state.recentSearchesMap)..remove(q);
    state = state.copyWith(recentSearchesMap: next);
  }

  void clearRecentSearches() {
    state = state.copyWith(recentSearchesMap: const {});
  }

  // ── 不感兴趣(任务⑫:负反馈闭环)──
  /// 标记某项目/动态 ID 为「不感兴趣」(单向 add,幂等)。
  /// discover 推荐/关注流 + kankan _mockList 渲染前过滤掉该 ID。
  /// 不对称 toggleSave(单向):「不感兴趣」是减少推荐,无「恢复」语义。
  void markNotInterested(String id) {
    if (state.notInterestedIds.contains(id)) return;
    final next = Set<String>.from(state.notInterestedIds)..add(id);
    state = state.copyWith(notInterestedIds: next);
  }
}

/// 全局 AppState provider。用法:ref.watch(appStateProvider).xxx
final appStateProvider =
    NotifierProvider<AppStateNotifier, AppStateData>(() => AppStateNotifier());
