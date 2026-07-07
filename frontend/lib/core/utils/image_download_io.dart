import 'dart:typed_data';

import 'package:gal/gal.dart';

// 非 web 平台实现:把 PNG 字节存到系统相册(gal)。
// web 走 image_download_web.dart 浏览器下载(dart:html 条件导入隔离),本文件不编译。
//
// 这个文件是干什么的:移动端把分享海报 RepaintBoundary.toImage → toByteData(png)
// 的字节直接落盘到系统相册(Pictures 目录),不再 stub return false。
// 它对应产品里的什么功能:share_sheet「保存图片」渠道按钮在移动端真存相册。
// 如果它出错了:返回 false,调用方 toast「保存失败」。
//
// 权限处理:
// - gal 内部已处理 Android 权限请求(Android 13+ scoped storage 豁免;
//   Android 12 及以下 WRITE_EXTERNAL_STORAGE 由 gal 的 manifest 自动合并)。
// - iOS 需 Info.plist 配 NSPhotoLibraryAddUsageDescription,否则 putImageBytes
//   会触发 fatal 异常(Info.plist 缺文案时 iOS 直接崩,不进 catch)。
//   本仓库当前无 ios/ 目录(Flutter 项目仅 scaffold 了 web 平台),
//   未来 scaffold ios/ 后必须加该权限文案(见 worklog Task 11-C 已知风险)。
// Gal.hasAccess / Gal.requestAccess 的 toAlbum:false = 存 Pictures 默认目录(不建相册)。
// Gal.putImageBytes 的 name 不带扩展名(gal 自动补 .png/.jpg),故 strip 入参 .png 后缀。

/// 把 PNG [bytes] 存到系统相册(gal)。
///
/// 成功返回 true;失败(权限拒绝 / IO 错误 / GalException)返回 false。
/// 调用方据结果 toast「已保存到相册」/「保存失败」。
Future<bool> platformDownloadPngBytes(Uint8List bytes, String filename) async {
  try {
    // 权限检查 / 请求(iOS 需 Info.plist 权限文案,Android gal 自动处理)。
    if (!await Gal.hasAccess(toAlbum: false)) {
      final granted = await Gal.requestAccess(toAlbum: false);
      if (!granted) return false;
    }
    // name 不带扩展名, gal 自动加 .jpg/.png; strip 入参 .png 避免双扩展。
    final name = filename.endsWith('.png')
        ? filename.substring(0, filename.length - 4)
        : filename;
    await Gal.putImageBytes(bytes, name: name);
    return true;
  } on GalException {
    return false;
  } catch (_) {
    return false;
  }
}
