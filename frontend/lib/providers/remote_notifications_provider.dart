// 这个文件是干什么的：远端通知列表 provider——从后端拉真实通知，并把未读集合回填到 appState。
// 它对应产品里的什么功能：通知中心（远端模式）、tab 角标红点的真实来源。
// 如果它出错了：通知中心报错态（不崩），红点回退本地。
//
// 只在 useRemote + 已登录时被通知屏 watch；demo/未登录走屏内 mock repo。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/notifications_api.dart';
import '../domain/models/models.dart';
import 'app_state_provider.dart';

/// 远端通知列表。拉回后用后端 is_read 回填 [appState] 的未读集合
/// （tab 角标 / 我的页 / 设置页的未读数都读它，必须同源）。
///
/// **autoDispose**：不缓存到天荒地老。原来是普通 FutureProvider，首次拉完就一直缓存——
/// 于是「换账号 / 别人给你点赞关注后再看通知」都还是旧的一份（甚至空的），新通知永远不出现。
/// 改成 autoDispose：离开通知屏即释放，每次进通知屏都重新拉最新；配合屏内下拉刷新兜底。
final remoteNotificationsProvider =
    FutureProvider.autoDispose<List<NotificationItem>>((ref) async {
  final list = await ref.read(notificationsApiProvider).list();
  final unread = {for (final n in list) if (!n.read) n.id};
  // 微任务里回填，避开「build 期改另一个 provider」的时序坑。
  Future.microtask(
      () => ref.read(appStateProvider.notifier).setUnreadNotifIds(unread));
  return list;
});
