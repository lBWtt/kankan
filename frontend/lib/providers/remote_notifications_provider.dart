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
final remoteNotificationsProvider =
    FutureProvider<List<NotificationItem>>((ref) async {
  final list = await ref.read(notificationsApiProvider).list();
  final unread = {for (final n in list) if (!n.read) n.id};
  // 微任务里回填，避开「build 期改另一个 provider」的时序坑。
  Future.microtask(
      () => ref.read(appStateProvider.notifier).setUnreadNotifIds(unread));
  return list;
});
