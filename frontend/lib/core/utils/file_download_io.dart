// 非 web 平台实现：dio 流式下载到 path_provider 临时目录。
//
// 这个文件是干什么的：移动端真后台下载文件到临时目录，返回路径。
// 它对应产品里的什么功能：take「下载」动作真落盘（不再用 url_launcher 兜底）。
// 如果它出错了：返回 null，调用方 toast 失败。
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// 下载 [url] 到临时目录，返回保存路径；失败返回 null。
Future<String?> platformDownloadUrlToFile(String url) async {
  try {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final dio = Dio();
    final dir = await getTemporaryDirectory();
    final name = uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
        ? uri.pathSegments.last
        : 'download_${DateTime.now().millisecondsSinceEpoch}';
    final savePath = '${dir.path}/$name';
    await dio.download(url, savePath);
    return savePath;
  } catch (_) {
    return null;
  }
}
