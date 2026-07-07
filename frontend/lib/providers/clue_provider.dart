import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/prefs.dart';
import '../core/utils/backend_id.dart';
import '../data/api/interactions_api.dart';
import '../domain/models/models.dart';
import '../domain/repositories/project_repository.dart';
import 'auth_provider.dart';

/// 实现线索(Implementation Clue)— ZAI_PLAYBOOK P0 主信号下游的网络层。
///
/// **归属**:Claude 的网络层车道(ZAI_PLAYBOOK Part 1)。zai 只消费本文件导出
/// 的 provider / 模型,不写网络代码。当前为 mock 实现(无真实后端),
/// Phase 5 接 SDK 时替换本文件内部,上层 [ImplementationClueScreen] 不动
/// (依赖倒置,与 ProjectRepository 同思路)。
///
/// 后端契约(待接):
///   - GET  /projects/{id}/implementation-clue  → ClueData
///   - POST /projects/{id}/how-to-interest      → { count: int }
///   - POST /projects/{id}/clue-subscription    → 订阅
///   - DELETE /projects/{id}/clue-subscription  → 取消订阅

// ──────────────────────────────────────────────────────────────────
// Domain 模型 — ClueData(ZAI_PLAYBOOK Part 4 数据契约)
// ──────────────────────────────────────────────────────────────────

/// 实现线索数据。告诉用户这个 AI 作品「怎么做出来的」:
/// 来源 / 工具 / AI 推测思路 / 相关作品 / 想看怎么做计数 / 是否订阅。
///
/// 用 plain immutable class(非 freezed):本模型由网络层独占,不需要 codegen,
/// 避免沙箱无 Dart SDK 跑 build_runner 的限制。字段与 ZAI_PLAYBOOK Part 4
/// 契约一致,zai 按 [ImplementationClueScreen] 渲染。
@immutable
class ClueData {
  final String projectId;

  /// 原作来源链接(可空)
  final String? sourceUrl;

  /// 来源平台,如 "小红书" / "GitHub"(可空)
  final String? sourcePlatform;

  /// 原作者名(可空)
  final String? originalAuthorName;

  /// 原作者主页(可空)
  final String? originalAuthorUrl;

  /// 用到的工具,如 ["Midjourney","Photoshop"]
  final List<String> tools;

  /// AI 推测的实现思路(可空,展示时必须标注「AI 推测」— 合规铁律)
  final String? aiImplementationHint;

  /// 相关作品(复用现有 Project 模型 + ProjectCard 渲染)
  final List<Project> relatedProjects;

  /// 「想看怎么做」累计人数
  final int howToInterestCount;

  /// 当前用户是否已订阅线索更新(游客恒 false)
  final bool isSubscribed;

  const ClueData({
    required this.projectId,
    this.sourceUrl,
    this.sourcePlatform,
    this.originalAuthorName,
    this.originalAuthorUrl,
    this.tools = const [],
    this.aiImplementationHint,
    this.relatedProjects = const [],
    this.howToInterestCount = 0,
    this.isSubscribed = false,
  });

  ClueData copyWith({
    String? projectId,
    String? sourceUrl,
    String? sourcePlatform,
    String? originalAuthorName,
    String? originalAuthorUrl,
    List<String>? tools,
    String? aiImplementationHint,
    List<Project>? relatedProjects,
    int? howToInterestCount,
    bool? isSubscribed,
  }) =>
      ClueData(
        projectId: projectId ?? this.projectId,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        sourcePlatform: sourcePlatform ?? this.sourcePlatform,
        originalAuthorName: originalAuthorName ?? this.originalAuthorName,
        originalAuthorUrl: originalAuthorUrl ?? this.originalAuthorUrl,
        tools: tools ?? this.tools,
        aiImplementationHint: aiImplementationHint ?? this.aiImplementationHint,
        relatedProjects: relatedProjects ?? this.relatedProjects,
        howToInterestCount: howToInterestCount ?? this.howToInterestCount,
        isSubscribed: isSubscribed ?? this.isSubscribed,
      );
}

// ──────────────────────────────────────────────────────────────────
// Mock 线索数据(网络层内部,不进 mock_seed.dart — 保持 FIXLOG_F 干净)
// ──────────────────────────────────────────────────────────────────

/// 一条 mock 线索的静态部分(来源 / 工具 / AI 思路 / 相关项目 ID)。
/// 计数与订阅态是交互态,由 [ClueInteractionNotifier] 持有,不写死在这。
class _MockClue {
  final String? sourceUrl;
  final String? sourcePlatform;
  final String? originalAuthorName;
  final String? originalAuthorUrl;
  final List<String> tools;
  final String? aiImplementationHint;
  final List<String> relatedProjectIds;

  const _MockClue({
    this.sourceUrl,
    this.sourcePlatform,
    this.originalAuthorName,
    this.originalAuthorUrl,
    this.tools = const [],
    this.aiImplementationHint,
    this.relatedProjectIds = const [],
  });
}

/// 「想看怎么做」初始累计(mock)。真实场景后端返回,这里写死真实数字
/// (HANDOFF §6.10 禁 ×200 编造,这里照办:给真实小数,不放大)。
const Map<String, int> _mockHowToCounts = {
  'p_aiimg_1': 48,
  'p_aiimg_2': 12,
  'p_aivid_1': 23,
  'p_aivid_2': 7,
  'p_web_1': 156,
  'p_web_2': 31,
  'p_app_1': 19,
  'p_app_2': 41,
  'p_tool_1': 64,
  'p_tool_2': 8,
  'p_repo_1': 102,
  'p_repo_2': 27,
  'p_prompt_1': 89,
  'p_prompt_2': 14,
};

/// 每条线索的静态内容。只给有代表性的项目配齐;未配的项目 → 各字段空,
/// clue 屏会按 SPEC §3 隐藏对应区块(全空 → EmptyState)。
const Map<String, _MockClue> _mockClue = {
  'p_aiimg_1': _MockClue(
    sourceUrl: 'https://www.xiaohongshu.com/explore/clue_aiimg_1',
    sourcePlatform: '小红书',
    originalAuthorName: '林夕的画板',
    originalAuthorUrl: 'https://www.xiaohongshu.com/user/linxi',
    tools: ['Midjourney', 'Photoshop', 'Topaz Gigapixel'],
    aiImplementationHint:
        '先用 Midjourney 跑出基础构图与光影,再用 Photoshop 做 inpainting 修补手部细节,'
        '最后 Topaz Gigapixel 放大并锐化。关键在 prompt 里锁死 --ar 3:4 与 --stylize 250,'
        '保证系列图风格统一。',
    relatedProjectIds: ['p_aiimg_2', 'p_prompt_1'],
  ),
  'p_aivid_1': _MockClue(
    sourceUrl: 'https://github.com/example/clue_aivid_1',
    sourcePlatform: 'GitHub',
    originalAuthorName: 'motion_lab',
    originalAuthorUrl: 'https://github.com/motion-lab',
    tools: ['Runway Gen-3', 'After Effects', 'DaVinci Resolve'],
    aiImplementationHint:
        'Runway Gen-3 生成 5 秒素材片段,After Effects 拼接 + 加转场,DaVinci 调色统一。'
        'prompt 用镜头语言描述运镜(push in / dolly),比描述画面本身更出片。',
    relatedProjectIds: ['p_aivid_2', 'p_aiimg_1'],
  ),
  'p_web_1': _MockClue(
    sourceUrl: 'https://github.com/example/clue_web_1',
    sourcePlatform: 'GitHub',
    originalAuthorName: 'chen_dev',
    originalAuthorUrl: 'https://github.com/chen-dev',
    tools: ['Next.js', 'Vercel', 'Claude', 'Tailwind'],
    aiImplementationHint:
        'Claude 生成主体组件与 API 路由,人工接数据库 schema 与鉴权。'
        'Vercel 一键部署,Tailwind 调样式。整套从想法到上线约 4 小时。',
    relatedProjectIds: ['p_web_2', 'p_app_1', 'p_repo_1'],
  ),
  'p_tool_1': _MockClue(
    sourceUrl: 'https://github.com/example/clue_tool_1',
    sourcePlatform: 'GitHub',
    originalAuthorName: 'ffmpeg_hacks',
    originalAuthorUrl: 'https://github.com/ffmpeg-hacks',
    tools: ['Python', 'FFmpeg', 'Click'],
    aiImplementationHint:
        'Python + Click 做 CLI 入口,FFmpeg 做实际的字幕烧录与转码。'
        '关键是 -filter_complex 把字幕轨叠加到视频轨,避免两遍编码。',
    relatedProjectIds: ['p_tool_2', 'p_repo_1'],
  ),
  'p_repo_1': _MockClue(
    sourceUrl: 'https://github.com/example/clue_repo_1',
    sourcePlatform: 'GitHub',
    originalAuthorName: 'bun_enthusiast',
    originalAuthorUrl: 'https://github.com/bun-enthusiast',
    tools: ['TypeScript', 'Bun', 'Hono'],
    aiImplementationHint:
        'Bun 原生跑 TypeScript 无需编译,Hono 提供 Web 框架。整套是单文件 server,'
        '部署直接 bun run。比 Node + Express 链路短很多。',
    relatedProjectIds: ['p_repo_2', 'p_web_1'],
  ),
  'p_prompt_1': _MockClue(
    sourceUrl: 'https://www.xiaohongshu.com/explore/clue_prompt_1',
    sourcePlatform: '小红书',
    originalAuthorName: 'prompt_craft',
    originalAuthorUrl: 'https://www.xiaohongshu.com/user/promptcraft',
    tools: ['ChatGPT', 'Claude'],
    aiImplementationHint:
        '用 role-play 框架:先让模型扮演资深编辑,再给评分维度,最后要求按维度逐条改写。'
        '比直接「帮我改好」出片率高很多。',
    relatedProjectIds: ['p_prompt_2', 'p_aiimg_1'],
  ),
  'p_aiimg_2': _MockClue(
    sourceUrl: 'https://www.xiaohongshu.com/explore/clue_aiimg_2',
    sourcePlatform: '小红书',
    originalAuthorName: '节气画师阿青',
    originalAuthorUrl: 'https://www.xiaohongshu.com/user/qing',
    tools: ['Stable Diffusion', 'ControlNet', 'Photoshop'],
    aiImplementationHint:
        'SDXL 基础出图 + ControlNet 锁线稿构图,保证 12 张节气图人物姿态一致。'
        'Photoshop 统一调色温与饱和度,让系列感成立。关键是 seed 锁死后只微调 prompt。',
    relatedProjectIds: ['p_aiimg_1', 'p_prompt_1'],
  ),
  'p_aivid_2': _MockClue(
    sourceUrl: 'https://github.com/example/clue_aivid_2',
    sourcePlatform: 'GitHub',
    originalAuthorName: 'ink_motion',
    originalAuthorUrl: 'https://github.com/ink-motion',
    tools: ['Kling', 'After Effects', 'Pr'],
    aiImplementationHint:
        'Kling 生成水墨笔触素材,AE 叠加纸纹与晕染,Pr 做节奏剪辑。'
        'prompt 用「留白」与「运笔速度」描述比描述画面更出片。',
    relatedProjectIds: ['p_aivid_1', 'p_aiimg_2'],
  ),
  'p_web_2': _MockClue(
    sourceUrl: 'https://github.com/example/clue_web_2',
    sourcePlatform: 'GitHub',
    originalAuthorName: 'portfolio_lab',
    originalAuthorUrl: 'https://github.com/portfolio-lab',
    tools: ['Astro', 'Tailwind', 'Vercel'],
    aiImplementationHint:
        'Astro 静态站 + Tailwind 排版,Vercel 部署。作品页用 view transitions 做切换动效,'
        '比 SPA 路由轻量。MDX 写内容,构建时生成静态页。',
    relatedProjectIds: ['p_web_1', 'p_repo_1'],
  ),
  'p_app_1': _MockClue(
    sourceUrl: 'https://github.com/example/clue_app_1',
    sourcePlatform: 'GitHub',
    originalAuthorName: 'minimal_dev',
    originalAuthorUrl: 'https://github.com/minimal-dev',
    tools: ['Flutter', 'Riverpod', 'Isar'],
    aiImplementationHint:
        'Flutter + Riverpod 状态管理,Isar 做本地数据库(无后端,纯离线记账)。'
        '重点是交互极简:记一笔最多 2 次点击,靠快捷分类 + 金额自动识别。',
    relatedProjectIds: ['p_app_2', 'p_tool_1'],
  ),
  'p_app_2': _MockClue(
    sourceUrl: 'https://www.xiaohongshu.com/explore/clue_app_2',
    sourcePlatform: '小红书',
    originalAuthorName: 'focus_craft',
    originalAuthorUrl: 'https://www.xiaohongshu.com/user/focuscraft',
    tools: ['React Native', 'Expo', 'Reanimated'],
    aiImplementationHint:
        'RN + Expo 托管构建,Reanimated 做番茄钟翻转动画。'
        '白噪音用 expo-av 本地音频,不依赖网络。重点是打断提醒用 haptic 反馈。',
    relatedProjectIds: ['p_app_1', 'p_prompt_2'],
  ),
  'p_tool_2': _MockClue(
    sourceUrl: 'https://github.com/example/clue_tool_2',
    sourcePlatform: 'GitHub',
    originalAuthorName: 'md_to_pdf',
    originalAuthorUrl: 'https://github.com/md-to-pdf',
    tools: ['Node.js', 'Pandoc', 'Playwright'],
    aiImplementationHint:
        'Pandoc 转 MD → HTML,Playwright 无头浏览器打印成 PDF(保证代码块与图片渲染一致)。'
        'Node 做 CLI 包装与配置合并。比 wkhtmltopdf 渲染现代 CSS 强很多。',
    relatedProjectIds: ['p_tool_1', 'p_repo_2'],
  ),
  'p_repo_2': _MockClue(
    sourceUrl: 'https://github.com/example/clue_repo_2',
    sourcePlatform: 'GitHub',
    originalAuthorName: 'rn_perf',
    originalAuthorUrl: 'https://github.com/rn-perf',
    tools: ['TypeScript', 'React Native', 'Flipper'],
    aiImplementationHint:
        'Hook 到 RN bridge 层抓 JS/native 调用耗时,Flipper 插件可视化。'
        '关键是 list 渲染用 FlashList 替代 FlatMap,渲染耗时降 60%。',
    relatedProjectIds: ['p_repo_1', 'p_app_2'],
  ),
  'p_prompt_2': _MockClue(
    sourceUrl: 'https://www.xiaohongshu.com/explore/clue_prompt_2',
    sourcePlatform: '小红书',
    originalAuthorName: 'writing_with_ai',
    originalAuthorUrl: 'https://www.xiaohongshu.com/user/writingai',
    tools: ['Claude', 'Notion AI'],
    aiImplementationHint:
        'Claude 做主体写作,Notion AI 做润色与排版建议。'
        'prompt 用「先列大纲再填充」的两步法,比一次性生成结构清晰很多。',
    relatedProjectIds: ['p_prompt_1', 'p_web_2'],
  ),
};

// ──────────────────────────────────────────────────────────────────
// 交互态 — 「想看怎么做」计数 + 订阅(Notifier,与 AppStateNotifier 同思路)
// ──────────────────────────────────────────────────────────────────

/// 线索交互态:每项目的「想看怎么做」计数 + 订阅集合。
/// 用全局 Notifier(非 family),与 [AppStateNotifier] 同模式,
/// Riverpod 3.x 稳定支持。watch 整个 state,increment/toggle 后自动 rebuild。
@immutable
class ClueInteractionState {
  /// projectId → 累计「想看怎么做」人数
  final Map<String, int> howToCounts;

  /// 已订阅线索更新的项目 ID 集合
  final Set<String> subscribedProjectIds;

  /// 当前用户(本会话内)已点过「想看怎么做」的项目 ID 集合。
  /// 防止同一用户反复点击导致 count 失真(P1 状态一致性修复)。
  /// mock 下用户恒 'me',真实场景此集合应来自后端「我是否已标记」。
  final Set<String> markedProjectIds;

  const ClueInteractionState({
    this.howToCounts = const {},
    this.subscribedProjectIds = const {},
    this.markedProjectIds = const {},
  });

  int howToCount(String projectId) => howToCounts[projectId] ?? 0;

  bool isSubscribed(String projectId) =>
      subscribedProjectIds.contains(projectId);

  /// 当前用户是否已对某项目点过「想看怎么做」。
  bool hasMarked(String projectId) => markedProjectIds.contains(projectId);

  ClueInteractionState copyWith({
    Map<String, int>? howToCounts,
    Set<String>? subscribedProjectIds,
    Set<String>? markedProjectIds,
  }) =>
      ClueInteractionState(
        howToCounts: howToCounts ?? this.howToCounts,
        subscribedProjectIds:
            subscribedProjectIds ?? this.subscribedProjectIds,
        markedProjectIds: markedProjectIds ?? this.markedProjectIds,
      );
}

class ClueInteractionNotifier extends Notifier<ClueInteractionState> {
  @override
  ClueInteractionState build() {
    // 启动载入 mock 初始计数(真实场景后端拉,这里写死)。
    return ClueInteractionState(howToCounts: Map.of(_mockHowToCounts));
  }

  /// 记一次「想看怎么做」(主信号,红线:游客可用,不设登录墙)。返回最新累计数。
  ///
  /// **幂等**:同一用户对同一项目重复调用不会重复 +1(基于 markedProjectIds)。
  /// 真后端项目(UUID)→ POST /how-to-interest(游客带 anon_client_id),用返回的真计数覆盖;
  /// 后端幂等,失败保留乐观本地值(主信号不因网络抖动丢感知)。mock 项目 → 只本地。
  Future<int> recordHowToInterest(String projectId) async {
    // 幂等守卫:已标记过 → 直接返回当前 count,不 increment。
    if (state.hasMarked(projectId)) {
      return state.howToCount(projectId);
    }
    // 乐观本地 +1(UI 即时响应)
    final nextCounts = Map<String, int>.from(state.howToCounts);
    nextCounts[projectId] = (nextCounts[projectId] ?? 0) + 1;
    final nextMarked = Set<String>.from(state.markedProjectIds)..add(projectId);
    state = state.copyWith(howToCounts: nextCounts, markedProjectIds: nextMarked);

    // 真后端项目 → 落库(游客可用)。用真计数覆盖乐观值。
    if (looksLikeBackendId(projectId)) {
      try {
        final real = await ref.read(interactionsApiProvider).recordHowToInterest(
              projectId,
              anonClientId: ref.read(anonClientIdProvider),
            );
        final c = Map<String, int>.from(state.howToCounts);
        c[projectId] = real;
        state = state.copyWith(howToCounts: c);
        return real;
      } catch (_) {
        // 落库失败:保留乐观本地值,不回滚(已标记幂等,后端下次也不会重复计)。
      }
    }
    return state.howToCount(projectId);
  }

  /// 切换订阅(ZAI_PLAYBOOK Part 4 订阅区)。乐观切换本地态;
  /// 登录 + 真后端项目(UUID)→ 同步 POST/DELETE /clue-subscription,失败回滚。
  /// mock 项目 / 未登录 → 只本地切换(演示,不设登录墙)。
  void toggleSubscription(String projectId) {
    final wasSubscribed = state.subscribedProjectIds.contains(projectId);
    final next = Set<String>.from(state.subscribedProjectIds);
    if (wasSubscribed) {
      next.remove(projectId);
    } else {
      next.add(projectId);
    }
    state = state.copyWith(subscribedProjectIds: next); // 乐观更新
    _syncSubscription(projectId, on: !wasSubscribed);
  }

  /// 订阅落库:登录 + 真后端项目才发请求;失败回滚本地,保持一致。
  Future<void> _syncSubscription(String projectId, {required bool on}) async {
    if (!ref.read(authProvider).isLoggedIn) return;
    if (!looksLikeBackendId(projectId)) return;
    try {
      await ref.read(interactionsApiProvider).setClueSubscription(projectId, on);
    } catch (_) {
      final revert = Set<String>.from(state.subscribedProjectIds);
      if (on) {
        revert.remove(projectId);
      } else {
        revert.add(projectId);
      }
      state = state.copyWith(subscribedProjectIds: revert);
    }
  }
}

final clueInteractionProvider =
    NotifierProvider<ClueInteractionNotifier, ClueInteractionState>(
  () => ClueInteractionNotifier(),
);

// ──────────────────────────────────────────────────────────────────
// Provider 契约(ZAI_PLAYBOOK Part 4)
// ──────────────────────────────────────────────────────────────────

/// 线索主数据 provider。clue 屏 `ref.watch(clueProvider(projectId))`。
///
/// 返回 [ClueData],含静态来源/工具/AI 思路/相关作品,以及交互态快照
/// (howToInterestCount / isSubscribed 取 fetch 时刻值)。屏内若需实时刷新
/// 计数与订阅态,另 `ref.watch(clueInteractionProvider)`(本 provider 不会
/// 在交互态变化时自动 rebuild — 这是刻意的:静态内容不必跟着计数变)。
final clueProvider =
    FutureProvider.family<ClueData, String>((ref, projectId) async {
  // 模拟异步(Phase 5 接 SDK 时是真网络)。
  await Future<void>.delayed(const Duration(milliseconds: 200));
  final repo = ref.read(projectRepositoryProvider);
  final interaction = ref.read(clueInteractionProvider);
  final mock = _mockClue[projectId];

  // 相关作品:按 mock.relatedProjectIds 从 repo 取真实 Project(过滤掉自身
  // 与不存在的)。结果顺序保持 mock 配置顺序(不在原地 sort,先 toList)。
  final related = <Project>[];
  if (mock != null) {
    for (final id in mock.relatedProjectIds) {
      if (id == projectId) continue;
      final p = repo.byId(id);
      if (p != null) related.add(p);
    }
  }

  return ClueData(
    projectId: projectId,
    sourceUrl: mock?.sourceUrl,
    sourcePlatform: mock?.sourcePlatform,
    originalAuthorName: mock?.originalAuthorName,
    originalAuthorUrl: mock?.originalAuthorUrl,
    tools: mock?.tools ?? const [],
    aiImplementationHint: mock?.aiImplementationHint,
    relatedProjects: related,
    howToInterestCount: interaction.howToCount(projectId),
    isSubscribed: interaction.isSubscribed(projectId),
  );
});

/// 主信号:点「想看怎么做」时调(ZAI_PLAYBOOK Part 4)。
/// 返回 `Future<int> Function(String projectId)`,调用即记一次,返回最新累计。
/// 游客可用,不设登录墙。
final howToInterestProvider =
    Provider<Future<int> Function(String projectId)>((ref) {
  return (String projectId) => ref
      .read(clueInteractionProvider.notifier)
      .recordHowToInterest(projectId);
});
