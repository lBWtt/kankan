// Mock seed 不变量单测。
//
// 覆盖 lib/data/seed/mock_seed.dart(1302 行)中明确文档化的不变量:
//
// 1. F-37 双向关注一致性:每个用户 A 的 followingIds 中每个 B,
//    其 followerIds 必须含 A.id;反之亦然。对所有 mockUsers 断言。
//
// 2. 谱系覆盖(HANDOFF §4):7 个 domain(ai_image / ai_video / web / app /
//    tool / opensource / prompt)每个 ≥ 2 个 project。
//
// 3. commentsFor(projectId) 返回 List(非 null);已知 projectId 返回正确数量;
//    未知 projectId 返回空列表。
//
// 4. 计数铁律(HANDOFF §6.10 禁 ×200 / ×8+30 编造公式):
//    - mockSavedTakeaways / mockNotifications / mockHeatmapCells 是真实数组长度。
//    - Topic heat 用文档化公式(projectCount*10 + postCount*5 + totalLikes~/100),
//      不是 Web 版重灾区 tag.length*8+30。
//    - AuthorRankingEntry.totalLikes 是真实聚合(projectLikes + postLikes)。
//
// 5. 每个 project.authorId 指向 mockUsers 中存在的用户(无悬空引用)。
//
// 6. 每个 mockSavedTakeaway.projectId 指向 mockProjects 中存在的项目。
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/data/seed/mock_seed.dart';
import 'package:kankan_flutter/domain/models/models.dart';

void main() {
  group('F-37 双向关注一致性', () {
    test('每个 followingIds 中的 B,其 followerIds 必含 A.id', () {
      for (final a in mockUsers) {
        for (final bId in a.followingIds) {
          final b = findUser(bId);
          expect(b, isNotNull, reason: '${a.id}.followingIds 含未知用户 $bId');
          expect(
            b!.followerIds.contains(a.id),
            isTrue,
            reason:
                '${a.id} → $bId 单向:B.followerIds 应含 ${a.id},实际 ${b.followerIds}',
          );
        }
      }
    });

    test('每个 followerIds 中的 B,其 followingIds 必含 A.id(反向)', () {
      for (final a in mockUsers) {
        for (final bId in a.followerIds) {
          final b = findUser(bId);
          expect(b, isNotNull, reason: '${a.id}.followerIds 含未知用户 $bId');
          expect(
            b!.followingIds.contains(a.id),
            isTrue,
            reason:
                '${a.id} ← $bId 单向:B.followingIds 应含 ${a.id},实际 ${b.followingIds}',
          );
        }
      }
    });

    test('没有人自己关注自己(无自环)', () {
      for (final u in mockUsers) {
        expect(
          u.followingIds.contains(u.id),
          isFalse,
          reason: '${u.id} 不该关注自己',
        );
        expect(
          u.followerIds.contains(u.id),
          isFalse,
          reason: '${u.id} 不该是自己的粉丝',
        );
      }
    });

    test('followingIds / followerIds 内部无重复 ID', () {
      for (final u in mockUsers) {
        expect(u.followingIds.length, u.followingIds.toSet().length,
            reason: '${u.id}.followingIds 有重复');
        expect(u.followerIds.length, u.followerIds.toSet().length,
            reason: '${u.id}.followerIds 有重复');
      }
    });
  });

  group('7 个 domain 谱系覆盖(每个 ≥ 2 个 project)', () {
    const expectedDomains = [
      'ai_image',
      'ai_video',
      'web',
      'app',
      'tool',
      'opensource',
      'prompt',
    ];

    test('mockProjects 覆盖全部 7 个 domain', () {
      final domains = mockProjects.map((p) => p.domain).toSet();
      for (final d in expectedDomains) {
        expect(domains.contains(d), isTrue, reason: '缺 domain: $d');
      }
    });

    test('每个 domain 至少 2 个 project', () {
      final byDomain = <String, int>{};
      for (final p in mockProjects) {
        byDomain[p.domain] = (byDomain[p.domain] ?? 0) + 1;
      }
      for (final d in expectedDomains) {
        expect(byDomain[d], greaterThanOrEqualTo(2),
            reason: 'domain $d 项目数 < 2');
      }
    });

    test('mockProjects 总数 = 14(7 谱系 × 2)', () {
      expect(mockProjects.length, 14);
    });

    test('每个 project 的 id 唯一', () {
      final ids = mockProjects.map((p) => p.id).toList();
      expect(ids.length, ids.toSet().length);
    });

    test('每个 project 的 domain 落在 7 个标准值内', () {
      for (final p in mockProjects) {
        expect(expectedDomains.contains(p.domain), isTrue,
            reason: '${p.id} 的 domain="${p.domain}" 不在标准 7 值内');
      }
    });
  });

  group('commentsFor · 返回 List 非空断言', () {
    test('对任意输入(含未知 id)都返回非 null 的 List', () {
      // 未知 id 也要返回空 List 而非 null。
      expect(commentsFor('not-exist'), isA<List<Comment>>());
      expect(commentsFor('not-exist'), isEmpty);
      expect(commentsFor(''), isA<List<Comment>>());
      expect(commentsFor(''), isEmpty);
    });

    test('已知 project id 返回正确数量的顶级评论', () {
      // 与 seed 里的实际数据一致(顶级评论数,不含楼中楼 replies)。
      expect(commentsFor('p_aiimg_1').length, 2); // c_p_aiimg_1_1, c_p_aiimg_1_2
      expect(commentsFor('p_aivid_1').length, 1); // c_p_aivid_1_1
      expect(commentsFor('p_prompt_1').length, 2); // c_p_prompt_1_1, c_p_prompt_1_2
    });

    test('已知 post id 返回正确数量', () {
      expect(commentsFor('post_2').length, 2); // c_post_2_1, c_post_2_2
      expect(commentsFor('post_7').length, 1); // c_post_7_1
    });

    test('返回的 Comment.hostId 与查询的 hostId 一致', () {
      for (final c in commentsFor('p_aiimg_1')) {
        expect(c.hostId, 'p_aiimg_1');
        expect(c.hostType, 'project');
      }
      for (final c in commentsFor('post_2')) {
        expect(c.hostId, 'post_2');
        expect(c.hostType, 'post');
      }
    });

    test('评论 id 唯一(含楼中楼)', () {
      final allIds = <String>[];
      for (final c in mockComments) {
        allIds.add(c.id);
        for (final r in c.replies) {
          allIds.add(r.id);
        }
      }
      expect(allIds.length, allIds.toSet().length,
          reason: '评论 id(含 replies)有重复');
    });
  });

  group('计数铁律(HANDOFF §6.10 禁 ×200 / ×8+30 编造公式)', () {
    group('数组长度即真实计数(无放大)', () {
      test('mockUsers.length = 6', () {
        expect(mockUsers.length, 6);
      });

      test('mockSavedTakeaways.length 是真实长度(无 ×200)', () {
        // HANDOFF §6.10:me 屏「我拿走的」直接读 .length,不放大。
        // 这里只断言 length > 0 且 length 与手动数一致(8)。
        expect(mockSavedTakeaways.length, greaterThan(0));
        expect(mockSavedTakeaways.length, 8);
      });

      test('mockNotifications.length 是真实长度(无 ×200)', () {
        expect(mockNotifications.length, 12); // n_1..n_12
      });

      test('mockRecentSearches.length 是真实长度', () {
        expect(mockRecentSearches.length, 6);
      });

      test('mockBrowseHistory.length 是真实长度', () {
        expect(mockBrowseHistory.length, 5);
      });

      test('mockHeatmapCells.length = 182(26 周 × 7 天)', () {
        expect(mockHeatmapCells.length, 182);
      });

      test('mockHeatmapCells 每项 level ∈ [0, 4]', () {
        for (final cell in mockHeatmapCells) {
          expect(cell.level, greaterThanOrEqualTo(0));
          expect(cell.level, lessThanOrEqualTo(4));
        }
      });
    });

    group('Topic heat = projectCount*10 + postCount*5 + totalLikes~/100(文档化公式)', () {
      test('每个 Topic 的 heat 与公式一致(非 ×8+30 编造)', () {
        for (final t in mockTopics) {
          final expected =
              t.projectCount * 10 + t.postCount * 5 + t.totalLikes ~/ 100;
          expect(t.heat, expected,
              reason: 'Topic "${t.tag}" heat 应为 $expected,实际 ${t.heat}');
        }
      });

      test('Topic 按 heat 降序排列', () {
        for (var i = 1; i < mockTopics.length; i++) {
          expect(
            mockTopics[i - 1].heat,
            greaterThanOrEqualTo(mockTopics[i].heat),
            reason: 'Topic 列表不是 heat 降序(第 $i 项)',
          );
        }
      });

      test('Topic 的 projectCount/postCount/totalLikes 与 seed 数据一致', () {
        // 独立聚合一遍,与 _computeTopics 的结果对照。
        final proj = <String, int>{};
        final pos = <String, int>{};
        final lik = <String, int>{};
        for (final p in mockProjects) {
          for (final t in p.tags) {
            proj[t] = (proj[t] ?? 0) + 1;
            lik[t] = (lik[t] ?? 0) + p.likes;
          }
        }
        for (final p in mockPosts) {
          for (final t in p.tags) {
            pos[t] = (pos[t] ?? 0) + 1;
            lik[t] = (lik[t] ?? 0) + p.likes;
          }
        }
        final allTags = <String>{...proj.keys, ...pos.keys};

        for (final t in mockTopics) {
          expect(allTags.contains(t.tag), isTrue,
              reason: 'Topic "${t.tag}" 在 seed 数据中找不到');
          expect(t.projectCount, proj[t.tag] ?? 0,
              reason: 'Topic "${t.tag}" projectCount');
          expect(t.postCount, pos[t.tag] ?? 0,
              reason: 'Topic "${t.tag}" postCount');
          expect(t.totalLikes, lik[t.tag] ?? 0,
              reason: 'Topic "${t.tag}" totalLikes');
        }
      });
    });

    group('AuthorRanking totalLikes 是真实聚合', () {
      test('每个 entry.totalLikes = 该用户所有 project.likes + post.likes 之和', () {
        for (final e in mockAuthorRanking) {
          final projLikes = mockProjects
              .where((p) => p.authorId == e.userId)
              .fold<int>(0, (s, p) => s + p.likes);
          final postLikes = mockPosts
              .where((p) => p.authorId == e.userId)
              .fold<int>(0, (s, p) => s + p.likes);
          expect(e.totalLikes, projLikes + postLikes,
              reason: '${e.userId} totalLikes 不等于真实聚合');
        }
      });

      test('projectCount / postCount 是真实计数(非 ×N)', () {
        for (final e in mockAuthorRanking) {
          final pc = mockProjects.where((p) => p.authorId == e.userId).length;
          final poc = mockPosts.where((p) => p.authorId == e.userId).length;
          expect(e.projectCount, pc, reason: '${e.userId} projectCount');
          expect(e.postCount, poc, reason: '${e.userId} postCount');
        }
      });

      test('按 totalLikes 降序(rank 1..N)', () {
        for (var i = 1; i < mockAuthorRanking.length; i++) {
          expect(
            mockAuthorRanking[i - 1].totalLikes,
            greaterThanOrEqualTo(mockAuthorRanking[i].totalLikes),
          );
        }
        for (var i = 0; i < mockAuthorRanking.length; i++) {
          expect(mockAuthorRanking[i].rank, i + 1);
        }
      });
    });
  });

  group('引用完整性(无悬空引用)', () {
    test('每个 project.authorId 指向 mockUsers 中存在的用户', () {
      final userIds = mockUsers.map((u) => u.id).toSet();
      for (final p in mockProjects) {
        expect(userIds.contains(p.authorId), isTrue,
            reason: 'Project ${p.id} 的 authorId=${p.authorId} 不在 mockUsers');
      }
    });

    test('每个 post.authorId 指向 mockUsers 中存在的用户', () {
      final userIds = mockUsers.map((u) => u.id).toSet();
      for (final p in mockPosts) {
        expect(userIds.contains(p.authorId), isTrue,
            reason: 'Post ${p.id} 的 authorId=${p.authorId} 不在 mockUsers');
      }
    });

    test('每个 comment.authorId 指向 mockUsers 中存在的用户(含 replies)', () {
      final userIds = mockUsers.map((u) => u.id).toSet();
      void checkComment(Comment c, String ctx) {
        expect(userIds.contains(c.authorId), isTrue,
            reason: '$ctx ${c.id} 的 authorId=${c.authorId} 不在 mockUsers');
        for (final r in c.replies) {
          checkComment(r, '$ctx(reply)');
        }
      }
      for (final c in mockComments) {
        checkComment(c, 'Comment');
      }
    });

    test('每个 SavedTakeaway.projectId 指向 mockProjects 中存在的项目', () {
      final projectIds = mockProjects.map((p) => p.id).toSet();
      for (final t in mockSavedTakeaways) {
        expect(projectIds.contains(t.projectId), isTrue,
            reason: 'SavedTakeaway ${t.id} 的 projectId=${t.projectId} 不在 mockProjects');
      }
    });

    test('每个 SavedTakeaway.domain 落在 7 个标准 domain 内', () {
      const domains = {
        'ai_image',
        'ai_video',
        'web',
        'app',
        'tool',
        'opensource',
        'prompt',
      };
      for (final t in mockSavedTakeaways) {
        expect(domains.contains(t.domain), isTrue,
            reason: 'SavedTakeaway ${t.id} domain=${t.domain} 不在标准值');
      }
    });

    test('每个 SavedTakeaway.kind 落在 text/file/link 三档内', () {
      const kinds = {'text', 'file', 'link'};
      for (final t in mockSavedTakeaways) {
        expect(kinds.contains(t.kind), isTrue,
            reason: 'SavedTakeaway ${t.id} kind=${t.kind} 不在 text/file/link');
      }
    });
  });

  group('findProject / findPost / findUser 便捷查找', () {
    test('findUser 已知 id → 返回对应 KkUser', () {
      expect(findUser('me')?.id, 'me');
      expect(findUser('chen')?.name, '陈小匠');
    });

    test('findUser 未知 id → null', () {
      expect(findUser('not-exist'), isNull);
    });

    test('findProject 已知 id → 返回对应 Project', () {
      expect(findProject('p_aiimg_1')?.title, '赛博朋克茶馆');
    });

    test('findProject 未知 id → null', () {
      expect(findProject('not-exist'), isNull);
    });

    test('findPost 已知 id → 返回对应 Post', () {
      expect(findPost('post_1'), isNotNull);
    });

    test('findPost 未知 id → null', () {
      expect(findPost('not-exist'), isNull);
    });
  });

  group('ranking 新上榜哨兵', () {
    test('kRankNewEntrySentinel = 999(任务⑥ Part B)', () {
      expect(kRankNewEntrySentinel, 999);
    });

    test('mockNewProjectIds 内的 id 返回哨兵值', () {
      for (final id in mockNewProjectIds) {
        expect(mockProjectRankChange(id), kRankNewEntrySentinel);
      }
    });

    test('mockNewPostIds 内的 id 返回哨兵值', () {
      for (final id in mockNewPostIds) {
        expect(mockPostRankChange(id), kRankNewEntrySentinel);
      }
    });

    test('其它 id 返回 -3..+3(确定性 hash,0 居中)', () {
      // 取一个肯定不在新上榜集合里的 id。
      final r = mockProjectRankChange('p_aiimg_1');
      expect(r, greaterThanOrEqualTo(-3));
      expect(r, lessThanOrEqualTo(3));

      final r2 = mockPostRankChange('post_1');
      expect(r2, greaterThanOrEqualTo(-3));
      expect(r2, lessThanOrEqualTo(3));
    });
  });

  group('mockWorkflows · HowAction.ref 完整覆盖', () {
    test('每个 HowAction.ref 都能在 mockWorkflows 找到对应工作流', () {
      // 收集所有 Project 引用的 HowAction ref(Post 无 actions 字段)。
      final refs = <String>{};
      for (final p in mockProjects) {
        for (final a in p.actions) {
          if (a is HowAction) refs.add(a.ref);
        }
      }
      for (final ref in refs) {
        expect(findWorkflow(ref), isNotNull,
            reason: 'HowAction.ref=$ref 在 mockWorkflows 中找不到');
      }
    });

    test('findWorkflow 未知 ref → null', () {
      expect(findWorkflow('not-exist'), isNull);
    });

    test('每个 MockWorkflow 必有 ref/title/after/language(非空)', () {
      for (final w in mockWorkflows) {
        expect(w.ref, isNotEmpty);
        expect(w.title, isNotEmpty);
        expect(w.after, isNotEmpty);
        expect(w.language, isNotEmpty);
      }
    });
  });
}
