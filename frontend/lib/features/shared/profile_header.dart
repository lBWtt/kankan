import 'package:flutter/material.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse_count.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import 'avatar.dart';

/// 任务⑩A:共享个人页头部 — me_screen 与 profile_screen 共用同一视觉语言
/// (暖色渐变 banner + 大头像压 banner + 名字 + inline 统计 + 右侧操作槽)。
///
/// 抽出原因:任务③重构 me_screen 后,profile_screen 仍是老式 64 头像卡片,
/// 用户点他人主页有割裂感。复用同一 widget 避免两处分叉。
///
/// 设计:
///   - 顶部暖色渐变 banner(160 高,浅珊瑚 → 暖纸底,同 me_screen)
///   - 大头像(72,白边圈)压 banner 下沿
///   - 名字(KkType.h2)+ bio(t3,可选)
///   - inline 统计(关注/粉丝/获赞,纯文字无框,可点)
///   - 右下操作槽(me 放"编辑资料"链接,profile 放关注/编辑按钮)
///   - banner 右上角槽(可选,放通知/设置或返回/更多)
///
/// 铁律:coral 只给 take(本组件不用 coral);无 emoji;零旁白;触控≥44pt。
/// 不搬热力图/关注领域/最近看过(那是 me 专属)。
class ProfileHeader extends StatelessWidget {
  /// 目标用户
  final KkUser? user;

  /// userId(头像/路由用)
  final String userId;

  /// 关注数(真实)
  final int followingCount;

  /// 粉丝数(真实)
  final int followerCount;

  /// 获赞数(真实)
  final int totalLikes;

  /// 点击关注数 → follows 页(可空)
  final VoidCallback? onTapFollowing;

  /// 点击粉丝数 → follows 页(可空)
  final VoidCallback? onTapFollowers;

  /// banner 右上角自定义槽(me: 通知+设置;profile: 返回+更多;null 不显)
  final List<Widget>? bannerActions;

  /// 右下操作区(me: 编辑资料链接;profile: 关注/编辑按钮)
  final Widget? actionSlot;

  /// 头像下方名字行的副槽(me 的"编辑资料"小链接放这,与名字同行)
  final Widget? nameTrailing;

  /// 第 4 统计槽标签(me 传「收藏」;profile 不传,改用 actionSlot)
  final String? fourthStatLabel;

  /// 第 4 统计槽数值
  final int? fourthStatValue;

  /// 第 4 统计槽点击(me 传跳 library)
  final VoidCallback? onTapFourthStat;

  /// banner 背景图 URL(null → 默认暖色渐变;非 null → 铺图 + 底部压暗保文字)
  final String? bannerImageUrl;

  /// 换背景回调(me 传 → 右下角显「换背景」相机按钮;profile 不传则不显)
  final VoidCallback? onChangeBanner;

  const ProfileHeader({
    super.key,
    required this.user,
    required this.userId,
    required this.followingCount,
    required this.followerCount,
    required this.totalLikes,
    this.onTapFollowing,
    this.onTapFollowers,
    this.bannerActions,
    this.actionSlot,
    this.nameTrailing,
    this.fourthStatLabel,
    this.fourthStatValue,
    this.onTapFourthStat,
    this.bannerImageUrl,
    this.onChangeBanner,
  });

  @override
  Widget build(BuildContext context) {
    const bannerHeight = 160.0;
    const avatarSize = 72.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          // banner + 半个头像(头像压 banner 底沿,一半上一半下)
          height: bannerHeight + avatarSize / 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // banner 背景:有换过的背景图 → 铺图 + 底部渐隐到暖纸底(保头像/文字对比);
              // 否则默认暖色渐变。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: bannerHeight,
                child: (bannerImageUrl != null && bannerImageUrl!.isNotEmpty)
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            bannerImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _GradientBanner(),
                          ),
                          // 底部渐隐到暖纸底,让压在下沿的头像/名字清晰
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.center,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00FBF9F4), KkColors.bg],
                              ),
                            ),
                          ),
                        ],
                      )
                    : const _GradientBanner(),
              ),
              // 右上角槽(可选)
              if (bannerActions != null && bannerActions!.isNotEmpty)
                Positioned(
                  top: KkSpacing.sm,
                  right: KkSpacing.xs,
                  child: Row(children: bannerActions!),
                ),
              // 换背景相机按钮(仅 me 传 onChangeBanner 时显,右下角浮在 banner 上)
              if (onChangeBanner != null)
                Positioned(
                  top: bannerHeight - 40,
                  right: KkSpacing.md,
                  child: Tappable(
                    onTap: onChangeBanner,
                    borderRadius: BorderRadius.circular(KkRadius.pill),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: Color(0x33000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.photo_camera_outlined,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              // 大头像(压 banner 底沿)+ 名字 + 副槽
              Positioned(
                top: bannerHeight - avatarSize / 2,
                left: KkSpacing.lg,
                right: KkSpacing.lg,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 头像外圈白边(在渐变上更清晰)
                    Container(
                      decoration: const BoxDecoration(
                        color: KkColors.bg,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(3),
                      child: KkAvatar(
                          userId: userId, user: user, size: avatarSize),
                    ),
                    const SizedBox(width: KkSpacing.md),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user?.name ?? userId,
                                    style: KkType.h2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (nameTrailing != null) ...[
                                  const SizedBox(width: KkSpacing.sm),
                                  nameTrailing!,
                                ],
                              ],
                            ),
                            if (user?.bio != null &&
                                user!.bio!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                user!.bio!,
                                style:
                                    KkType.bodySm.copyWith(color: KkColors.t3),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KkSpacing.lg),
        // inline 统计行(关注/粉丝/获赞 + 可选右侧操作槽)
        // - 无 actionSlot:三块均分(me 传 fourthStat 做第4块收藏)
        // - 有 actionSlot:三块均分 + 右侧按钮(关注/编辑,自然宽度右对齐)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: _StatBlock(
                  label: '关注',
                  value: followingCount,
                  onTap: onTapFollowing,
                ),
              ),
              Expanded(
                child: _StatBlock(
                  label: '粉丝',
                  value: followerCount,
                  onTap: onTapFollowers,
                ),
              ),
              Expanded(
                child: _StatBlock(
                  label: '获赞',
                  value: totalLikes,
                ),
              ),
              // me:第 4 槽「收藏」(fourthStatLabel 非空时均分第4块)
              if (fourthStatLabel != null)
                Expanded(
                  child: _StatBlock(
                    label: fourthStatLabel!,
                    value: fourthStatValue ?? 0,
                    onTap: onTapFourthStat,
                  ),
                ),
              // profile:右侧关注/编辑按钮(自然宽度,不均分)
              if (actionSlot != null) actionSlot!,
            ],
          ),
        ),
      ],
    );
  }
}

/// banner 右上角半透明白底圆图标按钮(通知带未读红点 / 设置 / 返回 / 更多)。
/// 复用 me_screen _bannerIconBtn 的视觉,抽出来 me/profile 都能用。
class BannerIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool hasDot;

  const BannerIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.hasDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.pill),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color(0x14FFFFFF), // 8% 白
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: KkColors.t1),
          ),
          if (hasDot)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  // SPEC:coral 只给 take;未读红点用 like 红(情感色,非 take)
                  color: KkColors.like,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// inline 统计块(纯文字,数字 mono + 标签 t3,可点)。
class _StatBlock extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback? onTap;

  const _StatBlock({
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatCount(value), style: KkType.monoLg),
        const SizedBox(height: 2),
        Text(
          label,
          style: KkType.bodySm.copyWith(color: KkColors.t3, fontSize: 11),
        ),
      ],
    );
    if (onTap == null) return content;
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: content,
    );
  }
}

// ── 默认暖色渐变 banner(浅珊瑚 → 暖纸底)──
class _GradientBanner extends StatelessWidget {
  const _GradientBanner();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF3E1CE), // 浅珊瑚/浅橙
            KkColors.bg, // 暖纸底 #FBF9F4
          ],
        ),
      ),
    );
  }
}
