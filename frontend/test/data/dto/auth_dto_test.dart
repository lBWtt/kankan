// 后端 /auth/login 返回解析单测。
//
// 覆盖 lib/data/dto/auth_dto.dart:
//   - userFromMeJson:后端 MeResponse{id,nickname,email,phone,avatar_url,bio} → KkUser。
//     nickname 缺失时依次退到 邮箱本地部分 / 手机号尾号 / id。
//   - loginResultFromJson:后端 LoginResponse{access_token,refresh_token,user,is_new_user}
//     → LoginResult(令牌 + 用户 + 新注册标记)。
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/data/dto/auth_dto.dart';
import 'package:kankan_flutter/domain/models/models.dart';

void main() {
  group('userFromMeJson · 昵称退路链', () {
    test('有 nickname → 用 nickname', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u-1',
        'nickname': '陈小匠',
        'email': 'chen@example.com',
        'phone': '13800001111',
      });
      expect(u.id, 'u-1');
      expect(u.name, '陈小匠');
    });

    test('nickname 带空白 → trim 后使用', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u-2',
        'nickname': '  陈小匠  ',
      });
      expect(u.name, '陈小匠');
    });

    test('nickname 空串 → 退到 email 本地部分', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u-3',
        'nickname': '',
        'email': 'lin@example.com',
      });
      expect(u.name, 'lin');
    });

    test('nickname 全空白 → trim 后空 → 退到 email 本地部分', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u-4',
        'nickname': '   ',
        'email': 'wang@example.com',
      });
      expect(u.name, 'wang');
    });

    test('nickname 缺失(null)→ 退到 email 本地部分', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u-5',
        'email': 'zhao@example.com',
      });
      expect(u.name, 'zhao');
    });

    test('email 无 @ → 不当邮箱用,退到 phone', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u-6',
        'email': 'not-an-email',
        'phone': '13800002222',
      });
      expect(u.name, '用户2222');
    });

    test('无 nickname / 无 email → 用 phone 后 4 位「用户XXXX」', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u-7',
        'phone': '13800003333',
      });
      expect(u.name, '用户3333');
    });

    test('phone 恰 4 位 → 用全部 4 位', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u-8',
        'phone': '4444',
      });
      expect(u.name, '用户4444');
    });

    test('phone < 4 位 → 退到 id', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u-9',
        'phone': '123',
      });
      expect(u.name, 'u-9');
    });

    test('phone 缺失 → 退到 id', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u-10',
        // 无 nickname / email / phone
      });
      expect(u.name, 'u-10');
    });

    test('全部都缺(只有 id)→ name = id', () {
      final u = userFromMeJson(const <String, dynamic>{'id': 'only-id'});
      expect(u.id, 'only-id');
      expect(u.name, 'only-id');
    });

    test('id 是 int → toString 成串', () {
      final u = userFromMeJson(const <String, dynamic>{'id': 42});
      expect(u.id, '42');
      expect(u.name, '42');
    });
  });

  group('userFromMeJson · avatar / bio 字段映射', () {
    test('avatar_url → avatar,bio → bio', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u',
        'nickname': 'n',
        'avatar_url': 'https://cdn/a.png',
        'bio': '做工具的',
      });
      expect(u.avatar, 'https://cdn/a.png');
      expect(u.bio, '做工具的');
    });

    test('avatar_url / bio 缺失 → null', () {
      final u = userFromMeJson(const <String, dynamic>{'id': 'u', 'nickname': 'n'});
      expect(u.avatar, isNull);
      expect(u.bio, isNull);
    });

    test('avatar_url / bio 显式 null → null', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u',
        'nickname': 'n',
        'avatar_url': null,
        'bio': null,
      });
      expect(u.avatar, isNull);
      expect(u.bio, isNull);
    });
  });

  group('userFromMeJson · 返回 KkUser 实例', () {
    test('返回的 KkUser 与手构 KkUser 等价(== / hashCode)', () {
      final u = userFromMeJson(const <String, dynamic>{
        'id': 'u',
        'nickname': 'n',
        'avatar_url': 'a',
        'bio': 'b',
      });
      expect(
        u,
        const KkUser(id: 'u', name: 'n', avatar: 'a', bio: 'b'),
      );
      expect(
        u.hashCode,
        const KkUser(id: 'u', name: 'n', avatar: 'a', bio: 'b').hashCode,
      );
    });
  });

  group('loginResultFromJson · 完整 payload', () {
    test('所有字段齐全 → 正确拆分', () {
      final r = loginResultFromJson(const <String, dynamic>{
        'access_token': 'jwt-access-123',
        'refresh_token': 'jwt-refresh-456',
        'is_new_user': true,
        'user': {
          'id': 'u-1',
          'nickname': '陈小匠',
          'avatar_url': 'https://cdn/a.png',
          'bio': '做工具的',
        },
      });

      expect(r.accessToken, 'jwt-access-123');
      expect(r.refreshToken, 'jwt-refresh-456');
      expect(r.isNewUser, isTrue);
      expect(r.user.id, 'u-1');
      expect(r.user.name, '陈小匠');
      expect(r.user.avatar, 'https://cdn/a.png');
      expect(r.user.bio, '做工具的');
    });

    test('is_new_user=false → false', () {
      final r = loginResultFromJson(const <String, dynamic>{
        'access_token': 'a',
        'refresh_token': 'r',
        'is_new_user': false,
        'user': {'id': 'u'},
      });
      expect(r.isNewUser, isFalse);
    });

    test('is_new_user 缺失 → false(默认)', () {
      final r = loginResultFromJson(const <String, dynamic>{
        'access_token': 'a',
        'refresh_token': 'r',
        'user': {'id': 'u'},
      });
      expect(r.isNewUser, isFalse);
    });

    test('is_new_user 是字符串 "true" → false(严格 === true)', () {
      // 实现是 j['is_new_user'] == true,字符串 "true" != true。
      final r = loginResultFromJson(const <String, dynamic>{
        'access_token': 'a',
        'refresh_token': 'r',
        'is_new_user': 'true',
        'user': {'id': 'u'},
      });
      expect(r.isNewUser, isFalse);
    });

    test('is_new_user 是 1(int)→ false(严格 === true)', () {
      final r = loginResultFromJson(const <String, dynamic>{
        'access_token': 'a',
        'refresh_token': 'r',
        'is_new_user': 1,
        'user': {'id': 'u'},
      });
      expect(r.isNewUser, isFalse);
    });
  });

  group('loginResultFromJson · 缺失字段兜底', () {
    test('access_token / refresh_token 缺失 → 空串', () {
      final r = loginResultFromJson(const <String, dynamic>{
        'user': {'id': 'u'},
      });
      expect(r.accessToken, '');
      expect(r.refreshToken, '');
    });

    test('access_token / refresh_token 为 null → 空串', () {
      final r = loginResultFromJson(const <String, dynamic>{
        'access_token': null,
        'refresh_token': null,
        'user': {'id': 'u'},
      });
      expect(r.accessToken, '');
      expect(r.refreshToken, '');
    });

    test('access_token 是 int → toString', () {
      final r = loginResultFromJson(const <String, dynamic>{
        'access_token': 12345,
        'refresh_token': 67890,
        'user': {'id': 'u'},
      });
      expect(r.accessToken, '12345');
      expect(r.refreshToken, '67890');
    });

    test('user 字段缺失 → user 用空 map 解析(id="" → name="")', () {
      final r = loginResultFromJson(const <String, dynamic>{
        'access_token': 'a',
        'refresh_token': 'r',
      });
      expect(r.user.id, '');
      expect(r.user.name, '');
    });

    test('user 字段为 null → 同上', () {
      final r = loginResultFromJson(const <String, dynamic>{
        'access_token': 'a',
        'refresh_token': 'r',
        'user': null,
      });
      expect(r.user.id, '');
      expect(r.user.name, '');
    });

    test('user 字段是非 Map 类型 → 当空 map 处理(不抛)', () {
      final r = loginResultFromJson(const <String, dynamic>{
        'access_token': 'a',
        'refresh_token': 'r',
        'user': 'oops',
      });
      expect(r.user.id, '');
      expect(r.user.name, '');
    });
  });

  group('loginResultFromJson · LoginResult 不变性', () {
    test('两次解析同一 JSON → 相等(因 KkUser 是 freezed 不可变)', () {
      const j = <String, dynamic>{
        'access_token': 'a',
        'refresh_token': 'r',
        'is_new_user': true,
        'user': {'id': 'u', 'nickname': 'n'},
      };
      final r1 = loginResultFromJson(j);
      final r2 = loginResultFromJson(j);
      // LoginResult 不是 freezed,但内部 user 是。比较字段:
      expect(r1.accessToken, r2.accessToken);
      expect(r1.refreshToken, r2.refreshToken);
      expect(r1.isNewUser, r2.isNewUser);
      expect(r1.user, r2.user);
    });
  });
}
