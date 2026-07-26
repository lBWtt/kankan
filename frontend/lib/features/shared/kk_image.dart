import 'package:flutter/material.dart';

/// 统一封面/配图渲染：
///   - url 以 `assets/` 开头 → `Image.asset`（打包的本地 mock 图，断网也显示）
///   - 否则 → `Image.network`（远端 /uploads 或外链）
/// 加载中 / 失败都回退到 [placeholder]（通常传 CoverArt）。
///
/// 目的：demo 模式用本地 asset 封面（不再 picsum/chatglm 外链破图），
/// 远端模式照旧走后端 URL——两条路同一个组件。
class KkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final WidgetBuilder? placeholder;

  const KkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  bool get _isAsset => url.startsWith('assets/');

  Widget _fallback(BuildContext context) =>
      placeholder?.call(context) ?? const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    if (_isAsset) {
      return Image.asset(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (c, _, __) => _fallback(c),
      );
    }
    // 解码上限：把图按「等比缩放进 1080×1080 盒子」再解码。
    // 后端 /uploads 里有 1440×3120 这类整屏截图，只 cap 宽会剩 1080×2340(2.5MP) 仍然过大，
    // 在真机上一次性解码/上传这么大的位图会卡死主线程 → 收藏页 ANR「应用无响应」。
    // ResizeImagePolicy.fit 等比装进盒子(1440×3120 → 498×1080≈0.5MP)，既治卡死也省内存；
    // allowUpscaling:false 保证小图不被拉大糊掉。封面/详情在手机上都够清晰。
    const maxSide = 1080;
    return Image(
      image: ResizeImage(
        NetworkImage(url),
        width: maxSide,
        height: maxSide,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      ),
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (c, child, progress) =>
          progress == null ? child : _fallback(c),
      errorBuilder: (c, _, __) => _fallback(c),
    );
  }
}
