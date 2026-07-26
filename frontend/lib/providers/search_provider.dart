// 这个文件是干什么的：搜索/话题的「数据源统一层」。mock 模式走内存 SearchRepository，
//   remote 模式走后端（/projects?q= 、/posts?q= 、/users/search 、/topics）。两种模式
//   都以 AsyncValue 暴露，屏幕统一用 .when(...) 消费，不再各自 reach into mock。
// 它对应产品里的什么功能：话题广场、今日话题横条、话题详情页、搜索结果页、搜索建议。
// 如果它出错了：搜索/话题拉不到或读了错数据源（remote 下读成 mock）。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../data/api/posts_api.dart';
import '../data/api/projects_api.dart';
import '../data/api/topics_api.dart';
import '../data/api/users_api.dart';
import '../domain/models/models.dart';
import '../domain/repositories/post_repository.dart';
import '../domain/repositories/project_repository.dart';
import '../domain/repositories/search_repository.dart';

/// 热门话题（话题广场 limit=30 / 发现页横条 limit=8）。
final topTopicsProvider =
    FutureProvider.autoDispose.family<List<Topic>, int>((ref, limit) async {
  if (AppConfig.useRemote) {
    return ref.watch(topicsApiProvider).topTopics(limit: limit);
  }
  return ref.watch(searchRepositoryProvider).topTopics(limit: limit);
});

final followedTopicsProvider = FutureProvider.autoDispose<List<Topic>>((ref) async {
  if (!AppConfig.useRemote) return const [];
  return ref.watch(topicsApiProvider).followedTopics();
});

/// 话题详情：热度头 + 该 tag 下项目 + 动态。
final topicDetailProvider =
    FutureProvider.autoDispose.family<TopicBundle, String>((ref, tag) async {
  if (AppConfig.useRemote) {
    return ref.watch(topicsApiProvider).detail(tag);
  }
  // mock：从内存 repo 聚合（与旧 topic_screen 同口径：项目按 likes、动态按时间）。
  final searchRepo = ref.watch(searchRepositoryProvider);
  final topic = searchRepo.searchTopics('').firstWhere(
        (t) => t.tag == tag,
        orElse: () => Topic(tag: tag),
      );
  final projects = ref.watch(projectRepositoryProvider).byTag(tag)
    ..sort((a, b) => b.likes.compareTo(a.likes));
  final posts = ref
      .watch(postRepositoryProvider)
      .all()
      .where((p) => p.tags.contains(tag))
      .toList()
    ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  return TopicBundle(topic, projects, posts, <String>{});
});

/// 搜话题（搜索结果页话题 tab / 搜索建议）。remote 下取全量话题后本地按子串筛。
final searchTopicsProvider =
    FutureProvider.autoDispose.family<List<Topic>, String>((ref, q) async {
  if (AppConfig.useRemote) {
    final all = await ref.watch(topicsApiProvider).topTopics(limit: 100);
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return all;
    return all.where((t) => t.tag.toLowerCase().contains(s)).toList();
  }
  return ref.watch(searchRepositoryProvider).searchTopics(q);
});

/// 搜项目（title/tagline/tools）。
final searchProjectsProvider =
    FutureProvider.autoDispose.family<List<Project>, String>((ref, q) async {
  final s = q.trim();
  if (s.isEmpty) return const [];
  if (AppConfig.useRemote) {
    return ref.watch(projectsApiProvider).search(s);
  }
  return ref.watch(searchRepositoryProvider).searchProjects(s);
});

/// 搜动态（正文/标签）。
final searchPostsProvider =
    FutureProvider.autoDispose.family<List<Post>, String>((ref, q) async {
  final s = q.trim();
  if (s.isEmpty) return const [];
  if (AppConfig.useRemote) {
    final r = await ref.watch(postsApiProvider).search(s);
    return r.posts;
  }
  return ref.watch(searchRepositoryProvider).searchPosts(s);
});

/// 搜用户（昵称/简介）。
final searchUsersProvider =
    FutureProvider.autoDispose.family<List<KkUser>, String>((ref, q) async {
  final s = q.trim();
  if (s.isEmpty) return const [];
  if (AppConfig.useRemote) {
    return ref.watch(usersApiProvider).searchUsers(s);
  }
  return ref.watch(searchRepositoryProvider).searchUsers(s);
});
