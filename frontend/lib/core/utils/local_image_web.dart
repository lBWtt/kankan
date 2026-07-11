import 'package:flutter/widgets.dart';

/// web：image_picker 返回的是 blob URL，Image.network 可直接显示。
Widget platformLocalImage(String path, {BoxFit fit = BoxFit.cover, Widget? placeholder}) {
  return Image.network(
    path,
    fit: fit,
    errorBuilder: (_, __, ___) => placeholder ?? const SizedBox.shrink(),
  );
}
