import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../data/api/projects_api.dart';
import '../data/remote_user_cache.dart';
import '../domain/repositories/project_repository.dart';
import '../domain/models/models.dart';

/// 按 ID 取单个 Project(family provider)。
///
/// detail 页用法:final project = ref.watch(projectByIdProvider(projectId));
///
/// 数据源策略(后端接入):
///   1. 先查内存 mock(命中 = 推荐条/浏览史/mock feed 的项目,含 remote 模式下的 mock id)。
///   2. mock miss 且 useRemote → fetch GET /projects/{id}(真数据 feed 的 uuid 项目)。
///   detail_screen 已按 AsyncValue 处理 loading/error/data,无需改动。
final projectByIdProvider =
    FutureProvider.family<Project?, String>((ref, id) async {
  final repo = ref.watch(projectRepositoryProvider);
  final local = repo.byId(id);
  if (local != null) {
    // 模拟异步(Phase 5 接 Drift 时是真异步)
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return local;
  }
  if (AppConfig.useRemote) {
    return ref.watch(projectsApiProvider).detail(id);
  }
  return null;
});

/// 作者 by ID(同步)。先查 mock repo;查不到再查远程用户缓存(feed/详情解析卡片时缓存的真作者)。
final userByIdProvider =
    Provider.family<KkUser?, String>((ref, id) {
  final repo = ref.watch(projectRepositoryProvider);
  return repo.userById(id) ?? remoteUserById(id);
});

/// 三 Tab 排序 provider(kankan 屏用)
final projectsSortedProvider =
    Provider.family<List<Project>, ({String sort, String? domain})>(
        (ref, params) {
  final repo = ref.watch(projectRepositoryProvider);
  return repo.sorted(params.sort, domain: params.domain);
});

/// 热门标签(从所有 project 的 tags 聚合,真实计数)
final popularTagsProvider = Provider<List<({String tag, int count})>>((ref) {
  final repo = ref.watch(projectRepositoryProvider);
  final counts = <String, int>{};
  for (final p in repo.all()) {
    for (final t in p.tags) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
  }
  final list = counts.entries
      .map((e) => (tag: e.key, count: e.value))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  return list;
});
