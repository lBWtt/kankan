import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/tappable.dart';
import '../../../domain/models/models.dart';
import '../../../features/detail/widgets/action_row.dart';
import '../../../features/detail/widgets/io_block_view.dart';
import '../../../features/detail/widgets/media_carousel.dart';
import '../../../features/detail/widgets/repo_card.dart';
import '../../../providers/publish_provider.dart';

/// 实时预览 — HANDOFF §4 验收:发布端产出的数据结构 = 详情端可组合渲染所读的
/// {media(视频优先), actions:[take/go/how]}。两端咬合。
///
/// 直接复用 detail 的渲染器(MediaCarousel / RepoCard / IoBlockView / ActionRow),
/// 保证发布端看到的样子 = 详情端真实显示的样子。
class PublishPreview extends ConsumerWidget {
  const PublishPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(publishDraftProvider);

    // 构建 ResultData(视频自动排前 — PublishDraft.toProject 已处理,这里预览同源)
    final sortedMedia = _videoFirst(draft.media);
    final rd = ResultData(
      media: sortedMedia,
      text: draft.text,
    );

    // 空内容 → 整块隐藏(HANDOFF §3 零旁白 + 空状态隐藏):不显"空"字、不撑高度。
    // 有内容才渲染预览。
    final isEmpty = draft.title.isEmpty &&
        draft.summary.isEmpty &&
        rd.media.isEmpty &&
        rd.text == null &&
        draft.actions.isEmpty;
    if (isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.md),
        border: Border.all(color: KkColors.bd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 预览标识(零旁白:只标"预览",不写"这是发布后的样子")
          Padding(
            padding: const EdgeInsets.all(KkSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined,
                    size: 14, color: KkColors.t3),
                const SizedBox(width: KkSpacing.xs),
                Text('预览', style: KkType.mono.copyWith(fontSize: 11)),
              ],
            ),
          ),

          // 标题(若有)
          if (draft.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KkSpacing.md),
              child: Text(draft.title, style: KkType.h2),
            ),

          // 一句话价值(若有)
          if (draft.summary.isNotEmpty) ...[
            const SizedBox(height: KkSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KkSpacing.md),
              child: Text(draft.summary, style: KkType.bodySm),
            ),
          ],

          // 成果区(复用 detail 渲染器)
          if (rd.media.isNotEmpty || rd.text != null) ...[
            const SizedBox(height: KkSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KkSpacing.md),
              child: _results(rd),
            ),
          ],

          // 动作区(复用 detail 的 ActionRow)
          if (draft.actions.isNotEmpty) ...[
            const SizedBox(height: KkSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KkSpacing.md),
              child: ActionRow(actions: draft.actions),
            ),
          ],

          const SizedBox(height: KkSpacing.md),
        ],
      ),
    );
  }

  /// 成果区渲染 — 与 detail_screen._results 同源逻辑(复用渲染器)
  Widget _results(ResultData rd) {
    final children = <Widget>[];
    if (rd.media.isNotEmpty) {
      children.add(MediaCarousel(media: rd.media));
    }
    if (rd.repo != null) {
      if (children.isNotEmpty) children.add(const SizedBox(height: KkSpacing.md));
      children.add(RepoCard(repo: rd.repo!));
    }
    if (rd.io != null) {
      if (children.isNotEmpty) children.add(const SizedBox(height: KkSpacing.md));
      children.add(IoBlockView(io: rd.io!));
    }
    if (rd.text != null && rd.text!.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: KkSpacing.md));
      children.add(Text(rd.text!, style: KkType.body.copyWith(height: 1.7)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// 视频排前(HANDOFF §4)
  List<MediaItem> _videoFirst(List<MediaItem> media) {
    final videos = media.where((m) => m.type == 'video').toList();
    final images = media.where((m) => m.type == 'image').toList();
    return [...videos, ...images];
  }
}
