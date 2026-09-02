import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/app_exception.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/tappable.dart';
import '../feedback/feedback_sheet.dart';

/// 远程加载失败统一组件 — B3。
///
/// 替换散落在 kankan_screen(_RemoteError)/ ranking_screen(_RankingError)/
/// implementation_clue_screen(_errorView) 三处各自手抄的 error 视觉。
///
/// 视觉(零旁白):Icon(cloud_off_outlined) + 一句事实(默认「加载失败」,
/// 调用方可定制如「榜单加载失败」)+ 重试按钮(mint 底 + teal 浅边 + teal 文字,
/// 非 coral;coral 只给 take)。
///
/// 重试按钮点击后显 loading 态(小 spinner 替换文字 + 禁用),onRetry 完成清。
/// onRetry 是 Future:调用方传 `() async { ref.invalidate(x); }` 即可
/// (同步 invalidate 包 async 无害);RemoteError 在 await 期间显 loading。
///
/// 若 onRetry 触发 provider 重建导致本组件卸载(切到 loading/data 态),
/// setState 由 mounted 守卫,不报错。
class RemoteError extends StatefulWidget {
  /// 重试回调。返回 Future 以驱动 loading 态。
  final Future<void> Function() onRetry;

  /// 错误文案(默认「加载失败」)。零旁白:陈述事实,不写「哎呀出错了」。
  final String? message;

  /// 真实错误对象(可选,一般传 provider 的 state.error)。传了就在标题下补一行
  /// **去泛化的真实原因**:分清「网络不可达 / HTTP 状态码 / 业务码 / 其它」,
  /// 排查不用再猜(踩过的坑:泛化文案「连不上服务器」掩盖了前端 provider 出错)。
  final Object? error;
  final String? feedbackPage;
  final String? feedbackErrorCode;

  const RemoteError({
    super.key,
    required this.onRetry,
    this.message,
    this.error,
    this.feedbackPage,
    this.feedbackErrorCode,
  });

  /// 把异常收敛成一行「人能读 + 能定位」的真实原因;null=没有可显示的细节。
  static String? reasonOf(Object? error) {
    if (error == null) return null;
    if (error is AppException) {
      if (error.code == 'NETWORK_ERROR') return '网络连不上 · NETWORK_ERROR';
      if (error.statusCode != null)
        return 'HTTP ${error.statusCode} · ${error.code}';
      return error.code == 'UNKNOWN' ? '请求失败 · UNKNOWN' : error.message;
    }
    final s = error.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  @override
  State<RemoteError> createState() => _RemoteErrorState();
}

class _RemoteErrorState extends State<RemoteError> {
  bool _loading = false;
  bool _feedbacking = false;

  Future<void> _handleRetry() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onRetry();
    } finally {
      // onRetry 若触发 provider 重建卸载本组件,mounted=false 跳过,不报错。
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleFeedback() async {
    if (_feedbacking) return;
    setState(() => _feedbacking = true);
    final code = widget.feedbackErrorCode ?? _codeOf(widget.error);
    final ok = await showFeedbackSheet(
      context,
      sourcePage: widget.feedbackPage ?? _currentLocation(context),
      errorCode: code,
    );
    if (!mounted) return;
    setState(() => _feedbacking = false);
    if (ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content:
              Text('\u53cd\u9988\u5df2\u63d0\u4ea4\uff0c\u8c22\u8c22\uff01'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String? _currentLocation(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.toString();
    } catch (_) {
      return null;
    }
  }

  String? _codeOf(Object? error) {
    if (error is AppException) {
      if (error.statusCode != null) {
        return 'HTTP_${error.statusCode}_${error.code}';
      }
      return error.code;
    }
    return error?.runtimeType.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KkSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: KkColors.t4),
            const SizedBox(height: KkSpacing.md),
            Text(
              widget.message ?? '加载失败',
              style: KkType.body.copyWith(color: KkColors.t3),
              textAlign: TextAlign.center,
            ),
            // 去泛化:标题下补一行真实原因(网络/HTTP码/业务码),没有 error 则不显示。
            if (RemoteError.reasonOf(widget.error) != null) ...[
              const SizedBox(height: KkSpacing.xs),
              Text(
                RemoteError.reasonOf(widget.error)!,
                style: KkType.bodySm.copyWith(color: KkColors.t4),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: KkSpacing.lg),
            Tappable(
              // loading 时禁用(防重复点 + 视觉降权)。
              disabled: _loading,
              onTap: _handleRetry,
              borderRadius: BorderRadius.circular(KkRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KkSpacing.xl,
                  vertical: KkSpacing.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: KkColors.mint,
                  borderRadius: BorderRadius.circular(KkRadius.pill),
                  border: Border.all(color: KkColors.teal.withAlpha(77)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KkColors.teal,
                        ),
                      )
                    : Text(
                        '重试',
                        style: TextStyle(
                          color: KkColors.teal,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          fontFamily: 'NotoSerifSC',
                        ),
                      ),
              ),
            ),
            const SizedBox(height: KkSpacing.sm),
            TextButton.icon(
              onPressed: _feedbacking ? null : _handleFeedback,
              icon: const Icon(Icons.bug_report_outlined, size: 18),
              label: const Text('\u53cd\u9988 Bug'),
            ),
          ],
        ),
      ),
    );
  }
}
