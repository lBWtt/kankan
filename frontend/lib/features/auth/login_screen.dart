// 这个文件是干什么的：登录/注册页——输手机号或邮箱、发验证码、验证码登录（未注册自动注册）。
// 它对应产品里的什么功能：登录入口（「我的」页点头像/「点击登录」进入）。
// 如果它出错了：登录不上，所有需要账号的写操作（收藏/发布/订阅）都用不了。
//
// 视觉铁律：coral 只给 take，本页主按钮是登录（非 take）→ 用 teal；无 emoji；零旁白；触控≥44pt。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/network/app_exception.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../providers/auth_provider.dart';
import '../../router/routes.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifierCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _sending = false; // 发码中
  bool _loggingIn = false; // 登录中
  int _countdown = 0; // 发码倒计时（秒）
  Timer? _timer;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _identifierCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _countdown--);
      if (_countdown <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    final id = _identifierCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _error = '请先输入手机号或邮箱');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).sendCode(id);
      if (!mounted) return;
      _startCountdown();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '发送失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _login() async {
    final id = _identifierCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _error = '请输入手机号或邮箱');
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(id, code);
      if (!mounted) return;
      final isNew = ref.read(authProvider).isNewUser;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(isNew ? '欢迎加入，账号已创建' : '登录成功'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: KkColors.t1,
          ),
        );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(KkRoutes.me);
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '登录失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KkColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          children: [
            const SizedBox(height: KkSpacing.sm),
            const Row(children: [KkBackButton()]),
            const SizedBox(height: KkSpacing.xl),
            const Text('登录 / 注册', style: KkType.h1),
            const SizedBox(height: KkSpacing.xs),
            Text(
              '手机号或邮箱验证码登录，未注册自动创建账号',
              style: KkType.bodySm.copyWith(color: KkColors.t3),
            ),
            const SizedBox(height: KkSpacing.xl),

            // 手机号 / 邮箱
            _fieldLabel('手机号或邮箱'),
            const SizedBox(height: KkSpacing.sm),
            _inputBox(
              child: TextField(
                controller: _identifierCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('输入手机号或邮箱'),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
            const SizedBox(height: KkSpacing.lg),

            // 验证码 + 发送按钮
            _fieldLabel('验证码'),
            const SizedBox(height: KkSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _inputBox(
                    child: TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: _inputDecoration('输入验证码'),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: KkSpacing.sm),
                _sendCodeButton(),
              ],
            ),

            // dev 提示
            if (AppConfig.apiBaseUrl.contains('127.0.0.1') ||
                AppConfig.apiBaseUrl.contains('localhost')) ...[
              const SizedBox(height: KkSpacing.sm),
              Text(
                '开发环境万能验证码：888888',
                style: KkType.bodySm.copyWith(color: KkColors.t3),
              ),
            ],

            // 错误提示
            if (_error != null) ...[
              const SizedBox(height: KkSpacing.md),
              Text(
                _error!,
                style: KkType.bodySm.copyWith(color: KkColors.like),
              ),
            ],

            const SizedBox(height: KkSpacing.xl),
            _loginButton(),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) =>
      Text(text, style: KkType.bodySm.copyWith(color: KkColors.t2));

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: KkType.body.copyWith(color: KkColors.t3),
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      );

  Widget _inputBox({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.md,
        ),
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: KkColors.bd),
        ),
        child: child,
      );

  Widget _sendCodeButton() {
    final disabled = _sending || _countdown > 0;
    final label = _countdown > 0
        ? '${_countdown}s'
        : (_sending ? '发送中' : '发送验证码');
    return Tappable(
      onTap: disabled ? null : _sendCode,
      disabled: disabled,
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: disabled ? KkColors.bgSubtle : KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: disabled ? KkColors.bd : KkColors.teal),
        ),
        child: Text(
          label,
          style: KkType.bodySm.copyWith(
            color: disabled ? KkColors.t3 : KkColors.teal,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _loginButton() {
    return Tappable(
      onTap: _loggingIn ? null : _login,
      disabled: _loggingIn,
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _loggingIn ? KkColors.t3 : KkColors.teal,
          borderRadius: BorderRadius.circular(KkRadius.md),
        ),
        child: _loggingIn
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                '登录',
                style: KkType.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
