// 这个文件是干什么的：一个令牌保管盒，存当前登录的 access/refresh token（并持久化到本地）。
// 它对应产品里的什么功能：登录后所有需要身份的接口靠它带 Bearer；令牌过期靠它换新；
//   web 刷新页面时从 SharedPreferences 恢复，不掉登录。
// 如果它出错了：带不上身份 → 写操作全 401；或旧令牌清不掉 → 换号后仍用旧身份；
//   或刷新页面掉登录（持久化没生效）。
//
// 为什么单独一个类而不放进 auth_provider：打破 provider 循环。
//   dio(拦截器要读令牌) → 依赖 tokenStore；authApi → 依赖 dio；authProvider → 依赖 authApi。
//   若拦截器直接读 authProvider 就成环。tokenStore 只依赖 prefs，谁都能读写，环断开。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';

/// 令牌保管盒（内存 + 持久化）。内存字段给 dio 同步读；set/clear 同步落 prefs。
class TokenStore {
  final SharedPreferences _prefs;
  final FlutterSecureStorage? _secureStorage;
  String? accessToken;
  String? refreshToken;

  /// 会话真正死亡（refresh 被后端 401 拒绝）时的通知钩子——auth_provider 注册它
  /// 把 UI 登录态一并清掉，否则界面还显示已登录、但所有写操作静默 401。
  /// 只由 [expireSession] 触发；普通 [clear]（登出/启动清理）不触发，避免 build 期重入。
  void Function()? onSessionExpired;

  TokenStore._(this._prefs, this._secureStorage);

  /// Provider 的同步兜底只用于 widget/unit test；真实 App 在 main 中异步创建后 override。
  TokenStore.fromPreferences(this._prefs) : _secureStorage = null {
    accessToken = _prefs.getString(PrefsKeys.accessToken);
    refreshToken = _prefs.getString(PrefsKeys.refreshToken);
  }

  /// 真 App 的令牌盒：Web 保持 localStorage；移动端使用系统安全存储。
  /// 首次升级会把旧 SharedPreferences 令牌无损迁移，成功写入后才删旧明文。
  static Future<TokenStore> create(SharedPreferences prefs) async {
    if (kIsWeb) return TokenStore.fromPreferences(prefs);

    const secure = FlutterSecureStorage();
    final store = TokenStore._(prefs, secure);
    var access = await secure.read(key: PrefsKeys.accessToken);
    var refresh = await secure.read(key: PrefsKeys.refreshToken);
    final legacyAccess = prefs.getString(PrefsKeys.accessToken);
    final legacyRefresh = prefs.getString(PrefsKeys.refreshToken);
    if ((access == null || access.isEmpty) &&
        legacyAccess != null &&
        legacyAccess.isNotEmpty) {
      await secure.write(key: PrefsKeys.accessToken, value: legacyAccess);
      access = legacyAccess;
    }
    if ((refresh == null || refresh.isEmpty) &&
        legacyRefresh != null &&
        legacyRefresh.isNotEmpty) {
      await secure.write(key: PrefsKeys.refreshToken, value: legacyRefresh);
      refresh = legacyRefresh;
    }
    store.accessToken = access;
    store.refreshToken = refresh;
    if (access != null &&
        access.isNotEmpty &&
        refresh != null &&
        refresh.isNotEmpty) {
      await prefs.remove(PrefsKeys.accessToken);
      await prefs.remove(PrefsKeys.refreshToken);
    }
    return store;
  }

  bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;

  Future<void> set({required String access, required String refresh}) async {
    if (_secureStorage != null) {
      await _secureStorage.write(key: PrefsKeys.refreshToken, value: refresh);
      await _secureStorage.write(key: PrefsKeys.accessToken, value: access);
      await _prefs.remove(PrefsKeys.accessToken);
      await _prefs.remove(PrefsKeys.refreshToken);
    } else {
      await _prefs.setString(PrefsKeys.accessToken, access);
      await _prefs.setString(PrefsKeys.refreshToken, refresh);
    }
    accessToken = access;
    refreshToken = refresh;
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    if (_secureStorage != null) {
      await _secureStorage.delete(key: PrefsKeys.accessToken);
      await _secureStorage.delete(key: PrefsKeys.refreshToken);
    }
    await _prefs.remove(PrefsKeys.accessToken);
    await _prefs.remove(PrefsKeys.refreshToken);
  }

  /// 会话死亡专用：清令牌并通知 UI 层（dio 拦截器在 refresh 被 401 拒绝时调用）。
  void expireSession() {
    unawaited(clear());
    final cb = onSessionExpired;
    if (cb != null) {
      // 从 dio 错误回调触发，schedule 到微任务避免任何「通知期间改 provider state」的时序坑。
      Future.microtask(cb);
    }
  }
}

/// 全局唯一令牌盒。用法：ref.read(tokenStoreProvider).accessToken
final tokenStoreProvider = Provider<TokenStore>(
    (ref) => TokenStore.fromPreferences(ref.watch(prefsProvider)));
