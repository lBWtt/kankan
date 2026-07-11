// 条件导入：非 web → Image.file（dart:io）；web → Image.network（picker 返回 blob URL）。
//
// 这个文件是干什么的：显示「本地选取的图片」（image_picker 返回的文件路径 / web blob URL）。
// 它对应产品里的什么功能：发图预览（compose / media_picker）、换背景图（我的页 banner）。
// 如果它出错了：选了图预览显不出（原来移动端本地路径用 Image.network 会挂 → 显随机占位图/兜底图）。
import 'package:flutter/widgets.dart';

import 'local_image_io.dart' if (dart.library.html) 'local_image_web.dart';

/// 显示本地选取的图片。移动端文件路径 → Image.file；web blob URL → Image.network。
/// 加载失败回退 [placeholder]（不给则 SizedBox.shrink）。
Widget localImage(String path, {BoxFit fit = BoxFit.cover, Widget? placeholder}) {
  return platformLocalImage(path, fit: fit, placeholder: placeholder);
}
