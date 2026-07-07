// 这个文件是干什么的：把后端 /auth/login 的返回 JSON 拆成「令牌 + 当前用户 + 是否新注册」。
// 它对应产品里的什么功能：登录成功后拿到真 JWT，并把后端用户映射成前端 KkUser。
// 如果它出错了：登录成功但拿不到令牌/用户，或用户名/头像错位。
import '../../domain/models/models.dart';

/// 登录返回的解析结果（令牌 + 用户 + 新注册标记）。
class LoginResult {
  final String accessToken;
  final String refreshToken;
  final KkUser user;
  final bool isNewUser;

  const LoginResult({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    required this.isNewUser,
  });
}

/// 后端 MeResponse → 前端 KkUser。
///   nickname 缺失时依次退到 邮箱本地部分 / 手机号尾号 / id。
///   avatar_url → avatar；bio 直传；关注/粉丝列表登录返回里没有，留空（详情端点再补）。
KkUser userFromMeJson(Map<String, dynamic> j) {
  // 兜底:user 缺失时 j 为空 map，j['id'] 为 null——不能直接 .toString()（会得到字面 "null"）。
  final id = (j['id'] ?? '').toString();
  final nickname = (j['nickname'] as String?)?.trim();
  final email = j['email'] as String?;
  final phone = j['phone'] as String?;
  String name;
  if (nickname != null && nickname.isNotEmpty) {
    name = nickname;
  } else if (email != null && email.contains('@')) {
    name = email.split('@').first;
  } else if (phone != null && phone.length >= 4) {
    name = '用户${phone.substring(phone.length - 4)}';
  } else {
    name = id;
  }
  return KkUser(
    id: id,
    name: name,
    avatar: j['avatar_url'] as String?,
    bio: j['bio'] as String?,
  );
}

/// 后端 LoginResponse → LoginResult。
LoginResult loginResultFromJson(Map<String, dynamic> j) {
  final userJson = j['user'];
  return LoginResult(
    accessToken: (j['access_token'] ?? '').toString(),
    refreshToken: (j['refresh_token'] ?? '').toString(),
    user: userFromMeJson(
      userJson is Map ? Map<String, dynamic>.from(userJson) : const {},
    ),
    isNewUser: j['is_new_user'] == true,
  );
}
