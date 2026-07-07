import 'package:freezed_annotation/freezed_annotation.dart';

import 'media_item.dart';

part 'post.freezed.dart';

/// HANDOFF §1 动态(轻)—— 文字 + 可选图 + 话题 + 引用项目。
///
/// 与 Project 二分:不进库、无详情页。长短都行,心得帖也在这。
/// 没有 resultData(无成果区)、没有 actions(无素材)。
@freezed
abstract class Post with _$Post {
  const factory Post({
    required String id,

    /// 正文
    required String content,

    /// 作者 ID
    required String authorId,

    /// 可选图片(无视频 — 视频走 Project)
    @Default([]) List<MediaItem> media,

    /// 话题标签(HANDOFF §6.2 — 真实 tags 字段)
    @Default([]) List<String> tags,

    /// 引用的项目 ID(可选)
    String? quoteProjectId,

    /// 点赞数(真实)
    @Default(0) int likes,

    /// 评论数(真实)
    @Default(0) int commentCount,

    /// 创建时间(毫秒)
    required int createdAtMs,
  }) = _Post;
}
