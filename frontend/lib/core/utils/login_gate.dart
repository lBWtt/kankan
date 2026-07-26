import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../router/routes.dart';

/// 需登录的动作（点赞 / 收藏等）前调用：已登录 → 返回 true（继续执行）；
/// 未登录 → 跳登录页并返回 false（调用方 return，别执行动作）。
/// 与 notifier 里的「未登录直接 return」兜底配合：这里给提示、那里保底。
bool guardLogin(BuildContext context, WidgetRef ref) {
  if (ref.read(authProvider).isLoggedIn) return true;
  context.push(KkRoutes.login);
  return false;
}
