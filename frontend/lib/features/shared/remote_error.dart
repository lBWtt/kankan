import 'package:flutter/material.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/tappable.dart';

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

  const RemoteError({
    super.key,
    required this.onRetry,
    this.message,
  });

  @override
  State<RemoteError> createState() => _RemoteErrorState();
}

class _RemoteErrorState extends State<RemoteError> {
  bool _loading = false;

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
                  border: Border.all(color: KkColors.teal.withOpacity(0.3)),
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
          ],
        ),
      ),
    );
  }
}
