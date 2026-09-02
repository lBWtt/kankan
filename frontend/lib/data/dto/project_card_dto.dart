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
import '../../core/utils/parse_ms.dart';
import '../../domain/models/models.dart';
import '../remote_user_cache.dart';

/// 解析后端 author(UserBrief){id,nickname,avatar_url} → 缓存成远程 KkUser + 返回 authorId。
/// 前端 Project 只存 authorId，作者名/头像靠 userByIdProvider 查——缓存让远程作者也查得到。
String _authorIdAndCache(dynamic author) {
  if (author is! Map) return '';
  final id = author['id']?.toString() ?? '';
  if (id.isEmpty) return '';
  final nickname = author['nickname']?.toString();
  final handle = author['handle']?.toString();
  cacheRemoteUser(KkUser(
    id: id,
    name: (nickname != null && nickname.isNotEmpty) ? nickname : id,
    handle: (handle != null && handle.isNotEmpty) ? handle : null,
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
/// 单一实现集中在 AppConfig.resolveMedia；这里保留同名薄封装，减少调用点改动。
String _resolveMediaUrl(String url) => AppConfig.resolveMedia(url);

/// 兜底：后端 content_type 为空（旧数据）时，从 category 尽力映射，兜底 'tool'。
/// 正常走后端真 content_type（见 domain 字段），此函数仅作 null 回退。
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

/// 把后端 repo_stars 字符串（"148k" / "1.2k" / "2300" / "—"）解析成 int（RepoInfo.stars 用）。
/// 解析不出（空 / 破折号）返回 0。
int _parseStars(dynamic raw) {
  if (raw == null) return 0;
  final s = raw.toString().trim().toLowerCase();
  if (s.isEmpty || s == '—' || s == '-') return 0;
  final m = RegExp(r'^([0-9]+(?:\.[0-9]+)?)\s*([km]?)').firstMatch(s);
  if (m == null) return 0;
  final base = double.tryParse(m.group(1)!) ?? 0;
  final unit = m.group(2);
  final mult = unit == 'k' ? 1000 : (unit == 'm' ? 1000000 : 1);
  return (base * mult).round();
}

/// 从详情 JSON 的 source_url 造 RepoInfo（成果区仓库卡 + 「去 GitHub」外链）。
/// 无 source_url → null（不出仓库卡）。owner/repo 从 URL 路径末两段取。
RepoInfo? _repoFromSource(Map<String, dynamic> j) {
  final url = j['source_url']?.toString();
  if (url == null || url.isEmpty) return null;
  // 只对 GitHub 源渲染「仓库卡 + 去 GitHub」出处；小红书/抖音等来源不展示出处
  // （马甲发布=纯用户原创感，决策：完全不留出处）。非 github 源直接不出卡。
  if (!url.contains('github.com')) return null;
  var fullName = url;
  final schemeIdx = url.indexOf('://');
  if (schemeIdx >= 0) {
    final path = url.substring(schemeIdx + 3);
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    // segs[0]=域名, segs[1]=owner, segs[2]=repo
    if (segs.length >= 3) {
      fullName = '${segs[1]}/${segs[2]}';
    } else if (segs.length == 2) {
      fullName = segs[1];
    }
  }
  final name = fullName.contains('/') ? fullName.split('/').last : fullName;
  final author = j['original_author_name']?.toString();
  return RepoInfo(
    name: name,
    fullName: fullName,
    stars: _parseStars(j['repo_stars']),
    // 后端不返回主语言 → 留空（RepoCard 空则不显示语言那段）。
    language: '',
    url: url,
    description: (author != null && author.isNotEmpty) ? '原作者：$author' : null,
  );
}

/// 轻量 markdown → 纯文本：去掉标题井号、把 -/* 列表符号换成 •、去掉 ** 粗体标记。
/// 后端 intro 可能带 markdown，详情页用纯 Text 渲染，先清一遍免得显示生 `##`。
String _stripLightMarkdown(String s) {
  final out = <String>[];
  for (final line in s.split('\n')) {
    var t = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
    t = t.replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ');
    t = t.replaceAll('**', '');
    out.add(t);
  }
  return out.join('\n').trim();
}

/// 后端 project_actions（ProjectActionOut）→ 前端 sealed ActionItem。
/// type∈{take,go,how}、sub∈{text,file,github,appstore,url,workflow}（响应用 alias type/sub）。
///   - take/text → 复制文本(content)  · take/file → 下载文件(url)
///   - go/*      → 外链(url)          · how/*     → 工作流(url 或 content)
List<ActionItem> _actionsFromJson(dynamic raw) {
  if (raw is! List) return const [];
  final out = <ActionItem>[];
  for (final e in raw.whereType<Map<dynamic, dynamic>>()) {
    final m = Map<String, dynamic>.from(e);
    final type = (m['type'] ?? m['action_type'])?.toString();
    final sub = (m['sub'] ?? m['action_sub'])?.toString();
    final label = (m['label'] as String?)?.trim();
    final content = (m['content'] as String?)?.trim();
    final url = (m['url'] as String?)?.trim();
    switch (type) {
      case 'take':
        if (sub == 'file' && url != null && url.isNotEmpty) {
          out.add(TakeAction(
            source: _resolveMediaUrl(url),
            takeKind: 'download',
            label: label,
          ));
        } else if (content != null && content.isNotEmpty) {
          out.add(TakeAction(
            source: content,
            takeKind: 'copy',
            label: label,
          ));
        }
      case 'go':
        if (url != null && url.isNotEmpty) {
          out.add(GoAction(url: url, label: label));
        }
      case 'how':
        final ref = (url != null && url.isNotEmpty) ? url : (content ?? '');
        if (ref.isNotEmpty) out.add(HowAction(ref: ref, label: label));
    }
  }
  return out;
}

/// 从后端**详情** JSON 造 Project（GET /projects/{id}，比卡片多 intro/author/media/counts）。
/// 详情页 `projectByIdProvider` 在 remote 模式命中时用。作者：后端展开了 author 对象，
/// 但前端 Project 只存 authorId（作者名靠 userByIdProvider 查 mock）——remote 作者不在 mock，
/// 故作者行会留空（已知分叉，同 feed 卡片）。
Project projectFromDetailJson(Map<String, dynamic> j) {
  // media：后端 media 数组 [{type,url,poster?,...}]；空则用 cover 兜一张。
  final media = <MediaItem>[];
  // 封面永远第一张：详情页顶部 Hero 用 media.first；_results 会跳过首图避免与画廊重复。
  final cover = j['cover_media_url'];
  final coverUrl =
      (cover is String && cover.isNotEmpty) ? _resolveMediaUrl(cover) : null;
  if (coverUrl != null) {
    media.add(MediaItem(type: 'image', url: coverUrl));
  }
  // 画廊媒体（后端 project_media：截图 / GIF 演示）接在封面之后 → 详情页图片轮播。
  final rawMedia = j['media'];
  if (rawMedia is List) {
    for (final m in rawMedia.whereType<Map<dynamic, dynamic>>()) {
      final url = m['url']?.toString();
      if (url == null || url.isEmpty) continue;
      final resolved = _resolveMediaUrl(url);
      final type = m['type']?.toString() == 'video' ? 'video' : 'image';
      // 去重：画廊里若混进与封面同一张图，不重复加。
      // 但视频不能因为和 cover_media_url 同 URL 被去掉；否则首个视频会只剩波点封面。
      if (resolved == coverUrl && type != 'video') continue;
      media.add(MediaItem(
        type: type,
        url: resolved,
        poster: m['poster'] != null
            ? _resolveMediaUrl(m['poster'].toString())
            : null,
      ));
    }
  }
  final tools = (j['tools'] is List)
      ? (j['tools'] as List).map((e) => e.toString()).toList()
      : const <String>[];
  final counts = j['counts'];
  final takeaway = counts is Map ? counts['takeaways'] : j['takeaway_count'];
  // 简介正文：intro > description，做轻量 markdown 清洗后进成果区 text（左对齐正文）。
  final rawIntro = (j['intro'] ?? j['description'])?.toString();
  final introText = (rawIntro != null && rawIntro.isNotEmpty)
      ? _stripLightMarkdown(rawIntro)
      : null;
  final repo = _repoFromSource(j);
  return Project(
    id: j['id'].toString(),
    status: (j['status'] ?? 'published').toString(),
    title: (j['title'] ?? '').toString(),
    summary: (j['tagline'] ?? j['subtitle'] ?? '').toString(),
    authorId: _authorIdAndCache(j['author']),
    // 成果区：封面 media + 仓库卡（source_url）+ 简介正文（intro）。
    // 详情页 _results 会跳过 media 首图（即顶部 Hero 封面），避免封面重复。
    resultData: ResultData(media: media, repo: repo, text: introText),
    actions: _actionsFromJson(
        j['actions']), // 后端 project_actions → 前端 sealed ActionItem
    tags: tools,
    // intro 已进 resultData.text（左对齐正文），不再塞 authorNote（居中「作者的话」）。
    authorNote: null,
    domain:
        j['content_type']?.toString() ?? _mapDomain(j['category']?.toString()),
    likes: _likesFromCounts(counts),
    commentCount: 0,
    takeawayCount: takeaway is int ? takeaway : int.tryParse('$takeaway') ?? 0,
    repoStars: _parseStars(j['repo_stars']),
    tryUrl: (j['try_url'] as String?)?.trim().isNotEmpty == true
        ? (j['try_url'] as String).trim()
        : null,
    createdAtMs: parseMs(j['published_at']),
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
    status: (j['status'] ?? 'published').toString(),
    title: (j['title'] ?? '').toString(),
    summary: (j['tagline'] ?? j['subtitle'] ?? j['intro'] ?? '').toString(),
    authorId:
        _authorIdAndCache(j['author']), // 后端已填 author(UserBrief)→缓存+authorId
    resultData: ResultData(media: media),
    actions: const [],
    tags: tools,
    domain:
        j['content_type']?.toString() ?? _mapDomain(j['category']?.toString()),
    likes: _likesFromCounts(counts),
    commentCount: 0,
    takeawayCount: takeaway is int ? takeaway : int.tryParse('$takeaway') ?? 0,
    createdAtMs: parseMs(j['published_at']),
  );
}
