// 条件导入：web → stub（action_row 走 url_launcher 兜底）；非 web → dio 真下载。
//
// 这个文件是干什么的：把一个 URL 文件下载到设备临时目录，返回保存路径（成功）或 null（失败）。
// 它对应产品里的什么功能：详情页 take 动作「下载」按钮真后台下载文件。
// 如果它出错了：下载失败 toast；web 端走 url_launcher 兜底浏览器下载。
import 'file_download_io.dart'
    if (dart.library.html) 'file_download_web.dart';

/// 下载 [url] 到设备临时目录，返回保存路径；失败返回 null。
/// web 平台返回 null（调用方应退 url_launcher 让浏览器下载）。
Future<String?> downloadUrlToFile(String url) {
  return platformDownloadUrlToFile(url);
}
