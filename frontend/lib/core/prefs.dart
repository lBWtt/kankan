// 这个文件是干什么的：提供全局唯一的 SharedPreferences 实例 + 持久化用的 key 常量。
// 它对应产品里的什么功能：登录令牌/用户的本地持久化（web 刷新页面不掉登录）。
// 如果它出错了：prefsProvider 没在 main override → 读它直接抛（提醒接线漏了）。
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局 SharedPreferences。main() 里 `await SharedPreferences.getInstance()` 后
/// 用 override 注入（这样各 provider 可同步读，不用到处 await）。
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider 必须在 main() 里 override 注入'),
);

/// 游客稳定 ID：主信号（想看怎么做，游客可用，红线不设登录墙）+ 登录归并用。
/// 首次生成后持久化，跨会话/刷新不变；登录时带上它让后端把游客记录归并进账号。
final anonClientIdProvider = Provider<String>(
  (ref) => _getOrCreateAnonId(ref.watch(prefsProvider)),
);

String _getOrCreateAnonId(SharedPreferences prefs) {
  var id = prefs.getString(PrefsKeys.anonClientId);
  if (id == null || id.isEmpty) {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = Random().nextInt(1 << 32).toRadixString(36);
    id = 'anon-$ts-$rnd'; // ≤64 字符，满足后端约束
    prefs.setString(PrefsKeys.anonClientId, id);
  }
  return id;
}

/// 持久化 key（集中定义，避免散落拼错）。
class PrefsKeys {
  PrefsKeys._();

  /// access token（Bearer，2h 有效）
  static const accessToken = 'auth_access_token';

  /// refresh token（30d，用于静默换新）
  static const refreshToken = 'auth_refresh_token';

  /// 当前登录用户的最小 JSON（{id,name,avatar,bio}），恢复登录态 UI 用
  static const authUser = 'auth_user';

  /// 游客稳定 ID（主信号 how-to-interest 归属 + 登录归并）
  static const anonClientId = 'anon_client_id';

  // ── 任务 A:草稿恢复（发动态 compose / 发项目 publish）──
  // 存 JSON:文本类字段（媒体不存——web 的 blob URL 刷新失效）。
  // 成功发布后删除（已发的不该再当草稿弹出来）。
  // 用 draft_ 前缀避与 auth_* / anon_client_id 冲突。

  /// compose 草稿 JSON:{content, tags}
  static const draftCompose = 'draft_compose';

  /// publish 草稿 JSON:{title, summary, authorNote, text, tags, domain}
  static const draftPublish = 'draft_publish';

  // ── P0-2 本地持久化：用户可变 state 切片 ──
  // 草稿已由 draft_* 覆盖；这里是「我拿走的 / 浏览历史 / 最近搜索 /
  // 不感兴趣 / 偏好设置 / 游客点赞收藏关注 / 通知未读」——重启不丢。
  // 合并策略（LocalStore.loadMerged）：persisted 存在则用 persisted，否则用 mock 种子。
  // 用 kv_ 前缀避与 auth_* / draft_* 冲突。

  /// 点赞过的项目/动态 ID 列表（List<String>）。游客点赞也能跨会话保留。
  static const kvLikedIds = 'kv_liked_ids';

  /// 收藏的项目 ID 列表。登录态另有后端回填（_loadFavoritesFromBackend）。
  static const kvSavedProjectIds = 'kv_saved_project_ids';

  /// 关注的用户 ID 列表。登录态另有后端回填。
  static const kvFollowedUserIds = 'kv_followed_user_ids';

  /// 「不感兴趣」ID 列表（单向 add）。
  static const kvNotInterestedIds = 'kv_not_interested_ids';

  /// 浏览历史（List<String>，最新在前，最多 50）。
  static const kvBrowseHistory = 'kv_browse_history';

  /// 通知未读 ID 列表。
  static const kvUnreadNotifIds = 'kv_unread_notif_ids';

  /// 最近搜索词 JSON：{query: tsMs}（Map<String,int> 序列化）。
  static const kvRecentSearches = 'kv_recent_searches';

  /// 「我拿走的」JSON：[{id,projectId,projectTitle,domain,kind,source,label,savedAtMs}]。
  static const kvSavedTakeaways = 'kv_saved_takeaways';

  // ── 偏好设置（settings 屏读写，重启生效）──

  /// 字号：'小'/'标准'/'大'/'特大'。
  static const kvFontScale = 'kv_font_scale';

  /// 暖纸底纹开关。
  static const kvPaperTexture = 'kv_paper_texture';

  /// 免打扰开关。
  static const kvDndEnabled = 'kv_dnd_enabled';
}
