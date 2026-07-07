// 这个文件是干什么的：把后端 GET /projects 的卡片 JSON 映射成前端 Project 模型。
// 它对应产品里的什么功能：看看 feed 的每张卡（真数据模式）。
// 如果它出错了：真数据 feed 解析失败或字段错位。
//
// 已知模型分叉（B 轨，见 flutter-backend-integration 记忆）：
//   - 后端 domains 是职业枚举(design/dev/...)，前端 domain 是成果类型(ai_image/...)——
//     这里按 category 尽力映射，不透传前端 domain 筛选。
//   - 卡片无 likes（counts 为 null）→ likes 记 0；author 不展开 → authorId 置空，
//     调用方在真数据模式下用 showAuthor:false 隐藏作者行。
//   - resultData 仅填封面 media；actions/io/repo 留空（详情级数据后续接详情端点）。
import '../../core/config/app_config.dart';
import '../../domain/models/models.dart';
import '../remote_user_cache.dart';

/// 解析后端 author(UserBrief){id,nickname,avatar_url} → 缓存成远程 KkUser + 返回 authorId。
/// 前端 Project 只存 authorId，作者名/头像靠 userByIdProvider 查——缓存让远程作者也查得到。
String _authorIdAndCache(dynamic author) {
  if (author is! Map) return '';
  final id = author['id']?.toString() ?? '';
  if (id.isEmpty) return '';
  final nickname = author['nickname']?.toString();
  cacheRemoteUser(KkUser(
    id: id,
    name: (nickname != null && nickname.isNotEmpty) ? nickname : id,
    avatar: author['avatar_url']?.toString(),
  ));
  return id;
}

/// 后端 counts.reactions{creative,big_brain,cool} 三项之和 = 前端「获赞/点赞」。
int _likesFromCounts(dynamic counts) {
  if (counts is! Map) return 0;
  final r = counts['reactions'];
  if (r is! Map) return 0;
  int n(String k) {
    final v = r[k];
    return v is int ? v : int.tryParse('$v') ?? 0;
  }

  return n('creative') + n('big_brain') + n('cool');
}

/// 后端媒体 URL 可能是相对路径（/uploads/xxx.png，local 存储）。相对路径要拼上后端 origin
/// 才能在浏览器显示（否则被当成前端同源 5599 解析）。绝对 URL（http/https）原样返回。
String _resolveMediaUrl(String url) {
  if (url.isEmpty || url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  // apiBaseUrl = 'http://127.0.0.1:8000/api/v1' → origin = 'http://127.0.0.1:8000'
  var origin = AppConfig.apiBaseUrl;
  final apiIdx = origin.indexOf('/api/');
  if (apiIdx > 0) origin = origin.substring(0, apiIdx);
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}

/// 后端 category → 前端 domain（成果类型）尽力映射，兜底 'tool'。
String _mapDomain(String? category) {
  switch (category) {
    case 'image_design':
    case 'image':
      return 'ai_image';
    case 'video':
    case 'video_edit':
      return 'ai_video';
    case 'web':
    case 'web_design':
      return 'web';
    case 'app':
    case 'mobile':
      return 'app';
    case 'prompt':
    case 'writing':
      return 'prompt';
    case 'opensource':
    case 'open_source':
      return 'opensource';
    default:
      return 'tool';
  }
}

int _parseMs(dynamic isoOrNull) {
  if (isoOrNull is String && isoOrNull.isNotEmpty) {
    final dt = DateTime.tryParse(isoOrNull);
    if (dt != null) return dt.millisecondsSinceEpoch;
  }
  return DateTime.now().millisecondsSinceEpoch;
}

/// 从后端**详情** JSON 造 Project（GET /projects/{id}，比卡片多 intro/author/media/counts）。
/// 详情页 `projectByIdProvider` 在 remote 模式命中时用。作者：后端展开了 author 对象，
/// 但前端 Project 只存 authorId（作者名靠 userByIdProvider 查 mock）——remote 作者不在 mock，
/// 故作者行会留空（已知分叉，同 feed 卡片）。
Project projectFromDetailJson(Map<String, dynamic> j) {
  // media：后端 media 数组 [{type,url,poster?,...}]；空则用 cover 兜一张。
  final rawMedia = j['media'];
  final media = <MediaItem>[];
  if (rawMedia is List) {
    for (final m in rawMedia.whereType<Map<dynamic, dynamic>>()) {
      final url = m['url']?.toString();
      if (url != null && url.isNotEmpty) {
        media.add(MediaItem(
          type: m['type']?.toString() == 'video' ? 'video' : 'image',
          url: _resolveMediaUrl(url),
          poster: m['poster'] != null
              ? _resolveMediaUrl(m['poster'].toString())
              : null,
        ));
      }
    }
  }
  if (media.isEmpty) {
    final cover = j['cover_media_url'];
    if (cover is String && cover.isNotEmpty) {
      media.add(MediaItem(type: 'image', url: _resolveMediaUrl(cover)));
    }
  }
  final tools = (j['tools'] is List)
      ? (j['tools'] as List).map((e) => e.toString()).toList()
      : const <String>[];
  final counts = j['counts'];
  final takeaway = counts is Map ? counts['takeaways'] : j['takeaway_count'];
  return Project(
    id: j['id'].toString(),
    title: (j['title'] ?? '').toString(),
    summary: (j['tagline'] ?? j['subtitle'] ?? '').toString(),
    authorId: _authorIdAndCache(j['author']),
    resultData: ResultData(media: media),
    actions: const [], // 后端 actions 结构与前端 sealed ActionItem 不同,暂不映射
    tags: tools,
    authorNote: (j['intro'] ?? j['description'])?.toString(),
    domain: _mapDomain(j['category']?.toString()),
    likes: _likesFromCounts(counts),
    commentCount: 0,
    takeawayCount: takeaway is int ? takeaway : int.tryParse('$takeaway') ?? 0,
    createdAtMs: _parseMs(j['published_at']),
  );
}

/// 从后端卡片 JSON 造一个前端 Project（feed 卡片够用的最小映射）。
Project projectFromCardJson(Map<String, dynamic> j) {
  final cover = j['cover_media_url'];
  final media = <MediaItem>[
    if (cover is String && cover.isNotEmpty)
      MediaItem(type: 'image', url: _resolveMediaUrl(cover)),
  ];
  final tools = (j['tools'] is List)
      ? (j['tools'] as List).map((e) => e.toString()).toList()
      : const <String>[];

  final counts = j['counts'];
  final takeaway = counts is Map ? counts['takeaways'] : j['takeaway_count'];
  return Project(
    id: j['id'].toString(),
    title: (j['title'] ?? '').toString(),
    summary: (j['tagline'] ?? j['subtitle'] ?? j['intro'] ?? '').toString(),
    authorId: _authorIdAndCache(j['author']), // 后端已填 author(UserBrief)→缓存+authorId
    resultData: ResultData(media: media),
    actions: const [],
    tags: tools,
    domain: _mapDomain(j['category']?.toString()),
    likes: _likesFromCounts(counts),
    commentCount: 0,
    takeawayCount: takeaway is int ? takeaway : int.tryParse('$takeaway') ?? 0,
    createdAtMs: _parseMs(j['published_at']),
  );
}
