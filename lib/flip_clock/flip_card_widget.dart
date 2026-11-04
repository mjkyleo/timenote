import 'package:flutter/material.dart';
import 'flip_renderer.dart';
import '../core/constants.dart';
import '../settings/enum_def.dart';

/// 翻页卡片：负责自适应尺寸、底板与翻页过渡
class FlipCardWidget extends StatelessWidget {
  final String content;
  final Duration animDur;
  final FlipAnimStyle animStyle;
  final ClockVisualStyle visualStyle;
  final ThemeBase themeBase;

  const FlipCardWidget({
    super.key,
    required this.content,
    required this.animDur,
    required this.animStyle,
    required this.visualStyle,
    required this.themeBase,
  });

  @override
  Widget build(BuildContext context) {
    final look = appearanceFor(visualStyle);
    final isDark = themeBase == ThemeBase.dark;
    final foreground = isDark ? Colors.white : Colors.black;
    final style = clockTextStyle(
      look: look,
      foreground: foreground,
      fontFamily: AppConstants.fontOf(visualStyle),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 数字占可用高度的 70%，其余交给 FittedBox 按宽度等比缩放
        final maxHeight = constraints.maxHeight;
        final boxHeight = maxHeight.isFinite ? maxHeight * 0.7 : null;
        return SizedBox(
          height: boxHeight,
          width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
          child: FittedBox(
            fit: BoxFit.contain,
            child: RepaintBoundary(
              child: AnimatedSwitcher(
                duration: animDur,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: getRenderer(animStyle).transition,
                child: KeyedSubtree(
                  key: ValueKey(content),
                  child: _Plate(
                    look: look,
                    plateColor:
                        foreground.withValues(alpha: look.plateOpacity),
                    seamColor: isDark
                        ? Colors.white.withValues(alpha: 0.28)
                        : Colors.black.withValues(alpha: 0.22),
                    child: Text(
                      content,
                      maxLines: 1,
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 数字底板 + 可选翻页中缝
class _Plate extends StatelessWidget {
  final ClockLook look;
  final Color plateColor;
  final Color seamColor;
  final Widget child;

  const _Plate({
    required this.look,
    required this.plateColor,
    required this.seamColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget result = Padding(padding: look.padding, child: child);
    if (look.seam) {
      result = Stack(
        fit: StackFit.passthrough,
        children: [
          result,
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(height: 2, color: seamColor),
              ),
            ),
          ),
        ],
      );
    }
    if (look.plateOpacity <= 0) return result;
    return Container(
      decoration: BoxDecoration(
        color: plateColor,
        borderRadius: BorderRadius.circular(look.radius),
      ),
      child: result,
    );
  }
}
