// 这个文件是干什么的：把 GET /projects 包成 AsyncValue，给看看 feed（真数据模式）用。
// 它对应产品里的什么功能：feed 的加载/错误/数据三态。
// 如果它出错了：feed 无法显示真数据的加载或错误态。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../data/api/interactions_api.dart';
import '../data/api/projects_api.dart';
import '../domain/models/models.dart';
import 'auth_provider.dart';

/// 真数据项目列表（AsyncValue：loading→骨架 / error→重试 / data→卡片）。
/// autoDispose + 可 ref.invalidate 重拉。
final remoteProjectsProvider =
    FutureProvider.autoDispose<List<Project>>((ref) async {
  return ref.watch(projectsApiProvider).list(limit: 30);
});

/// TA 的作品（个人主页「项目」Tab，仅 published）。userId 是后端 UUID。
final userProjectsProvider =
    FutureProvider.autoDispose.family<List<Project>, String>((ref, userId) {
  return ref.watch(projectsApiProvider).byUser(userId);
});

/// 我的全部作品，包含审核中等非公开状态；“我的”页不能只读公开主页接口。
final myProjectsProvider = FutureProvider.autoDispose<List<Project>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn) return const [];
  return ref.watch(projectsApiProvider).mine();
});

/// 项目搜索结果（搜索屏「项目」Tab，远端模式用）。后端只搜 title/tagline/tools。
/// query 变化自动重拉；空 query 早退返空。
final remoteSearchProjectsProvider =
    FutureProvider.autoDispose.family<List<Project>, String>((ref, q) async {
  return ref.watch(projectsApiProvider).search(q);
});

/// 我的收藏「完整卡片」（收藏屏用）。仅登录 + useRemote 才拉后端，否则空。
/// 登录态变化会重拉（watch authProvider）；登出即空，回落 mock 演示收藏。
final remoteFavoritesProvider =
    FutureProvider.autoDispose<List<Project>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!AppConfig.useRemote || !auth.isLoggedIn) return const <Project>[];
  return ref.watch(interactionsApiProvider).listFavorites();
});

final remoteTryItemsProvider =
    FutureProvider.autoDispose<List<TryProjectItem>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!AppConfig.useRemote || !auth.isLoggedIn) return const <TryProjectItem>[];
  return ref.watch(interactionsApiProvider).listTryItems();
});
