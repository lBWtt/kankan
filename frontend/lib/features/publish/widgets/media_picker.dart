import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/local_image.dart';

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
          // 先查文件大小再读字节，避免 4K/长视频 readAsBytes 直接 OOM。
          const maxVideoBytes = 80 * 1024 * 1024; // 80MB
          final size = await f.length();
          if (size > maxVideoBytes) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('视频太大（上限 80MB），请压缩后再传')),
              );
            }
            return;
          }
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
    // 空态：大号「画布」主角——薄荷底 + 圆形图标 + 邀请文案（视觉优先，先给作品一个大位置）。
    if (current.isEmpty) {
      return GestureDetector(
        onTap: () => _showPickSheet(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          height: 216,
          decoration: BoxDecoration(
            color: KkColors.mint.withAlpha(90),
            borderRadius: BorderRadius.circular(KkRadius.lg),
            border: Border.all(color: KkColors.teal.withAlpha(70), width: 1.4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: KkColors.teal.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_photo_alternate_outlined,
                    size: 30, color: KkColors.teal),
              ),
              const SizedBox(height: KkSpacing.md),
              Text('放上你的作品',
                  style: KkType.body.copyWith(
                      color: KkColors.teal, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('图片 · 视频',
                  style: KkType.bodySm.copyWith(color: KkColors.t3)),
            ],
          ),
        ),
      );
    }
    // 有内容：横向缩略图 + 末尾小加号入口。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: current.length,
            separatorBuilder: (_, __) => const SizedBox(width: KkSpacing.sm),
            itemBuilder: (context, i) {
              final m = current[i];
              return _MediaThumb(media: m, onRemove: () => onRemoved(i));
            },
          ),
        ),
        const SizedBox(height: KkSpacing.md),
        _addButton(
          context,
          icon: Icons.add_photo_alternate_outlined,
          label: '加图片 / 视频',
          onTap: () => _showPickSheet(context),
        ),
      ],
    );
  }

  // 一个入口 → 底部选「图片 / 视频」。
  void _showPickSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KkColors.bgCard,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pickSheetItem(sheetCtx, Icons.image_outlined, '图片', 'image'),
            const Divider(height: 1, color: KkColors.divider, indent: 56),
            _pickSheetItem(sheetCtx, Icons.video_library_outlined, '视频', 'video'),
          ],
        ),
      ),
    );
  }

  Widget _pickSheetItem(
      BuildContext sheetCtx, IconData icon, String label, String type) {
    return Tappable(
      onTap: () {
        Navigator.pop(sheetCtx);
        _pick(sheetCtx, type);
      },
      borderRadius: BorderRadius.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: KkColors.teal),
            const SizedBox(width: KkSpacing.md),
            Text(label, style: KkType.body.copyWith(color: KkColors.t1)),
          ],
        ),
      ),
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
    if (media.url.startsWith('http')) {
      return Image.network(media.url, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    }
    // 本地选取的图片：移动端 Image.file / web blob URL → 真显示（不再用随机占位图）。
    return localImage(media.url, fit: BoxFit.cover, placeholder: _placeholder());
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
