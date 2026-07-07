import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_item.freezed.dart';

/// HANDOFF §6.8 通知 — 5 类精准跳转。
///
/// Web 版重灾区:通知点击无差别跳到一个固定页,或跳错宿主。
/// Flutter 端从零做对:type 决定跳转目的地,跳转字段必填。
///
/// 5 类 + 跳转目的地:
///   - like      → 点赞  → 跳 PostDetail(targetId = postId)
///   - comment   → 评论  → 跳 Comments(hostType + hostId,hostType 'post'|'project')
///   - follow    → 关注  → 跳 Profile(targetId = userId)
///   - favorite  → 收藏(我的项目被人收藏)→ 跳 Detail(targetId = projectId)
///   - system    → 系统  → 不跳转(纯展示)
///
/// 计数铁律(HANDOFF §6.10):未读数取真实 unread 集合长度,不放大。
@freezed
abstract class NotificationItem with _$NotificationItem {
  const factory NotificationItem({
    required String id,

    /// 5 类:'like' | 'comment' | 'follow' | 'favorite' | 'system'
    required String type,

    /// 触发者 ID(system 类为 null)
    String? actorId,

    /// 跳转目标 ID:
    ///   - like → postId
    ///   - comment → hostId(postId 或 projectId)
    ///   - follow → userId
    ///   - favorite → projectId
    ///   - system → null(不跳转)
    String? targetId,

    /// 评论类专用:宿主类型 'post' | 'project'(决定跳 comments 时传哪个 hostType)
    String? hostType,

    /// 文案预览(评论类是评论内容截断,系统类是公告全文)
    String? preview,

    /// 是否已读
    @Default(false) bool read,

    /// 时间(毫秒)
    required int createdAtMs,
  }) = _NotificationItem;
}
