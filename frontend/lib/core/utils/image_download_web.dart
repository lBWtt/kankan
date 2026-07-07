import 'dart:html' as html;
import 'dart:typed_data';

/// Web 平台实现:用 dart:html 的 Blob + AnchorElement 触发浏览器下载。
/// 任务 B:share_sheet 海报 RepaintBoundary.toImage → toByteData(png) →
/// Uint8List → Blob(image/png) → AnchorElement.download → click → revoke。
/// 全程同步(无网络),浏览器下载到默认下载目录。
Future<bool> platformDownloadPngBytes(Uint8List bytes, String filename) async {
  try {
    final blob = html.Blob([bytes], 'image/png');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
    return true;
  } catch (_) {
    return false;
  }
}
