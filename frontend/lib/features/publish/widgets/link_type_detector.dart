/// 链接类型识别 — HANDOFF §4:放链接 → 当场识别 GitHub/App Store/网址。
///
/// 发布页贴链接时实时识别,显示会渲染成什么 go 按钮(如"查看 GitHub")。
enum LinkType { github, appStore, googlePlay, generic }

/// 识别 URL 类型
LinkType detectLinkType(String url) {
  final u = url.toLowerCase();
  if (u.contains('github.com')) return LinkType.github;
  if (u.contains('apps.apple.com')) return LinkType.appStore;
  if (u.contains('play.google.com')) return LinkType.googlePlay;
  return LinkType.generic;
}

/// 默认 go 按钮文案(按类型推导)
String defaultGoLabel(LinkType t) => switch (t) {
      LinkType.github => 'GitHub',
      LinkType.appStore => 'App Store',
      LinkType.googlePlay => 'Google Play',
      LinkType.generic => '访问',
    };

/// 识别 + 返回 label(发布页当场显示用)
(String, LinkType) detectLinkLabel(String url) {
  if (url.isEmpty) return ('', LinkType.generic);
  final t = detectLinkType(url);
  if (t != LinkType.generic) return (defaultGoLabel(t), t);
  // 取域名做 label
  final uri = Uri.tryParse(url);
  if (uri != null && uri.host.isNotEmpty) {
    return (uri.host.replaceFirst('www.', ''), t);
  }
  return ('访问', t);
}

/// 判断是否是合法 URL(发布页校验用)
bool isValidUrl(String url) {
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
}
