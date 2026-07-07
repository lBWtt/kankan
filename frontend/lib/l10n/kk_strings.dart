// P2-i18n:看看 app 字符串 SSOT(手写方案,免 codegen)。
//
// 设计依据(用户:"未来会用英文,但不准备第一次就上线,接口之类的留好就行"):
//   - 不依赖 flutter gen-l10n(沙箱无 flutter SDK 也能编译;CI 跑 gen-l10n 也不冲突);
//   - 同名 key 与 lib/l10n/app_zh.arb / app_en.arb 并行维护 — arb 是切 gen-l10n
//     时的输入,kk_strings.dart 是当前运行的输出,两边 key 同名同语义;
//   - 当前 zh 默认,en 是 stub(不暴露给用户:app.dart locale 写死 zh);
//   - 切 gen-l10n 时:删本文件,改用 `AppLocalizations.of(context)!.xxx`,
//     app.dart 的 localizationsDelegates 改为 AppLocalizations.localizationsDelegates,
//     调用方把 `ref.watch(kkStringsProvider).xxx` 改为
//     `AppLocalizations.of(context)!.xxx`(1 文件替换 + 调用点改 import)。
//
// 已迁移的调用点(参考实现):
//   - lib/core/widgets/kk_tab_bar.dart:底栏 4 Tab 标签(discoverTab / kankanTab /
//     libraryTab / meTab)。
//
// 未迁移(按需逐步搬):
//   - lib/ 内 ~27k 行硬编码中文字面量。本文件先暴露 30 个最高频 key 证明模式可用;
//     其余按需逐批迁移到 KkStrings,迁移时同步加 arb 条目保持对齐。
//
// 命名约定:getter 名 = arb key(camelCase);含占位符的用方法(如
// projectSemantic(title))— 切 gen-l10n 时方法签名兼容(ARB 的 {placeholder}
// 也变成方法参数)。

import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 看看 app 字符串集合(不可变)。
///
/// 两种实例:
///   - [KkStrings.zh]:中文(默认,当前 app 唯一对外暴露的 locale)。
///   - [KkStrings.en]:英文 stub(预留接口,文案已对齐 zh 全部 key;切 en 上线
///     时一行 locale 改动即生效)。
class KkStrings {
  /// 中文(默认)。
  const KkStrings.zh() : _v = _zhValues;

  /// 英文 stub(预留接口,当前不暴露)。
  const KkStrings.en() : _v = _enValues;

  final Map<String, String> _v;

  // ── App 标题 ──

  /// MaterialApp.title / 顶栏标题(arb: appTitle)。
  String get appTitle => _v['appTitle']!;

  // ── 底栏 4 Tab ──

  /// 底栏 Tab 1(arb: discoverTab)。
  String get discoverTab => _v['discoverTab']!;

  /// 底栏 Tab 2(arb: kankanTab)。
  String get kankanTab => _v['kankanTab']!;

  /// 底栏 Tab 3(arb: libraryTab)。
  String get libraryTab => _v['libraryTab']!;

  /// 底栏 Tab 4(arb: meTab)。
  String get meTab => _v['meTab']!;

  // ── 通用动作(多用于 icon-only 按钮的 semanticLabel)──

  /// 发布动作(arb: publish)。
  String get publish => _v['publish']!;

  /// 搜索动作(arb: search)。
  String get search => _v['search']!;

  /// 收藏动作(arb: save)。
  String get save => _v['save']!;

  /// 点赞动作(arb: like)。
  String get like => _v['like']!;

  /// 评论动作(arb: comment)。
  String get comment => _v['comment']!;

  /// 分享动作(arb: share)。
  String get share => _v['share']!;

  /// 关注(未关注态,arb: follow)。
  String get follow => _v['follow']!;

  /// 已关注(关注态,arb: unfollow)。
  String get unfollow => _v['unfollow']!;

  /// 删除动作(arb: delete)。
  String get delete => _v['delete']!;

  /// 取消(arb: cancel)。
  String get cancel => _v['cancel']!;

  /// 确定(arb: confirm)。
  String get confirm => _v['confirm']!;

  /// 重试(arb: retry)。
  String get retry => _v['retry']!;

  /// 榜单(看看页顶栏榜单图标 semanticLabel,arb: ranking)。
  String get ranking => _v['ranking']!;

  // ── 空状态 ──

  /// feed 空状态(arb: emptyFeed)。
  String get emptyFeed => _v['emptyFeed']!;

  /// 通用空状态(arb: emptyGeneric)。
  String get emptyGeneric => _v['emptyGeneric']!;

  /// 搜索结果空状态(arb: emptySearch)。
  String get emptySearch => _v['emptySearch']!;

  // ── 错误状态 ──

  /// 加载失败兜底(arb: loadFailed)。
  String get loadFailed => _v['loadFailed']!;

  /// 连不上服务器(RemoteError message,arb: connectFailed)。
  String get connectFailed => _v['connectFailed']!;

  // ── 含占位符的(方法,与 arb 的 {placeholder} 对应)──

  /// 项目卡整体无障碍标签(arb: projectSemantic = "项目:{title}" /
  /// "Project: {title}")。读屏会念「项目: <标题>」。
  String projectSemantic(String title) =>
      _v['projectSemantic']!.replaceAll('{title}', title);

  /// 动态卡整体无障碍标签(arb: postSemantic = "动态:{author}" /
  /// "Post: {author}")。
  String postSemantic(String author) =>
      _v['postSemantic']!.replaceAll('{author}', author);

  // ── 中文(默认)── 与 lib/l10n/app_zh.arb 同步维护。
  static const Map<String, String> _zhValues = <String, String>{
    'appTitle': '看看',
    'discoverTab': '发现',
    'kankanTab': '看看',
    'libraryTab': '收藏',
    'meTab': '我的',
    'publish': '发布',
    'search': '搜索',
    'save': '收藏',
    'like': '点赞',
    'comment': '评论',
    'share': '分享',
    'follow': '关注',
    'unfollow': '已关注',
    'delete': '删除',
    'cancel': '取消',
    'confirm': '确定',
    'retry': '重试',
    'ranking': '榜单',
    'emptyFeed': '这里还没有内容',
    'emptyGeneric': '什么都没找到',
    'emptySearch': '搜不到相关内容',
    'loadFailed': '加载失败',
    'connectFailed': '连不上服务器',
    'projectSemantic': '项目:{title}',
    'postSemantic': '动态:{author}',
  };

  // ── 英文 stub(用户:"未来会用英文,但不准备第一次就上线")──
  // 当前不暴露给用户(app.dart locale 写死 zh)。完整保留 zh 全部 key,
  // 切 en 时一行 locale 改动即生效。文案为 stub,正式上线前需 native speaker 校对。
  // 与 lib/l10n/app_en.arb 同步维护。
  static const Map<String, String> _enValues = <String, String>{
    'appTitle': 'Kankan',
    'discoverTab': 'Discover',
    'kankanTab': 'Kankan',
    'libraryTab': 'Library',
    'meTab': 'Me',
    'publish': 'Publish',
    'search': 'Search',
    'save': 'Save',
    'like': 'Like',
    'comment': 'Comment',
    'share': 'Share',
    'follow': 'Follow',
    'unfollow': 'Following',
    'delete': 'Delete',
    'cancel': 'Cancel',
    'confirm': 'Confirm',
    'retry': 'Retry',
    'ranking': 'Rankings',
    'emptyFeed': 'Nothing here yet',
    'emptyGeneric': 'Nothing found',
    'emptySearch': 'No results found',
    'loadFailed': 'Failed to load',
    'connectFailed': 'Cannot reach server',
    'projectSemantic': 'Project: {title}',
    'postSemantic': 'Post: {author}',
  };
}

/// P2-i18n:当前 locale provider。
///
/// 当前写死 zh(用户:"未来会用英文,但不准备第一次就上线")。
/// 切英文上线时:
///   1) 接 settings 层的 toggleProvider 改这里(如 `StateProvider<Locale>`);
///   2) app.dart 的 locale 改 `ref.watch(kkLocaleProvider)`;
///   3) [kkStringsProvider] 自动重算 → 全 UI 切 en。
final kkLocaleProvider = Provider<Locale>((ref) => const Locale('zh'));

/// P2-i18n:字符串 SSOT provider。按当前 locale 返回对应 [KkStrings]。
///
/// 用法:`final s = ref.watch(kkStringsProvider); s.discoverTab`。
///
/// 切 gen-l10n 时:删本文件,调用方改为
/// `AppLocalizations.of(context)!.discoverTab`。
final kkStringsProvider = Provider<KkStrings>((ref) {
  final locale = ref.watch(kkLocaleProvider);
  return locale.languageCode == 'en' ? KkStrings.en() : KkStrings.zh();
});
