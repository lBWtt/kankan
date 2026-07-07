// Web 平台 stub：web 不走 dio+path_provider（dart:html 下载由调用方 url_launcher 处理）。
// 返回 null，调用方退 url_launcher 让浏览器原生下载。
//
// 这个文件是干什么的：web 端 file_download 的占位实现。
/// web 平台返回 null（下载由 url_launcher 处理）。
Future<String?> platformDownloadUrlToFile(String url) async {
  return null;
}
