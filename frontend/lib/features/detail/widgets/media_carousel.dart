import 'package:flutter/material.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/tappable.dart';
import '../../../domain/models/models.dart';
import '../../shared/image_lightbox.dart';
import 'video_block.dart';

/// 成果区 media 渲染器 — HANDOFF §2.1。
///
/// 规则:
///   - 视频优先:有视频,视频块排最上(真播放器)
///   - 视频之下,照片做小红书式横向滑动轮播:swipe + 右上"当前/总数" +
///     下方圆点 + 统一比例裁切框 + 点开 lightbox
///   - 无任何 media → 不出空展示块(由 detail screen 控制)
class MediaCarousel extends StatefulWidget {
  final List<MediaItem> media;

  const MediaCarousel({super.key, required this.media});

  @override
  State<MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<MediaCarousel> {
  late final List<MediaItem> _videos;
  late final List<MediaItem> _images;
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _videos = widget.media.where((m) => m.type == 'video').toList();
    _images = widget.media.where((m) => m.type == 'image').toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 视频块(每个一个,排最上)
        for (final v in _videos) ...[
          VideoBlock(media: v),
          const SizedBox(height: KkSpacing.sm),
        ],

        // 照片轮播(小红书式)
        if (_images.isNotEmpty) _imageCarousel(),
      ],
    );
  }

  Widget _imageCarousel() {
    return Stack(
      children: [
        // 统一比例裁切框(4:3,避免高矮不齐 — HANDOFF §2.1)
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KkRadius.md),
            child: PageView.builder(
              itemCount: _images.length,
              onPageChanged: (i) => setState(() => _imageIndex = i),
              itemBuilder: (context, i) {
                final img = _images[i];
                return Tappable(
                  onTap: () => _openLightbox(i),
                  borderRadius: BorderRadius.zero,
                  child: Image.network(
                    img.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: KkColors.bgSubtle,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined,
                          color: KkColors.t3, size: 32),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // 右上:当前/总数(HANDOFF §2.1)
        if (_images.length > 1)
          Positioned(
            top: KkSpacing.sm,
            right: KkSpacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x80000000),
                borderRadius: BorderRadius.circular(KkRadius.pill),
              ),
              child: Text(
                '${_imageIndex + 1}/${_images.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
          ),

        // 下方圆点(HANDOFF §2.1)
        if (_images.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: KkSpacing.sm,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_images.length, (i) {
                final active = i == _imageIndex;
                return AnimatedContainer(
                  duration: KkDuration.fast,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: active ? 16 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : const Color(0x80FFFFFF),
                    borderRadius: BorderRadius.circular(KkRadius.pill),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  void _openLightbox(int index) {
    // 任务 A:改用共享 openImageLightbox(收 List<String> url)。
    openImageLightbox(
      context,
      urls: [for (final m in _images) m.url],
      initialIndex: index,
    );
  }
}
