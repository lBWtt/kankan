// 这个文件是干什么的：集中放后端接入的编译期配置（API 地址、是否走真后端）。
// 它对应产品里的什么功能：决定看看 feed 等页面读 mock 还是读 FastAPI 真数据。
// 如果它出错了：接口地址错→全站接口连不上；useRemote 判断错→读错数据源。
//
// 用 --dart-define 覆盖，例：
//   flutter build web --dart-define=USE_REMOTE=true --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
class AppConfig {
  AppConfig._();

  /// 后端 API 根地址（含 /api/v1）。默认本机 uvicorn。
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  /// 是否走真后端。默认 false=读内存 mock（保证不带 flag 构建时行为不变）。
  static const bool useRemote = bool.fromEnvironment(
    'USE_REMOTE',
    defaultValue: true,
  );

  /// 管理员构建开关。默认 false —— **给用户下载的正式 app 里恒为 false**，
  /// 审核入口（悬浮球）+ 审核页整片代码在编译期被 tree-shake 掉，不进公开包。
  /// 只有本机/后台用 `--dart-define=ADMIN=true` 构建时才出现，跟消费端完全隔离。
  /// 上线后同一份代码 `flutter build web --dart-define=ADMIN=true` 即变浏览器审核后台。
  static const bool adminBuild = bool.fromEnvironment(
    'ADMIN',
    defaultValue: false,
  );

  /// 后端站点根（去掉 /api/v1）——用于把 /uploads/... 这类相对媒体地址补成可加载的绝对 URL。
  /// 例：apiBaseUrl=http://127.0.0.1:8000/api/v1 → serverOrigin=http://127.0.0.1:8000
  static String get serverOrigin {
    var s = apiBaseUrl;
    for (final suffix in const ['/api/v1', '/api']) {
      if (s.endsWith(suffix)) {
        s = s.substring(0, s.length - suffix.length);
        break;
      }
    }
    return s;
  }

  /// 把后端返回的媒体地址补全：已是 http(s) 原样返回；`/uploads/x` 前面补 serverOrigin。
  static String resolveMedia(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$serverOrigin$url';
    return '$serverOrigin/$url';
  }
}
