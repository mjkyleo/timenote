import 'package:flutter/material.dart';
import '../settings/enum_def.dart';
import '../core/constants.dart';

/// 翻页渲染抽象接口：5 种翻页动画各自实现
abstract class FlipRenderer {
  Widget buildWidget(
    BuildContext context,
    String text,
    bool isNew,
    Duration animDur,
    ClockVisualStyle visualStyle,
    ThemeBase themeBase,
  );
}

/// 01 经典机场翻牌（上下卡片 3D 翻转）
class FlipCardRenderer implements FlipRenderer {
  @override
  Widget buildWidget(BuildContext context, String text, bool isNew,
      Duration animDur, ClockVisualStyle visualStyle, ThemeBase themeBase) {
    final fg = themeBase == ThemeBase.dark ? Colors.white : Colors.black;
    final fontFam = AppConstants.styleFontMap[visualStyle]!;
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: animDur,
        transitionBuilder: (child, anim) {
          return RotationYTransition(turns: anim, child: child);
        },
        child: Text(
          text,
          key: ValueKey(text),
          style: TextStyle(
            fontFamily: fontFam,
            fontSize: 120,
            color: fg,
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// 02 书页卷曲翻页
class PageCurlRenderer implements FlipRenderer {
  @override
  Widget buildWidget(BuildContext context, String text, bool isNew,
      Duration animDur, ClockVisualStyle visualStyle, ThemeBase themeBase) {
    final fg = themeBase == ThemeBase.dark ? Colors.white : Colors.black;
    final fontFam = AppConstants.styleFontMap[visualStyle]!;
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: animDur,
        transitionBuilder: (child, anim) {
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(1.57 * (1 - anim.value)),
            alignment: Alignment.center,
            child: child,
          );
        },
        child: Text(
          text,
          key: ValueKey(text),
          style: TextStyle(
            fontFamily: fontFam,
            fontSize: 120,
            color: fg,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// 03 滑动翻页（板块上下滑入）
class SlideFlipRenderer implements FlipRenderer {
  @override
  Widget buildWidget(BuildContext context, String text, bool isNew,
      Duration animDur, ClockVisualStyle visualStyle, ThemeBase themeBase) {
    final fg = themeBase == ThemeBase.dark ? Colors.white : Colors.black;
    final fontFam = AppConstants.styleFontMap[visualStyle]!;
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: animDur,
        transitionBuilder: (child, anim) {
          return SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                    .animate(anim),
            child: child,
          );
        },
        child: Text(
          text,
          key: ValueKey(text),
          style: TextStyle(
            fontFamily: fontFam,
            fontSize: 120,
            color: fg,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// 04 分段碎裂翻（缩放翻牌）
class SegmentFlipRenderer implements FlipRenderer {
  @override
  Widget buildWidget(BuildContext context, String text, bool isNew,
      Duration animDur, ClockVisualStyle visualStyle, ThemeBase themeBase) {
    final fg = themeBase == ThemeBase.dark ? Colors.white : Colors.black;
    final fontFam = AppConstants.styleFontMap[visualStyle]!;
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: animDur,
        transitionBuilder: (child, anim) {
          return ScaleTransition(scale: anim, child: child);
        },
        child: Text(
          text,
          key: ValueKey(text),
          style: TextStyle(
            fontFamily: fontFam,
            fontSize: 120,
            color: fg,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// 05 渐变溶解翻（淡入淡出）
class FadeFlipRenderer implements FlipRenderer {
  @override
  Widget buildWidget(BuildContext context, String text, bool isNew,
      Duration animDur, ClockVisualStyle visualStyle, ThemeBase themeBase) {
    final fg = themeBase == ThemeBase.dark ? Colors.white : Colors.black;
    final fontFam = AppConstants.styleFontMap[visualStyle]!;
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: animDur,
        transitionBuilder: (child, anim) {
          return FadeTransition(opacity: anim, child: child);
        },
        child: Text(
          text,
          key: ValueKey(text),
          style: TextStyle(
            fontFamily: fontFam,
            fontSize: 120,
            color: fg,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// 按枚举获取渲染器实例
FlipRenderer getRenderer(FlipAnimStyle style) {
  switch (style) {
    case FlipAnimStyle.flipCard:
      return FlipCardRenderer();
    case FlipAnimStyle.pageCurl:
      return PageCurlRenderer();
    case FlipAnimStyle.slideFlip:
      return SlideFlipRenderer();
    case FlipAnimStyle.segmentFlip:
      return SegmentFlipRenderer();
    case FlipAnimStyle.fadeFlip:
      return FadeFlipRenderer();
  }
}

/// Y 轴翻转过渡动画（经典机场翻牌）
class RotationYTransition extends AnimatedWidget {
  final Widget child;

  const RotationYTransition({
    super.key,
    required Animation<double> turns,
    required this.child,
  }) : super(listenable: turns);

  @override
  Widget build(BuildContext context) {
    final Animation<double> anim = listenable as Animation<double>;
    return Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateY(anim.value * 3.1415926),
      alignment: Alignment.center,
      child: child,
    );
  }
}
