// 这个文件是干什么的：一个令牌保管盒，存当前登录的 access/refresh token（并持久化到本地）。
// 它对应产品里的什么功能：登录后所有需要身份的接口靠它带 Bearer；令牌过期靠它换新；
//   web 刷新页面时从 SharedPreferences 恢复，不掉登录。
// 如果它出错了：带不上身份 → 写操作全 401；或旧令牌清不掉 → 换号后仍用旧身份；
//   或刷新页面掉登录（持久化没生效）。
//
// 为什么单独一个类而不放进 auth_provider：打破 provider 循环。
//   dio(拦截器要读令牌) → 依赖 tokenStore；authApi → 依赖 dio；authProvider → 依赖 authApi。
//   若拦截器直接读 authProvider 就成环。tokenStore 只依赖 prefs，谁都能读写，环断开。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';

/// 令牌保管盒（内存 + 持久化）。内存字段给 dio 同步读；set/clear 同步落 prefs。
class TokenStore {
  final SharedPreferences _prefs;
  String? accessToken;
  String? refreshToken;

  TokenStore(this._prefs) {
    // 启动即从持久化恢复（web 刷新/重开不掉登录）。
    accessToken = _prefs.getString(PrefsKeys.accessToken);
    refreshToken = _prefs.getString(PrefsKeys.refreshToken);
  }

  bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;

  void set({required String access, required String refresh}) {
    accessToken = access;
    refreshToken = refresh;
    _prefs.setString(PrefsKeys.accessToken, access);
    _prefs.setString(PrefsKeys.refreshToken, refresh);
  }

  void clear() {
    accessToken = null;
    refreshToken = null;
    _prefs.remove(PrefsKeys.accessToken);
    _prefs.remove(PrefsKeys.refreshToken);
  }
}

/// 全局唯一令牌盒。用法：ref.read(tokenStoreProvider).accessToken
final tokenStoreProvider =
    Provider<TokenStore>((ref) => TokenStore(ref.watch(prefsProvider)));
