import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// HANDOFF §5 触控区铁律:所有可点元素实际点击区 ≥ 44×44pt。
///
/// 视觉可小(图标 22px),热区撑到 44。实现:
///   ConstrainedBox(minWidth/Height: 44) + Material(透明) + InkWell + Center。
///
/// Phase 4 按下反馈增强:
///   按下 → scale 1.0 → 0.96(100ms,Curves.easeIn,即时响应)
///   抬起 → scale 0.96 → 1.0(200ms,Curves.easeOutBack,弹性回弹带轻微过冲)
///   InkWell 涟漪 + onTap/onLongPress 回调全保留;外层 GestureDetector
///   (behavior: HitTestBehavior.translucent)只接管动画手势(onTapDown /
///   onTapUp / onTapCancel),不挂 onTap,事件穿透到 InkWell 触发涟漪与回调。
///   disabled 态:InkWell.onTap/onLongPress 置 null(无涟漪无回调),
///   GestureDetector 处理器早返(无动画),Opacity 0.4 视觉降权。
///
/// 触控区不因 scale 缩小:ConstrainedBox 在 ScaleTransition 之外撑 44pt,
/// ScaleTransition 是视觉变换不影响外层命中区,disabled 静止态稳态 44pt。
///
/// Web 版重灾区:detail 动作钮 34×34、Tab pill 30×23、搜索图标 20×20……
/// Flutter 端从组件层做对——所有可点元素走这个 Tappable,默认 44pt。
///
/// P2-无障碍:[semanticLabel] 可选。Icon-only 按钮必须传(读屏需要文字念),
/// 含文字的按钮 Flutter 自动从子 Text 推断语义标签,可省略。null 时不包
/// Semantics(向后兼容现有 ~146 处调用点)。
///
/// 用法:
///   Tappable(onTap: ..., child: Icon(Icons.add, size: 22))
///   Tappable(onTap: ..., borderRadius: ..., padding: ..., child: Row(...))
///   // icon-only 必须:
///   Tappable(onTap: ..., semanticLabel: '搜索', child: Icon(Icons.search))
class Tappable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final Color? splashColor;
  final bool disabled;
  final EdgeInsetsGeometry padding;
  final double minSize;

  /// P2-无障碍:可选语义标签。null 时不包 Semantics(向后兼容)。
  /// Icon-only 按钮必须传,否则读屏只会念「按钮」无具体含义。
  final String? semanticLabel;

  const Tappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(KkRadius.sm)),
    this.splashColor,
    this.disabled = false,
    this.padding = EdgeInsets.zero,
    this.minSize = KkTouch.minTarget,
    this.semanticLabel,
  });

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  // Phase 4 按下反馈参数:按下 100ms 缩到 0.96,抬起 200ms 弹性回弹到 1.0
  static const Duration _pressDownDuration = Duration(milliseconds: 100);
  static const Duration _pressUpDuration = Duration(milliseconds: 200);
  static const double _pressedScale = 0.96;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _pressDownDuration,
      reverseDuration: _pressUpDuration,
    );
    _scale = Tween<double>(begin: 1.0, end: _pressedScale).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeIn,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.disabled) return;
    _ctrl.forward();
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.disabled) return;
    _ctrl.reverse();
  }

  void _onTapCancel() {
    if (widget.disabled) return;
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final core = Opacity(
      opacity: widget.disabled ? 0.4 : 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minSize,
          minHeight: widget.minSize,
        ),
        child: GestureDetector(
          // translucent:让事件穿透到 InkWell 触发涟漪 + onTap 回调,
          // GestureDetector 自身只跟踪动画手势,不抢 tap 主权。
          behavior: HitTestBehavior.translucent,
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: ScaleTransition(
            scale: _scale,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.disabled ? null : widget.onTap,
                onLongPress: widget.disabled ? null : widget.onLongPress,
                borderRadius: widget.borderRadius,
                splashColor: widget.splashColor,
                child: Padding(
                  padding: widget.padding,
                  child: Center(child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // P2-无障碍:icon-only 按钮传 semanticLabel 时包 Semantics,把语义标签
    // 合并到 InkWell 自带的 button 节点(读屏念「<label>, 按钮」)。
    // null 时直接返回 core,向后兼容(不引入额外语义节点,不破坏现有行为)。
    final label = widget.semanticLabel;
    if (label == null) return core;
    return Semantics(
      label: label,
      button: true,
      child: core,
    );
  }
}
