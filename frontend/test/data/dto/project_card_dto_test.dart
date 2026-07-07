// 后端 Project 卡片/详情 DTO 解析单测。
//
// 覆盖 lib/data/dto/project_card_dto.dart:
//   - projectFromCardJson:GET /projects 卡片 JSON → 前端 Project(最小映射)。
//   - projectFromDetailJson:GET /projects/{id} 详情 JSON → 前端 Project(带 intro/author/media/counts)。
//   - 私有 helper 的间接覆盖:_authorIdAndCache / _likesFromCounts / _resolveMediaUrl /
//     _mapDomain / _parseMs。
//
// 已知模型分叉(见源文件注释):
//   - 后端 category → 前端 domain 映射(_mapDomain)。
//   - likes = counts.reactions.{creative,big_brain,cool} 之和。
//   - takeawayCount 取 counts.takeaways 或顶层 takeaway_count(兼容两种位置)。
//   - author 展开时缓存到 remoteUserCache(通过 remoteUserById 验证副作用)。
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/data/dto/project_card_dto.dart';
import 'package:kankan_flutter/data/remote_user_cache.dart';
import 'package:kankan_flutter/domain/models/models.dart';

void main() {
  group('projectFromCardJson · 完整 payload', () {
    test('所有字段齐全 → 正确映射', () {
      const j = <String, dynamic>{
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'title': '赛博朋克茶馆',
        'tagline': '用 Midjourney 做的赛博朋克茶馆',
        'author': {
          'id': 'auth-1',
          'nickname': '林设计',
          'avatar_url': 'https://cdn/avatar.png',
        },
        'cover_media_url': 'https://cdn/cover.png',
        'tools': const ['midjourney', 'v6'],
        'category': 'image_design',
        'counts': {
          'reactions': {'creative': 10, 'big_brain': 5, 'cool': 3},
          'takeaways': 42,
        },
        'published_at': '2025-11-30T10:00:00Z',
      };

      final p = projectFromCardJson(j);

      expect(p.id, '550e8400-e29b-41d4-a716-446655440000');
      expect(p.title, '赛博朋克茶馆');
      expect(p.summary, '用 Midjourney 做的赛博朋克茶馆');
      expect(p.authorId, 'auth-1');
      expect(p.domain, 'ai_image');
      expect(p.tags, ['midjourney', 'v6']);
      expect(p.likes, 18); // 10 + 5 + 3
      expect(p.commentCount, 0); // 卡片层固定 0
      expect(p.takeawayCount, 42);
      expect(p.actions, isEmpty);
      // media = 一张封面图
      expect(p.resultData.media.length, 1);
      expect(p.resultData.media.first.type, 'image');
      expect(p.resultData.media.first.url, 'https://cdn/cover.png');
      // authorNote 在卡片层不填(详情才有)
      expect(p.authorNote, isNull);
      // 时间戳:2025-11-30T10:00:00Z → ms
      expect(
        p.createdAtMs,
        DateTime.parse('2025-11-30T10:00:00Z').millisecondsSinceEpoch,
      );
    });

    test('author 被缓存到 remoteUserCache(副作用验证)', () {
      const j = <String, dynamic>{
        'id': 'p1',
        'title': 't',
        'author': {
          'id': 'remote-author-x',
          'nickname': '陈小匠',
          'avatar_url': 'https://cdn/chen.png',
        },
        'category': 'image',
      };
      projectFromCardJson(j);
      final u = remoteUserById('remote-author-x');
      expect(u, isNotNull);
      expect(u!.id, 'remote-author-x');
      expect(u.name, '陈小匠');
      expect(u.avatar, 'https://cdn/chen.png');
    });

    test('author nickname 缺失 → name 退到 id', () {
      const j = <String, dynamic>{
        'id': 'p2',
        'title': 't',
        'author': {'id': 'no-nick-author', 'avatar_url': null},
      };
      projectFromCardJson(j);
      final u = remoteUserById('no-nick-author');
      expect(u, isNotNull);
      expect(u!.name, 'no-nick-author');
    });
  });

  group('projectFromCardJson · 缺失/空字段兜底', () {
    test('所有可选字段缺失 → 安全默认', () {
      const j = <String, dynamic>{'id': 'p3', 'title': '只有标题'};
      final p = projectFromCardJson(j);

      expect(p.id, 'p3');
      expect(p.title, '只有标题');
      expect(p.summary, ''); // tagline / subtitle / intro 都缺 → ''
      expect(p.authorId, ''); // author 不是 Map → ''
      expect(p.tags, isEmpty); // tools 不是 List → []
      expect(p.domain, 'tool'); // category 缺 → 兜底 'tool'
      expect(p.likes, 0); // counts 缺 → 0
      expect(p.takeawayCount, 0); // counts 与 takeaway_count 都缺 → 0
      expect(p.resultData.media, isEmpty); // cover_media_url 缺 → 空 media
      // published_at 缺 → 用 now(只能验"非 0")
      expect(p.createdAtMs, greaterThan(0));
    });

    test('字段为 null 与缺失等价', () {
      const j = <String, dynamic>{
        'id': 'p4',
        'title': null,
        'tagline': null,
        'author': null,
        'cover_media_url': null,
        'tools': null,
        'category': null,
        'counts': null,
        'published_at': null,
      };
      final p = projectFromCardJson(j);

      expect(p.id, 'p4'); // j['id'].toString() 仍可用(但 null.toString() → 'null')
      expect(p.title, ''); // null ?? '' → ''
      expect(p.summary, '');
      expect(p.authorId, '');
      expect(p.tags, isEmpty);
      expect(p.domain, 'tool');
      expect(p.likes, 0);
      expect(p.takeawayCount, 0);
      expect(p.resultData.media, isEmpty);
      // published_at null → now
      expect(p.createdAtMs, greaterThan(0));
    });

    test('cover_media_url 空串 → media 列表空', () {
      const j = <String, dynamic>{'id': 'p5', 'cover_media_url': ''};
      final p = projectFromCardJson(j);
      expect(p.resultData.media, isEmpty);
    });
  });

  group('projectFromCardJson · likes 解析(counts.reactions 三项之和)', () {
    test('三项都是 int → 直接求和', () {
      const j = <String, dynamic>{
        'id': 'p',
        'counts': {
          'reactions': {'creative': 10, 'big_brain': 20, 'cool': 30},
        },
      };
      expect(projectFromCardJson(j).likes, 60);
    });

    test('三项是字符串(int.tryParse 成功)→ 求和', () {
      const j = <String, dynamic>{
        'id': 'p',
        'counts': {
          'reactions': {'creative': '7', 'big_brain': '8', 'cool': '9'},
        },
      };
      expect(projectFromCardJson(j).likes, 24);
    });

    test('缺 big_brain / cool → 视为 0', () {
      const j = <String, dynamic>{
        'id': 'p',
        'counts': {
          'reactions': {'creative': 5},
        },
      };
      expect(projectFromCardJson(j).likes, 5);
    });

    test('reactions 不是 Map → 0', () {
      const j = <String, dynamic>{
        'id': 'p',
        'counts': {'reactions': 'oops'},
      };
      expect(projectFromCardJson(j).likes, 0);
    });

    test('counts 不是 Map → 0', () {
      const j = <String, dynamic>{'id': 'p', 'counts': 'oops'};
      expect(projectFromCardJson(j).likes, 0);
    });

    test('counts 缺失 → 0', () {
      const j = <String, dynamic>{'id': 'p'};
      expect(projectFromCardJson(j).likes, 0);
    });
  });

  group('projectFromCardJson · takeawayCount 双位置兼容', () {
    test('counts.takeaways 是 int → 取该值', () {
      const j = <String, dynamic>{
        'id': 'p',
        'counts': {'takeaways': 42},
      };
      expect(projectFromCardJson(j).takeawayCount, 42);
    });

    test('counts.takeaways 是字符串 → int.tryParse', () {
      const j = <String, dynamic>{
        'id': 'p',
        'counts': {'takeaways': '42'},
      };
      expect(projectFromCardJson(j).takeawayCount, 42);
    });

    test('counts 不是 Map → 退到 j.takeaway_count', () {
      const j = <String, dynamic>{'id': 'p', 'takeaway_count': 99};
      expect(projectFromCardJson(j).takeawayCount, 99);
    });

    test('counts 不是 Map 且 takeaway_count 是字符串 → int.tryParse', () {
      const j = <String, dynamic>{'id': 'p', 'takeaway_count': '99'};
      expect(projectFromCardJson(j).takeawayCount, 99);
    });

    test('两处都缺 → 0', () {
      const j = <String, dynamic>{'id': 'p'};
      expect(projectFromCardJson(j).takeawayCount, 0);
    });
  });

  group('projectFromCardJson · _mapDomain 覆盖', () {
    void checkDomain(String? category, String expected) {
      final p = projectFromCardJson(<String, dynamic>{
        'id': 'p',
        'category': category,
      });
      expect(p.domain, expected, reason: 'category=$category');
    }

    test('image_design / image → ai_image', () {
      checkDomain('image_design', 'ai_image');
      checkDomain('image', 'ai_image');
    });

    test('video / video_edit → ai_video', () {
      checkDomain('video', 'ai_video');
      checkDomain('video_edit', 'ai_video');
    });

    test('web / web_design → web', () {
      checkDomain('web', 'web');
      checkDomain('web_design', 'web');
    });

    test('app / mobile → app', () {
      checkDomain('app', 'app');
      checkDomain('mobile', 'app');
    });

    test('prompt / writing → prompt', () {
      checkDomain('prompt', 'prompt');
      checkDomain('writing', 'prompt');
    });

    test('opensource / open_source → opensource', () {
      checkDomain('opensource', 'opensource');
      checkDomain('open_source', 'opensource');
    });

    test('未知 / null → tool(兜底)', () {
      checkDomain('unknown_category', 'tool');
      checkDomain(null, 'tool');
    });
  });

  group('projectFromCardJson · 媒体 URL 解析(_resolveMediaUrl)', () {
    test('绝对 http(s) URL → 原样返回', () {
      final p = projectFromCardJson(const <String, dynamic>{
        'id': 'p',
        'cover_media_url': 'https://cdn.example.com/cover.png',
      });
      expect(p.resultData.media.first.url, 'https://cdn.example.com/cover.png');
    });

    test('相对路径 /uploads/x.png → 拼后端 origin', () {
      final p = projectFromCardJson(const <String, dynamic>{
        'id': 'p',
        'cover_media_url': '/uploads/x.png',
      });
      // 默认 apiBaseUrl = 'http://127.0.0.1:8000/api/v1',origin = 'http://127.0.0.1:8000'。
      expect(
        p.resultData.media.first.url,
        'http://127.0.0.1:8000/uploads/x.png',
      );
    });

    test('相对路径不带前导 / → 拼时补 /', () {
      final p = projectFromCardJson(const <String, dynamic>{
        'id': 'p',
        'cover_media_url': 'uploads/y.png',
      });
      expect(
        p.resultData.media.first.url,
        'http://127.0.0.1:8000/uploads/y.png',
      );
    });
  });

  group('projectFromDetailJson · 详情级解析', () {
    test('media 数组齐全 → 全部映射,按 type 区分 image/video', () {
      const j = <String, dynamic>{
        'id': 'd1',
        'title': '水墨游鱼',
        'tagline': '可灵 AI 做的水墨风游鱼',
        'intro': '试了 7 次才稳定。',
        'author': {
          'id': 'lin',
          'nickname': '林设计',
          'avatar_url': 'https://cdn/lin.png',
        },
        'media': [
          {
            'type': 'video',
            'url': 'https://cdn/fish.mp4',
            'poster': 'https://cdn/fish.jpg',
          },
          {'type': 'image', 'url': 'https://cdn/frame.png'},
        ],
        'tools': const ['可灵', '水墨'],
        'category': 'video',
        'counts': {
          'reactions': {'creative': 100, 'big_brain': 50, 'cool': 139},
          'takeaways': 67,
        },
        'published_at': '2025-11-29T02:00:00Z',
      };

      final p = projectFromDetailJson(j);

      expect(p.id, 'd1');
      expect(p.title, '水墨游鱼');
      expect(p.summary, '可灵 AI 做的水墨风游鱼');
      expect(p.authorNote, '试了 7 次才稳定。'); // 详情层有 intro
      expect(p.authorId, 'lin');
      expect(p.tags, ['可灵', '水墨']);
      expect(p.domain, 'ai_video');
      expect(p.likes, 289);
      expect(p.takeawayCount, 67);
      expect(p.resultData.media.length, 2);
      expect(p.resultData.media[0].type, 'video');
      expect(p.resultData.media[0].url, 'https://cdn/fish.mp4');
      expect(p.resultData.media[0].poster, 'https://cdn/fish.jpg');
      expect(p.resultData.media[1].type, 'image');
      expect(p.resultData.media[1].url, 'https://cdn/frame.png');
    });

    test('media 数组空但 cover_media_url 有 → 兜底一张图', () {
      final j = <String, dynamic>{
        'id': 'd2',
        'cover_media_url': 'https://cdn/cover.png',
        'media': const <Map<String, dynamic>>[],
      };
      final p = projectFromDetailJson(j);
      expect(p.resultData.media.length, 1);
      expect(p.resultData.media.first.type, 'image');
      expect(p.resultData.media.first.url, 'https://cdn/cover.png');
    });

    test('media 缺失 + cover_media_url 有 → 兜底一张图', () {
      const j = <String, dynamic>{
        'id': 'd3',
        'cover_media_url': 'https://cdn/cover2.png',
      };
      final p = projectFromDetailJson(j);
      expect(p.resultData.media.length, 1);
      expect(p.resultData.media.first.url, 'https://cdn/cover2.png');
    });

    test('media 缺失 + cover_media_url 也缺失 → media 空', () {
      const j = <String, dynamic>{'id': 'd4'};
      final p = projectFromDetailJson(j);
      expect(p.resultData.media, isEmpty);
    });

    test('media 数组里的 url 空 → 该项被跳过', () {
      const j = <String, dynamic>{
        'id': 'd5',
        'media': [
          {'type': 'image', 'url': ''}, // 空 url 跳过
          {'type': 'image', 'url': 'https://cdn/keep.png'},
        ],
      };
      final p = projectFromDetailJson(j);
      expect(p.resultData.media.length, 1);
      expect(p.resultData.media.first.url, 'https://cdn/keep.png');
    });

    test('media 项的 type 不是 "video" → 视为 image', () {
      const j = <String, dynamic>{
        'id': 'd6',
        'media': [
          {'type': 'unknown', 'url': 'https://cdn/x.png'},
        ],
      };
      final p = projectFromDetailJson(j);
      expect(p.resultData.media.first.type, 'image');
    });

    test('authorNote:intro 缺失 → 退到 description', () {
      const j = <String, dynamic>{
        'id': 'd7',
        'description': '从 description 来',
      };
      final p = projectFromDetailJson(j);
      expect(p.authorNote, '从 description 来');
    });

    test('authorNote:intro 与 description 都缺 → null', () {
      const j = <String, dynamic>{'id': 'd8'};
      final p = projectFromDetailJson(j);
      expect(p.authorNote, isNull);
    });

    test('summary:tagline 缺失 → 退到 subtitle → 再退到 空', () {
      // 注:detail 的 summary 只看 tagline / subtitle,不看 intro(intro 给 authorNote)。
      final p1 = projectFromDetailJson(const <String, dynamic>{
        'id': 'd9',
        'subtitle': '从 subtitle 来',
      });
      expect(p1.summary, '从 subtitle 来');

      final p2 = projectFromDetailJson(const <String, dynamic>{'id': 'd10'});
      expect(p2.summary, '');
    });

    test('media 相对 URL → 拼后端 origin(poster 同样)', () {
      const j = <String, dynamic>{
        'id': 'd11',
        'media': [
          {'type': 'video', 'url': '/uploads/v.mp4', 'poster': '/uploads/p.jpg'},
        ],
      };
      final p = projectFromDetailJson(j);
      expect(p.resultData.media.first.url, 'http://127.0.0.1:8000/uploads/v.mp4');
      expect(p.resultData.media.first.poster, 'http://127.0.0.1:8000/uploads/p.jpg');
    });

    test('published_at 缺失 → 用 now(时间戳 > 0)', () {
      final p = projectFromDetailJson(const <String, dynamic>{'id': 'd12'});
      expect(p.createdAtMs, greaterThan(0));
    });

    test('published_at 非法字符串 → 用 now(不抛)', () {
      final p = projectFromDetailJson(const <String, dynamic>{
        'id': 'd13',
        'published_at': 'not-a-date',
      });
      expect(p.createdAtMs, greaterThan(0));
    });
  });

  group('projectFromCardJson · id 类型兼容', () {
    test('id 是 int → toString 成串', () {
      final p = projectFromCardJson({'id': 12345});
      expect(p.id, '12345');
    });

    test('id 是 UUID 字符串 → 原样', () {
      final p = projectFromCardJson(const <String, dynamic>{
        'id': '550e8400-e29b-41d4-a716-446655440000',
      });
      expect(p.id, '550e8400-e29b-41d4-a716-446655440000');
    });
  });
}
