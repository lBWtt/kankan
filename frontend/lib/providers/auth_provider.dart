// 这个文件是干什么的：管当前登录态——是否已登录、当前用户、发码/登录/登出动作。
// 它对应产品里的什么功能：登录页驱动它；「我的」页据它显示真实昵称或「点击登录」。
// 如果它出错了：登录后 UI 不刷新，或登出后仍显示旧身份。
//
// 令牌本身存在 tokenStore（无依赖、拦截器直接读）；这里只管 UI 关心的用户对象与状态。
import 'dart:async';
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

  /// 当前账号是否为管理员（后端 is_admin）。审核悬浮球/入口据此显示——
  /// 未登录或普通用户恒为 false，只有以管理员账号登录才为 true。
  final bool isAdmin;

  const AuthState(
      {this.currentUser, this.isNewUser = false, this.isAdmin = false});

  bool get isLoggedIn => currentUser != null;

  AuthState copyWith(
          {KkUser? currentUser,
          bool? isNewUser,
          bool? isAdmin,
          bool clearUser = false}) =>
      AuthState(
        currentUser: clearUser ? null : (currentUser ?? this.currentUser),
        isNewUser: isNewUser ?? this.isNewUser,
        isAdmin: clearUser ? false : (isAdmin ?? this.isAdmin),
      );
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final restored = _restore();
    // 会话死亡（refresh 被后端拒绝）→ dio 已清令牌，这里把 UI 登录态与持久化用户一并清掉，
    // 否则界面仍显示已登录、但所有写操作静默 401。钩子经 microtask 触发，不在 build 期执行。
    ref.read(tokenStoreProvider).onSessionExpired = () {
      ref.read(prefsProvider).remove(PrefsKeys.authUser);
      state = const AuthState();
    };
    return restored;
  }

  /// 启动恢复登录态：tokenStore 已从 prefs 载回令牌；再读持久化的用户 JSON。
  /// 有令牌但无用户 JSON（异常残留）→ 清令牌保持一致，回游客态。
  AuthState _restore() {
    final store = ref.read(tokenStoreProvider);
    if (!store.isLoggedIn) return const AuthState();
    final raw = ref.read(prefsProvider).getString(PrefsKeys.authUser);
    if (raw == null || raw.isEmpty) {
      unawaited(store.clear());
      return const AuthState();
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AuthState(
        currentUser: KkUser(
          id: j['id'].toString(),
          name: (j['name'] ?? j['id']).toString(),
          handle: j['handle'] as String?,
          avatar: j['avatar'] as String?,
          bio: j['bio'] as String?,
          school: j['school'] as String?,
          age: (j['age'] as num?)?.toInt(),
        ),
        isAdmin: j['is_admin'] == true,
      );
    } catch (_) {
      unawaited(store.clear());
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
    await ref.read(tokenStoreProvider).set(
          access: result.accessToken,
          refresh: result.refreshToken,
        );
    _persistUser(result.user, result.isAdmin);
    state = AuthState(
      currentUser: result.user,
      isNewUser: result.isNewUser,
      isAdmin: result.isAdmin,
    );
  }

  /// 编辑资料保存后，同步更新当前登录用户的显示信息（名字/简介）并持久化。
  /// 修 bug：原来编辑资料只改了 mock 'me'，没动 authProvider，me 页读的是
  /// auth.currentUser.name，所以保存后名字不刷新（要退出重登才变）。
  void updateCurrentUser({
    required String name,
    String? handle,
    String? avatar,
    String? bio,
    String? school,
    int? age,
  }) {
    final cur = state.currentUser;
    if (cur == null) return;
    final updated = cur.copyWith(
      name: name,
      handle: handle ?? cur.handle,
      avatar: avatar ?? cur.avatar,
      bio: bio,
      school: school,
      age: age,
    );
    _persistUser(updated, state.isAdmin);
    state = state.copyWith(currentUser: updated);
  }

  /// 登出：清令牌 + 清持久化用户 + 清 state。回到游客态。
  Future<void> logout() async {
    await ref.read(tokenStoreProvider).clear();
    await ref.read(prefsProvider).remove(PrefsKeys.authUser);
    state = const AuthState();
  }

  /// 注销账号：后端成功匿名化并撤销全部设备会话后，再清本机凭证。
  Future<void> deleteAccount() async {
    await ref.read(authApiProvider).deleteAccount();
    await ref.read(tokenStoreProvider).clear();
    await ref.read(prefsProvider).remove(PrefsKeys.authUser);
    state = const AuthState();
  }

  /// 把当前用户的最小信息持久化（刷新页面后恢复 UI 显示用）。
  void _persistUser(KkUser user, bool isAdmin) {
    ref.read(prefsProvider).setString(
          PrefsKeys.authUser,
          jsonEncode({
            'id': user.id,
            'name': user.name,
            'handle': user.handle,
            'avatar': user.avatar,
            'bio': user.bio,
            'school': user.school,
            'age': user.age,
            'is_admin': isAdmin,
          }),
        );
  }
}

/// 全局登录态。用法：ref.watch(authProvider).isLoggedIn
final authProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
