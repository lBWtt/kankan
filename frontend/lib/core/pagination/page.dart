// 这个文件是干什么的：分页基础设施的数据载体。
// 它对应产品里的什么功能：feed 类页面（发现/看看/评论/关注列表）的无限滚动加载。
// 如果它出错了：分页状态错乱 → 重复加载 / 漏页 / 加载态卡死。
import 'package:flutter/foundation.dart';

/// 一次分页拉取的结果（API 层返回）。
///
/// [items] 本页数据；[nextCursor] 下一页游标（null=无更多）；
/// [hasMore] 是否还有下一页。后端返回 has_more 用 has_more，否则按
/// items.length >= pageSize 启发式推断。
@immutable
class Page<T> {
  final List<T> items;
  final String? nextCursor;
  final bool hasMore;

  const Page({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  /// 便捷构造：单页全量（无更多）。mock 数据源用。
  factory Page.last(List<T> items) =>
      Page(items: items, nextCursor: null, hasMore: false);
}

/// 分页列表的 UI 状态（Notifier 持有 + 屏 watch）。
///
/// 三态合一：
///   - [isLoading] 首次加载（显示骨架/转圈）
///   - [isLoadingMore] 追加加载（底部转圈）
///   - [error] 加载失败（首屏错误兜底 / 追加失败 toast）
///   - [items] 已累积的全部数据
///   - [hasMore] 是否还能加载更多
///   - [nextCursor] 下一页游标
@immutable
class PaginatedState<T> {
  final List<T> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;
  final String? nextCursor;

  const PaginatedState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.nextCursor,
  });

  /// 首次加载中。
  const PaginatedState.loading()
      : items = const [],
        isLoading = true,
        isLoadingMore = false,
        hasMore = true,
        error = null,
        nextCursor = null;

  PaginatedState<T> copyWith({
    List<T>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    String? nextCursor,
    bool clearError = false,
  }) =>
      PaginatedState<T>(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
        nextCursor: nextCursor ?? this.nextCursor,
      );
}
