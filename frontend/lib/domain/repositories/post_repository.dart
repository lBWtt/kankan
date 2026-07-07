import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed/mock_seed.dart';
import '../../domain/models/models.dart';

/// P1:Repo-module-private backing list — 启动期从 mockPosts 拷贝一次,此后 repo
/// 运行时读写都走它,不再 reach into mock_seed 全局。与 backingProjects 同理
/// (见 project_repository.dart):top-level final 跨 invalidate 存活,compose 屏
/// `addPost()` 后的 `ref.invalidate(postRepositoryProvider)` 不会丢新动态。
/// 与 SearchRepository 共享(同源):新发的动态要能被搜到。
final List<Post> backingPosts = List.of(mockPosts);

/// PostRepository — 动态(轻)的内存 repo。持有 owned 数据副本(P1 解耦)。
/// HANDOFF §1:动态不进库、无详情页。这里只提供 feed 查询。
class PostRepository {
  final List<Post> _posts;
  // P1:仍是 mockComments 全局引用——screens 直接调 mock_seed.commentsFor 读它,
  // 且与 ProjectRepository 同源共享。改 owned 副本会撕裂读写。
  final List<Comment> _comments;

  PostRepository(this._posts, this._comments);

  /// F-36:返回可变副本 `List.of(_posts)`,不再用 `List.unmodifiable`。
  /// 原因:不可变 List 调 `..sort()` 运行时抛 `UnsupportedError`(discover 屏踩过)。
  /// 约定(Codex 规则 C):repository 的 all() 统一返回可变副本,调用方可直接 sort。
  List<Post> all() => List.of(_posts);

  Post? byId(String id) => _posts.where((p) => p.id == id).firstOrNull;

  List<Post> byAuthor(String userId) =>
      _posts.where((p) => p.authorId == userId).toList();

  List<Comment> commentsFor(String hostId) =>
      _comments.where((c) => c.hostId == hostId).toList();

  /// F-4:写入评论到 _comments(P1:仍是 mockComments 全局引用,与
  /// ProjectRepository 同源)。CommentThread 发送时调用,detail 底栏 / 卡片 /
  /// CommentThread 读同一份,计数一致。hostType/hostId 透传仅作文档;
  /// Comment 自身已带这两个字段。
  void addComment(String hostType, String hostId, Comment comment) {
    _comments.add(comment);
  }

  /// 任务⑪:发动态 — 写入新 Post 到 owned _posts 头部(backingPosts,对称 addComment)。
  /// compose 屏发送时调用,discover 推荐/关注流读同一份,新动态出现在顶部
  /// (按 createdAtMs 降序排)。内存级,Phase 5 接后端时替换。
  void addPost(Post post) {
    _posts.insert(0, post);
  }

  /// 删除自己发布的动态(对称 addPost)。动态详情页 own 二次确认后调用,
  /// 写 owned _posts(backingPosts)。真·后端 DELETE /posts/{id} 由 Claude 后续接,
  /// 这里先 mock 层(内存 repo 删除)。
  void removePost(String postId) {
    _posts.removeWhere((p) => p.id == postId);
  }

  /// 任务⑨:删除评论(对称 addComment,与 ProjectRepository 同源 mockComments)。
  void removeComment(String commentId) {
    _comments.removeWhere((c) => c.id == commentId);
  }

  /// 任务⑨:更新评论(编辑)。与 ProjectRepository 同源 mockComments。
  void updateComment(Comment updated) {
    final i = _comments.indexWhere((c) => c.id == updated.id);
    if (i >= 0) _comments[i] = updated;
  }
}

/// P1:注入 [backingPosts](owned 副本,跨 invalidate 存活)。mockComments 保留
/// 全局引用(commentsFor 依赖,见类注释)。
final postRepositoryProvider = Provider<PostRepository>((ref) {
  return PostRepository(backingPosts, mockComments);
});
