import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/repositories/post_repository.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import '../shared/avatar.dart';

/// 通知屏 — HANDOFF §6.8 五类精准跳转 + 时间桶分组。
///
/// Web 版重灾区:通知点击无差别跳转或跳错宿主。Flutter 端从零做对:
/// NotificationItem.type 决定跳转目的地:
///   - like      → 点赞 → postDetail(targetId = postId)
///   - comment   → 评论 → 宿主详情
///                 hostType='project' → detail(targetId)
///                 hostType='post'    → postDetail(targetId = postId)
///   - follow    → 关注 → profile(actorId / targetId 都是 userId)
///   - favorite  → 收藏(我的项目被人收藏)→ detail(targetId)
///   - system    → 系统 → 不跳转(纯展示)
///
/// 时间桶分组:今天 / 昨天 / 本周(3-6 天)/ 更早。
/// 点击单条 → markNotifRead + 跳转;顶栏"全部已读"按钮。
///
/// 计数铁律(HANDOFF §6.10):未读数取 unreadNotifIds 真实长度。
/// 零旁白(HANDOFF §3):无"暂无通知"引导,空状态只一行字。
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(notificationRepositoryProvider);
    final appState = ref.watch(appStateProvider);
    final all = repo.all();
    final unreadIds = appState.unreadNotifIds;

    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: AppBar(
        backgroundColor: KkColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const KkBackButton(),
        titleSpacing: 0,
        title: const Text('通知', style: KkType.h2),
        actions: [
          if (unreadIds.isNotEmpty)
            Tappable(
              onTap: () =>
                  ref.read(appStateProvider.notifier).markAllNotifRead(),
              child: Container(
                margin: const EdgeInsets.only(right: KkSpacing.lg),
                alignment: Alignment.center,
                child: Text(
                  '全部已读',
                  style: KkType.bodySm.copyWith(color: KkColors.teal),
                ),
              ),
            ),
        ],
      ),
      body: all.isEmpty
          ? Center(
              child: Text('暂无通知',
                  style: KkType.bodySm.copyWith(color: KkColors.t4)),
            )
          : _groupedList(context, ref, all, unreadIds),
    );
  }

  Widget _groupedList(BuildContext context, WidgetRef ref,
      List<NotificationItem> all, Set<String> unreadIds) {
    // 时间桶分组(今天 / 昨天 / 本周 / 更早)
    final buckets = _bucketize(all);

    return ListView(
      padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
      children: [
        for (final entry in buckets.entries)
          if (entry.value.isNotEmpty) ...[
            _bucketHeader(entry.key),
            for (final n in entry.value)
              _NotifTile(
                item: n,
                unread: unreadIds.contains(n.id),
                onTap: () => _handleTap(context, ref, n),
              ),
          ],
      ],
    );
  }

  /// 时间桶分组。HANDOFF §6.8 时间桶:今天 / 昨天 / 本周(3-6 天)/ 更早。
  Map<_Bucket, List<NotificationItem>> _bucketize(
      List<NotificationItem> all) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final map = <_Bucket, List<NotificationItem>>{
      _Bucket.today: [],
      _Bucket.yesterday: [],
      _Bucket.thisWeek: [],
      _Bucket.earlier: [],
    };

    for (final n in all) {
      final dt = DateTime.fromMillisecondsSinceEpoch(n.createdAtMs);
      if (dt.isAfter(today)) {
        map[_Bucket.today]!.add(n);
      } else if (dt.isAfter(yesterday)) {
        map[_Bucket.yesterday]!.add(n);
      } else if (dt.isAfter(weekAgo)) {
        map[_Bucket.thisWeek]!.add(n);
      } else {
        map[_Bucket.earlier]!.add(n);
      }
    }
    return map;
  }

  Widget _bucketHeader(_Bucket b) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.sm,
      ),
      color: KkColors.bg,
      child: Text(
        b.label,
        style: KkType.bodySm.copyWith(
          color: KkColors.t3,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  /// HANDOFF §6.8 五类精准跳转
  void _handleTap(BuildContext context, WidgetRef ref, NotificationItem n) {
    // 先标记已读
    ref.read(appStateProvider.notifier).markNotifRead(n.id);

    switch (n.type) {
      case 'like':
        // F-7:点赞 targetId = postId → 跳动态详情(postDetail 路由已存在,
        // 原 stale TODO "Phase 4 post-detail 未做,暂跳作者 profile" 已修正)。
        final post = ref.read(postRepositoryProvider).byId(n.targetId ?? '');
        if (post != null) {
          context.push(KkRoutes.postDetail(post.id));
        }
        break;
      case 'comment':
        // F-7:评论 hostType 'project' → detail(targetId);
        //                'post'    → postDetail(targetId)(原跳作者 profile 已修正)
        if (n.hostType == 'project') {
          context.push(KkRoutes.detail(n.targetId ?? ''));
        } else {
          final post =
              ref.read(postRepositoryProvider).byId(n.targetId ?? '');
          if (post != null) {
            context.push(KkRoutes.postDetail(post.id));
          }
        }
        break;
      case 'follow':
        // 关注:actorId 就是新粉丝,targetId 也是 userId
        context.push(KkRoutes.profile(n.targetId ?? n.actorId ?? ''));
        break;
      case 'favorite':
        // 收藏(我的项目被人收藏):targetId = projectId
        context.push(KkRoutes.detail(n.targetId ?? ''));
        break;
      case 'system':
        // 系统:不跳转
        break;
    }
  }
}

enum _Bucket {
  today('今天'),
  yesterday('昨天'),
  thisWeek('本周'),
  earlier('更早');

  final String label;
  const _Bucket(this.label);
}

// ──────────────────────────────────────────────────────────────────
// 通知单元
// ──────────────────────────────────────────────────────────────────

class _NotifTile extends ConsumerWidget {
  final NotificationItem item;
  final bool unread;
  final VoidCallback onTap;

  const _NotifTile({
    required this.item,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = item.actorId != null
        ? ref.watch(userByIdProvider(item.actorId!))
        : null;

    return Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg,
          vertical: KkSpacing.md,
        ),
        decoration: const BoxDecoration(
          color: KkColors.bgCard,
          border: Border(bottom: BorderSide(color: KkColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头像 / 系统图标
            if (item.type == 'system')
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KkColors.bgSubtle,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.campaign_outlined,
                    size: 18, color: KkColors.t2),
              )
            else
              Stack(
                children: [
                  TappableAvatar(
                    userId: item.actorId,
                    user: actor,
                    size: 36,
                    onTap: () {
                      if (item.actorId != null) {
                        context.push(KkRoutes.profile(item.actorId!));
                      }
                    },
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: _typeColor(item.type),
                        shape: BoxShape.circle,
                        border: Border.all(color: KkColors.bgCard, width: 2),
                      ),
                      child: Icon(
                        _typeIcon(item.type),
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(width: KkSpacing.md),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(
                      children: _buildText(actor?.name ?? item.actorId ?? ''),
                      style: KkType.body,
                    ),
                  ),
                  if (item.preview != null && item.preview!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KkSpacing.sm,
                        vertical: KkSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: KkColors.bgSubtle,
                        borderRadius: BorderRadius.circular(KkRadius.sm),
                      ),
                      child: Text(
                        item.preview!,
                        style: KkType.bodySm.copyWith(
                          color: KkColors.t2,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    timeAgo(item.createdAtMs),
                    style: KkType.mono.copyWith(
                      fontSize: 11,
                      color: KkColors.t4,
                    ),
                  ),
                ],
              ),
            ),
            // 未读红点
            if (unread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4, left: KkSpacing.xs),
                decoration: const BoxDecoration(
                  color: KkColors.coral,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 文案构造(零旁白 HANDOFF §3,不写"快来回复"之类引导)
  /// 珊瑚橙只给 take(HANDOFF §5),这里不涉及 take 动作,不用珊瑚橙
  List<TextSpan> _buildText(String actorName) {
    switch (item.type) {
      case 'like':
        return [
          TextSpan(
            text: actorName,
            style: KkType.body.copyWith(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' 赞了你的动态', style: KkType.body),
        ];
      case 'comment':
        return [
          TextSpan(
            text: actorName,
            style: KkType.body.copyWith(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' 评论了你的', style: KkType.body),
          TextSpan(
            text: item.hostType == 'project' ? '项目' : '动态',
            style: KkType.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ];
      case 'follow':
        return [
          TextSpan(
            text: actorName,
            style: KkType.body.copyWith(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' 关注了你', style: KkType.body),
        ];
      case 'favorite':
        return [
          TextSpan(
            text: actorName,
            style: KkType.body.copyWith(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' 收藏了你的项目', style: KkType.body),
        ];
      case 'system':
        return [
          TextSpan(
            text: item.preview ?? '系统通知',
            style: KkType.body,
          ),
        ];
      default:
        return [TextSpan(text: '通知', style: KkType.body)];
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.chat_bubble;
      case 'follow':
        return Icons.person_add;
      case 'favorite':
        return Icons.bookmark;
      case 'system':
        return Icons.campaign;
      default:
        return Icons.notifications;
    }
  }

  /// 类型色:不用珊瑚橙(HANDOFF §5 只给 take)
  Color _typeColor(String type) {
    switch (type) {
      case 'like':
        return KkColors.coral; // 点赞可用珊瑚橙(情感色,与 take 区分)
      case 'comment':
        return KkColors.teal;
      case 'follow':
        return KkColors.teal;
      case 'favorite':
        return KkColors.teal;
      case 'system':
        return KkColors.t3;
      default:
        return KkColors.t3;
    }
  }
}
