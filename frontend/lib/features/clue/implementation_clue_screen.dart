import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/noise_background.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/skeletons.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/clue_provider.dart';
import '../shared/empty_state.dart';
import '../shared/project_card.dart';
import '../shared/remote_error.dart';

/// 实现线索页 — ZAI_PLAYBOOK P0 主信号下游落地页。
///
/// 用户在详情页点「想看怎么做」后到达:告诉他这个 AI 作品**怎么做出来的**——
/// 来源 / 工具 / AI 推测思路 / 相关作品,并能订阅后续线索更新。
///
/// **数据契约**:只消费 [clueProvider] / [howToInterestProvider] /
/// [clueInteractionProvider](Claude 的网络层)。本屏不写网络代码。
///
/// **视觉**:与 [DetailScreen] 一致 — 暖纸底 + 衬线标题 + 卡片式区块。
///
/// **铁律**(SPEC §5):
///   - 零旁白(无教学副标题,除 AI 思路那句强制标注「AI 推测」)
///   - 无 emoji
///   - 触控 ≥44pt 走 [Tappable]
///   - 珊瑚橙本屏**不出现**(无 take 场景)
///   - 禁对任何列表原地 `..sort`(本屏不排序)
class ImplementationClueScreen extends ConsumerStatefulWidget {
  final String projectId;

  const ImplementationClueScreen({super.key, required this.projectId});

  @override
  ConsumerState<ImplementationClueScreen> createState() =>
      _ImplementationClueScreenState();
}

class _ImplementationClueScreenState
    extends ConsumerState<ImplementationClueScreen> {
  /// 主信号按钮 tap 进行中(防抖 + 显示 loading)。
  /// 「是否已点」不再用本地 state,改从 [clueInteractionProvider] 的
  /// markedProjectIds 派生(P1 状态一致性修复:退出重进页面 marked 态不丢,
  /// 同一用户反复点击不会重复 +1)。
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    // 埋点:线索页浏览 = 点了「想看怎么做」(漏斗 clue_views)。真后端项目(UUID)才发。
    ref.read(analyticsProvider).track('how_to_interest', projectId: widget.projectId);
  }

  /// 点「想看怎么做」— ZAI_PLAYBOOK Part 4 主信号,游客可用,不设登录墙。
  Future<void> _onHowToTap() async {
    // 幂等守卫:已标记 → 不再触发(provider 层也有守卫,这里提前挡)。
    final alreadyMarked =
        ref.read(clueInteractionProvider).hasMarked(widget.projectId);
    if (alreadyMarked || _marking) return;
    setState(() => _marking = true);
    try {
      final fn = ref.read(howToInterestProvider);
      // 调用即记一次;clueInteractionProvider 自动 rebuild,watch 它的地方
      // 会刷新计数与 marked 态。recordHowToInterest 内部幂等(已标记不 +1)。
      await fn(widget.projectId);
      if (mounted) {
        setState(() => _marking = false);
      }
    } catch (_) {
      if (mounted) setState(() => _marking = false);
    }
  }

  /// 点「订阅线索更新」— ZAI_PLAYBOOK Part 4 订阅区,**登录拦截点**。
  /// mock 下用户恒 'me',直接切换。真实场景:未登录 → 走全局登录流程,
  /// 登录成功后再 toggle。本回调即 onSubscribeTap hook,Claude 接登录 helper。
  void _onSubscribeTap() {
    ref.read(clueInteractionProvider.notifier).toggleSubscription(
          widget.projectId,
        );
  }

  Future<void> _openUrl(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final clueAsync = ref.watch(clueProvider(widget.projectId));
    // 交互态实时 watch:计数 / 订阅态变化即 rebuild。
    final interaction = ref.watch(clueInteractionProvider);
    final count = interaction.howToCount(widget.projectId);
    final marked = interaction.hasMarked(widget.projectId);
    final subscribed = interaction.isSubscribed(widget.projectId);

    return Scaffold(
      backgroundColor: KkColors.bg,
      body: NoiseBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: clueAsync.when(
                  loading: _clueSkeleton,
                  error: (e, _) => RemoteError(
                    message: '线索加载失败',
                    onRetry: () async {
                      ref.invalidate(clueProvider(widget.projectId));
                    },
                  ),
                  data: (clue) => _body(clue, count, marked, subscribed),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 顶栏(KkBackButton + 衬线标题)──
  Widget _topBar() {
    return Container(
      decoration: const BoxDecoration(
        color: KkColors.bg,
        border: Border(bottom: BorderSide(color: KkColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.sm,
        vertical: KkSpacing.sm,
      ),
      child: Row(
        children: [
          const KkBackButton(),
          const SizedBox(width: KkSpacing.xs),
          Text('实现线索', style: KkType.h3),
          const Spacer(),
          // 右侧占位,与详情页顶栏视觉重心平衡(无操作)。
          const SizedBox(width: KkTouch.minTarget),
        ],
      ),
    );
  }

  // ── data 态:6 块从上到下 ──
  Widget _body(ClueData clue, int count, bool marked, bool subscribed) {
    // 整页无线索(所有可选块全空)→ EmptyState(SPEC §3)。
    final hasSource =
        clue.sourceUrl != null || clue.sourcePlatform != null;
    final hasContent = hasSource ||
        clue.tools.isNotEmpty ||
        clue.aiImplementationHint != null ||
        clue.relatedProjects.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.only(bottom: KkSpacing.xxxl),
      children: [
        // 1. 主信号区(永远显示)
        _mainSignal(count, marked),
        // 2–5. 内容区(全空 → EmptyState)
        if (!hasContent)
          const EmptyState(
            variant: EmptyStateVariant.generic,
            title: '暂无线索',
            subtitle: '还没有人补充这个作品的实现线索',
          )
        else ...[
          if (hasSource) _sourceCard(clue),
          if (clue.tools.isNotEmpty) ...[
            const SizedBox(height: KkSpacing.lg),
            _toolsBlock(clue.tools),
          ],
          if (clue.aiImplementationHint != null) ...[
            const SizedBox(height: KkSpacing.lg),
            _aiHintCard(clue.aiImplementationHint!),
          ],
          if (clue.relatedProjects.isNotEmpty) ...[
            const SizedBox(height: KkSpacing.lg),
            _relatedBlock(clue.relatedProjects),
          ],
        ],
        // 6. 订阅区(永远显示)
        const SizedBox(height: KkSpacing.xxl),
        _subscribeBlock(subscribed),
      ],
    );
  }

  // ── 1. 主信号区:大字计数 + 墨绿主按钮 ──
  Widget _mainSignal(int count, bool marked) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.xl,
        KkSpacing.xxl,
        KkSpacing.xl,
        KkSpacing.xl,
      ),
      child: Column(
        children: [
          // 大字计数(Mono)— 「N」
          Text(
            '$count',
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 44,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: KkColors.t1,
            ),
          ),
          const SizedBox(height: KkSpacing.xs),
          // 副标题:有人标记 → 「N 人也想知道怎么做」;无人 → 鼓励先行
          Text(
            count > 0 ? '人也想知道怎么做' : '做个先行者，标记你想看',
            style: KkType.body.copyWith(color: KkColors.t2),
          ),
          const SizedBox(height: KkSpacing.xl),
          // 主按钮:想看怎么做 / 已想看
          _howToButton(marked),
        ],
      ),
    );
  }

  Widget _howToButton(bool marked) {
    final marking = _marking;
    return Tappable(
      onTap: marked ? null : _onHowToTap,
      borderRadius: BorderRadius.circular(KkRadius.pill),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: KkSpacing.lg),
        decoration: BoxDecoration(
          // 墨绿(KkColors.teal)— 主按钮/链接(SPEC §1)。本屏无珊瑚橙。
          color: marked ? KkColors.mint : KkColors.teal,
          border:
              marked ? Border.all(color: KkColors.teal, width: 1.5) : null,
          borderRadius: BorderRadius.circular(KkRadius.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (marking)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                marked ? Icons.check_circle_outline : Icons.lightbulb_outline,
                size: 20,
                color: marked ? KkColors.teal : Colors.white,
              ),
            const SizedBox(width: KkSpacing.sm),
            Text(
              marked ? '已想看' : '想看怎么做',
              style: TextStyle(
                color: marked ? KkColors.teal : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                fontFamily: marked ? 'NotoSerifSC' : 'JetBrainsMono',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 2. 来源卡 ──
  Widget _sourceCard(ClueData clue) {
    final platform = clue.sourcePlatform;
    final url = clue.sourceUrl;
    final authorName = clue.originalAuthorName;
    final authorUrl = clue.originalAuthorUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: _ClueCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 来源行
            Row(
              children: [
                const Icon(Icons.link_outlined, size: 16, color: KkColors.t3),
                const SizedBox(width: KkSpacing.xs),
                Text('来源', style: KkType.bodySm.copyWith(color: KkColors.t3)),
                const SizedBox(width: KkSpacing.sm),
                if (platform != null)
                  Text(
                    platform,
                    style: KkType.body.copyWith(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            if (url != null) ...[
              const SizedBox(height: KkSpacing.sm),
              Tappable(
                onTap: () => _openUrl(url),
                borderRadius: BorderRadius.circular(KkRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: KkSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          url,
                          style: KkType.mono.copyWith(
                            fontSize: 12,
                            color: KkColors.teal,
                            decoration: TextDecoration.underline,
                            decorationColor: KkColors.teal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.open_in_new,
                          size: 14, color: KkColors.teal),
                    ],
                  ),
                ),
              ),
            ],
            // 原作者行(若有)
            if (authorName != null) ...[
              const SizedBox(height: KkSpacing.md),
              const Divider(height: 1, color: KkColors.divider),
              const SizedBox(height: KkSpacing.md),
              Tappable(
                onTap: authorUrl != null ? () => _openUrl(authorUrl) : null,
                borderRadius: BorderRadius.circular(KkRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: KkSpacing.xs),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 16, color: KkColors.t3),
                      const SizedBox(width: KkSpacing.xs),
                      Text('原作者',
                          style: KkType.bodySm.copyWith(color: KkColors.t3)),
                      const SizedBox(width: KkSpacing.sm),
                      Expanded(
                        child: Text(
                          authorName,
                          style: KkType.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: authorUrl != null
                                ? KkColors.teal
                                : KkColors.t1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (authorUrl != null)
                        const Icon(Icons.chevron_right,
                            size: 16, color: KkColors.teal),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 3. 工具清单 ──
  Widget _toolsBlock(List<String> tools) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(text: '用到的工具'),
          const SizedBox(height: KkSpacing.md),
          Wrap(
            spacing: KkSpacing.sm,
            runSpacing: KkSpacing.sm,
            children: [for (final t in tools) _toolChip(t)],
          ),
        ],
      ),
    );
  }

  Widget _toolChip(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        // mint 底 + teal 字(SPEC §1 / Part 4 工具 chip 规范)
        color: KkColors.mint,
        borderRadius: BorderRadius.circular(KkRadius.pill),
      ),
      child: Text(
        name,
        style: const TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: KkColors.teal,
        ),
      ),
    );
  }

  // ── 4. AI 思路卡(顶部强制标注「AI 推测」)──
  Widget _aiHintCard(String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: _ClueCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 强制标注(合规铁律)— 唯一允许的旁白句
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined,
                    size: 14, color: KkColors.t3),
                const SizedBox(width: KkSpacing.xs),
                Text(
                  'AI 推测思路，仅供参考',
                  style: KkType.bodySm.copyWith(color: KkColors.t3),
                ),
              ],
            ),
            const SizedBox(height: KkSpacing.md),
            Text(hint, style: KkType.body.copyWith(height: 1.7)),
          ],
        ),
      ),
    );
  }

  // ── 5. 相关作品(复用 ProjectCard compact 模式)──
  Widget _relatedBlock(List<Project> relatedProjects) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(text: '相关作品'),
          const SizedBox(height: KkSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: KkColors.bgCard,
              borderRadius: BorderRadius.circular(KkRadius.lg),
              border: Border.all(color: KkColors.bd),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < relatedProjects.length; i++) ...[
                  ProjectCard(
                    project: relatedProjects[i],
                    compact: true,
                    showAuthor: false,
                  ),
                  if (i < relatedProjects.length - 1)
                    const Divider(height: 1, color: KkColors.divider),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 6. 订阅区(登录拦截点)──
  Widget _subscribeBlock(bool subscribed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Tappable(
        onTap: _onSubscribeTap,
        borderRadius: BorderRadius.circular(KkRadius.md),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: KkSpacing.lg),
          decoration: BoxDecoration(
            // 已订阅 → 描边态;未订阅 → 墨绿浅底
            color: subscribed ? Colors.transparent : KkColors.mint,
            border: Border.all(
              color: subscribed ? KkColors.bd : KkColors.teal.withOpacity(0.3),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(KkRadius.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                subscribed
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none_outlined,
                size: 18,
                color: subscribed ? KkColors.t2 : KkColors.teal,
              ),
              const SizedBox(width: KkSpacing.sm),
              Text(
                subscribed ? '已订阅' : '订阅线索更新',
                style: TextStyle(
                  color: subscribed ? KkColors.t2 : KkColors.teal,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'NotoSerifSC',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── loading 态:骨架屏 ──
  Widget _clueSkeleton() {
    return ListView(
      padding: const EdgeInsets.only(bottom: KkSpacing.xxxl),
      children: [
        // 主信号区骨架:大数字 + 标签 + 按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KkSpacing.xl,
            KkSpacing.xxl,
            KkSpacing.xl,
            KkSpacing.xl,
          ),
          child: Column(
            children: [
              SkeletonBox(
                width: 120,
                height: 44,
                borderRadius: BorderRadius.circular(KkRadius.sm),
              ),
              const SizedBox(height: KkSpacing.sm),
              const SkeletonLine(width: 140, height: 14),
              const SizedBox(height: KkSpacing.xl),
              SkeletonBox(
                width: double.infinity,
                height: 48,
                borderRadius: BorderRadius.circular(KkRadius.pill),
              ),
            ],
          ),
        ),
        // 来源卡骨架
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: _ClueCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonLine(width: 100, height: 14),
                SizedBox(height: KkSpacing.md),
                SkeletonLine(width: 200, height: 12),
                SizedBox(height: KkSpacing.md),
                SkeletonLine(width: 160, height: 12),
              ],
            ),
          ),
        ),
        const SizedBox(height: KkSpacing.lg),
        // AI 思路卡骨架
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: _ClueCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonLine(width: 140, height: 12),
                SizedBox(height: KkSpacing.md),
                SkeletonLine(height: 12),
                SizedBox(height: KkSpacing.xs),
                SkeletonLine(height: 12),
                SizedBox(height: KkSpacing.xs),
                SkeletonLine(width: 220, height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 私有组件
// ──────────────────────────────────────────────────────────────────

/// 区块标题(衬线 + 次文字色)。零旁白:只陈述区块名,不写引导句。
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: KkType.h3.copyWith(fontSize: 16));
  }
}

/// 线索卡片容器(bgCard + bd + lg 圆角),与详情页卡片视觉一致。
class _ClueCard extends StatelessWidget {
  final Widget child;
  const _ClueCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(KkSpacing.lg),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.lg),
        border: Border.all(color: KkColors.bd),
      ),
      child: child,
    );
  }
}
