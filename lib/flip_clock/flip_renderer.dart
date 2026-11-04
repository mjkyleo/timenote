import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../settings/enum_def.dart';
import '../core/constants.dart';

/// 翻页动画的过渡构建：5 种动画各自实现
///
/// 约定：[transition] 收到的 animation 对入场子节点是 0→1，对出场子节点是 1→0，
/// 静止时当前子节点的值恒为 1，因此公式必须在 value==1 时回到「平铺」状态，
/// 否则数字会停在镜像/半边上。
abstract class FlipRenderer {
  const FlipRenderer();

  Widget transition(Widget child, Animation<double> anim);
}

/// 带透视的 3D 旋转变换（绕 X 轴上下翻合 / 绕 Y 轴左右翻卷）
///
/// 必须监听 [animation] 重建：只在 build 里读一次 `animation.value`
/// 会把数字冻结在入场瞬间的角度（侧立 = 看不见），这是历史 bug 的根因。
class _FlipTransform extends StatelessWidget {
  /// value == 0 时的角度，value == 1 时回到平铺
  final double angleX;
  final double angleY;
  final Animation<double> animation;
  final Widget child;

  const _FlipTransform({
    required this.angleX,
    required this.angleY,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = 1 - animation.value;
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateX(angleX * progress)
            ..rotateY(angleY * progress),
          alignment: Alignment.center,
          child: child,
        );
      },
    );
  }
}

/// 01 经典机场翻牌：绕水平中轴上下翻合
class FlipCardRenderer extends FlipRenderer {
  const FlipCardRenderer();

  @override
  Widget transition(Widget child, Animation<double> anim) {
    return _FlipTransform(
      angleX: math.pi / 2,
      angleY: 0,
      animation: anim,
      child: child,
    );
  }
}

/// 02 书页卷曲翻页：绕竖直轴左右翻卷
class PageCurlRenderer extends FlipRenderer {
  const PageCurlRenderer();

  @override
  Widget transition(Widget child, Animation<double> anim) {
    return _FlipTransform(
      angleX: 0,
      angleY: math.pi / 2,
      animation: anim,
      child: child,
    );
  }
}

/// 03 滑动翻页：新数字从下方推入
class SlideFlipRenderer extends FlipRenderer {
  const SlideFlipRenderer();

  @override
  Widget transition(Widget child, Animation<double> anim) {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(anim),
      child: child,
    );
  }
}

/// 04 分段碎裂翻：小角度翻动 + 缩放
class SegmentFlipRenderer extends FlipRenderer {
  const SegmentFlipRenderer();

  @override
  Widget transition(Widget child, Animation<double> anim) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.86, end: 1).animate(anim),
      child: _FlipTransform(
        angleX: math.pi / 4,
        angleY: 0,
        animation: anim,
        child: child,
      ),
    );
  }
}

/// 05 渐变溶解翻：纯淡入淡出
class FadeFlipRenderer extends FlipRenderer {
  const FadeFlipRenderer();

  @override
  Widget transition(Widget child, Animation<double> anim) {
    return FadeTransition(opacity: anim, child: child);
  }
}

const Map<FlipAnimStyle, FlipRenderer> _renderers = {
  FlipAnimStyle.flipCard: FlipCardRenderer(),
  FlipAnimStyle.pageCurl: PageCurlRenderer(),
  FlipAnimStyle.slideFlip: SlideFlipRenderer(),
  FlipAnimStyle.segmentFlip: SegmentFlipRenderer(),
  FlipAnimStyle.fadeFlip: FadeFlipRenderer(),
};

FlipRenderer getRenderer(FlipAnimStyle style) =>
    _renderers[style] ?? const FlipCardRenderer();

/// 数字外观：10 种计时画面风格的设计参数表
///
/// 字体 family 只是其中一个维度（字体未打包时会回退系统字体），
/// 字重/字距/底板/圆角/描边/斜体才是风格真正可辨的来源。
@immutable
class ClockLook {
  final FontWeight weight;
  final FontStyle fontStyle;
  final double letterSpacing;

  /// 相对 [AppConstants.baseFontSize] 的倍率
  final double sizeScale;

  /// >0 表示镂空描边文字（此时不填充颜色）
  final double strokeWidth;

  /// 数字底板不透明度，0 表示无底板
  final double plateOpacity;
  final double radius;
  final EdgeInsets padding;

  /// 是否绘制翻牌中缝
  final bool seam;
  final bool tabular;

  const ClockLook({
    this.weight = FontWeight.w500,
    this.fontStyle = FontStyle.normal,
    this.letterSpacing = 0,
    this.sizeScale = 1,
    this.strokeWidth = 0,
    this.plateOpacity = 0,
    this.radius = 0,
    this.padding = EdgeInsets.zero,
    this.seam = false,
    this.tabular = false,
  });
}

const Map<ClockVisualStyle, ClockLook> clockLooks = {
  // 01 苹果极简：细体无底板，宽松字距
  ClockVisualStyle.appleMinimal: ClockLook(
    weight: FontWeight.w300,
    letterSpacing: 2,
  ),
  // 02 复古机械粗牌：厚重底板 + 翻页中缝
  ClockVisualStyle.retroMechanical: ClockLook(
    weight: FontWeight.w800,
    letterSpacing: 1,
    plateOpacity: 0.14,
    radius: 6,
    padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
    seam: true,
    tabular: true,
  ),
  // 03 软圆角卡片：大圆角柔和底板
  ClockVisualStyle.softRoundCard: ClockLook(
    weight: FontWeight.w500,
    letterSpacing: 2,
    plateOpacity: 0.07,
    radius: 28,
    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 18),
  ),
  // 04 高对比窄版：直角满底板，字距收紧
  ClockVisualStyle.narrowHighContrast: ClockLook(
    weight: FontWeight.w900,
    letterSpacing: -3,
    sizeScale: 1.06,
    plateOpacity: 0.18,
    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    tabular: true,
  ),
  // 05 手写文艺：小字号、疏朗字距、无底板
  ClockVisualStyle.handwritten: ClockLook(
    weight: FontWeight.w400,
    letterSpacing: 6,
    sizeScale: 0.9,
  ),
  // 06 粗黑力量：最重字重、放大
  ClockVisualStyle.boldPower: ClockLook(
    weight: FontWeight.w900,
    sizeScale: 1.1,
    tabular: true,
  ),
  // 07 纤细思源：极细字重 + 宽字距
  ClockVisualStyle.thinSourceHan: ClockLook(
    weight: FontWeight.w100,
    letterSpacing: 10,
  ),
  // 08 得意黑潮流：斜体 + 微收字距
  ClockVisualStyle.deyiTrend: ClockLook(
    weight: FontWeight.w700,
    fontStyle: FontStyle.italic,
    letterSpacing: -1,
    sizeScale: 1.05,
  ),
  // 09 点阵风：等宽数字 + 深色底板
  ClockVisualStyle.dotMatrix: ClockLook(
    weight: FontWeight.w600,
    letterSpacing: 4,
    plateOpacity: 0.1,
    radius: 2,
    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    tabular: true,
  ),
  // 10 镂空描边：只描边不填充
  ClockVisualStyle.hollowStroke: ClockLook(
    weight: FontWeight.w700,
    strokeWidth: 2.5,
    sizeScale: 1.05,
    letterSpacing: 1,
  ),
};

ClockLook appearanceFor(ClockVisualStyle style) =>
    clockLooks[style] ?? const ClockLook();

/// 由外观参数生成数字文字样式
TextStyle clockTextStyle({
  required ClockLook look,
  required Color foreground,
  required String? fontFamily,
  double fontSize = AppConstants.baseFontSize,
}) {
  final stroked = look.strokeWidth > 0;
  return TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize * look.sizeScale,
    fontWeight: look.weight,
    fontStyle: look.fontStyle,
    letterSpacing: look.letterSpacing,
    height: 1,
    color: stroked ? null : foreground,
    foreground: stroked
        ? (Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = look.strokeWidth * fontSize / AppConstants.baseFontSize
          ..color = foreground
          ..strokeJoin = StrokeJoin.round)
        : null,
    fontFeatures: look.tabular ? const [FontFeature.tabularFigures()] : null,
  );
}
