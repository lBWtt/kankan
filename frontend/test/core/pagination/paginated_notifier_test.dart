// PaginatedNotifier 逻辑测试：首次加载 / 追加 / 去重 / hasMore / 防重入。
//
// 沙箱无 flutter SDK——本文件靠 CI (`flutter test`) 验证。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/core/pagination/page.dart';
import 'package:kankan_flutter/core/pagination/paginated_notifier.dart';

/// 假 Notifier：按预设 pages 队列依次返回，记录调用次数。
class _FakeNotifier extends PaginatedNotifier<String> {
  final List<Page<String>> pages;
  int callCount = 0;
  _FakeNotifier(this.pages);

  @override
  int get pageSize => 2;

  @override
  Future<Page<String>> fetchPage(String? cursor) async {
    return pages[callCount++];
  }

  @override
  String idOf(String item) => item;
}

/// 泵送 microtask + async 解析：build() 里 Future.microtask(_refresh)，
/// _refresh 里 await fetchPage。需要两轮 pump。
Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('首次加载 → items + hasMore + nextCursor', () async {
    final pages = [
      const Page(items: ['a', 'b'], nextCursor: 'c1', hasMore: true),
    ];
    final provider = NotifierProvider<_FakeNotifier, PaginatedState<String>>(
      () => _FakeNotifier(pages),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(provider).isLoading, isTrue);
    await _pump();

    final s = container.read(provider);
    expect(s.isLoading, isFalse);
    expect(s.items, ['a', 'b']);
    expect(s.hasMore, isTrue);
    expect(s.nextCursor, 'c1');
  });

  test('loadMore 追加 + hasMore 收敛到 false', () async {
    final pages = [
      const Page(items: ['a', 'b'], nextCursor: 'c1', hasMore: true),
      const Page(items: ['c', 'd'], nextCursor: null, hasMore: false),
    ];
    final provider = NotifierProvider<_FakeNotifier, PaginatedState<String>>(
      () => _FakeNotifier(pages),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(provider);
    await _pump();
    await container.read(provider.notifier).loadMore();

    final s = container.read(provider);
    expect(s.items, ['a', 'b', 'c', 'd']);
    expect(s.hasMore, isFalse);
    expect(s.nextCursor, isNull);
  });

  test('去重：后端返回重复 id 不重复渲染', () async {
    final pages = [
      const Page(items: ['a', 'b'], nextCursor: 'c1', hasMore: true),
      // 第二页含已存在的 'b'（后端不支持分页时可能发生）
      const Page(items: ['b', 'c'], nextCursor: null, hasMore: false),
    ];
    final provider = NotifierProvider<_FakeNotifier, PaginatedState<String>>(
      () => _FakeNotifier(pages),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(provider);
    await _pump();
    await container.read(provider.notifier).loadMore();

    expect(container.read(provider).items, ['a', 'b', 'c']);
  });

  test('防重入：isLoadingMore 时重复 loadMore 只触发一次 fetchPage', () async {
    final pages = [
      const Page(items: ['a', 'b'], nextCursor: 'c1', hasMore: true),
      const Page(items: ['c', 'd'], nextCursor: null, hasMore: false),
    ];
    final notifier = _FakeNotifier(pages);
    final provider =
        NotifierProvider<_FakeNotifier, PaginatedState<String>>(() => notifier);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(provider);
    await _pump();

    // 并发触发两次 loadMore（第二次应被防重入挡掉）
    final f1 = container.read(provider.notifier).loadMore();
    final f2 = container.read(provider.notifier).loadMore();
    await Future.wait([f1, f2]);

    expect(notifier.callCount, 2); // 首页 1 + 追加 1（第二次 loadMore no-op）
    expect(container.read(provider).items, ['a', 'b', 'c', 'd']);
  });

  test('hasMore=false 时 loadMore 不再触发', () async {
    final pages = [
      const Page(items: ['a'], nextCursor: null, hasMore: false),
    ];
    final notifier = _FakeNotifier(pages);
    final provider =
        NotifierProvider<_FakeNotifier, PaginatedState<String>>(() => notifier);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(provider);
    await _pump();
    await container.read(provider.notifier).loadMore(); // no-op
    await container.read(provider.notifier).loadMore(); // no-op

    expect(notifier.callCount, 1); // 只有首页
    expect(container.read(provider).items, ['a']);
  });

  test('refresh 重置 cursor + 替换 items', () async {
    final pages = [
      const Page(items: ['a', 'b'], nextCursor: 'c1', hasMore: true),
      const Page(items: ['c', 'd'], nextCursor: null, hasMore: false),
      // refresh 后第三页（新首页）
      const Page(items: ['x', 'y'], nextCursor: null, hasMore: false),
    ];
    final notifier = _FakeNotifier(pages);
    final provider =
        NotifierProvider<_FakeNotifier, PaginatedState<String>>(() => notifier);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(provider);
    await _pump();
    await container.read(provider.notifier).loadMore();
    expect(container.read(provider).items, ['a', 'b', 'c', 'd']);

    await container.read(provider.notifier).refresh();
    expect(container.read(provider).items, ['x', 'y']);
    expect(container.read(provider).hasMore, isFalse);
  });
}
