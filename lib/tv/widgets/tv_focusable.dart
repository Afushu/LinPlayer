import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/tv_design_tokens.dart';
import '../theme/tv_metrics.dart';

/// TV 焦点包装器
/// 为任何子组件添加 TV 焦点效果（放大、边框、光晕）
/// 支持遥控器方向键导航和确认键触发
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  /// 次级动作：平板/Pad 长按触发；TV 遥控器按「菜单键」(contextMenu) 触发。
  /// 用于「长按进入编辑模式」等场景。
  final VoidCallback? onLongPress;
  final VoidCallback? onFocus;
  final VoidCallback? onBlur;
  final bool autofocus;
  final FocusNode? focusNode;
  /// 内边距，传 null 时按当前屏幕响应式取 spacingSm。
  final EdgeInsets? padding;
  final double scale;
  final bool enableGlow;

  /// 焦点环/高亮的圆角，传 null 时按当前屏幕取 posterRadius。
  /// 让焦点环沿子组件真实形状走：pill 传 999、卡片传 posterRadius。
  final double? borderRadius;

  const TvFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.onLongPress,
    this.onFocus,
    this.onBlur,
    this.autofocus = false,
    this.focusNode,
    this.padding,
    this.scale = TvDesignTokens.focusScale,
    this.enableGlow = true,
    this.borderRadius,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    final padding = widget.padding ?? EdgeInsets.all(m.spacingSm);
    final radius = BorderRadius.circular(widget.borderRadius ?? m.posterRadius);
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          widget.onFocus?.call();
        } else {
          widget.onBlur?.call();
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onSelect?.call();
            return KeyEventResult.handled;
          }
          // 遥控器「菜单键」= 次级动作（进入编辑等）。
          if (widget.onLongPress != null &&
              (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonY)) {
            widget.onLongPress!.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      // 性能/观感要点：
      // - 缩放用原生 AnimatedScale（单隐式动画），焦点环/光晕用 AnimatedOpacity 淡入淡出，
      //   阴影是“静态”的，绝不对 blurRadius 做动画（那是焦点网格掉帧的元凶）；
      // - 焦点环沿子组件真实圆角走（pill=999、卡片=posterRadius），不再是看不清的方形蒙版；
      // - 外层 RepaintBoundary 把每个卡片的重绘隔离开。
      child: Builder(
        builder: (context) => GestureDetector(
          // TV 界面同时跑在平板/Pad 上：点击 = 聚焦 + 激活，等价于遥控器确认键。
          // opaque 让整张卡片区域可点；嵌套的子手势（如内部按钮）仍由更深层捕获。
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Focus.of(context).requestFocus();
            widget.onSelect?.call();
          },
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  Focus.of(context).requestFocus();
                  widget.onLongPress!.call();
                },
          child: RepaintBoundary(
            child: Padding(
              padding: padding,
              child: AnimatedScale(
                scale: _isFocused ? widget.scale : 1.0,
                duration: TvDesignTokens.focusAnimationDuration,
                curve: TvDesignTokens.focusAnimationCurve,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      duration: TvDesignTokens.focusAnimationDuration,
                      curve: TvDesignTokens.focusAnimationCurve,
                      opacity: _isFocused ? 1.0 : TvDesignTokens.nonFocusOpacity,
                      child: widget.child,
                    ),
                    // 焦点指示：品牌蓝高亮环 + 淡填充 + 柔和外发光，沿子组件圆角。
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          duration: TvDesignTokens.focusAnimationDuration,
                          curve: TvDesignTokens.focusAnimationCurve,
                          opacity: _isFocused ? 1.0 : 0.0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: TvDesignTokens.focusFill,
                              borderRadius: radius,
                              border: Border.all(
                                color: TvDesignTokens.focusRing,
                                width: TvDesignTokens.focusRingWidth,
                              ),
                              boxShadow: widget.enableGlow
                                  ? const [
                                      BoxShadow(
                                        color: TvDesignTokens.focusGlow,
                                        blurRadius: 16,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
