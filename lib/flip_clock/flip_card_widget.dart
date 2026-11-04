import 'package:flutter/material.dart';
import 'flip_renderer.dart';
import '../core/constants.dart';
import '../settings/enum_def.dart';
import '../theme/ui_style.dart';

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
    // 没有 UiScope（单独 pump 本组件做测试）时退回本组件自己的黑白底，
    // 而不是按 Theme.brightness 猜，否则会跟传入的 themeBase 打架
    final tokens =
        UiScope.maybeOf(context) ?? UiTokens.classic(isDark);
    final foreground = tokens.fg;
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
                    tokens: tokens,
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
///
/// 底板的「环境」（填充/描边/光影/圆角）来自界面风格令牌；令牌没提供装饰时
/// （classic）完全退回数字样式自己的 plateOpacity/radius，与历史行为一致。
class _Plate extends StatelessWidget {
  final ClockLook look;
  final UiTokens tokens;
  final Color plateColor;
  final Color seamColor;
  final Widget child;

  const _Plate({
    required this.look,
    required this.tokens,
    required this.plateColor,
    required this.seamColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // 界面风格给了底板但数字样式没留内边距时，兜一点「土」，否则字会贴边
    final plain = look.padding == EdgeInsets.zero;
    final pad = plain && tokens.hasPlateDecor
        ? const EdgeInsets.symmetric(horizontal: 36, vertical: 18)
        : look.padding;
    Widget result = Padding(padding: pad, child: child);
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
    final fill = tokens.plateFill ??
        (look.plateOpacity > 0 ? plateColor : null);
    final stroke = tokens.plateStroke;
    if (fill == null && stroke == null && tokens.plateShadow.isEmpty) {
      return result;
    }
    return Container(
      // 有底板装饰时才存在这个节点，测试用它验证「界面风格真的画到了数字上」
      key: const Key('flip-plate'),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(tokens.radiusOr(look.radius)),
        border: stroke == null
            ? null
            : Border.all(color: stroke, width: tokens.plateStrokeWidth),
        boxShadow:
            tokens.plateShadow.isEmpty ? null : tokens.plateShadow,
      ),
      child: result,
    );
  }
}
