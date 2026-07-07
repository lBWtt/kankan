import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/models.dart';

/// 发布草稿 state — 实时构建 resultData + actions。
///
/// HANDOFF §4:放什么系统猜什么。用户操作 → 此 state 更新 →
/// publish_preview 实时读 → 显示详情端会渲染的样子。两端咬合。
///
/// HANDOFF §4 验收:发布端产出的数据结构 = 详情端可组合渲染所读的
/// {media(视频优先), actions:[take/go/how]}。
@immutable
class PublishDraft {
  /// 标题
  final String title;

  /// 一句话价值
  final String summary;

  /// 领域(可选,用户不选则发布时按内容猜)
  final String? domain;

  /// 标签(输入的 # 话题)
  final List<String> tags;

  /// 作者的话
  final String authorNote;

  /// 成果区 media(传的图/视频,视频自动排前)
  final List<MediaItem> media;

  /// 动作区(用户加的 take/go/how,任意组合)
  final List<ActionItem> actions;

  /// 正文(无 media 时,纯文字心得)
  final String? text;

  const PublishDraft({
    this.title = '',
    this.summary = '',
    this.domain,
    this.tags = const [],
    this.authorNote = '',
    this.media = const [],
    this.actions = const [],
    this.text,
  });

  PublishDraft copyWith({
    String? title,
    String? summary,
    String? domain,
    List<String>? tags,
    String? authorNote,
    List<MediaItem>? media,
    List<ActionItem>? actions,
    String? text,
  }) =>
      PublishDraft(
        title: title ?? this.title,
        summary: summary ?? this.summary,
        domain: domain ?? this.domain,
        tags: tags ?? this.tags,
        authorNote: authorNote ?? this.authorNote,
        media: media ?? this.media,
        actions: actions ?? this.actions,
        text: text ?? this.text,
      );

  /// 构建为 Project(发布时调用)。
  ///
  /// 关键:产出结构 = detail 端可组合渲染所读的 {resultData, actions}。
  /// 视频自动排前(HANDOFF §4)。
  Project toProject({
    required String id,
    required String authorId,
    required int createdAtMs,
  }) {
    final sortedMedia = _videoFirst(media);
    return Project(
      id: id,
      title: title.isEmpty ? '未命名' : title,
      summary: summary,
      authorId: authorId,
      resultData: ResultData(
        media: sortedMedia,
        text: text,
      ),
      actions: actions,
      tags: tags,
      authorNote: authorNote.isEmpty ? null : authorNote,
      domain: domain ?? _guessDomain(),
      createdAtMs: createdAtMs,
    );
  }

  /// 构造后端 POST /projects 的 v2 payload（登录后真发布用）。
  ///
  /// 走 v2 路径：source_kind='user_original' 标记 v2 + 直接 published。
  /// 准入（后端 409 红线）：actions 非空 / tools≥1 / intro≥20 字 任一即过——
  /// 前端把「作者的话 / 正文 / 一句话」拼进 intro，短于 20 字且无方法则后端拒发（正确行为）。
  ///
  /// 已知分叉（媒体）：media 是 image_picker 的 blob URL，未走 POST /media 上传，
  /// 故 media_ids 空——真媒体上传是独立后续。domain(成果类型)与后端 domains(职业枚举)
  /// 不同源，不透传，交后端按 vertical 兜底。
  Map<String, dynamic> toCreateJson({List<String> mediaIds = const []}) {
    // intro：优先作者的话，其次正文，再次一句话价值（尽量凑够准入 20 字）。
    final introParts = <String>[
      if (authorNote.trim().isNotEmpty) authorNote.trim(),
      if (text != null && text!.trim().isNotEmpty) text!.trim(),
    ];
    var intro = introParts.join('\n');
    if (intro.isEmpty) intro = summary.trim();
    return <String, dynamic>{
      'title': title.trim(),
      if (summary.trim().length >= 5) 'tagline': summary.trim(),
      if (intro.isNotEmpty) 'intro': intro,
      'source_kind': 'user_original',
      'is_original': true,
      'tags': tags,
      if (mediaIds.isNotEmpty) 'media_ids': mediaIds,
    };
  }

  /// 视频排前(HANDOFF §4:传图视频→成果,视频自动排前)
  static List<MediaItem> _videoFirst(List<MediaItem> media) {
    final videos = media.where((m) => m.type == 'video').toList();
    final images = media.where((m) => m.type == 'image').toList();
    return [...videos, ...images];
  }

  /// 猜领域(用户不选时)
  String _guessDomain() {
    if (media.any((m) => m.type == 'video')) return 'ai_video';
    if (media.any((m) => m.type == 'image')) return 'ai_image';
    if (actions.any((a) => a is GoAction)) {
      final go = actions.whereType<GoAction>().first;
      if (go.url.contains('github.com')) return 'opensource';
      if (go.url.contains('apps.apple.com') || go.url.contains('play.google.com')) return 'app';
      return 'web';
    }
    if (actions.any((a) => a is TakeAction && a.takeKind == 'copy')) return 'prompt';
    if (actions.any((a) => a is TakeAction && a.takeKind == 'download')) return 'tool';
    return 'prompt'; // 兜底
  }
}

class PublishDraftNotifier extends Notifier<PublishDraft> {
  @override
  PublishDraft build() => const PublishDraft();

  /// 媒体真实字节缓存（url → bytes）。发布时上传后端拿 media_id 用。
  /// MediaItem 只存 blob url（web 上传要真字节），故 pick 时读一次缓存这里。
  /// notifier 实例稳定（非 autoDispose），缓存跨 state 变更保留，reset 清空。
  final Map<String, Uint8List> _mediaBytes = {};

  /// 取某条媒体的字节（发布上传用）。没有则 null（如老数据/无字节）。
  Uint8List? bytesFor(String url) => _mediaBytes[url];

  void setTitle(String t) => state = state.copyWith(title: t);
  void setSummary(String s) => state = state.copyWith(summary: s);
  void setDomain(String d) => state = state.copyWith(domain: d);
  void setAuthorNote(String n) => state = state.copyWith(authorNote: n);
  void setText(String t) => state = state.copyWith(text: t);

  void addTag(String tag) {
    if (!state.tags.contains(tag)) {
      state = state.copyWith(tags: [...state.tags, tag]);
    }
  }
  void removeTag(String tag) =>
      state = state.copyWith(tags: state.tags.where((t) => t != tag).toList());

  /// 加媒体(图/视频)。HANDOFF §4:传图视频→成果,视频自动排前由 toProject 处理。
  /// [bytes] 非空则缓存(发布时真上传后端)；null 保持旧行为(mock 演示)。
  void addMedia(MediaItem m, [Uint8List? bytes]) {
    if (bytes != null) _mediaBytes[m.url] = bytes;
    state = state.copyWith(media: [...state.media, m]);
  }

  void removeMediaAt(int i) {
    final list = [...state.media];
    if (i >= 0 && i < list.length) {
      _mediaBytes.remove(list[i].url); // 连带清缓存字节
      list.removeAt(i);
    }
    state = state.copyWith(media: list);
  }

  /// 加动作(HANDOFF §4:"+"底部 sheet 三选一 → take/go/how)
  void addAction(ActionItem a) => state = state.copyWith(actions: [...state.actions, a]);
  void removeActionAt(int i) {
    final list = [...state.actions];
    if (i >= 0 && i < list.length) list.removeAt(i);
    state = state.copyWith(actions: list);
  }

  /// 重置(发布成功后调用)
  void reset() {
    _mediaBytes.clear();
    state = const PublishDraft();
  }
}

final publishDraftProvider =
    NotifierProvider<PublishDraftNotifier, PublishDraft>(
        () => PublishDraftNotifier());
