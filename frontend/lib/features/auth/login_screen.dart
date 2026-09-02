// 这个文件是干什么的：登录/注册页——输手机号或邮箱、发验证码、验证码登录（未注册自动注册）。
// 它对应产品里的什么功能：登录入口（「我的」页点头像/「点击登录」进入）。
// 如果它出错了：登录不上，所有需要账号的写操作（收藏/发布/订阅）都用不了。
//
// 视觉铁律：coral 只给 take，本页主按钮是登录（非 take）→ 用 teal；无 emoji；零旁白；触控≥44pt。
import 'dart:async';

import 'package:flutter/gestures.dart';
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
  bool _agreed = false; // 已勾选同意《用户协议》《隐私政策》（合规：注册前须同意）
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

  /// 仅手机号：邮箱验证码后端只写日志不真发（未接邮件服务商），暂不放行邮箱入口。
  /// 简单校验中国大陆 11 位手机号；带 @ 明确提示暂不支持邮箱。
  static final _phoneRe = RegExp(r'^1\d{10}$');

  static const _devCodePhones = <String, String>{
    '1': '17700000001',
    '2': '17700000002',
    '3': '17700000003',
    '4': '17700000004',
    '5': '17700000005',
    '6': '17700000006',
    '777': '17700000777',
    '888': '18800000888',
  };

  bool get _isLocalApi =>
      AppConfig.apiBaseUrl.contains('127.0.0.1') ||
      AppConfig.apiBaseUrl.contains('localhost') ||
      AppConfig.apiBaseUrl.contains('10.0.2.2');

  String? _devPhoneForCode(String code) =>
      _isLocalApi ? _devCodePhones[code] : null;

  String? _phoneError(String id) {
    if (id.isEmpty) return '请输入手机号';
    if (id.contains('@')) return '暂仅支持手机号登录';
    if (!_phoneRe.hasMatch(id)) return '请输入 11 位手机号';
    return null;
  }

  /// 合规闸：注册/登录（含发码）前必须已勾选同意两份协议。未勾选给出明确提示。
  bool _ensureAgreed() {
    if (_agreed) return true;
    setState(() => _error = '请先阅读并勾选同意《用户协议》和《隐私政策》');
    return false;
  }

  Future<void> _sendCode() async {
    final id = _identifierCtrl.text.trim();
    final err = _phoneError(id);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (!_ensureAgreed()) return;
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
    if (!_ensureAgreed()) return;
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }
    final devPhone = _devPhoneForCode(code);
    final id = devPhone ?? _identifierCtrl.text.trim();
    final err = _phoneError(id);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    // 捕获路由守卫带来的目标（?from=...）：登录成功后跳回原意图页，而非停在「我」页。
    final from = GoRouterState.of(context).uri.queryParameters['from'];
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
      // 登录是一次身份切换，不应回到设置等“入口页”而让人以为没登录。
      // 有受保护操作的原始目标时回到目标；其余一律进入“我的”。
      context.go(from != null && from.isNotEmpty ? from : KkRoutes.me);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '登录失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  /// dev 一键登录：填入测试码直接走登录（_login 会用 _devCodePhones 自动补手机号）。
  Future<void> _devQuickLogin(String code) async {
    if (_loggingIn) return;
    _codeCtrl.text = code;
    await _login();
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
              '手机号验证码登录，未注册自动创建账号',
              style: KkType.bodySm.copyWith(color: KkColors.t3),
            ),
            const SizedBox(height: KkSpacing.xl),

            // 手机号（邮箱登录未接邮件服务商，暂不开放）
            _fieldLabel('手机号'),
            const SizedBox(height: KkSpacing.sm),
            _inputBox(
              child: TextField(
                controller: _identifierCtrl,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration('输入手机号'),
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

            // dev 一键登录：本地 API 下显示测试号快捷入口，点一下直接进，免输手机号/验证码。
            // 用于在一台手机上快速切换多个测试账号，模拟真实用户互动（各账号后端隔离）。
            if (_isLocalApi) ...[
              const SizedBox(height: KkSpacing.lg),
              _fieldLabel('开发快捷登录 · 点一下直接进（免输手机号）'),
              const SizedBox(height: KkSpacing.sm),
              Wrap(
                spacing: KkSpacing.sm,
                runSpacing: KkSpacing.sm,
                children: [
                  _devChip('管理员', '888'),
                  _devChip('用户一', '1'),
                  _devChip('用户二', '2'),
                  _devChip('用户三', '3'),
                  _devChip('用户四', '4'),
                  _devChip('用户五', '5'),
                  _devChip('用户六', '6'),
                ],
              ),
              const SizedBox(height: KkSpacing.xs),
              Text(
                '手动登录仍可用：验证码 888888 = 当前填的手机号万能码。',
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

            const SizedBox(height: KkSpacing.lg),
            _consentRow(),

            const SizedBox(height: KkSpacing.lg),
            _loginButton(),
          ],
        ),
      ),
    );
  }

  /// 合规勾选：注册/登录前须同意两份协议。可点方框切换，协议名可点开阅读。
  Widget _consentRow() {
    final linkStyle = KkType.bodySm.copyWith(
      color: KkColors.teal,
      fontWeight: FontWeight.w600,
    );
    final baseStyle = KkType.bodySm.copyWith(color: KkColors.t3);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tappable(
          onTap: () => setState(() {
            _agreed = !_agreed;
            if (_agreed && _error != null) _error = null;
          }),
          borderRadius: BorderRadius.circular(KkRadius.sm),
          child: Padding(
            padding: const EdgeInsets.only(right: KkSpacing.sm, top: 1),
            child: Icon(
              _agreed ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: _agreed ? KkColors.teal : KkColors.t3,
            ),
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                const TextSpan(text: '我已阅读并同意 '),
                TextSpan(
                  text: '《用户协议》',
                  style: linkStyle,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => context.push(KkRoutes.userAgreement),
                ),
                const TextSpan(text: ' 和 '),
                TextSpan(
                  text: '《隐私政策》',
                  style: linkStyle,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => context.push(KkRoutes.privacyPolicy),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) =>
      Text(text, style: KkType.bodySm.copyWith(color: KkColors.t2));

  /// 一键登录小标签：点一下用对应测试码登录（免手动输入）。
  Widget _devChip(String label, String code) {
    return Tappable(
      onTap: _loggingIn ? null : () => _devQuickLogin(code),
      disabled: _loggingIn,
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: KkColors.teal),
        ),
        child: Text(
          label,
          style: KkType.bodySm.copyWith(
            color: KkColors.teal,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

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
    final label =
        _countdown > 0 ? '${_countdown}s' : (_sending ? '发送中' : '发送验证码');
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
