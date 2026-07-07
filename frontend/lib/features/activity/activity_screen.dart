import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse_count.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/skeletons.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../data/seed/mock_seed.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/project_repository.dart';
import '../../providers/app_state_provider.dart';
import '../me/widgets/contribution_heatmap.dart';

/// 个人活动页 — HANDOFF §6.10 真实数字 + §3 零旁白 + §5 珊瑚橙只给 take/like。
///
/// Web 版重灾区:activity 屏 ×200 编造贡献数 / 获赞 / 收藏,Flutter 端从零做对:
///   - 三档统计(发布/获赞/收藏)从 repository / appState 真实计算,不放大
///   - 时间线从 4 个真实数据源聚合(我发的项目 / 我发的动态 / 我拿走的 / 我收到的通知),
///     按时间降序合并,最多 30 条
///   - 大热力图复用 ContributionHeatmap(86 cells mock 数据),区别于 me 屏的小热力图
///
/// 珊瑚橙(HANDOFF §5):只给 take(takeaway 事件)+ like(获赞 outline 心形 / like 通知)。
/// 零旁白:无"继续加油"之类引导。无 emoji,用 Material Icons。
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  // Phase 5-c:300ms 假 loading,骨架屏占位(与 discover/kankan/library/follows/ranking 一致)
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectRepo = ref.watch(projectRepositoryProvider);
    final postRepo = ref.watch(postRepositoryProvider);
    final appState = ref.watch(appStateProvider);

    // ── 真实统计(HANDOFF §6.10,禁 ×200 编造)──
    final myProjects = projectRepo.byAuthor('me');
    final myPosts = postRepo.byAuthor('me');
    final publishCount = myProjects.length + myPosts.length;
    final likeCount = myProjects.fold<int>(0, (s, p) => s + p.likes) +
        myPosts.fold<int>(0, (s, p) => s + p.likes);
    final savedCount = appState.savedProjectIds.length;

    // ── 时间线事件聚合(4 类真实数据源,按 createdAtMs 降序)──
    final events = _buildEvents(myProjects, myPosts, appState.savedTakeaways);

    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: AppBar(
        backgroundColor: KkColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const KkBackButton(),
        titleSpacing: 0,
        title: Text('我的活动', style: KkType.h1),
        // 原日历入口是 no-op 死按钮(无日历页),移除——宁可没按钮,不放假按钮。
      ),
      body: _loading
          ? _skeletonContent()
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: KkSpacing.lg),
              children: [
                // Section 1: 年度统计三档卡片
                _statsRow(publishCount, likeCount, savedCount),
                const SizedBox(height: KkSpacing.lg),

                // Section 2: 大热力图(标题 + 副文 + 自定义 4 档图例)
                _heatmapSection(),
                const SizedBox(height: KkSpacing.lg),

                // Section 3: 活动时间线(4 类事件聚合,最多 30 条)
                _timelineSection(events),

                // Section 4: 底部留白
                const SizedBox(height: KkSpacing.xxl),
              ],
            ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Phase 5-c:加载态骨架 — 三 section 镜像:
  //   ① 三档统计卡(bgCard+bd,Icon+count+label)
  //   ② 热力图卡(bgCard+bd,title+subtitle+7×13 网格)
  //   ③ 时间线(title + 4 行圆点+线)
  // HANDOFF §5:不用 coral;只用 KkColors.*(bgCard/bgSubtle)+ 骨架 shimmer
  // ──────────────────────────────────────────────────────────────────
  Widget _skeletonContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: KkSpacing.lg),
      children: [
        // Section 1 skeleton: 三档统计卡(横向三等分)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: Row(
            children: const [
              Expanded(child: _SkeletonStatBlock()),
              SizedBox(width: KkSpacing.md),
              Expanded(child: _SkeletonStatBlock()),
              SizedBox(width: KkSpacing.md),
              Expanded(child: _SkeletonStatBlock()),
            ],
          ),
        ),
        const SizedBox(height: KkSpacing.lg),

        // Section 2 skeleton: 热力图卡(title + subtitle + 7×13 网格)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: Container(
            padding: const EdgeInsets.all(KkSpacing.lg),
            decoration: BoxDecoration(
              color: KkColors.bgCard,
              borderRadius: BorderRadius.circular(KkRadius.md),
              border: Border.all(color: KkColors.bd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SkeletonLine(width: 120, height: 18),
                const SizedBox(height: 4),
                const SkeletonLine(width: 60, height: 12),
                const SizedBox(height: KkSpacing.md),
                // 7×26 网格骨架(镜像 ContributionHeatmap:7 行 × N 列,mock 182 cells → 26 周)
                Column(
                  children: List.generate(
                    7,
                    (_) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: List.generate(
                          26,
                          (_) => Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 1),
                              child: SkeletonBox(
                                width: double.infinity,
                                height: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: KkSpacing.lg),

        // Section 3 skeleton: 时间线(title + 4 行圆点+线)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SkeletonLine(width: 100, height: 18),
              const SizedBox(height: KkSpacing.md),
              for (var i = 0; i < 4; i++) ...[
                _skeletonTimelineItem(),
                const SizedBox(height: KkSpacing.lg),
              ],
            ],
          ),
        ),
        const SizedBox(height: KkSpacing.xxl),
      ],
    );
  }

  // 时间线骨架项(8×8 圆点 + 1px 竖线 + 内容线 ×2)
  Widget _skeletonTimelineItem() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                SkeletonBox(
                  width: 8,
                  height: 8,
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                ),
                const SizedBox(height: 4),
                Expanded(child: Container(width: 1, color: KkColors.bd)),
              ],
            ),
          ),
          const SizedBox(width: KkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                SkeletonLine(height: 12),
                SizedBox(height: 4),
                SkeletonLine(width: 60, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Section 1: 年度统计三档卡片(横向三等分)
  // ──────────────────────────────────────────────────────────────────
  Widget _statsRow(int publishCount, int likeCount, int savedCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: _statBlock(
              icon: Icons.publish_outlined,
              label: '今年发布',
              count: publishCount,
              color: KkColors.teal,
            ),
          ),
          const SizedBox(width: KkSpacing.md),
          Expanded(
            child: _statBlock(
              icon: Icons.favorite_border, // outline 心形(HANDOFF §5 允许获赞用 coral)
              label: '今年获赞',
              count: likeCount,
              color: KkColors.coral,
            ),
          ),
          const SizedBox(width: KkSpacing.md),
          Expanded(
            child: _statBlock(
              icon: Icons.bookmark_border_outlined,
              label: '今年收藏',
              count: savedCount,
              color: KkColors.teal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBlock({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.md,
      ),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.md),
        border: Border.all(color: KkColors.bd),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: KkSpacing.xs),
          Text(
            formatCount(count),
            style: KkType.monoLg.copyWith(color: color),
          ),
          Text(
            label,
            style: KkType.bodySm.copyWith(color: KkColors.t3, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Section 2: 大热力图(区别于 me 屏的小热力图)
  // ──────────────────────────────────────────────────────────────────
  // 复用 ContributionHeatmap,包在外层 bgCard 卡里 + 标题 + 副文;
  // 卡片下方加自定义 4 档图例(teal alpha 0.2 / 0.4 / 0.7 / 1.0)。
  Widget _heatmapSection() {
    // 4 档色阶:teal 透明度 0.2 / 0.4 / 0.7 / 1.0
    const alphas = [0.2, 0.4, 0.7, 1.0];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 外层卡:标题 + 副文 + 热力图
          Container(
            padding: const EdgeInsets.all(KkSpacing.lg),
            decoration: BoxDecoration(
              color: KkColors.bgCard,
              borderRadius: BorderRadius.circular(KkRadius.md),
              border: Border.all(color: KkColors.bd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('贡献热力图', style: KkType.h3),
                const SizedBox(height: 4),
                Text(
                  '近 26 周',
                  style: KkType.bodySm.copyWith(color: KkColors.t3),
                ),
                const SizedBox(height: KkSpacing.md),
                // 热力图组件(自带 bgCard + 边框,在此作为内嵌面板)
                ContributionHeatmap(
                  cells: mockHeatmapCells,
                  showStats: false,
                  showLegend: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: KkSpacing.sm),
          // 卡片下方:4 档图例(少 → 多)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '少',
                style: TextStyle(
                  fontSize: 9,
                  color: KkColors.t4,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
              const SizedBox(width: 4),
              for (final a in alphas) ...[
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: KkColors.teal.withOpacity(a),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Text(
                '多',
                style: TextStyle(
                  fontSize: 9,
                  color: KkColors.t4,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Section 3: 活动时间线
  // ──────────────────────────────────────────────────────────────────
  // 视觉:左侧 1px 竖线(KkColors.bd)+ 每项 8x8 圆点(teal/coral)+
  // 右侧内容块(icon + text + timeAgo)。
  Widget _timelineSection(List<_ActivityEvent> events) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: KkSpacing.md),
            child: Text('活动时间线', style: KkType.h3),
          ),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KkSpacing.xl),
              child: Center(
                child: Text(
                  '暂无活动',
                  style: KkType.bodySm.copyWith(color: KkColors.t4),
                ),
              ),
            )
          else
            for (var i = 0; i < events.length; i++)
              _timelineItem(events[i], isLast: i == events.length - 1),
        ],
      ),
    );
  }

  Widget _timelineItem(_ActivityEvent event, {required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左:圆点 + 竖线(连接下一项)
          SizedBox(
            width: 20,
            child: Column(
              children: [
                // 8x8 圆点(顶对齐)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: event.color,
                    shape: BoxShape.circle,
                  ),
                ),
                // 竖线填满剩余高度(连接下一项的圆点)
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: KkColors.bd,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                    ),
                  )
                else
                  const SizedBox(height: KkSpacing.lg),
              ],
            ),
          ),
          const SizedBox(width: KkSpacing.sm),
          // 右:内容块(icon + text + timeAgo)
          Expanded(
            child: Padding(
              padding:
                  EdgeInsets.only(bottom: isLast ? 0 : KkSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(event.icon, size: 16, color: event.color),
                  const SizedBox(width: KkSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          event.text,
                          style: KkType.bodySm.copyWith(height: 1.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timeAgo(event.createdAtMs),
                          style: KkType.mono.copyWith(
                            fontSize: 10,
                            color: KkColors.t4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // 时间线事件聚合(4 类真实数据源)
  // ──────────────────────────────────────────────────────────────────
  // 1. 我发布的项目 (projectRepo.byAuthor('me'))
  // 2. 我发布的动态 (postRepo.byAuthor('me'))
  // 3. 我拿走的内容 (appState.savedTakeaways)
  // 4. 我收到的通知 (mockNotifications 过滤 actorId != 'me' 或 type == 'system')
  //
  // 按时间降序合并,最多 30 条(HANDOFF §6.10 真实数据,禁编造)。
  List<_ActivityEvent> _buildEvents(
    List<Project> myProjects,
    List<Post> myPosts,
    List<SavedTakeaway> savedTakeaways,
  ) {
    final events = <_ActivityEvent>[];

    // 1. 我发布的项目
    for (final p in myProjects) {
      events.add(_ActivityEvent(
        type: 'publish_project',
        icon: Icons.work_outline,
        color: KkColors.teal,
        text: '发布了作品《${p.title}》',
        createdAtMs: p.createdAtMs,
      ));
    }

    // 2. 我发布的动态(preview = content 前 40 字)
    for (final p in myPosts) {
      final preview = p.content.length > 40
          ? '${p.content.substring(0, 40)}…'
          : p.content;
      events.add(_ActivityEvent(
        type: 'publish_post',
        icon: Icons.chat_bubble_outline,
        color: KkColors.teal,
        text: '发布了动态',
        preview: preview,
        createdAtMs: p.createdAtMs,
      ));
    }

    // 3. 我拿走的内容(珊瑚橙,只给 take — HANDOFF §5)
    for (final t in savedTakeaways) {
      events.add(_ActivityEvent(
        type: 'takeaway',
        icon: Icons.download_done_outlined,
        color: KkColors.coral,
        text: '存下了《${t.projectTitle}》的 ${t.label ?? ''}',
        createdAtMs: t.savedAtMs,
      ));
    }

    // 4. 我收到的通知(actorId != 'me' 或 type == 'system')
    for (final n in mockNotifications) {
      final isRecipient = n.actorId != 'me' || n.type == 'system';
      if (!isRecipient) continue;

      // actorName:actorId 为 null → '系统';否则 findUser(actorId)?.name ?? '系统'
      final actorName = n.actorId == null
          ? '系统'
          : (findUser(n.actorId!)?.name ?? '系统');

      String text;
      IconData icon;
      Color color;

      switch (n.type) {
        case 'like':
          text = '$actorName 赞了你的动态';
          icon = Icons.favorite_border; // outline 心形,§5 允许 like 用 coral
          color = KkColors.coral;
          break;
        case 'comment':
          // preview 截断 30 字
          final preview = n.preview ?? '';
          final truncated = preview.length > 30
              ? '${preview.substring(0, 30)}…'
              : preview;
          text = '$actorName 评论了你:$truncated';
          icon = Icons.chat_bubble_outline;
          color = KkColors.teal;
          break;
        case 'follow':
          text = '$actorName 关注了你';
          icon = Icons.person_add_outlined;
          color = KkColors.teal;
          break;
        case 'favorite':
          text = '$actorName 收藏了你的作品';
          icon = Icons.bookmark_border_outlined;
          color = KkColors.teal;
          break;
        case 'system':
          // preview 截断 40 字
          final preview = n.preview ?? '';
          final truncated = preview.length > 40
              ? '${preview.substring(0, 40)}…'
              : preview;
          text = '系统通知:$truncated';
          icon = Icons.info_outline;
          color = KkColors.teal;
          break;
        default:
          continue;
      }

      events.add(_ActivityEvent(
        type: 'notif',
        icon: icon,
        color: color,
        text: text,
        createdAtMs: n.createdAtMs,
      ));
    }

    // 按 createdAtMs 降序(最近在前)
    events.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));

    // 最多 30 条,超过截断
    if (events.length > 30) {
      return events.sublist(0, 30);
    }
    return events;
  }
}

/// 活动时间线事件(私有值对象)。
///
/// 4 类:type ∈ {'publish_project','publish_post','takeaway','notif'}
/// 颜色规则:teal / coral 二选一(HANDOFF §5,coral 只给 take/like)。
class _ActivityEvent {
  final String type;
  final IconData icon;
  final Color color;
  final String text;
  final String? preview;
  final int createdAtMs;

  const _ActivityEvent({
    required this.type,
    required this.icon,
    required this.color,
    required this.text,
    this.preview,
    required this.createdAtMs,
  });
}

// ──────────────────────────────────────────────────────────────────
// 骨架统计卡 — 镜像 _statBlock(Icon 20 + count 16 + label 10)
// bgCard + bd + md padding,与真实统计卡边距一致
// ──────────────────────────────────────────────────────────────────

class _SkeletonStatBlock extends StatelessWidget {
  const _SkeletonStatBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.md,
      ),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.md),
        border: Border.all(color: KkColors.bd),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SkeletonBox(
            width: 20,
            height: 20,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          const SizedBox(height: KkSpacing.xs),
          const SkeletonLine(width: 32, height: 16),
          const SizedBox(height: 2),
          const SkeletonLine(width: 48, height: 10),
        ],
      ),
    );
  }
}
