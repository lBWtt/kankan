// 这个文件是干什么的：无限滚动辅助——监听 ScrollController，接近底部时触发加载更多。
// 它对应产品里的什么功能：feed 类页面下拉到底自动加载下一页。
// 如果它出错了：加载过早（频繁触发）/ 过晚（用户看到底了还没加载）。
import 'package:flutter/material.dart';

/// 无限滚动辅助。
///
/// 用法（在 StatefulWidget initState）：
///   ```
///   _scrollCtrl = ScrollController();
///   InfiniteScroll.attach(_scrollCtrl, onLoadMore: () {
///     ref.read(paginatedProvider.notifier).loadMore();
///   });
///   ```
/// 防抖由 Notifier.loadMore 的防重入保证（isLoading/isLoadingMore/!hasMore 时 no-op）。
class InfiniteScroll {
  InfiniteScroll._();

  /// 默认触底阈值（距底部 300px 即预加载）。
  static const double defaultThreshold = 300;

  /// 给 [controller] 挂监听，滚动到距底部 [threshold]px 内时调 [onLoadMore]。
  static void attach(
    ScrollController controller, {
    required VoidCallback onLoadMore,
    double threshold = defaultThreshold,
  }) {
    controller.addListener(() {
      if (!controller.hasClients) return;
      final pos = controller.position;
      if (pos.pixels >= pos.maxScrollExtent - threshold) {
        onLoadMore();
      }
    });
  }
}

/// 列表底部加载指示器（追加加载时显示）。
///
/// 用法：ListView.builder itemCount +1，最后一个 itemBuilder 返回本组件。
/// [enabled]=false 时返回 SizedBox.shrink（无更多/未加载时不占位）。
class LoadMoreIndicator extends StatelessWidget {
  const LoadMoreIndicator({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
