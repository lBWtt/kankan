import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/tappable.dart';

/// 全屏图片灯箱(共享组件)— 任务 A 抽出。
///
/// 从 media_carousel._Lightbox 抽出,供:
///   - detail 封面轮播(media_carousel)
///   - 动态卡九宫格(post_card._ImageGrid)
///   - 动态详情图片网格(post_detail_screen._ImageGrid)
/// 三处复用。统一 PhotoViewGallery 缩放 + 左右滑 + 点击关闭。
///
/// 只收**图片** url(video 排除,由调用方过滤)。url 用各卡已解析好的绝对地址。
///
/// 用法:
///   openImageLightbox(context, urls: ['https://.../a.jpg', 'https://.../b.jpg'], initialIndex: 0);
void openImageLightbox(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
}) {
  if (urls.isEmpty) return;
  final clamped = initialIndex.clamp(0, urls.length - 1);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _ImageLightbox(
        urls: urls,
        initialIndex: clamped,
      ),
      fullscreenDialog: true,
    ),
  );
}

class _ImageLightbox extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _ImageLightbox({required this.urls, required this.initialIndex});

  @override
  State<_ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<_ImageLightbox> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PhotoViewGallery.builder(
              itemCount: widget.urls.length,
              pageController: _controller,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              onPageChanged: (i) => setState(() => _index = i),
              builder: (context, index) {
                return PhotoViewGalleryPageOptions(
                  imageProvider: NetworkImage(widget.urls[index]),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 2,
                  errorBuilder: (_, __, ___) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_outlined,
                            color: Colors.white54, size: 48),
                        const SizedBox(height: KkSpacing.sm),
                        Text(
                          '图片加载失败',
                          style: KkType.bodySm
                              .copyWith(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // 关闭按钮(右上,44pt 热区)
            Positioned(
              top: 0,
              right: 0,
              child: Tappable(
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(KkSpacing.md),
                  child: Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
            // 计数指示(多图时左上)
            if (widget.urls.length > 1)
              Positioned(
                top: 0,
                left: 0,
                child: Padding(
                  padding: const EdgeInsets.all(KkSpacing.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x80000000),
                      borderRadius: BorderRadius.circular(KkRadius.pill),
                    ),
                    child: Text(
                      '${_index + 1}/${widget.urls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
