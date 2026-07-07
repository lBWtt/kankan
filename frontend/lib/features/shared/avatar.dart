import 'package:flutter/material.dart';

import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';

/// 通用头像组件 — 有 avatar URL 则渲染网络图,否则用户名首字母 fallback(HANDOFF §5:无 emoji)。
///
/// 用法:
///   KkAvatar(userId: 'chen', size: 36)
///   KkAvatar(user: user, size: 44)
///
/// 登录后真账号的 avatar_url 走 Image.network(加载中/坏链自动回退首字母)。
class KkAvatar extends StatelessWidget {
  final String? userId;
  final KkUser? user;
  final double size;

  const KkAvatar({super.key, this.userId, this.user, required this.size});

  @override
  Widget build(BuildContext context) {
    final u = user;
    final name = u?.name ?? userId ?? '';
    final ch = name.isNotEmpty ? name[0].toUpperCase() : '?';

    // 用名字 hash 出稳定色相,避免所有头像同色
    final hue = (name.hashCode % 360).abs().toDouble();
    final bg = HSLColor.fromAHSL(1, hue, 0.3, 0.85).toColor();
    final fg = HSLColor.fromAHSL(1, hue, 0.5, 0.35).toColor();

    final letterFallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: Text(
        ch,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
          fontFamily: 'JetBrainsMono',
        ),
      ),
    );

    final avatarUrl = u?.avatar;
    if (avatarUrl == null || avatarUrl.isEmpty) return letterFallback;
    return ClipOval(
      child: Image.network(
        avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : letterFallback,
        errorBuilder: (_, __, ___) => letterFallback,
      ),
    );
  }
}

/// 通用 44pt 触控热区的可点击头像。
class TappableAvatar extends StatelessWidget {
  final String? userId;
  final KkUser? user;
  final double size;
  final VoidCallback? onTap;

  const TappableAvatar({
    super.key,
    this.userId,
    this.user,
    required this.size,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: KkAvatar(userId: userId, user: user, size: size),
    );
  }
}
