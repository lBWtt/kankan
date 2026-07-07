// Domain 模型 freezed 行为单测。
//
// 覆盖 lib/domain/models/{project,post,user,comment}.dart(及其 .freezed.dart 生成代码):
//   - copyWith() 无参 → 与原实例等价
//   - copyWith(field: value) → 仅指定字段被覆盖
//   - == 与 hashCode:同内容相等 / 不同内容不等 / hashCode 一致
//   - @Default 默认值
//   - 嵌套 List 字段(tags / replies / media)的深比较
//
// 这些是 freezed 生成的"合约"。如果 .freezed.dart 重新生成时丢字段或误改 ==,
// 这里会立刻失败。
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/domain/models/models.dart';

void main() {
  // ── 测试夹具:可复用的最小有效实例 ──
  ResultData makeResultData() => const ResultData(
        media: [MediaItem(type: 'image', url: 'https://cdn/a.png')],
      );

  group('Project (freezed)', () {
    Project makeProject() => Project(
          id: 'p1',
          title: '标题',
          summary: '一句话',
          authorId: 'lin',
          resultData: makeResultData(),
          domain: 'ai_image',
          createdAtMs: 1700000000000,
        );

    group('默认值', () {
      test('actions / tags 默认空列表,authorNote 默认 null', () {
        final p = makeProject();
        expect(p.actions, isEmpty);
        expect(p.tags, isEmpty);
        expect(p.authorNote, isNull);
      });

      test('likes / commentCount / takeawayCount / repoStars 默认 0', () {
        final p = makeProject();
        expect(p.likes, 0);
        expect(p.commentCount, 0);
        expect(p.takeawayCount, 0);
        expect(p.repoStars, 0);
      });
    });

    group('copyWith', () {
      test('无参 copyWith → 与原实例 == (但不 identical)', () {
        final p = makeProject();
        final copy = p.copyWith();
        expect(copy, equals(p));
        expect(copy.hashCode, p.hashCode);
        expect(identical(copy, p), isFalse);
      });

      test('覆盖单个字段 → 仅该字段变化,其余保持', () {
        final p = makeProject();
        final copy = p.copyWith(title: '新标题');
        expect(copy.title, '新标题');
        expect(copy.id, p.id);
        expect(copy.summary, p.summary);
        expect(copy.authorId, p.authorId);
        expect(copy.domain, p.domain);
        expect(copy.createdAtMs, p.createdAtMs);
        expect(copy.resultData, p.resultData);
      });

      test('覆盖 int 字段', () {
        final p = makeProject();
        final copy = p.copyWith(likes: 99, commentCount: 5, repoStars: 234);
        expect(copy.likes, 99);
        expect(copy.commentCount, 5);
        expect(copy.repoStars, 234);
        // 其它不变
        expect(copy.id, p.id);
        expect(copy.title, p.title);
      });

      test('覆盖 nullable 字段:authorNote null → 非 null', () {
        final p = makeProject(); // authorNote 默认 null
        expect(p.authorNote, isNull);
        final copy = p.copyWith(authorNote: '作者的话');
        expect(copy.authorNote, '作者的话');
      });

      test('覆盖 nullable 字段:authorNote 非 null → null(freezed 支持)', () {
        final p = makeProject().copyWith(authorNote: '原来的');
        final copy = p.copyWith(authorNote: null);
        expect(copy.authorNote, isNull);
      });

      test('覆盖 List 字段(tags)→ 替换为新列表', () {
        final p = makeProject().copyWith(tags: const ['old']);
        final copy = p.copyWith(tags: const ['new', 'tags']);
        expect(copy.tags, ['new', 'tags']);
        expect(p.tags, ['old']); // 原 instance 不变(不可变)
      });

      test('覆盖 resultData → 整个对象替换', () {
        final p = makeProject();
        final newRd = const ResultData(text: '纯心得正文');
        final copy = p.copyWith(resultData: newRd);
        expect(copy.resultData, newRd);
        expect(copy.resultData.text, '纯心得正文');
        expect(copy.resultData.media, isEmpty);
      });
    });

    group('== / hashCode', () {
      test('同内容两个实例 == 且 hashCode 相同', () {
        final a = makeProject();
        final b = makeProject();
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('任一字段不同 → !=', () {
        final base = makeProject();
        expect(base.copyWith(id: 'p2'), isNot(equals(base)));
        expect(base.copyWith(title: '其他'), isNot(equals(base)));
        expect(base.copyWith(summary: '其他'), isNot(equals(base)));
        expect(base.copyWith(authorId: 'wang'), isNot(equals(base)));
        expect(base.copyWith(domain: 'tool'), isNot(equals(base)));
        expect(base.copyWith(likes: 1), isNot(equals(base)));
        expect(base.copyWith(commentCount: 1), isNot(equals(base)));
        expect(base.copyWith(takeawayCount: 1), isNot(equals(base)));
        expect(base.copyWith(repoStars: 1), isNot(equals(base)));
        expect(base.copyWith(createdAtMs: 1), isNot(equals(base)));
        expect(base.copyWith(authorNote: 'note'), isNot(equals(base)));
        expect(base.copyWith(tags: const ['t']), isNot(equals(base)));
        expect(base.copyWith(actions: const [TakeAction(source: 's', takeKind: 'copy')]),
            isNot(equals(base)));
      });

      test('List 字段深比较:同内容(不同实例)→ ==', () {
        final a = makeProject().copyWith(tags: ['a', 'b']);
        final b = makeProject().copyWith(tags: ['a', 'b']);
        expect(a, equals(b));
      });

      test('List 字段顺序不同 → !=', () {
        final a = makeProject().copyWith(tags: ['a', 'b']);
        final b = makeProject().copyWith(tags: ['b', 'a']);
        expect(a, isNot(equals(b)));
      });
    });

    group('toString 不抛(便于日志调试)', () {
      test('包含 id 与 title', () {
        final s = makeProject().toString();
        expect(s.contains('p1'), isTrue);
        expect(s.contains('标题'), isTrue);
      });
    });
  });

  group('Post (freezed)', () {
    Post makePost() => Post(
          id: 'post_1',
          content: '正文内容',
          authorId: 'lin',
          createdAtMs: 1700000000000,
        );

    group('默认值', () {
      test('media / tags 默认空列表,quoteProjectId 默认 null', () {
        final p = makePost();
        expect(p.media, isEmpty);
        expect(p.tags, isEmpty);
        expect(p.quoteProjectId, isNull);
      });

      test('likes / commentCount 默认 0', () {
        final p = makePost();
        expect(p.likes, 0);
        expect(p.commentCount, 0);
      });
    });

    group('copyWith', () {
      test('无参 → == 但不 identical', () {
        final p = makePost();
        final copy = p.copyWith();
        expect(copy, equals(p));
        expect(copy.hashCode, p.hashCode);
        expect(identical(copy, p), isFalse);
      });

      test('覆盖 content', () {
        final p = makePost();
        final copy = p.copyWith(content: '新内容');
        expect(copy.content, '新内容');
        expect(copy.id, p.id);
        expect(copy.authorId, p.authorId);
      });

      test('覆盖 quoteProjectId(null → 非 null → null)', () {
        final p = makePost();
        expect(p.quoteProjectId, isNull);
        final withQuote = p.copyWith(quoteProjectId: 'p_aiimg_1');
        expect(withQuote.quoteProjectId, 'p_aiimg_1');
        final removed = withQuote.copyWith(quoteProjectId: null);
        expect(removed.quoteProjectId, isNull);
      });

      test('覆盖 media List', () {
        final p = makePost();
        final copy = p.copyWith(
          media: const [MediaItem(type: 'image', url: 'https://cdn/a.png')],
        );
        expect(copy.media.length, 1);
        expect(copy.media.first.url, 'https://cdn/a.png');
        expect(p.media, isEmpty); // 原 instance 不变
      });
    });

    group('== / hashCode', () {
      test('同内容 == 且 hashCode 一致', () {
        final a = makePost();
        final b = makePost();
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('不同内容 !=', () {
        final base = makePost();
        expect(base.copyWith(content: 'x'), isNot(equals(base)));
        expect(base.copyWith(likes: 1), isNot(equals(base)));
        expect(base.copyWith(tags: const ['t']), isNot(equals(base)));
      });
    });
  });

  group('KkUser (freezed)', () {
    KkUser makeUser() => const KkUser(
          id: 'me',
          name: '看看君',
          avatar: 'https://cdn/a.png',
          bio: '在看 AI 做的东西',
          followingIds: ['chen', 'lin'],
          followerIds: ['chen'],
        );

    group('默认值', () {
      test('avatar / bio 默认 null,followingIds / followerIds 默认空', () {
        const u = KkUser(id: 'u', name: 'n');
        expect(u.avatar, isNull);
        expect(u.bio, isNull);
        expect(u.followingIds, isEmpty);
        expect(u.followerIds, isEmpty);
      });
    });

    group('copyWith', () {
      test('无参 → == 但不 identical', () {
        final u = makeUser();
        final copy = u.copyWith();
        expect(copy, equals(u));
        expect(copy.hashCode, u.hashCode);
        expect(identical(copy, u), isFalse);
      });

      test('覆盖 name', () {
        final u = makeUser();
        final copy = u.copyWith(name: '新名字');
        expect(copy.name, '新名字');
        expect(copy.id, u.id);
      });

      test('覆盖 followingIds / followerIds(F-37 双向关注重算路径)', () {
        final u = makeUser();
        final copy = u.copyWith(
          followingIds: const ['chen', 'lin', 'wang'],
          followerIds: const ['chen'],
        );
        expect(copy.followingIds, ['chen', 'lin', 'wang']);
        expect(copy.followerIds, ['chen']);
        expect(u.followingIds, ['chen', 'lin']); // 原 instance 不变
      });
    });

    group('== / hashCode', () {
      test('同内容 ==', () {
        final a = makeUser();
        final b = makeUser();
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('List 字段内容差异 → !=', () {
        final a = makeUser();
        final b = a.copyWith(followingIds: const ['chen']); // 少一个
        expect(a, isNot(equals(b)));
      });
    });
  });

  group('Comment (freezed, 含嵌套 replies)', () {
    Comment makeComment() => Comment(
          id: 'c1',
          hostType: 'project',
          hostId: 'p1',
          authorId: 'wang',
          content: '评论内容',
          likes: 12,
          createdAtMs: 1700000000000,
        );

    group('默认值', () {
      test('likes 默认 0,replies 默认空', () {
        final c = Comment(
          id: 'c',
          hostType: 'project',
          hostId: 'p',
          authorId: 'u',
          content: 'x',
          createdAtMs: 1,
        );
        expect(c.likes, 0);
        expect(c.replies, isEmpty);
      });
    });

    group('copyWith', () {
      test('无参 → == 但不 identical', () {
        final c = makeComment();
        final copy = c.copyWith();
        expect(copy, equals(c));
        expect(copy.hashCode, c.hashCode);
        expect(identical(copy, c), isFalse);
      });

      test('覆盖 content 与 likes', () {
        final c = makeComment();
        final copy = c.copyWith(content: '新内容', likes: 99);
        expect(copy.content, '新内容');
        expect(copy.likes, 99);
        expect(c.content, '评论内容'); // 原 instance 不变
        expect(c.likes, 12);
      });
    });

    group('嵌套 replies 深比较', () {
      test('replies 内容相同(不同实例)→ ==', () {
        final replyA = Comment(
          id: 'r1',
          hostType: 'project',
          hostId: 'p1',
          authorId: 'lin',
          content: '回复',
          createdAtMs: 1,
        );
        final replyB = Comment(
          id: 'r1',
          hostType: 'project',
          hostId: 'p1',
          authorId: 'lin',
          content: '回复',
          createdAtMs: 1,
        );
        final a = makeComment().copyWith(replies: [replyA]);
        final b = makeComment().copyWith(replies: [replyB]);
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('replies 内容不同 → !=', () {
        final replyA = Comment(
          id: 'r1',
          hostType: 'project',
          hostId: 'p1',
          authorId: 'lin',
          content: '回复 A',
          createdAtMs: 1,
        );
        final replyB = Comment(
          id: 'r1',
          hostType: 'project',
          hostId: 'p1',
          authorId: 'lin',
          content: '回复 B',
          createdAtMs: 1,
        );
        final a = makeComment().copyWith(replies: [replyA]);
        final b = makeComment().copyWith(replies: [replyB]);
        expect(a, isNot(equals(b)));
      });

      test('replies 数量不同 → !=', () {
        final reply = Comment(
          id: 'r1',
          hostType: 'project',
          hostId: 'p1',
          authorId: 'lin',
          content: '回复',
          createdAtMs: 1,
        );
        final a = makeComment().copyWith(replies: [reply]);
        final b = makeComment().copyWith(replies: const []);
        expect(a, isNot(equals(b)));
      });
    });

    group('== / hashCode 基础', () {
      test('同内容 ==', () {
        final a = makeComment();
        final b = makeComment();
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('hostType / hostId 不同 → !=', () {
        final base = makeComment();
        expect(base.copyWith(hostType: 'post'), isNot(equals(base)));
        expect(base.copyWith(hostId: 'p2'), isNot(equals(base)));
      });
    });
  });

  group('ResultData (freezed, 组合容器)', () {
    test('默认全空(media=[], repo/io/text=null)', () {
      const rd = ResultData();
      expect(rd.media, isEmpty);
      expect(rd.repo, isNull);
      expect(rd.io, isNull);
      expect(rd.text, isNull);
    });

    test('copyWith 无参 → ==', () {
      const rd = ResultData(text: '心得');
      expect(rd.copyWith(), equals(rd));
    });

    test('同字段同内容 → ==', () {
      const a = ResultData(text: '心得', media: [MediaItem(type: 'image', url: 'u')]);
      const b = ResultData(text: '心得', media: [MediaItem(type: 'image', url: 'u')]);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('字段不同 → !=', () {
      const a = ResultData(text: 'a');
      const b = ResultData(text: 'b');
      expect(a, isNot(equals(b)));
    });
  });

  group('MediaItem / RepoInfo / IoBlock (freezed)', () {
    test('MediaItem == 与 copyWith', () {
      const a = MediaItem(type: 'image', url: 'u', alt: 'a');
      const b = MediaItem(type: 'image', url: 'u', alt: 'a');
      expect(a, equals(b));
      expect(a.copyWith(alt: null).alt, isNull);
    });

    test('RepoInfo == 与 copyWith', () {
      const a = RepoInfo(
        name: 'flutter',
        fullName: 'flutter/flutter',
        stars: 100,
        language: 'Dart',
        url: 'https://github.com/flutter/flutter',
      );
      const b = RepoInfo(
        name: 'flutter',
        fullName: 'flutter/flutter',
        stars: 100,
        language: 'Dart',
        url: 'https://github.com/flutter/flutter',
      );
      expect(a, equals(b));
      expect(a.copyWith(stars: 200).stars, 200);
    });

    test('IoBlock == 与 copyWith', () {
      const a = IoBlock(input: 'i', output: 'o', model: 'm', lang: 'l');
      const b = IoBlock(input: 'i', output: 'o', model: 'm', lang: 'l');
      expect(a, equals(b));
      expect(a.copyWith(model: null).model, isNull);
    });
  });
}
