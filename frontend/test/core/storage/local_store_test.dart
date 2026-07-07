// LocalStore 持久化测试。
//
// 沙箱无 flutter SDK——本文件靠 CI (`flutter test`) 验证。
// 用 SharedPreferences.setMockInitialValues 模拟空盘 / 有数据盘。
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/core/prefs.dart';
import 'package:kankan_flutter/core/storage/local_store.dart';
import 'package:kankan_flutter/domain/models/models.dart';
import 'package:kankan_flutter/providers/app_state_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalStore> _storeWith(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return LocalStore(prefs);
}

void main() {
  group('LocalStore.loadMerged — 首启（空盘）', () {
    test('无任何 kv_* key → 全用 seed（mock 演示数据原样返回）', () async {
      final store = await _storeWith({});
      final seed = AppStateData.initial();
      final merged = store.loadMerged(seed);

      // seed 片原样保留（首启无 persisted 覆盖）
      expect(merged.savedTakeaways, seed.savedTakeaways);
      expect(merged.browseHistory, seed.browseHistory);
      expect(merged.recentSearchesMap, seed.recentSearchesMap);
      expect(merged.unreadNotifIds, seed.unreadNotifIds);
      expect(merged.likedItemIds, isEmpty); // seed 默认空
      expect(merged.fontScale, '标准');
      expect(merged.paperTexture, isTrue);
      expect(merged.dndEnabled, isFalse);
    });
  });

  group('LocalStore.loadMerged — 已有 persisted 数据', () {
    test('persisted 覆盖 seed 各片', () async {
      final store = await _storeWith({
        PrefsKeys.kvLikedIds: <String>['p1', 'post-abc'],
        PrefsKeys.kvSavedProjectIds: <String>['proj-1'],
        PrefsKeys.kvFollowedUserIds: <String>['chen'],
        PrefsKeys.kvNotInterestedIds: <String>['bad-1'],
        PrefsKeys.kvBrowseHistory: <String>['h1', 'h2'],
        PrefsKeys.kvUnreadNotifIds: <String>['n1'],
        PrefsKeys.kvRecentSearches: '{"ai":1700000000000,"flutter":1700000001000}',
        PrefsKeys.kvFontScale: '大',
        PrefsKeys.kvPaperTexture: false,
        PrefsKeys.kvDndEnabled: true,
      });
      final merged = store.loadMerged(AppStateData.initial());

      expect(merged.likedItemIds, {'p1', 'post-abc'});
      expect(merged.savedProjectIds, {'proj-1'});
      expect(merged.followedUserIds, {'chen'});
      expect(merged.notInterestedIds, {'bad-1'});
      expect(merged.browseHistory, ['h1', 'h2']);
      expect(merged.unreadNotifIds, {'n1'});
      expect(merged.recentSearchesMap['ai'], 1700000000000);
      expect(merged.recentSearchesMap['flutter'], 1700000001000);
      expect(merged.fontScale, '大');
      expect(merged.paperTexture, isFalse);
      expect(merged.dndEnabled, isTrue);
    });

    test('persisted 空集合覆盖 seed（清空状态跨会话保留，不被 seed 塞回）', () async {
      // kv_* 存在但为空 → loadMerged 应返回空，而非 seed 的 mock 演示数据
      final store = await _storeWith({
        PrefsKeys.kvSavedTakeaways: '[]',
        PrefsKeys.kvBrowseHistory: <String>[],
        PrefsKeys.kvRecentSearches: '{}',
        PrefsKeys.kvUnreadNotifIds: <String>[],
      });
      final seed = AppStateData.initial();
      final merged = store.loadMerged(seed);

      // 关键：清空过的片不会被 seed 重新塞回演示数据
      expect(merged.savedTakeaways, isEmpty);
      expect(merged.browseHistory, isEmpty);
      expect(merged.recentSearchesMap, isEmpty);
      expect(merged.unreadNotifIds, isEmpty);
    });

    test('脏 JSON → 该片退 seed（其它片不受影响）', () async {
      final store = await _storeWith({
        PrefsKeys.kvRecentSearches: 'not-json{',
        PrefsKeys.kvSavedTakeaways: 'broken',
        PrefsKeys.kvFontScale: '特大',
      });
      final seed = AppStateData.initial();
      final merged = store.loadMerged(seed);

      // 脏 JSON 的片退 seed
      expect(merged.recentSearchesMap, seed.recentSearchesMap);
      expect(merged.savedTakeaways, seed.savedTakeaways);
      // 其它片正常读
      expect(merged.fontScale, '特大');
    });
  });

  group('LocalStore.persist → loadMerged 往返', () {
    test('写入后读回等价（SavedTakeaway 含可选 label）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);

      final t1 = SavedTakeaway(
        id: 'p1-0',
        projectId: 'p1',
        projectTitle: 'AI 图一',
        domain: 'ai_image',
        kind: 'text',
        source: 'prompt text here',
        label: '复制提示词',
        savedAtMs: 1700000000000,
      );
      final t2 = SavedTakeaway(
        id: 'p2-0',
        projectId: 'p2',
        projectTitle: '工具',
        domain: 'tool',
        kind: 'link',
        source: 'https://example.com',
        label: null, // 无 label
        savedAtMs: 1700000001000,
      );
      final state = AppStateData(
        likedItemIds: {'a', 'b'},
        savedProjectIds: {'s1'},
        followedUserIds: {'u1'},
        notInterestedIds: {'ni1'},
        browseHistory: ['h1'],
        unreadNotifIds: {'n1'},
        recentSearchesMap: {'q1': 111, 'q2': 222},
        savedTakeaways: [t1, t2],
        fontScale: '大',
        paperTexture: false,
        dndEnabled: true,
      );
      store.persist(state);

      // 用同一 prefs 实例新 store 读回（模拟重启：盘上已有数据）
      final reread = LocalStore(prefs).loadMerged(AppStateData.initial());

      expect(reread.likedItemIds, {'a', 'b'});
      expect(reread.savedProjectIds, {'s1'});
      expect(reread.followedUserIds, {'u1'});
      expect(reread.notInterestedIds, {'ni1'});
      expect(reread.browseHistory, ['h1']);
      expect(reread.unreadNotifIds, {'n1'});
      expect(reread.recentSearchesMap, {'q1': 111, 'q2': 222});
      expect(reread.savedTakeaways.length, 2);
      expect(reread.savedTakeaways[0].id, 'p1-0');
      expect(reread.savedTakeaways[0].label, '复制提示词');
      expect(reread.savedTakeaways[1].label, isNull);
      expect(reread.fontScale, '大');
      expect(reread.paperTexture, isFalse);
      expect(reread.dndEnabled, isTrue);
    });
  });
}
