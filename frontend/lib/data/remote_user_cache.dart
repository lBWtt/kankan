// 这个文件是干什么的：缓存从后端卡片/详情里解析出的作者（UserBrief → KkUser）。
// 它对应产品里的什么功能：远程 feed/详情显示真作者名/头像（前端 Project 只存 authorId，
//   名字靠 userByIdProvider 查——mock 里没有远程作者，靠这个缓存兜底）。
// 如果它出错了：远程项目的作者行显示为空/id。
//
// 为什么用全局单例而非 provider：DTO 是纯函数（无 ref），解析时直接写这里；
// userByIdProvider 读它做 mock 之外的兜底。会话内有效，不持久化。
import '../domain/models/models.dart';

final Map<String, KkUser> _remoteUsers = {};

/// 解析卡片/详情的 author 时调用，把远程作者缓存起来。
void cacheRemoteUser(KkUser user) {
  if (user.id.isEmpty) return;
  _remoteUsers[user.id] = user;
}

/// userByIdProvider 的兜底：mock 查不到时读这里（远程作者）。
KkUser? remoteUserById(String id) => _remoteUsers[id];
