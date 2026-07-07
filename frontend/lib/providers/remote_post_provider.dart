// 这个文件是干什么的：把动态流/详情包成 AsyncValue，并把「我已赞」并进 app_state（点亮心）。
// 它对应产品里的什么功能：发现页动态流、动态详情（真数据模式）。
// 如果它出错了：动态流/详情无法显示加载/错误/数据态。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../data/api/posts_api.dart';
import '../domain/models/models.dart';
import '../domain/repositories/post_repository.dart';
import 'app_state_provider.dart';

/// 真数据动态流。加载后把 is_liked 的动态 id 并入 app_state.likedItemIds（点亮心）。
final remotePostsProvider = FutureProvider.autoDispose<List<Post>>((ref) async {
  final result = await ref.watch(postsApiProvider).list(limit: 30);
  if (result.likedIds.isNotEmpty) {
    ref.read(appStateProvider.notifier).mergeLikedIds(result.likedIds);
  }
  return result.posts;
});

/// TA 的动态（个人主页「动态」Tab）。userId 是后端 UUID；加载后并「我已赞」点亮心。
final userPostsProvider =
    FutureProvider.autoDispose.family<List<Post>, String>((ref, userId) async {
  final result = await ref.watch(postsApiProvider).byUser(userId);
  if (result.likedIds.isNotEmpty) {
    ref.read(appStateProvider.notifier).mergeLikedIds(result.likedIds);
  }
  return result.posts;
});

/// 按 id 取动态：先查 mock repo（命中=mock feed 的动态），miss 且 useRemote → 拉后端。
/// 动态详情页用（AsyncValue：loading/error/data）。命中已赞则点亮心。
final postByIdProvider =
    FutureProvider.autoDispose.family<Post?, String>((ref, id) async {
  final local = ref.watch(postRepositoryProvider).byId(id);
  if (local != null) {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return local;
  }
  if (AppConfig.useRemote) {
    final r = await ref.watch(postsApiProvider).detail(id);
    if (r.isLiked) ref.read(appStateProvider.notifier).mergeLikedIds({id});
    return r.post;
  }
  return null;
});
