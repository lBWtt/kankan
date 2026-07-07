import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';

/// 用户(作者)。
///
/// HANDOFF §6.10:followers/following/posts/projects 计数全部取真实数组长度,
/// 禁止 ×200 / ×8+30 编造公式(Web 版重灾区)。
/// 那些计数是 User 的派生属性,这里只存原始字段,计数由 repository 派生。
@freezed
abstract class KkUser with _$KkUser {
  const factory KkUser({
    required String id,
    required String name,

    /// 头像 URL(null 用首字母 fallback)
    String? avatar,

    /// 一句话简介
    String? bio,

    /// 关注的人 ID 列表
    @Default([]) List<String> followingIds,

    /// 粉丝 ID 列表
    @Default([]) List<String> followerIds,
  }) = _KkUser;
}
