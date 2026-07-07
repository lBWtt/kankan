import 'package:freezed_annotation/freezed_annotation.dart';

part 'comment.freezed.dart';

/// 评论(Project / Post 共用)。
///
/// HANDOFF §6.1:CommentThread 统一组件 — 点赞、楼中楼回复、删除/编辑,
/// 四处一致(详情内联 / 评论页 / 动态弹层 / 动态详情)。
/// Phase 3 实现 CommentThread 组件;Phase 2 先用此模型。
@freezed
abstract class Comment with _$Comment {
  const factory Comment({
    required String id,

    /// 宿主类型 'project' | 'post'
    required String hostType,

    /// 宿主 ID(project.id / post.id)
    required String hostId,

    /// 评论者 ID
    required String authorId,

    /// 正文
    required String content,

    /// 点赞数(真实)
    @Default(0) int likes,

    /// 楼中楼回复(简化:同结构 List<Comment>)
    @Default([]) List<Comment> replies,

    /// 创建时间(毫秒)
    required int createdAtMs,
  }) = _Comment;
}
