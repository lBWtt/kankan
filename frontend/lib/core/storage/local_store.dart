// 这个文件是干什么的：本地持久化层——把用户可变 state 切片落到 SharedPreferences，
//   重启后读回并入 mock 种子，让「我拿走的 / 浏览历史 / 最近搜索 / 偏好 / 游客点赞收藏」不丢。
// 它对应产品里的什么功能：草稿恢复（PR#17 已做 draft_*）；本文件补的是其它用户可变数据。
//   PR#17 的草稿横条 + 入场动画是「写一半的内容不丢」；本文件是「用户的行为痕迹不丢」。
// 如果它出错了：读回脏数据 → 显示陈旧状态；写失败 → 本会话内仍正确（state 已更新），仅重启丢。
//
// 设计：
//   - 不引入 Drift/Hive（F-34：drift_dev analyzer 冲突已删；freezed 3.x + shared_preferences 足够）。
//   - ID 集合 / 列表 → SharedPreferences.setStringList（原生支持 List<String>）。
//   - 复杂对象（SavedTakeaway）/ Map → JSON string（手动 toMap/fromMap，免 codegen）。
//   - 合并策略：persisted 存在 → 用 persisted；不存在 → 用 seed（mock 演示数据，首启可见）。
//   - persist() 在每次 state 突变后调用（fire-and-forget；SharedPreferences 内部排队写盘）。
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prefs.dart';
import '../../domain/models/models.dart';
import '../../providers/app_state_data.dart';

/// 本地持久化门面。无状态——所有读写直接走 SharedPreferences。
///
/// 用法：
///   - 启动：`final s = LocalStore(prefs).loadMerged(AppStateData.initial());`
///   - 突变后：`LocalStore(prefs).persist(state);`
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  // ── 读：合并 persisted 与 seed ──

  /// 把 persisted 切片并入 seed。每片独立判断：persisted 存在则覆盖 seed 该片。
  ///
  /// 语义：
  ///   - 首次启动（无任何 kv_* key）→ 全用 seed（mock 演示数据）。
  ///   - 用户互动后（至少一个 kv_* 已写）→ 该片用 persisted；未写过的片仍用 seed。
  ///   - 「清空」操作也会写 kv_*（写空集合/空列表），所以清空状态能跨会话保留——
  ///     不会被 seed 重新塞回演示数据。这是关键：用 _containsKey 区分「未写过」与「写过空」。
  AppStateData loadMerged(AppStateData seed) {
    return seed.copyWith(
      likedItemIds: _readIdSet(PrefsKeys.kvLikedIds) ?? seed.likedItemIds,
      savedProjectIds:
          _readIdSet(PrefsKeys.kvSavedProjectIds) ?? seed.savedProjectIds,
      followedUserIds:
          _readIdSet(PrefsKeys.kvFollowedUserIds) ?? seed.followedUserIds,
      notInterestedIds:
          _readIdSet(PrefsKeys.kvNotInterestedIds) ?? seed.notInterestedIds,
      browseHistory:
          _readStringList(PrefsKeys.kvBrowseHistory) ?? seed.browseHistory,
      unreadNotifIds:
          _readIdSet(PrefsKeys.kvUnreadNotifIds) ?? seed.unreadNotifIds,
      recentSearchesMap:
          _readRecentSearches() ?? seed.recentSearchesMap,
      savedTakeaways: _readTakeaways() ?? seed.savedTakeaways,
      fontScale: _prefs.getString(PrefsKeys.kvFontScale) ?? seed.fontScale,
      paperTexture:
          _prefs.getBool(PrefsKeys.kvPaperTexture) ?? seed.paperTexture,
      dndEnabled: _prefs.getBool(PrefsKeys.kvDndEnabled) ?? seed.dndEnabled,
    );
  }

  // ── 写：全量落盘 ──
  // 每次突变后调用。SharedPreferences.setStringList/setString/setBool 是异步的，
  // 但 in-memory 缓存同步更新；fire-and-forget 即可，下一会话必能读回。
  void persist(AppStateData s) {
    _prefs.setStringList(PrefsKeys.kvLikedIds, s.likedItemIds.toList());
    _prefs.setStringList(
        PrefsKeys.kvSavedProjectIds, s.savedProjectIds.toList());
    _prefs.setStringList(
        PrefsKeys.kvFollowedUserIds, s.followedUserIds.toList());
    _prefs.setStringList(
        PrefsKeys.kvNotInterestedIds, s.notInterestedIds.toList());
    _prefs.setStringList(PrefsKeys.kvBrowseHistory, s.browseHistory);
    _prefs.setStringList(
        PrefsKeys.kvUnreadNotifIds, s.unreadNotifIds.toList());
    _writeRecentSearches(s.recentSearchesMap);
    _writeTakeaways(s.savedTakeaways);
    _prefs.setString(PrefsKeys.kvFontScale, s.fontScale);
    _prefs.setBool(PrefsKeys.kvPaperTexture, s.paperTexture);
    _prefs.setBool(PrefsKeys.kvDndEnabled, s.dndEnabled);
  }

  // ── 内部：读 ──

  /// 读 ID 集合。未写过返回 null（让 seed 兜底）；写过空列表返回空 Set。
  Set<String>? _readIdSet(String key) {
    if (!_prefs.containsKey(key)) return null;
    return _prefs.getStringList(key)?.toSet() ?? <String>{};
  }

  /// 读字符串列表。未写过返回 null。
  List<String>? _readStringList(String key) {
    if (!_prefs.containsKey(key)) return null;
    return _prefs.getStringList(key) ?? const [];
  }

  /// 读最近搜索 Map<String,int>。未写过返回 null。
  Map<String, int>? _readRecentSearches() {
    final raw = _prefs.getString(PrefsKeys.kvRecentSearches);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      return {
        for (final e in m.entries)
          if (e.key is String && e.value is int) e.key as String: e.value as int,
      };
    } catch (_) {
      return null; // 脏 JSON → 退 seed
    }
  }

  /// 读「我拿走的」列表。未写过返回 null。
  List<SavedTakeaway>? _readTakeaways() {
    final raw = _prefs.getString(PrefsKeys.kvSavedTakeaways);
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return null;
      return [
        for (final m in list)
          if (m is Map) _takeawayFromMap(Map<String, dynamic>.from(m)),
      ];
    } catch (_) {
      return null;
    }
  }

  // ── 内部：写 ──

  void _writeRecentSearches(Map<String, int> m) {
    _prefs.setString(
      PrefsKeys.kvRecentSearches,
      jsonEncode({for (final e in m.entries) e.key: e.value}),
    );
  }

  void _writeTakeaways(List<SavedTakeaway> list) {
    _prefs.setString(
      PrefsKeys.kvSavedTakeaways,
      jsonEncode([for (final t in list) _takeawayToMap(t)]),
    );
  }

  // ── SavedTakeaway 手动序列化（免 codegen）──

  static Map<String, dynamic> _takeawayToMap(SavedTakeaway t) => {
        'id': t.id,
        'projectId': t.projectId,
        'projectTitle': t.projectTitle,
        'domain': t.domain,
        'kind': t.kind,
        'source': t.source,
        if (t.label != null) 'label': t.label,
        'savedAtMs': t.savedAtMs,
      };

  static SavedTakeaway _takeawayFromMap(Map<String, dynamic> m) => SavedTakeaway(
        id: m['id'] as String,
        projectId: m['projectId'] as String,
        projectTitle: m['projectTitle'] as String,
        domain: m['domain'] as String,
        kind: m['kind'] as String,
        source: m['source'] as String,
        label: m['label'] as String?,
        savedAtMs: m['savedAtMs'] as int,
      );
}

/// LocalStore provider——读 prefsProvider（main 里 override 注入）。
/// AppStateNotifier 用它 loadMerged + persist。
final localStoreProvider = Provider<LocalStore>(
  (ref) => LocalStore(ref.watch(prefsProvider)),
);
