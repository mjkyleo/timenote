import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../settings/enum_def.dart';
import '../core/constants.dart';

/// 翻页过渡的过渡构建：一次翻牌里新旧两张牌同时在场景子里
///
/// 约定：[transition] 的 t 为 0 时仍是旧数字，为 1 时完全变成新数字；
/// t == 1 由基类兜底直接返回新数字本体，所以任何实现都不许把静止态留在
/// 镜像/侧立/半透明上（历史 bug），也不许让旧牌赖在树里。
abstract class FlipRenderer {
  const FlipRenderer();

  Widget transition({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) =>
      t >= 1 ? newChild : flip(newChild: newChild, oldChild: oldChild, t: t);

  /// 只在 0 <= t < 1 时被调用；[oldChild] 为 null 表示首次出现，只有入场动画
  @protected
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  });
}

/// 总进度 [t] 落在子区间 [from, to] 内的 0→1 值，并按 [curve] 变形。
///
/// 拆区间是手感的关键：翻牌不是「匀速转过去」，而是上半被重力拉着加速倒下、
/// 下半落位时越过平铺一点点再弹回来。
double _phase(double t, double from, double to, Curve curve) {
  if (to <= from) return t >= to ? 1 : 0;
  return curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));
}

/// 叶片侧立到什么程度就暗到什么程度
double _shade(double angle) => math.sin(angle).abs() * 0.62;

/// 只露出上半或下半（另一半裁掉），盒子高度正好是牌子的一半
Widget _halfOf(Widget child, {required bool top}) => ClipRect(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        heightFactor: 0.5,
        child: child,
      ),
    );

/// 绕中缝铰链摆动的一片叶子
///
/// 铰链在牌子正中：上叶的下缘、下叶的上缘都贴在中缝上，所以 alignment 分别是
/// bottomCenter / topCenter。角度符号相反 —— 两片叶子都得朝观察者倒（rotateX 取负
/// 才让「上缘向外」的前倒成立），否则翻牌会看成往后倒。
Widget _hingedLeaf(
  Widget child, {
  required bool top,
  required double angle,
}) {
  final half = _halfOf(child, top: top);
  final shade = _shade(angle);
  final leaf = shade <= 0.005
      ? half
      : Stack(
          fit: StackFit.passthrough,
          children: [
            half,
            Positioned.fill(
              child: IgnorePointer(
                // 靠中缝一侧受光，自由端转进阴影里
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: top ? Alignment.bottomCenter : Alignment.topCenter,
                      end: top ? Alignment.topCenter : Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: shade * 0.25),
                        Colors.black.withValues(alpha: shade),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
  return Transform(
    alignment: top ? Alignment.bottomCenter : Alignment.topCenter,
    transform: Matrix4.identity()
      ..setEntry(3, 2, 0.0022)
      ..rotateX(top ? -angle : angle),
    child: leaf,
  );
}

/// 整块牌子做 3D 摆动（绕 [alignment] 指定的轴）
Widget _swing(
  Widget child, {
  required double angleX,
  required double angleY,
  required Alignment alignment,
}) =>
    Transform(
      alignment: alignment,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0018)
        ..rotateX(angleX)
        ..rotateY(angleY),
      child: child,
    );

/// 沿 Y 平移一整格（offset 用牌子自身高度做单位），越靠边越扁的滚筒感
Widget _roll(Widget child, double dy, double squeeze) => Transform.scale(
      scaleY: 1 - squeeze,
      child: FractionalTranslation(translation: Offset(0, dy), child: child),
    );

/// 01 经典机场翻牌：上叶绕中缝加速倒下，下叶从中缝展开并轻微回弹
class FlipCardRenderer extends FlipRenderer {
  const FlipCardRenderer();

  /// 上叶只占前 42% 时间：剩下的留给下叶，留出「啪」的落位节奏
  static const double _hingeEnd = 0.42;

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    if (oldChild == null) {
      // 入场没有旧牌可掀，只把下叶从中缝放下来
      final land = _phase(t, 0, 1, Curves.easeOutBack);
      return Stack(
        fit: StackFit.loose,
        children: [
          _halfOf(newChild, top: true),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _hingedLeaf(newChild, top: false, angle: (1 - land) * math.pi / 2),
          ),
        ],
      );
    }
    final fall = _phase(t, 0, _hingeEnd, Curves.easeInCubic);
    // easeOutBack 末端会超过 1 → 角度变成小的负值，读起来就是落牌那一下回弹
    final land = _phase(t, _hingeEnd, 1, Curves.easeOutBack);
    final upper = fall * math.pi / 2;
    final lower = (1 - land) * math.pi / 2;
    return Stack(
      fit: StackFit.loose,
      children: [
        // 底层：新数字整张（上叶倒下后露出的就是它）
        newChild,
        // 新下半盖住旧下半，所以排在它前面
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _hingedLeaf(newChild, top: false, angle: lower),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _halfOf(oldChild, top: false),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _hingedLeaf(oldChild, top: true, angle: upper),
        ),
      ],
    );
  }
}

/// 02 书页卷曲翻页：旧数字像被掀起的一页，绕左缘向后翻卷
class PageCurlRenderer extends FlipRenderer {
  const PageCurlRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final reveal = _phase(t, 0.05, 0.9, Curves.easeOut);
    if (oldChild == null) {
      return Opacity(opacity: reveal, child: newChild);
    }
    final turn = _phase(t, 0, 1, Curves.easeInOutCubic);
    final angle = turn * math.pi / 2;
    return Stack(
      fit: StackFit.loose,
      children: [
        newChild,
        Opacity(
          opacity: 1 - _phase(t, 0.7, 1, Curves.easeIn),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              _swing(oldChild,
                  angleX: 0,
                  angleY: angle,
                  alignment: Alignment.centerLeft),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: _shade(angle) * 0.3),
                          Colors.black.withValues(alpha: _shade(angle)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 03 滑动翻页：新数字从下方推入并过冲一点，旧数字被顶出去
class SlideFlipRenderer extends FlipRenderer {
  const SlideFlipRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final push = _phase(t, 0, 1, Curves.easeOutBack);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          FractionalTranslation(
            translation: Offset(0, -_phase(t, 0, 0.7, Curves.easeInCubic)),
            child: Opacity(
              opacity: 1 - _phase(t, 0.45, 0.8, Curves.easeIn),
              child: oldChild,
            ),
          ),
        // 从 1 格下方推到 0；easeOutBack 让它冲过头再收回来
        FractionalTranslation(
          translation: Offset(0, 1 - push),
          child: newChild,
        ),
      ],
    );
  }
}

/// 04 分段碎裂翻：新数字带倾角砸下来并回弹，旧数字散开淡出
class SegmentFlipRenderer extends FlipRenderer {
  const SegmentFlipRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final pop = _phase(t, 0, 0.8, Curves.easeOutBack);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - _phase(t, 0, 0.5, Curves.easeOut),
            child: Transform.scale(
              scale: 1 + 0.12 * _phase(t, 0, 0.5, Curves.easeOut),
              child: oldChild,
            ),
          ),
        Transform.scale(
          scale: 0.86 + 0.14 * pop,
          child: _swing(
            newChild,
            angleX: math.pi / 4 * (1 - pop),
            angleY: 0,
            alignment: Alignment.center,
          ),
        ),
      ],
    );
  }
}

/// 05 渐变溶解翻：旧数字整体化开，新数字带一点收拢淡入
class FadeFlipRenderer extends FlipRenderer {
  const FadeFlipRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final inAndOut = _phase(t, 0, 0.85, Curves.easeOut);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(opacity: 1 - _phase(t, 0, 0.7, Curves.easeIn), child: oldChild),
        Opacity(opacity: inAndOut, child: newChild),
      ],
    );
  }
}

/// 06 滚筒走字：数字贴在转动的鼓面上滚过去，越接近顶端越扁
class TickerRollRenderer extends FlipRenderer {
  const TickerRollRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final rise = _phase(t, 0, 0.6, Curves.easeIn);
    final drop = _phase(t, 0.25, 1, Curves.easeOutCubic);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - rise,
            child: _roll(oldChild, -_phase(t, 0, 0.6, Curves.easeInQuad), 0.45 * rise),
          ),
        Opacity(opacity: drop, child: _roll(newChild, 1 - drop, 0.45 * (1 - drop))),
      ],
    );
  }
}

/// 07 落体回弹：新数字从上方自由落下，落地后弹两下才停
class DropSettleRenderer extends FlipRenderer {
  const DropSettleRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final land = _phase(t, 0, 1, Curves.bounceOut);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - _phase(t, 0, 0.45, Curves.easeOut),
            child: Transform.scale(
              scale: 1 + 0.18 * _phase(t, 0, 0.45, Curves.easeOut),
              child: oldChild,
            ),
          ),
        // 从 1 格上方落到 0；bounceOut 自带落地后的连续小弹跳
        FractionalTranslation(
          translation: Offset(0, land - 1),
          child: newChild,
        ),
      ],
    );
  }
}

const Map<FlipAnimStyle, FlipRenderer> _renderers = {
  FlipAnimStyle.flipCard: FlipCardRenderer(),
  FlipAnimStyle.pageCurl: PageCurlRenderer(),
  FlipAnimStyle.slideFlip: SlideFlipRenderer(),
  FlipAnimStyle.segmentFlip: SegmentFlipRenderer(),
  FlipAnimStyle.fadeFlip: FadeFlipRenderer(),
  FlipAnimStyle.tickerRoll: TickerRollRenderer(),
  FlipAnimStyle.dropSettle: DropSettleRenderer(),
  // autoMix 由 _FlipBoard 先展开成具体动画，这里只是兜底
  FlipAnimStyle.autoMix: FlipCardRenderer(),
};

FlipRenderer getRenderer(FlipAnimStyle style) =>
    _renderers[style] ?? const FlipCardRenderer();

/// 混合轮换的取序：相邻两次翻页拿到不同效果，同一次翻页里各位也错开
const List<FlipAnimStyle> flipMixCycle = [
  FlipAnimStyle.flipCard,
  FlipAnimStyle.tickerRoll,
  FlipAnimStyle.slideFlip,
  FlipAnimStyle.dropSettle,
  FlipAnimStyle.pageCurl,
  FlipAnimStyle.segmentFlip,
  FlipAnimStyle.fadeFlip,
];

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
