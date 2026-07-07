// 这个文件是干什么的：管当前登录态——是否已登录、当前用户、发码/登录/登出动作。
// 它对应产品里的什么功能：登录页驱动它；「我的」页据它显示真实昵称或「点击登录」。
// 如果它出错了：登录后 UI 不刷新，或登出后仍显示旧身份。
//
// 令牌本身存在 tokenStore（无依赖、拦截器直接读）；这里只管 UI 关心的用户对象与状态。
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/prefs.dart';
import '../data/api/auth_api.dart';
import '../data/token_store.dart';
import '../domain/models/models.dart';

/// 登录态数据。currentUser 非空 = 已登录（真后端账号）。
@immutable
class AuthState {
  /// 当前登录用户（真后端账号）；null = 未登录（游客）。
  final KkUser? currentUser;

  /// 本次登录是否为新注册（前端据此可进兴趣采集 onboarding，MVP 暂只提示）。
  final bool isNewUser;

  const AuthState({this.currentUser, this.isNewUser = false});

  bool get isLoggedIn => currentUser != null;

  AuthState copyWith({KkUser? currentUser, bool? isNewUser, bool clearUser = false}) =>
      AuthState(
        currentUser: clearUser ? null : (currentUser ?? this.currentUser),
        isNewUser: isNewUser ?? this.isNewUser,
      );
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => _restore();

  /// 启动恢复登录态：tokenStore 已从 prefs 载回令牌；再读持久化的用户 JSON。
  /// 有令牌但无用户 JSON（异常残留）→ 清令牌保持一致，回游客态。
  AuthState _restore() {
    final store = ref.read(tokenStoreProvider);
    if (!store.isLoggedIn) return const AuthState();
    final raw = ref.read(prefsProvider).getString(PrefsKeys.authUser);
    if (raw == null || raw.isEmpty) {
      store.clear();
      return const AuthState();
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AuthState(
        currentUser: KkUser(
          id: j['id'].toString(),
          name: (j['name'] ?? j['id']).toString(),
          avatar: j['avatar'] as String?,
          bio: j['bio'] as String?,
        ),
      );
    } catch (_) {
      store.clear();
      return const AuthState();
    }
  }

  /// 发送验证码。异常（频控 429 等）原样抛给 UI 提示。
  Future<void> sendCode(String identifier) =>
      ref.read(authApiProvider).sendCode(identifier);

  /// 验证码登录：成功后把令牌写进 tokenStore、当前用户写进 state + 持久化。
  /// 失败（验证码错等）抛异常给 UI。
  Future<void> login(String identifier, String code) async {
    // 带上游客 ID：后端把登录前游客的「想看怎么做」记录归并进账号（主信号不丢，红线）。
    final result = await ref.read(authApiProvider).login(
          identifier,
          code,
          anonClientId: ref.read(anonClientIdProvider),
        );
    ref.read(tokenStoreProvider).set(
          access: result.accessToken,
          refresh: result.refreshToken,
        );
    _persistUser(result.user);
    state = AuthState(currentUser: result.user, isNewUser: result.isNewUser);
  }

  /// 登出：清令牌 + 清持久化用户 + 清 state。回到游客态。
  void logout() {
    ref.read(tokenStoreProvider).clear();
    ref.read(prefsProvider).remove(PrefsKeys.authUser);
    state = const AuthState();
  }

  /// 把当前用户的最小信息持久化（刷新页面后恢复 UI 显示用）。
  void _persistUser(KkUser user) {
    ref.read(prefsProvider).setString(
          PrefsKeys.authUser,
          jsonEncode({
            'id': user.id,
            'name': user.name,
            'avatar': user.avatar,
            'bio': user.bio,
          }),
        );
  }
}

/// 全局登录态。用法：ref.watch(authProvider).isLoggedIn
final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
