// P1:验证 domain repository 持有 owned 数据副本——add() 写 owned 副本,
// all()/byId() 读同一份 owned 副本(不再 reach into mock_seed 全局)。
//
// 沙箱无 flutter/dart SDK,无法本地 `flutter test`;靠 GitHub CI 跑。
// 测试只构造 repo 实例(纯 Dart,不依赖 Riverpod ProviderContainer),
// 注入独立 List.of(mockProjects) 副本保证 hermetic、不污染全局。
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/data/seed/mock_seed.dart';
import 'package:kankan_flutter/domain/models/models.dart';
import 'package:kankan_flutter/domain/repositories/post_repository.dart';
import 'package:kankan_flutter/domain/repositories/project_repository.dart';
import 'package:kankan_flutter/domain/repositories/search_repository.dart';

Project _probeProject(String id) => Project(
      id: id,
      title: 'ownership probe $id',
      summary: 'probe',
      authorId: 'me',
      resultData: const ResultData(),
      domain: 'tool',
      createdAtMs: 1,
    );

Post _probePost(String id) => Post(
      id: id,
      content: 'ownership probe $id',
      authorId: 'me',
      createdAtMs: 1,
    );

void main() {
  group('ProjectRepository ownership (P1)', () {
    test(
        'add() then all()/byId() reflects the addition — repo reads its own state',
        () {
      // 注入独立副本(非 mockProjects 全局),保证测试 hermetic、不污染其它测试。
      final repo = ProjectRepository(
        List.of(mockProjects),
        List.of(mockUsers),
        <Comment>[],
      );
      final before = repo.all().length;
      const probeId = 'test_owner_probe_1';

      repo.add(_probeProject(probeId));

      expect(
        repo.all().length,
        before + 1,
        reason: 'all() must reflect add() — owned 副本读写同源',
      );
      expect(
        repo.byId(probeId)?.title,
        'ownership probe $probeId',
        reason: 'byId() must read the same owned 副本 add() wrote to',
      );
    });

    test('add() inserts at head (F-2 新发布置顶)', () {
      final repo = ProjectRepository(
        List.of(mockProjects),
        <KkUser>[],
        <Comment>[],
      );
      repo.add(_probeProject('test_owner_head'));
      expect(repo.all().first.id, 'test_owner_head');
    });

    test('two repos with separate backing lists do not share state', () {
      // 两个独立副本——一个 repo 的 add 不应渗到另一个(ownership 隔离)。
      final listA = List.of(mockProjects);
      final listB = List.of(mockProjects);
      final repoA = ProjectRepository(listA, <KkUser>[], <Comment>[]);
      final repoB = ProjectRepository(listB, <KkUser>[], <Comment>[]);
      const probeId = 'test_owner_isolated';

      repoA.add(_probeProject(probeId));

      expect(repoA.byId(probeId), isNotNull, reason: 'repoA 应看到自己 add 的项目');
      expect(
        repoB.byId(probeId),
        isNull,
        reason: '独立 backing 副本不应渗漏——repoB 不应看到 repoA 的 add',
      );
      // 全局 mockProjects 也不应被改写(P1:repo 写 owned 副本,不写全局)。
      expect(
        mockProjects.where((p) => p.id == probeId).firstOrNull,
        isNull,
        reason: 'add() 不应再写 mockProjects 全局',
      );
    });

    test('removeProject mutates owned 副本 only', () {
      final listA = List.of(mockProjects);
      final repo = ProjectRepository(listA, <KkUser>[], <Comment>[]);
      // 取一个 mock seed 里真实存在的 id 删,验证 owned 副本被改、全局未被改。
      const targetId = 'p_aiimg_1';
      // 前置:mock seed 确有此项目(若 seed 变了,测试会显式失败提示)。
      expect(
        mockProjects.any((p) => p.id == targetId),
        isTrue,
        reason: 'mock seed 应含 p_aiimg_1(若改了 seed,改测试 targetId)',
      );
      final before = repo.all().length;

      repo.removeProject(targetId);

      expect(repo.byId(targetId), isNull, reason: 'owned 副本应已删除该项目');
      expect(repo.all().length, before - 1);
      // 全局未被动(owned 副本与全局解耦)。
      expect(
        mockProjects.any((p) => p.id == targetId),
        isTrue,
        reason: 'removeProject 不应改 mockProjects 全局',
      );
    });

    test('incrementTakeaway bumps owned 副本计数', () {
      final repo = ProjectRepository(
        List.of(mockProjects),
        <KkUser>[],
        <Comment>[],
      );
      const targetId = 'p_aiimg_1';
      final before = repo.byId(targetId)!.takeawayCount;

      repo.incrementTakeaway(targetId);

      expect(
        repo.byId(targetId)!.takeawayCount,
        before + 1,
        reason: 'incrementTakeaway 写 owned 副本,byId 读同一份',
      );
    });
  });

  group('PostRepository ownership (P1)', () {
    test('addPost() then all()/byId() reflects the addition', () {
      final repo = PostRepository(List.of(mockPosts), <Comment>[]);
      final before = repo.all().length;
      const probeId = 'test_owner_post_1';

      repo.addPost(_probePost(probeId));

      expect(repo.all().length, before + 1);
      expect(repo.byId(probeId)?.content, 'ownership probe $probeId');
      expect(repo.all().first.id, 'test_owner_post_1', reason: 'addPost 置顶');
    });

    test('addPost does not leak to mockPosts global', () {
      final repo = PostRepository(List.of(mockPosts), <Comment>[]);
      const probeId = 'test_owner_post_iso';

      repo.addPost(_probePost(probeId));

      expect(
        mockPosts.where((p) => p.id == probeId).firstOrNull,
        isNull,
        reason: 'addPost 不应写 mockPosts 全局',
      );
    });

    test('removePost mutates owned 副本 only', () {
      const targetId = 'post_1';
      expect(
        mockPosts.any((p) => p.id == targetId),
        isTrue,
        reason: 'mock seed 应含 post_1',
      );
      final repo = PostRepository(List.of(mockPosts), <Comment>[]);
      final before = repo.all().length;

      repo.removePost(targetId);

      expect(repo.byId(targetId), isNull);
      expect(repo.all().length, before - 1);
      expect(
        mockPosts.any((p) => p.id == targetId),
        isTrue,
        reason: 'removePost 不应改 mockPosts 全局',
      );
    });
  });

  group('SearchRepository ownership (P1)', () {
    test(
        'searchProjects reflects add via shared backing list (same-source wiring)',
        () {
      // 模拟 provider 接线:ProjectRepo 与 SearchRepo 同源 backing 副本。
      // 同源 listA 同时喂给 ProjectRepo(写)和 SearchRepo(读)——P1 接线的关键。
      final listA = List.of(mockProjects);
      final users = List.of(mockUsers);
      final pRepo = ProjectRepository(listA, users, <Comment>[]);
      final sRepo = SearchRepository(listA, List.of(mockPosts), users);
      final searchable = Project(
        id: 'test_owner_search_probe',
        title: 'zzz-unique-probe-zzz',
        summary: '',
        authorId: 'me',
        resultData: const ResultData(),
        domain: 'tool',
        createdAtMs: 1,
      );

      pRepo.add(searchable);

      expect(
        sRepo
            .searchProjects('zzz-unique-probe')
            .any((p) => p.id == searchable.id),
        isTrue,
        reason: 'SearchRepo 读与 ProjectRepo 同源的 backing,应搜到新发布项目',
      );
    });

    test('searchProjects on independent copy does NOT see add to another copy',
        () {
      // 对照组:不同源 → 搜不到(证明同源才是 P1 的接线,而非全局魔法)。
      final listA = List.of(mockProjects);
      final listB = List.of(mockProjects);
      final users = List.of(mockUsers);
      final pRepo = ProjectRepository(listA, users, <Comment>[]);
      final sRepo = SearchRepository(listB, List.of(mockPosts), users);

      pRepo.add(
        Project(
          id: 'test_owner_search_iso',
          title: 'zzz-other-copy-zzz',
          summary: '',
          authorId: 'me',
          resultData: const ResultData(),
          domain: 'tool',
          createdAtMs: 1,
        ),
      );

      expect(
        sRepo
            .searchProjects('zzz-other-copy')
            .any((p) => p.id == 'test_owner_search_iso'),
        isFalse,
        reason: '不同源 backing 副本应搜不到——证明 search 见到的是同源 owned 副本,不是全局',
      );
    });
  });
}
