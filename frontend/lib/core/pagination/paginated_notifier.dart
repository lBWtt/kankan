// 这个文件是干什么的：分页 Notifier 基类——子类只实现 fetchPage，自动获得
//   首次加载 / 追加 / 刷新 / 去重 / 防重入 能力。
// 它对应产品里的什么功能：发现流 / 看看流 / 评论列表 / 关注列表的无限滚动。
// 如果它出错了：重复加载 / 漏页 / 加载态卡死 / 刷新不重置。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'page.dart';

/// 分页 Notifier 基类。子类实现 [fetchPage]（拉一页）+ [idOf]（去重键）。
///
/// 生命周期：
///   - build()：返回 loading 态，microtask 触发首次 [refresh]。
///   - [refresh]：重置 cursor，拉首页，替换 items。
///   - [loadMore]：用 nextCursor 拉下一页，追加 items（去重）。
///
/// 防重入：isLoading / isLoadingMore 时忽略重复触发。
/// 去重：追加时按 [idOf] 跳过已存在的 item（后端若不支持分页会返回相同首页，
///   去重避免重复渲染 + hasMore 启发式会在 items.length < pageSize 时自然停止）。
abstract class PaginatedNotifier<T> extends Notifier<PaginatedState<T>> {
  /// 每页大小。子类可覆盖。
  int get pageSize => 20;

  /// 子类实现：用 [cursor]（null=首页）拉一页数据。
  Future<Page<T>> fetchPage(String? cursor);

  /// 子类实现：返回 item 的唯一 id（用于追加去重）。
  /// 默认用 toString()——子类应覆盖为真实 id 字段以正确去重。
  String idOf(T item) => item.toString();

  @override
  PaginatedState<T> build() {
    // microtask 触发首次加载，避免在 build() 里同步发请求（Riverpod 推荐）。
    Future.microtask(_refresh);
    return const PaginatedState.loading();
  }

  /// 刷新：重置 cursor + 拉首页 + 替换 items。下拉刷新用。
  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await fetchPage(null);
      if (page.items.isEmpty) {
        // 空首页：保留空列表，hasMore=false
        state = PaginatedState<T>(
          items: const [],
          isLoading: false,
          hasMore: false,
          nextCursor: page.nextCursor,
        );
        return;
      }
      state = PaginatedState<T>(
        items: page.items,
        isLoading: false,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  /// 追加下一页。滚动到底部触发。防重入 + 无更多时 no-op。
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final cursor = state.nextCursor;
    if (cursor == null) return; // 无游标且 hasMore 仍 true（首页启发式）→ 停
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await fetchPage(cursor);
      // 去重：跳过已存在的 id（后端不支持分页时避免重复）。
      final existing = {for (final x in state.items) idOf(x)};
      final fresh = page.items.where((x) => !existing.contains(idOf(x))).toList();
      state = PaginatedState<T>(
        items: [...state.items, ...fresh],
        isLoadingMore: false,
        hasMore: page.hasMore && fresh.isNotEmpty,
        // 后端返回空本页但 hasMore=true（边界）→ 用 page.nextCursor，但 hasMore 已被 fresh.isEmpty 置 false
        nextCursor: fresh.isEmpty ? null : page.nextCursor,
      );
    } catch (e) {
      // 追加失败：保留已有 items，记录 error 让 UI toast，不卡 isLoadingMore。
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }

  /// 乐观移除一个 item（按 [idOf] 匹配）。发评论 / 删评论等本地即时反馈用。
  /// 不触发网络请求；调用方负责后续 [refresh] / 后端同步 + 失败时 refresh 回滚。
  /// 用于 CommentThread 删评论：先本地移除给即时反馈，再 await 后端 delete，
  /// 失败时 refresh 重拉恢复。
  void removeItem(String id) {
    final next = state.items.where((x) => idOf(x) != id).toList();
    if (next.length == state.items.length) return; // 没找到，no-op
    state = state.copyWith(items: next);
  }
}
