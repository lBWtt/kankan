import 'package:flutter/material.dart';

import '../data/seed/mock_seed.dart';
import '../domain/models/models.dart';

/// 全局 AppState 的不可变数据载体。
///
/// 抽离到独立文件（P0-2 持久化）：[LocalStore] 需要 [AppStateData] 类型做
/// loadMerged/persist，而 AppStateNotifier 又需要 LocalStore——拆文件破循环 import。
/// [app_state_provider.dart] 用 `export` 透出本类，所有既有 import 路径不变。
///
/// 状态分两类:
///   1. ID 集合(likedItemIds / savedProjectIds / followedUserIds / unreadNotifIds)
///   2. 实体列表(savedTakeaways / browseHistory / recentSearches)— 找回内容用
///
/// 所有计数取真实 Set/List 长度(HANDOFF §6.10,禁 ×200 编造)。
///
/// recentSearches 升级为 Map<String, int>(query → 最近一次时间戳,毫秒),
/// 天然去重 + 时间戳排序。旧 [recentSearches] getter 返回 List<String>
/// (按时间戳降序),向后兼容。新 [recentSearchesWithTime] 返回带时间戳 record。
@immutable
class AppStateData {
  final ThemeMode themeMode;

  /// 当前激活的 branch index(0..3)。
  final int currentTabIndex;

  // ── 点赞(ID 集合,Project / Post 共用同一池,因为 ID 唯一)──
  /// 点赞过的项目/动态 ID 集合
  final Set<String> likedItemIds;

  // ── 收藏(HANDOFF §6.3 收藏页)──
  /// 收藏的项目 ID 集合
  final Set<String> savedProjectIds;

  // ── 关注(HANDOFF §1 二分:关注流是 discover 屏的第二个 tab)──
  /// 关注的用户 ID 集合
  final Set<String> followedUserIds;

  // ── 我拿走的(HANDOFF §6.3 内容库,按 文本/文件/链接 分类)──
  /// 拿走的内容列表(找回库,真存数据)
  final List<SavedTakeaway> savedTakeaways;

  // ── 浏览历史(me 屏可读,Phase 3 完善)──
  /// 最近浏览的项目 ID(最新在前,最多 50 条)
  final List<String> browseHistory;

  // ── 通知未读 ID 集合(HANDOFF §6.8)— 真实长度,不放大 ──
  final Set<String> unreadNotifIds;

  // ── 最近搜索词(search 屏用,Map<String, int> 时间戳)──
  /// query → 最近一次搜索时间戳(毫秒)。Map 天然去重,更新时刷新时间戳。
  final Map<String, int> recentSearchesMap;

  // ── 不感兴趣(任务⑫:负反馈闭环)──
  /// 标记「不感兴趣」的项目/动态 ID 集合(单向 add,不可撤销)。
  /// discover 推荐/关注流 + kankan _mockList 渲染前过滤掉这些 ID。
  /// kankan _remoteList(真数据)不过滤(后端另说)。
  final Set<String> notInterestedIds;

  // ── 偏好设置(真生效,settings 屏读写)──
  /// 字号:'小'/'标准'/'大'/'特大' → app.dart 应用全局 textScaler。
  final String fontScale;

  /// 暖纸底纹开关 → NoiseBackground 读它决定画不画噪点。
  final bool paperTexture;

  /// 免打扰:开 → 通知铃未读红点被抑制(effectiveUnreadCount 归零)。
  final bool dndEnabled;

  /// 我的页 banner 背景图 URL(用户换背景;web 是 image_picker 的 blob URL,
  /// 会话内有效不持久化。null → 用默认暖色渐变)。
  final String? bannerImageUrl;

  const AppStateData({
    this.themeMode = ThemeMode.light,
    this.currentTabIndex = 0,
    this.likedItemIds = const {},
    this.savedProjectIds = const {},
    this.followedUserIds = const {},
    this.savedTakeaways = const [],
    this.browseHistory = const [],
    this.unreadNotifIds = const {},
    this.recentSearchesMap = const {},
    this.notInterestedIds = const {},
    this.fontScale = '标准',
    this.paperTexture = true,
    this.dndEnabled = false,
    this.bannerImageUrl,
  });

  /// 免打扰生效后的未读数:DND 开 → 0(红点消失);否则真实未读数。
  int get effectiveUnreadCount => dndEnabled ? 0 : unreadNotifIds.length;

  /// 字号 → textScaler 倍率。
  double get textScaleFactor => switch (fontScale) {
        '小' => 0.9,
        '大' => 1.15,
        '特大' => 1.3,
        _ => 1.0,
      };

  /// 向后兼容:返回 List<String>(按时间戳降序,最新在前)。
  /// 供 settings_screen(searchCount = .length)/ search_results_screen 等使用。
  List<String> get recentSearches {
    final entries = recentSearchesMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries) e.key];
  }

  /// 带时间戳的最近搜索(按时间戳降序)。
  /// 供 search_screen 时间分组(今天 / 昨天 / 更早)用。
  List<({String query, int createdAtMs})> get recentSearchesWithTime {
    final entries = recentSearchesMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in entries) (query: e.key, createdAtMs: e.value),
    ];
  }

  factory AppStateData.initial() => AppStateData(
        // HANDOFF §6.3:启动即载入 mock 的"我拿走的",library 屏可直接读真实数据。
        savedTakeaways: mockSavedTakeaways,
        // Phase 3:启动载入 mock 通知未读(全部 mock 通知默认未读)+ 浏览历史 + 最近搜索。
        unreadNotifIds: {for (final n in mockNotifications) n.id},
        browseHistory: mockBrowseHistory,
        // recentSearches 升级为 Map<String, int>,mock 词分散到今天/昨天/更早
        // 三段时间区间,让 search_screen 时间分组有真实演示数据。
        recentSearchesMap: _seedRecentSearches(),
      );

  /// 把 mockRecentSearches 6 条词分散到 今天/昨天/更早 三段。
  /// 第 0-1 条:今天(30min / 2h 前);2-3:昨天(26h / 30h 前);4-5:更早(3d / 10d 前)。
  static Map<String, int> _seedRecentSearches() {
    final now = DateTime.now().millisecondsSinceEpoch;
    const hour = 60 * 60 * 1000;
    const day = 24 * hour;
    const offsets = [
      30 * 60 * 1000, // 0:今天 30min 前
      2 * hour, // 1:今天 2h 前
      26 * hour, // 2:昨天 26h 前
      30 * hour, // 3:昨天 30h 前
      3 * day, // 4:更早 3d 前
      10 * day, // 5:更早 10d 前
    ];
    final out = <String, int>{};
    for (var i = 0; i < mockRecentSearches.length; i++) {
      final offset = i < offsets.length ? offsets[i] : day * (i + 1);
      out[mockRecentSearches[i]] = now - offset;
    }
    return out;
  }

  AppStateData copyWith({
    ThemeMode? themeMode,
    int? currentTabIndex,
    Set<String>? likedItemIds,
    Set<String>? savedProjectIds,
    Set<String>? followedUserIds,
    List<SavedTakeaway>? savedTakeaways,
    List<String>? browseHistory,
    Set<String>? unreadNotifIds,
    Map<String, int>? recentSearchesMap,
    Set<String>? notInterestedIds,
    String? fontScale,
    bool? paperTexture,
    bool? dndEnabled,
    String? bannerImageUrl,
  }) =>
      AppStateData(
        themeMode: themeMode ?? this.themeMode,
        currentTabIndex: currentTabIndex ?? this.currentTabIndex,
        likedItemIds: likedItemIds ?? this.likedItemIds,
        savedProjectIds: savedProjectIds ?? this.savedProjectIds,
        followedUserIds: followedUserIds ?? this.followedUserIds,
        savedTakeaways: savedTakeaways ?? this.savedTakeaways,
        browseHistory: browseHistory ?? this.browseHistory,
        unreadNotifIds: unreadNotifIds ?? this.unreadNotifIds,
        recentSearchesMap: recentSearchesMap ?? this.recentSearchesMap,
        notInterestedIds: notInterestedIds ?? this.notInterestedIds,
        fontScale: fontScale ?? this.fontScale,
        paperTexture: paperTexture ?? this.paperTexture,
        dndEnabled: dndEnabled ?? this.dndEnabled,
        bannerImageUrl: bannerImageUrl ?? this.bannerImageUrl,
      );
}
