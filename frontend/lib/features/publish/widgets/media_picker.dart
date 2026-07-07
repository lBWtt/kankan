import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/tappable.dart';
import '../../../domain/models/models.dart';

/// 媒体选择 — HANDOFF §4:传图/视频 → 成果(media),视频自动排前,首张作封面。
///
/// 用 image_picker 包。选完 → 调用 onPicked 回调 → publish_draft.addMedia。
///
/// 注意:image_picker 返回 XFile(本地路径)。Phase 2 mock 用本地路径做 Image.file
/// 显示。Phase 5 接后端上传,产出 URL 后存入 MediaItem.url。
class MediaPicker extends StatelessWidget {
  final List<MediaItem> current;
  /// 选中回调。bytes = 文件真实字节（发布时真上传后端；web 上必须靠它）。
  final void Function(MediaItem item, Uint8List? bytes) onPicked;
  final void Function(int) onRemoved;

  const MediaPicker({
    super.key,
    required this.current,
    required this.onPicked,
    required this.onRemoved,
  });

  Future<void> _pick(BuildContext context, String type) async {
    final picker = ImagePicker();
    try {
      if (type == 'image') {
        final files = await picker.pickMultiImage(imageQuality: 85);
        for (final f in files) {
          // url 存 blob/本地路径做预览；bytes 读真字节，发布时真上传后端。
          final bytes = await f.readAsBytes();
          onPicked(
            MediaItem(type: 'image', url: f.path, alt: '本地图片'),
            bytes,
          );
        }
      } else {
        final f = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 1),
        );
        if (f != null) {
          final bytes = await f.readAsBytes();
          onPicked(
            MediaItem(
              type: 'video',
              url: f.path,
              // 视频封面 Phase 5 用 ffmpeg 抽帧,Phase 2 留空
              poster: null,
              durationSec: 0,
              alt: '本地视频',
            ),
            bytes,
          );
        }
      }
    } catch (_) {
      // 用户取消或权限拒绝,静默
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已选媒体预览(视频在前 — toProject 时排序,这里按选择顺序显示)
        if (current.isNotEmpty) ...[
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: current.length,
              separatorBuilder: (_, __) => const SizedBox(width: KkSpacing.sm),
              itemBuilder: (context, i) {
                final m = current[i];
                return _MediaThumb(
                  media: m,
                  onRemove: () => onRemoved(i),
                );
              },
            ),
          ),
          const SizedBox(height: KkSpacing.md),
        ],

        // 添加按钮(两个:图 / 视频)
        Row(
          children: [
            _addButton(
              context,
              icon: Icons.image_outlined,
              label: '图片',
              onTap: () => _pick(context, 'image'),
            ),
            const SizedBox(width: KkSpacing.sm),
            _addButton(
              context,
              icon: Icons.video_library_outlined,
              label: '视频',
              onTap: () => _pick(context, 'video'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _addButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: KkSpacing.md,
          horizontal: KkSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: KkColors.bd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: KkColors.teal),
            const SizedBox(width: KkSpacing.xs),
            Text(label, style: KkType.bodySm.copyWith(color: KkColors.teal)),
          ],
        ),
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  final MediaItem media;
  final VoidCallback onRemove;

  const _MediaThumb({required this.media, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isVideo = media.type == 'video';
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(KkRadius.sm),
          child: SizedBox(
            width: 100,
            height: 100,
            child: _buildImage(),
          ),
        ),
        // 视频标记
        if (isVideo)
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0x80000000),
                borderRadius: BorderRadius.circular(KkRadius.sm),
              ),
              child: const Text(
                'VIDEO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
          ),
        // 删除按钮
        Positioned(
          right: 0,
          top: 0,
          child: Tappable(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(KkRadius.pill),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xCC000000),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close,
                  color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage() {
    // Phase 2:本地路径用 Image.file;Phase 5 上传后是 URL 用 Image.network
    if (media.url.startsWith('http')) {
      return Image.network(media.url, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    }
    // 本地路径
    // 注意:Image.file 需要 dart:io,Flutter mobile 可用,Web 不行
    // Phase 2 假设移动端,Web 兼容 Phase 6 处理
    try {
      return Image.network(
        'https://picsum.photos/seed/${media.url.hashCode}/100/100',
        fit: BoxFit.cover,
      ); // 占位(本地路径真显示需 Image.file,但跨平台兼容性差,先用占位)
    } catch (_) {
      return _placeholder();
    }
  }

  Widget _placeholder() {
    return Container(
      color: KkColors.bgSubtle,
      alignment: Alignment.center,
      child: Icon(
        media.type == 'video' ? Icons.videocam_outlined : Icons.image_outlined,
        color: KkColors.t3,
        size: 24,
      ),
    );
  }
}
