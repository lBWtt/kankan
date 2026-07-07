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
    defaultValue: false,
  );
}
