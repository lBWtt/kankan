// 这个文件是干什么的：判断一个 id 是不是后端真项目（UUID）而非 mock 短 id。
// 它对应产品里的什么功能：写通路（收藏/删除/订阅）只对真后端项目发请求，mock 项目本地处理。
// 如果它出错了：对 mock 项目误发后端请求（404），或对真项目漏发（不落库）。
//
// 后端 id 是标准 UUID；mock id 是 'p1'/'chen' 这类短串。
// 用严格 UUID 正则判断（比"含 - 且 ≥32"稳：不会被含连字符的长 mock 串误判）。
final RegExp _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool looksLikeBackendId(String id) => _uuidRe.hasMatch(id);
