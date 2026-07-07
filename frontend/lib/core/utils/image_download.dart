import 'dart:typed_data';

// 条件导入:web → dart:html AnchorElement+Blob 下载;非 web → stub。
// 任务 B:share_sheet 海报 RepaintBoundary.toImage → toByteData(png) →
// 触发浏览器下载。移动端不编译 dart:html(条件导入隔离)。
import 'image_download_io.dart'
    if (dart.library.html) 'image_download_web.dart';

/// 把 PNG 字节下载到用户设备(web:浏览器下载;非 web:暂不支持,返回 false)。
/// 成功返回 true。调用方据结果 toast「已保存」/「保存失败」。
Future<bool> downloadPngBytes(Uint8List bytes, String filename) {
  return platformDownloadPngBytes(bytes, filename);
}
