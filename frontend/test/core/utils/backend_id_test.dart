// 后端 id 识别单测。
//
// 覆盖 lib/core/utils/backend_id.dart 的 looksLikeBackendId:
//   `id.contains('-') && id.length >= 32`
//
// 后端真项目用 UUID v4(8-4-4-4-12 = 36 字符,含 4 个 '-'),
// mock 项目用 'p1' / 'p_aiimg_1' 这类短串。本 helper 区分二者,
// 决定写接口(收藏/删除/订阅/关注)是否真发后端请求。
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/core/utils/backend_id.dart';

void main() {
  group('looksLikeBackendId', () {
    group('真后端 UUID v4 → true', () {
      test('标准 UUID v4(36 字符,含 4 个 -)', () {
        expect(
          looksLikeBackendId('550e8400-e29b-41d4-a716-446655440000'),
          isTrue,
        );
      });

      test('另一个 UUID v4', () {
        expect(
          looksLikeBackendId('12345678-1234-1234-1234-123456789012'),
          isTrue,
        );
      });

      test('全 0 UUID(虽非法但仍满足形似 UUID)', () {
        expect(
          looksLikeBackendId('00000000-0000-0000-0000-000000000000'),
          isTrue,
        );
      });

      test('32 字符且含 - 也算真后端(边界下限)', () {
        // 长度恰 32,含 '-',满足两个条件。
        // '0123456789abcdef0123456789-abc' 是 16+10+1+3 = 30... 重数:
        // '0123456789abcdef' = 16, '0123456789' = 10, '-' = 1, 'abc' = 3 → 30。
        // 改成 32 长度:16 + 1 + 15 = 32。
        final id = '0123456789abcdef-0123456789abcde';
        expect(id.length, 32);
        expect(id.contains('-'), isTrue);
        expect(looksLikeBackendId(id), isTrue);
      });
    });

    group('mock 短 id → false', () {
      test('"me" → false(短且无 -)', () {
        expect(looksLikeBackendId('me'), isFalse);
      });

      test('"p1" → false', () {
        expect(looksLikeBackendId('p1'), isFalse);
      });

      test('"p_aiimg_1" → false(含 _ 但无 -,长度 9)', () {
        expect(looksLikeBackendId('p_aiimg_1'), isFalse);
      });

      test('"chen" / "wang" / "liu" → false', () {
        expect(looksLikeBackendId('chen'), isFalse);
        expect(looksLikeBackendId('wang'), isFalse);
        expect(looksLikeBackendId('liu'), isFalse);
      });

      test('"post_1" → false', () {
        expect(looksLikeBackendId('post_1'), isFalse);
      });
    });

    group('数字串 / 纯短串 → false', () {
      test('纯数字串无 - → false', () {
        expect(looksLikeBackendId('1234567890'), isFalse);
      });

      test('长纯数字串无 - → false', () {
        expect(
          looksLikeBackendId('1234567890123456789012345678901234567890'),
          isFalse,
        );
      });
    });

    group('边界:有 - 但长度不足 / 长度够但无 -', () {
      test('有 - 但长度 < 32 → false', () {
        expect(looksLikeBackendId('a-b'), isFalse);
        expect(looksLikeBackendId('12345678-1234'), isFalse);
      });

      test('长度 ≥ 32 但无 - → false', () {
        final id = '0123456789abcdef0123456789abcdef'; // 32 字符无 -
        expect(id.length, 32);
        expect(id.contains('-'), isFalse);
        expect(looksLikeBackendId(id), isFalse);
      });

      test('31 字符且含 - → false(差 1 位)', () {
        final id = '0123456789abcdef-0123456789abcd'; // 16+1+14 = 31
        expect(id.length, 31);
        expect(id.contains('-'), isTrue);
        expect(looksLikeBackendId(id), isFalse);
      });
    });

    group('空 / 极端输入', () {
      test('空串 → false(无 - 且长度 0)', () {
        expect(looksLikeBackendId(''), isFalse);
      });

      test('单字符 "-" → false(长度 1)', () {
        expect(looksLikeBackendId('-'), isFalse);
      });

      test('32 个连字符 → true(长度 32,含 -)', () {
        final id = '-' * 32;
        expect(looksLikeBackendId(id), isTrue);
      });
    });
  });
}
