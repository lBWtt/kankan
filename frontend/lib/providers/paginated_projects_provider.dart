// 这个文件是干什么的：项目流的分页 provider（看看页 feed 用）。
// 它对应产品里的什么功能：看看页无限滚动加载更多项目。
// 如果它出错了：流加载/追加/刷新失败，或重复加载。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/pagination/paginated_notifier.dart';
import '../core/pagination/page.dart';
import '../data/api/projects_api.dart';
import '../domain/models/models.dart';
import '../domain/repositories/project_repository.dart';

/// 看看页项目流的分页 state。
///
/// useRemote：游标分页 GET /projects。
/// mock：一次性返回全部 mock 项目（hasMore=false）——mock 数据量小，无需真分页。
/// autoDispose：离开看看页释放，回来重新加载。
class PaginatedProjectsNotifier extends PaginatedNotifier<Project> {
  static const _afterSlateCursor = '__after_home_slate__';

  @override
  int get pageSize => AppConfig.useRemote ? 20 : 999;

  @override
  String idOf(Project item) => item.id;

  @override
  Future<Page<Project>> fetchPage(String? cursor) async {
    if (!AppConfig.useRemote) {
      // mock：全部一次性返回，hasMore=false。
      final all = ref.read(projectRepositoryProvider).all();
      return Page.last(all);
    }
    if (cursor == null) {
      final slate = await ref.read(projectsApiProvider).homeSlate();
      final isCompleteSlate = slate.length >= 10;
      return Page<Project>(
        items: slate,
        // 宪法要求库存不足时宁可少于十条，不能拿普通时间流悄悄补位。
        nextCursor: isCompleteSlate ? _afterSlateCursor : null,
        hasMore: isCompleteSlate,
      );
    }
    if (cursor == _afterSlateCursor) {
      // 首批十条之后回到普通时间流；取大页并由基类按项目 id 去重。
      return ref.read(projectsApiProvider).listPaged(limit: 50);
    }
    return ref.read(projectsApiProvider).listPaged(
          limit: pageSize,
          cursor: cursor,
        );
  }
}

/// 看看页项目流分页 provider。
final paginatedProjectsProvider = NotifierProvider.autoDispose<
    PaginatedProjectsNotifier, PaginatedState<Project>>(
  () => PaginatedProjectsNotifier(),
);
