import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/login_gate.dart';
import '../../core/utils/parse_count.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/cover_art.dart';
import 'kk_image.dart';
import '../../core/widgets/kk_reaction_button.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../l10n/kk_strings.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import 'avatar.dart';

/// HANDOFF 搂1 椤圭洰鍗?閲?鈥?鐪嬬湅椤?/ 鏀惰棌椤?/ 鎴戠殑椤靛叡鐢ㄣ€?
///
/// 椤圭洰鏈夋垚鏋?+ 绱犳潗,鍙繘搴?鏈夎鎯呴〉銆傚崱鏄剧ず:
///   - 灏侀潰(鏈?media 鍙栭寮?鍚﹀垯棰嗗煙鑹插潡 + 鍥炬爣)
///   - 鏍囬 + 涓€鍙ヨ瘽浠峰€?
///   - 浣滆€?+ 棰嗗煙
///   - 鐪熷疄璁℃暟:鐐硅禐 / 蹇冨緱 / 鎷胯蛋(HANDOFF 搂6.10,鍙栫湡瀹炴暟缁勯暱搴?绂佺紪閫?
///
/// 闆舵梺鐧?HANDOFF 搂3):鏃?蹇潵鍥磋"涔嬬被寮曞銆?
///
/// Phase 4 Hero 鍏变韩鍏冪礌(HANDOFF 搂5 鍔ㄦ晥绯荤粺):
///   - full 妯″紡灏侀潰澶栧眰鍖?`Hero(tag: 'project-cover-{project.id}')`,
///     璇︽儏椤?detail_screen 椤堕儴 cover 鐢ㄥ悓 tag 閰嶅,瀹炵幇鍗＄墖 鈫?璇︽儏 cover 椋炲叆杩囨浮銆?
///   - compact 妯″紡(56脳56 缂╃暐鍥?涓嶅弬涓?Hero,閬垮厤涓?full 妯″紡鍦ㄥ悓涓€灞忓悓鏃?
///     娓叉煋鍚屼竴 project.id 鏃堕€犳垚 Hero tag 鍐茬獊(Flutter 鍚?tag 澶?Hero 鎶ラ敊)銆?
///   - **绾︽潫**:鍚屼竴 project.id 鍦ㄥ悓涓€灞忓彧鑳藉嚭鐜颁竴娆¤ Hero tag銆傝嫢鏈潵鏌愬睆闇€
///     鍚屾椂灞曠ず full + compact 鍚屼竴椤圭洰,鏀圭敤 flightShuttleBuilder 鎴栦负 compact
///     鍗曠嫭鍛藉悕 tag銆?
///   - tag 鍛藉悕绾﹀畾:`'project-cover-{project.id}'`(4-f 瀛愪唬鐞嗗湪 detail_screen
///     椤堕儴 cover 鐢ㄥ悓 tag 閰嶅)銆?
class ProjectCard extends ConsumerWidget {
  final Project project;
  final bool showAuthor;

  /// 绱у噾妯″紡(鏀惰棌椤电敤,鏃犲皝闈?浠呮枃瀛楄)
  final bool compact;

  const ProjectCard({
    super.key,
    required this.project,
    this.showAuthor = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (project.status == 'deleted' || project.status == 'taken_down') {
      return _UnavailableProjectCard(status: project.status, compact: compact);
    }
    // 鍩嬬偣:鍗＄墖鏇濆厜(浼氳瘽鍐呭悓椤圭洰鍙涓€娆?銆傜湡鍚庣椤圭洰(UUID)鎵嶅彂銆?
    ref.read(analyticsProvider).trackImpressionOnce(project.id);
    if (compact) return _compact(context, ref);
    return _full(context, ref);
  }

  Widget _full(BuildContext context, WidgetRef ref) {
    final author = ref.watch(userByIdProvider(project.authorId));
    final appState = ref.watch(appStateProvider);
    final isSaved = appState.savedProjectIds.contains(project.id);
    final isLiked = appState.likedItemIds.contains(project.id);
    final likeCount = project.likes + (isLiked ? 1 : 0);
    // P2-i18n / 鏃犻殰纰?鏁村崱 + 鐐硅禐 + 鏀惰棌 icon-only 鎸夐挳鐨?semanticLabel銆?
    final s = ref.watch(kkStringsProvider);

    return Tappable(
      onTap: () {
        ref.read(analyticsProvider).track('card_click', projectId: project.id);
        ref.read(appStateProvider.notifier).recordBrowse(project.id);
        context.push(KkRoutes.detail(project.id));
      },
      borderRadius: BorderRadius.circular(KkRadius.lg),
      // P2-鏃犻殰纰?鏁村崱 Tappable 浼?semanticLabel,璇诲睆蹇点€岄」鐩?<鏍囬>銆嶃€?
      semanticLabel: s.projectSemantic(project.title),
      child: Container(
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.lg),
          border: Border.all(color: KkColors.bd),
          boxShadow: KkElevation.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 灏侀潰(Hero 鍏变韩鍏冪礌,4-f 瀛愪唬鐞嗗湪 detail_screen 椤堕儴鐢ㄥ悓 tag 閰嶅)
            Hero(
              tag: 'project-cover-${project.id}',
              child: _Cover(project: project),
            ),
            // 鍐呭
            Padding(
              padding: const EdgeInsets.all(KkSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(project.title,
                      style: KkType.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    project.summary,
                    style: KkType.bodySm,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 浠诲姟鈶?鎷涚墝 take 琛?can-takeaway)鈥斺€攕ummary 涓嬨€佷綔鑰呰涓娿€?
                  // 鏈?TakeAction 鈫?鐝婄憵姗欐祬搴?chip;鍚﹀垯鏈?GoAction 鈫?閫€鍖?teal銆屽幓鐪嬬湅銆?
                  // 閮芥棤(绾?HowAction / 绌?鈫?鏁磋涓嶆樉绀恒€傜 if(artifactType) 鍒嗘敮(SPEC 搂6.1)銆?
                  if (project.actions.whereType<TakeAction>().isNotEmpty ||
                      project.actions.whereType<GoAction>().isNotEmpty) ...[
                    const SizedBox(height: KkSpacing.sm),
                    _TakeawayChip(actions: project.actions),
                  ],
                  if (showAuthor) ...[
                    const SizedBox(height: KkSpacing.md),
                    Row(
                      children: [
                        Tappable(
                          onTap: () =>
                              context.push(KkRoutes.profile(project.authorId)),
                          borderRadius: BorderRadius.circular(KkRadius.pill),
                          child: KkAvatar(
                              userId: project.authorId, user: author, size: 20),
                        ),
                        const SizedBox(width: KkSpacing.xs),
                        GestureDetector(
                          onTap: () =>
                              context.push(KkRoutes.profile(project.authorId)),
                          behavior: HitTestBehavior.translucent,
                          child: Text(
                            author?.name ?? project.authorId,
                            style: KkType.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: KkSpacing.sm),
                        Text(
                          timeAgo(project.createdAtMs),
                          style: KkType.mono.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: KkSpacing.md),
                  // 鐪熷疄璁℃暟琛?HANDOFF 搂6.10)
                  Row(
                    children: [
                      // 浠诲姟 C:鐐硅禐鐢?KkReactionButton鈥斺€旂偣浜?scale 寮?+ haptic銆?
                      // P2-鏃犻殰纰?icon-only 鎸夐挳浼?semanticLabel,璇诲睆蹇点€岀偣璧?<n>銆嶃€?
                      KkReactionButton(
                        icon: isLiked ? Icons.favorite : Icons.favorite_border,
                        value: formatCount(likeCount),
                        color: isLiked ? KkColors.like : KkColors.t3,
                        isLit: isLiked,
                        iconSize: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 4,
                        ),
                        semanticLabel: '${s.like} ${formatCount(likeCount)}',
                        onTap: () {
                          if (!guardLogin(context, ref)) return;
                          ref
                              .read(appStateProvider.notifier)
                              .toggleLike(project.id);
                        },
                      ),
                      const SizedBox(width: KkSpacing.lg),
                      _Stat(
                        icon: Icons.chat_bubble_outline,
                        // F-9:璇勮鏁板彇 commentsFor(project.id).length(涓庤鎯呴〉鍚屾簮),
                        // 涓嶇敤鍐欐鐨?project.commentCount(D 绫?bug 鍦ㄥ崱鐗囧鐜?銆?
                        value: formatCount(project.commentCount),
                        color: KkColors.t3,
                      ),
                      if (project.takeawayCount > 0) ...[
                        const SizedBox(width: KkSpacing.lg),
                        _Stat(
                          icon: Icons.download_outlined,
                          value: formatCount(project.takeawayCount),
                          color: KkColors.t3,
                        ),
                      ],
                      const Spacer(),
                      // 鏀惰棌(浠诲姟 C:鐢?KkReactionButton鈥斺€旂偣浜?scale 寮?+ haptic)銆?
                      // P2-鏃犻殰纰?icon-only 鎸夐挳浼?semanticLabel,璇诲睆蹇点€屾敹钘忋€嶃€?
                      KkReactionButton(
                        icon: isSaved
                            ? Icons.bookmark
                            : Icons.bookmark_border_outlined,
                        color: isSaved ? KkColors.teal : KkColors.t3,
                        isLit: isSaved,
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        semanticLabel: s.save,
                        onTap: () {
                          if (!guardLogin(context, ref)) return;
                          ref
                              .read(appStateProvider.notifier)
                              .toggleSave(project.id);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compact(BuildContext context, WidgetRef ref) {
    // P2-i18n / 鏃犻殰纰?鏁村崱 Tappable 浼?semanticLabel,璇诲睆蹇点€岄」鐩?<鏍囬>銆嶃€?
    final s = ref.watch(kkStringsProvider);
    return Tappable(
      onTap: () {
        ref.read(analyticsProvider).track('card_click', projectId: project.id);
        ref.read(appStateProvider.notifier).recordBrowse(project.id);
        context.push(KkRoutes.detail(project.id));
      },
      semanticLabel: s.projectSemantic(project.title),
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
          children: [
            // 灏忓皝闈?B2:Hero 閰嶅璇︽儏椤?'project-cover-{id}',绱у噾鍗￠鍏ヨ鎯呫€?
            // library/ranking 鍚勮嚜鍗曞睆椤圭洰鍞竴,涓嶅悓灞忎笉鍐茬獊,discover 鐢?_full 涓嶆贩鐢?
            Hero(
              tag: 'project-cover-${project.id}',
              child: _Cover(project: project, width: 56, height: 56),
            ),
            const SizedBox(width: KkSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(project.title,
                      style: KkType.body.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    project.summary,
                    style: KkType.bodySm.copyWith(color: KkColors.t3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        // F-9:compact 妯″紡璇勮鏁板悓婧?commentsFor(璇︽儏椤?/ full 妯″紡涓€鑷?銆?
                        '${formatCount(project.likes)} 赞 · ${formatCount(project.commentCount)} 评论',
                        style: KkType.mono.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: KkColors.t3),
          ],
        ),
      ),
    );
  }
}

// 鈹€鈹€ 灏侀潰(鐪熷疄灏侀潰鍥?+ CoverArt 鍥為€€)鈹€鈹€
//
// 浠诲姟鈶犵湡瀹炲皝闈㈠浘:鏈?URL 鈫?Image.network(loadingBuilder/errorBuilder 鍥為€€ CoverArt);
// 鏃?URL 鈫?CoverArt 鍗犱綅銆倂ideo 鍙?play 鎸夐挳;鏃犲皝闈㈡椂鍙犻鍩熷浘鏍囥€?
// 澶栧眰 ProjectCard Container 宸?clipBehavior.antiAlias,_Cover 涓嶅啀鍗曠嫭 ClipRRect銆?
class _UnavailableProjectCard extends StatelessWidget {
  final String status;
  final bool compact;

  const _UnavailableProjectCard({
    required this.status,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final isTakenDown = status == 'taken_down';
    final title = isTakenDown ? '内容已下架' : '该作品已被作者删除';
    final subtitle = isTakenDown ? '收藏记录会保留，但原内容暂不可查看' : '收藏记录会保留，但原内容已不可查看';
    return Container(
      padding: EdgeInsets.all(compact ? KkSpacing.md : KkSpacing.lg),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.lg),
        border: Border.all(color: KkColors.bd),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 44 : 52,
            height: compact ? 44 : 52,
            decoration: BoxDecoration(
              color: KkColors.bg,
              borderRadius: BorderRadius.circular(KkRadius.md),
            ),
            child: const Icon(Icons.inventory_2_outlined, color: KkColors.t3),
          ),
          const SizedBox(width: KkSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: KkType.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: KkType.bodySm.copyWith(color: KkColors.t3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final Project project;
  final double? width;
  final double? height;

  const _Cover({required this.project, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final w = width ?? double.infinity;
    final h = height ?? 180.0;
    // compact 妯″紡(浼犱簡 width 閫氬父鏄?56脳56):灏忓昂瀵哥敤 grid 绠€鍖栧浘妗?
    // 鐪嬩笉鍑哄鏉傜殑娉㈡氮 / 灞卞肠 / 姘村ⅷ缁嗚妭
    final isCompact = width != null;
    final hasMedia = project.resultData.media.isNotEmpty;
    final first = hasMedia ? project.resultData.media.first : null;
    final isImage = hasMedia && first!.type == 'image';
    final isVideo = hasMedia && first!.type == 'video';
    // 灏侀潰 URL:image 鐢?first.url;video 鐢?first.poster;鏃?media 鈫?null(璧?CoverArt 鍗犱綅)
    final coverUrl = isImage ? first!.url : (isVideo ? first!.poster : null);

    final pattern = isCompact ? 'grid' : _domainPattern(project.domain);
    final domainIcon = _domainIcon(project.domain);

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 灏侀潰:鏈?URL 鈫?Image.network(loadingBuilder/errorBuilder 鍥為€€ CoverArt);
          // 鏃?URL 鈫?CoverArt 鍗犱綅(浠诲姟鈶犵湡瀹炲皝闈㈠浘,涓嶅紩鍏ユ柊渚濊禆)
          if (coverUrl != null && coverUrl.isNotEmpty)
            KkImage(
              url: coverUrl,
              fit: BoxFit.cover,
              width: w,
              height: h,
              placeholder: (context) =>
                  CoverArt(pattern: pattern, width: w, height: h),
            )
          else
            CoverArt(pattern: pattern, width: w, height: h),
          // 鍗婇€忔槑鍘嬫殫閬僵,璁╁墠鏅?play / domain icon 鏇寸獊鍑?
          Container(color: Colors.black.withAlpha(20)),
          // 鍓嶆櫙:video 鍙?play 鎸夐挳(鐪熷浘涓?;鏃犲皝闈㈡椂鍙犻鍩熷浘鏍?鏈夌湡鍥句笉鍙?鍥炬湰韬嵆瑙嗚)
          if (isVideo)
            Center(
              child: Icon(Icons.play_circle_outline,
                  size: 48, color: Colors.white.withAlpha(220)),
            )
          else if (coverUrl == null || coverUrl.isEmpty)
            Center(
              child: Icon(domainIcon,
                  size: 36, color: Colors.white.withAlpha(200)),
            ),
        ],
      ),
    );
  }

  IconData _domainIcon(String domain) {
    switch (domain) {
      case 'ai_image':
        return Icons.image_outlined;
      case 'ai_video':
        return Icons.play_circle_outline;
      case 'web':
        return Icons.language;
      case 'app':
        return Icons.phone_iphone;
      case 'tool':
        return Icons.build_outlined;
      case 'opensource':
        return Icons.code;
      case 'prompt':
        return Icons.chat_bubble_outline;
      default:
        return Icons.work_outline;
    }
  }

  /// 棰嗗煙 鈫?CoverArt 鍥炬鏄犲皠(HANDOFF 搂5 瑁呴グ鐢?5 绉嶅浘妗堝搴斾笉鍚岄鍩熻涔?
  ///
  /// - ai_image   鈫?circles(鍚屽績鍦?鍛煎簲鍥惧儚鐢熸垚鐨勬墿鏁ｆ劅)
  /// - ai_video   鈫?waves(娉㈡氮,鍛煎簲瑙嗛娴佸姩)
  /// - web        鈫?grid(缃戞牸,鍛煎簲缃戦〉缁撴瀯)
  /// - app        鈫?mountains(灞卞肠,鍛煎簲 app 灞傚彔鏋舵瀯)
  /// - tool       鈫?grid(缃戞牸,宸ュ叿鎰?
  /// - opensource 鈫?ink(姘村ⅷ,寮€婧愭枃鍖栨劅)
  /// - prompt     鈫?waves(娉㈡氮,鏂囧瓧娴佸姩)
  /// - 鍏滃簳        鈫?mountains
  String _domainPattern(String domain) {
    switch (domain) {
      case 'ai_image':
        return 'circles';
      case 'ai_video':
        return 'waves';
      case 'web':
        return 'grid';
      case 'app':
        return 'mountains';
      case 'tool':
        return 'grid';
      case 'opensource':
        return 'ink';
      case 'prompt':
        return 'waves';
      default:
        return 'mountains';
    }
  }
}

// 鈹€鈹€ 璁℃暟灏忔爣(鏃?44pt 瑕佹眰,绾睍绀?鈹€鈹€
class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _Stat({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(value, style: KkType.mono.copyWith(fontSize: 11, color: color)),
      ],
    );
  }
}

// 鈹€鈹€ 浠诲姟鈶?鎷涚墝 take 琛?can-takeaway row)鈹€鈹€
//
// 鍦?summary 涓嬨€佷綔鑰呰涓?鏄剧ず銆岃兘鎷胯蛋浠€涔?路 鎬庝箞鐢ㄣ€嶁€斺€旀湰浜у搧鏈€鏍稿績 UX,
// 璁╀汉涓€鐪肩湅鍒般€岃兘鎷垮埌浠€涔堛€佹€庝箞鐢ㄣ€?鐩存帴椹卞姩銆屾兂鍋?鎯虫嬁璧般€嶆剰鍥俱€傚師鍨嬫瘡寮犲崱閮芥湁銆?
//
// 娓叉煋瑙勫垯(绂?if(artifactType) 纭紪鐮佸垎鏀?SPEC 搂6.1鈥斺€旂敤 whereType 妯″紡鍖归厤):
// - 鏈?TakeAction 鈫?鐝婄憵姗欐祬搴?chip(coralMint 搴?+ coral 鍥炬爣/鏂囧瓧);
//   鍥炬爣鎸?takeKind:copy 鈫?copy_outlined / download 鈫?download_outlined;
//   鏂囧瓧 = label 路 hint(浠诲姟鈶?Part B,hint null 鍙樉 label,鍚戝悗鍏煎)銆?
// - 鏃?TakeAction 鏈?GoAction 鈫?閫€鍖?teal銆屽幓鐪嬬湅銆峜hip(mint 搴?+ teal 鏂囧瓧 + 鈫?銆?
// - 閮芥棤(绾?HowAction / 绌?鈫?鏁磋涓嶆樉绀?璋冪敤鏂?whereType 鍒ゆ柇;姝?widget 闃插尽杩斿洖 shrink)銆?
//
// 閾佸緥(SPEC 搂6):
// - coral 鍙粰 take(go 閫€鍖栫敤 teal/mint,涓嶇敤 coral)銆?
// - 鏃犮€屾嬁璧般€嶄簩瀛?闈犲浘鏍?+ 鍚嶈瘝琛ㄦ剰),闆舵梺鐧?鏃?emoji銆?
// - 瑙︽帶 鈮?4pt:姝?chip 鏄€屾嫑鐗屾弿杩般€嶇函灞曠ず,鐐瑰嚮鐢卞崱鐗囨暣浣撴壙鎷?宸?Tappable),
//   鏁?chip 鑷韩涓嶅彲鐐?涓嶅己鍒?44pt(44pt 浠呯害鏉熷彲浜や簰鍏冪礌)銆?
class _TakeawayChip extends StatelessWidget {
  final List<ActionItem> actions;

  const _TakeawayChip({required this.actions});

  @override
  Widget build(BuildContext context) {
    // 绂?if(artifactType) 纭紪鐮佸垎鏀?SPEC 搂6.1)鈥斺€旂敤 whereType 妯″紡鍖归厤銆?
    final take = actions.whereType<TakeAction>().firstOrNull;
    if (take != null) return _takeChip(take);
    final go = actions.whereType<GoAction>().firstOrNull;
    if (go != null) return _goChip();
    return const SizedBox.shrink();
  }

  Widget _takeChip(TakeAction take) {
    final isCopy = take.takeKind == 'copy';
    final icon = isCopy ? Icons.copy_outlined : Icons.download_outlined;
    final label = take.label ?? (isCopy ? '澶嶅埗' : '涓嬭浇');
    final hasHint = take.hint != null && take.hint!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.sm,
        vertical: 6.0,
      ),
      decoration: BoxDecoration(
        // 鐝婄憵姗欐祬搴?SPEC 搂6.2:coral 鍙粰 take)
        color: KkColors.coralMint,
        borderRadius: BorderRadius.circular(KkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: KkColors.coral),
          const SizedBox(width: KkSpacing.xs),
          Text(
            label,
            style: KkType.bodySm.copyWith(
              fontSize: 12,
              color: KkColors.coral,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasHint) ...[
            Text(
              ' 路 ',
              // 寰皟:鍒嗛殧鐐圭敤涓€?t3,鍜?hint 涓€鑷?label 鎵嶆槸鍝佺墝鑹茬劍鐐?
              style: KkType.bodySm.copyWith(
                fontSize: 12,
                color: KkColors.t3,
              ),
            ),
            Flexible(
              child: Text(
                take.hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // 寰皟:hint銆屾€庝箞鐢ㄣ€嶇敤涓€?t2,璁?鎷垮埌浠€涔?(label coral)涓?
                // "鎬庝箞鐢?(鐏?灞傛鍒嗘槑,涓嶈嚦浜庢暣鏉￠兘鐝婄憵姗?鍙戞弧"銆?
                style: KkType.bodySm.copyWith(
                  fontSize: 12,
                  color: KkColors.t2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _goChip() {
    // 閫€鍖?teal銆屽幓鐪嬬湅銆?mint 搴?+ teal 鏂囧瓧 + 鈫?銆備笉鐢?coral(SPEC 搂6.2)銆?
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.sm,
        vertical: 6.0,
      ),
      decoration: BoxDecoration(
        color: KkColors.mint,
        borderRadius: BorderRadius.circular(KkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '去看看',
            style: KkType.bodySm.copyWith(
              fontSize: 12,
              color: KkColors.teal,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.arrow_outward,
            size: 14,
            color: KkColors.teal,
          ),
        ],
      ),
    );
  }
}
