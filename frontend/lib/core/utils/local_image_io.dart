import 'dart:io';

import 'package:flutter/widgets.dart';

/// 非 web：本地文件路径用 Image.file 真显示。
Widget platformLocalImage(String path, {BoxFit fit = BoxFit.cover, Widget? placeholder}) {
  return Image.file(
    File(path),
    fit: fit,
    errorBuilder: (_, __, ___) => placeholder ?? const SizedBox.shrink(),
  );
}
