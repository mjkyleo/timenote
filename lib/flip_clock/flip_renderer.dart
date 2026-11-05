import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
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

  /// [delay] 是该格子在整串里的起跑偏移（0→1 占比），级联错位一类用它把各位错开。
  ///
  /// 走时长而不是走定时器：格子自己的 controller 已经被拉长到 `基础时长 + 偏移`，
  /// 这里把 t 重新映射回 0→1，所以测试里按帧推进依然确定，不会留悬空 Timer。
  Widget transition({
    required Widget newChild,
    required double t,
    Widget? oldChild,
    double delay = 0,
  }) {
    final local =
        delay <= 0 ? t : ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
    return local >= 1
        ? newChild
        : flip(newChild: newChild, oldChild: oldChild, t: local);
  }

  /// 只在 0 <= t < 1 时被调用；[oldChild] 为 null 表示首次出现，只有入场动画
  @protected
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  });
}

/// 绕 Y 轴转的包装（书页/整卡翻面/对角斜折都靠它）
Widget _yaw(Widget child, double angle, Alignment alignment) => Transform(
      alignment: alignment,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0020)
        ..rotateY(angle),
      child: child,
    );

/// 沿 X 平移一整格（offset 用牌子自身宽度做单位）
Widget _slideX(Widget child, double dx) =>
    FractionalTranslation(translation: Offset(dx, 0), child: child);

/// 运动模糊：中段最糊，两头收干净，所以静止态一定是清晰的
Widget _motionBlur(Widget child, double sigma) => sigma <= 0.05
    ? child
    : ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      );

/// 滚筒上下被吃进去的暗角，强度跟着模糊走
Widget _vignette(Widget child, double strength) => Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.42 * strength),
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.42 * strength),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
        ),
      ],
    );

/// 只露出第 [index] 条横向带（百叶窗的每一叶）
class _BandClipper extends CustomClipper<Rect> {
  final int index;
  final int strips;

  const _BandClipper(this.index, this.strips);

  @override
  Rect getClip(Size size) {
    final h = size.height / strips;
    return Rect.fromLTRB(0, h * index, size.width, h * (index + 1));
  }

  @override
  bool shouldReclip(_BandClipper old) => old.index != index || old.strips != strips;
}

/// 从中心张开的凸多边形遮罩（径向光圈 = 1 段圆，多边形遮罩 = 4 段菱形）
class _IrisClipper extends CustomClipper<Path> {
  final double progress;
  final int sides;

  const _IrisClipper(this.progress, {this.sides = 0});

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 半径要能盖住角，否则张开到一半时四角还是旧的
    final reach = math.sqrt(size.width * size.width + size.height * size.height) / 2;
    final r = reach * progress;
    final path = Path();
    if (sides <= 0) {
      path.addOval(Rect.fromCircle(center: center, radius: r));
      return path;
    }
    for (var i = 0; i < sides; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / sides);
      final p = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_IrisClipper old) =>
      old.progress != progress || old.sides != sides;
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

/// 05 滚筒里程表：整列数字直线下滑，中段带运动模糊，上下被暗角吃掉
///
/// 取自老式电表/汽车里程表。之前这版做成了「鼓面透视旋转、靠顶变扁」，
/// 和实验室样本 #5 不是一回事；实验室版才是用户认的「滚筒」，所以按 #5 重写。
/// 位移 108% 而不是 100%，是为了让数字彻底离开窗口再进新的，不留残影。
class TickerRollRenderer extends FlipRenderer {
  const TickerRollRenderer();

  static const double _travel = 1.08;
  static const double _blurSigma = 3;

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final move = _phase(t, 0, 1, Curves.easeOutCubic);
    // 正弦包络：起跑和落位时都是清晰的，只有中段糊，所以静止态一定锐利
    final blur = _blurSigma * math.sin(math.pi * t);
    final shade = math.sin(math.pi * t);
    return _vignette(
      Stack(
        fit: StackFit.loose,
        children: [
          if (oldChild != null)
            _motionBlur(
              FractionalTranslation(
                  translation: const Offset(0, -_travel), child: oldChild),
              blur,
            ),
          _motionBlur(
            FractionalTranslation(
                translation: Offset(0, _travel * (1 - move)), child: newChild),
            blur,
          ),
        ],
      ),
      shade,
    );
  }
}

/// 03 对角斜折：沿 (1,1,0) 轴翻转，旧数字斜着掀起来
///
/// 视觉噪声偏大，实验室标的是「建议只用在短计时或结束前倒数十秒」，
/// 所以它进轮换池但别当默认。
class DiagFoldRenderer extends FlipRenderer {
  const DiagFoldRenderer();

  /// 实验室原样是 `rotate3d(1,1,0,θ)` 单轴翻；这里用两次等角的 X/Y 复合，
  /// 视觉上同样是「斜着从一个角掀起来」，但不依赖 vector_math 的 Vector3。
  Widget _turn(Widget child, double angle) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0022)
          ..rotateX(angle)
          ..rotateY(angle),
        child: child,
      );

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final lift = _phase(t, 0, 0.5, Curves.easeInCubic);
    final settle = _phase(t, 0.35, 1, Curves.easeOutCubic);
    return Stack(
      fit: StackFit.loose,
      children: [
        Opacity(
          opacity: 0.2 + 0.8 * settle,
          child: _turn(newChild, -math.pi / 2 * (1 - settle)),
        ),
        if (oldChild != null)
          Opacity(
            opacity: 1 - lift,
            child: _turn(oldChild, math.pi / 2 * lift),
          ),
      ],
    );
  }
}

/// 04 弹跳翻牌：翻折照旧，落位时整块牌子再沉一下弹回来
///
/// 和 01 经典翻牌的区别：01 的回弹只发生在下叶角度上，这一版把回弹
/// 做成了看得见的整体位移，活泼但长计时里更抢注意力。
class BounceFlipRenderer extends FlipRenderer {
  const BounceFlipRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    const hingeEnd = 0.4;
    final fall = _phase(t, 0, hingeEnd, Curves.easeInCubic);
    final land = _phase(t, hingeEnd, 1, Curves.easeOutBack);
    // 落位那一下的上下弹跳：sin 半周期，起终点都是 0，静止态不会被留在偏移上
    final kick = math.sin(math.pi * _phase(t, 0.55, 1, Curves.linear)) * 0.05;
    final card = Stack(
      fit: StackFit.loose,
      children: [
        newChild,
        if (oldChild != null) ...[
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _hingedLeaf(newChild, top: false, angle: (1 - land) * math.pi / 2),
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
            child: _hingedLeaf(oldChild, top: true, angle: fall * math.pi / 2),
          ),
        ] else
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _hingedLeaf(newChild, top: false, angle: (1 - land) * math.pi / 2),
          ),
      ],
    );
    return FractionalTranslation(translation: Offset(0, kick), child: card);
  }
}

/// 24 整卡翻面：绕中心竖轴转，转过 90° 的那一瞬换成新数字再转回来
///
/// 不做「转到 180° 再翻面」，因为那会让新数字在收尾时是镜像的（历史 bug 的
/// 同源问题）；两段各 90°、中间换面，静止态永远正面。
class CardFlipRenderer extends FlipRenderer {
  const CardFlipRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final turn = _phase(t, 0, 1, Curves.easeInOutCubic);
    final angle = turn * math.pi;
    final old = oldChild;
    // 转过 90° 侧立的那一瞬换面，之后新数字从 -90° 转回正面
    final showingOld = old != null && angle < math.pi / 2;
    final face = showingOld ? old : newChild;
    // 侧立到 90° 时最暗，换面之后从暗里亮回来
    final shade = _shade(math.pi / 2 - (angle - math.pi / 2).abs());
    return Stack(
      fit: StackFit.loose,
      children: [
        _yaw(
          shade <= 0.005
              ? face
              : Stack(
                  fit: StackFit.passthrough,
                  children: [
                    face,
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: shade * 0.55),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          showingOld ? angle : angle - math.pi,
          Alignment.center,
        ),
      ],
    );
  }
}

/// 06 横向滑移：旧数字向左滑出，新数字从右侧滑入，两段交叠 30%
class SlideAcrossRenderer extends FlipRenderer {
  const SlideAcrossRenderer();

  static const double _travel = 1.12;

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final out = _phase(t, 0, 0.7, Curves.easeInCubic);
    final in_ = _phase(t, 0.3, 1, Curves.easeOutCubic);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - _phase(t, 0.5, 0.85, Curves.easeIn),
            child: _slideX(oldChild, -_travel * out),
          ),
        _slideX(newChild, _travel * (1 - in_)),
      ],
    );
  }
}

/// 07 级联错位：逐格错开落下，像水波从时位传到秒位
///
/// 错开量由 [FlipRenderer.transition] 的 delay 提供，本类只负责单格的动作。
class CascadeRenderer extends FlipRenderer {
  const CascadeRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final drop = _phase(t, 0, 1, Curves.easeOutBack);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - _phase(t, 0, 0.35, Curves.easeIn),
            child: oldChild,
          ),
        FractionalTranslation(
          translation: Offset(0, -1.12 * (1 - drop)),
          child: newChild,
        ),
      ],
    );
  }
}

/// 08 百叶窗擦除：7 条横向带依次向自己的中线收起，把旧数字擦掉
///
/// 纯 2D 裁剪，没有透视也没有模糊，是这一批里最省的一档（实验室标的
/// 「最省性能」）。
class BlindRenderer extends FlipRenderer {
  const BlindRenderer();

  static const int strips = 7;

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    if (oldChild == null) {
      return Opacity(opacity: _phase(t, 0, 0.8, Curves.easeOut), child: newChild);
    }
    return Stack(
      fit: StackFit.loose,
      children: [
        newChild,
        for (var i = 0; i < strips; i++)
          ClipRect(
            clipper: _BandClipper(i, strips),
            child: Transform(
              // 铰链放在这条带自己的中线上，收起时才是「卷帘」而不是「整体缩」
              alignment: Alignment(0, (2 * i + 1) / strips - 1),
              transform: Matrix4.diagonal3Values(
                  1, 1 - _phase(t, i * 0.06, i * 0.06 + 0.6, Curves.easeIn), 1),
              child: oldChild,
            ),
          ),
      ],
    );
  }
}

/// 09 径向光圈：圆形遮罩从中心张开，新数字被光圈推出来
class IrisRenderer extends FlipRenderer {
  const IrisRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final open = _phase(t, 0, 0.85, Curves.easeOutCubic);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - _phase(t, 0.2, 0.9, Curves.easeIn),
            child: oldChild,
          ),
        ClipPath(
          clipper: _IrisClipper(open),
          child: Transform.scale(scale: 1.08 - 0.08 * open, child: newChild),
        ),
      ],
    );
  }
}

/// 22 多边形遮罩：菱形从中心冲出，旧数字被切出几何边界
///
/// 实验室标的是「做主题皮肤比做默认更合适」，所以它进池但不当默认。
class PolygonRenderer extends FlipRenderer {
  const PolygonRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final open = _phase(t, 0, 0.8, Curves.easeOutCubic);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - _phase(t, 0, 0.6, Curves.easeIn),
            child: Transform.scale(scale: 1 + 0.1 * _phase(t, 0, 0.6, Curves.easeIn), child: oldChild),
          ),
        ClipPath(
          clipper: _IrisClipper(open, sides: 4),
          child: Transform.rotate(
            angle: math.pi / 4 * (1 - open),
            child: newChild,
          ),
        ),
      ],
    );
  }
}

/// 17 交叉淡入：旧牌淡出缩小、新牌淡入放大，两段交错
///
/// 没有滤镜也没有裁剪，是低端机与省电模式的降级目标（实验室标的「兜底方案」）。
class CrossfadeRenderer extends FlipRenderer {
  const CrossfadeRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final out = _phase(t, 0, 0.5, Curves.easeIn);
    final in_ = _phase(t, 0.35, 1, Curves.easeOut);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - out,
            child: Transform.scale(scale: 1 - 0.06 * out, child: oldChild),
          ),
        Opacity(
          opacity: in_,
          child: Transform.scale(scale: 0.94 + 0.06 * in_, child: newChild),
        ),
      ],
    );
  }
}

/// 18 模糊对焦：旧数字虚化散掉，新数字从模糊里对上焦
///
/// 变化极轻、几乎不打断注意力，代价是「跳秒」的存在感也一起变弱。
class BlurFocusRenderer extends FlipRenderer {
  const BlurFocusRenderer();

  static const double _sigma = 6;

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final out = _phase(t, 0, 0.6, Curves.easeIn);
    final in_ = _phase(t, 0.2, 1, Curves.easeOutCubic);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(opacity: 1 - out, child: _motionBlur(oldChild, _sigma * out)),
        Opacity(opacity: 0.25 + 0.75 * in_, child: _motionBlur(newChild, _sigma * (1 - in_))),
      ],
    );
  }
}

/// 16 果冻挤压：压到最扁的那一帧换数，再弹回原形
class JellyRenderer extends FlipRenderer {
  const JellyRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    // sin 半周期：t=0 与 t=1 都是 0，所以静止态既没被压扁也没被拉长
    final squash = math.sin(math.pi * t);
    // 换面发生在最扁的那一帧，看起来才像「被挤出去又弹回来」
    final face = (oldChild != null && t < 0.5) ? oldChild : newChild;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(1 + 0.22 * squash, 1 - 0.3 * squash, 1),
      child: face,
    );
  }
}


/// 碎片类的稳定伪随机：同一枚碎片每一帧必须朝同一个方向飞，不然会看成噪点抖动
///
/// 取的是着色器里常用的 sin-hash；这里只用它取「散开方向」，不参与逐帧变化。
double _rand(int seed) {
  final x = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
  return x - x.floor();
}

/// 碎片飞回原位：[progress] 为 0 时还散着，为 1 时已经拼好
///
/// 位移用 [FractionalTranslation]，单位是「整张牌子的宽高占比」，所以散开量按
/// 格子数折算（一格是 1/cols），换字号换屏幕都不用重算像素。
Widget _flyHome(
  Widget child, {
  required Offset scatter,
  required double progress,
  double spin = 0,
}) {
  final left = 1 - progress;
  if (left <= 0.001) return child;
  return FractionalTranslation(
    translation: Offset(scatter.dx * left, scatter.dy * left),
    child: Transform.rotate(
      angle: spin * left,
      child: Transform.scale(scale: 1 + 0.3 * left, child: child),
    ),
  );
}

/// 网格遮罩：只露出第 [index] 格（像素洗牌的一块）
class _GridClipper extends CustomClipper<Path> {
  final int index;
  final int cols;
  final int rows;

  const _GridClipper(this.index, this.cols, this.rows);

  static Rect cellRect(Size size, int index, int cols, int rows) {
    final w = size.width / cols, h = size.height / rows;
    return Rect.fromLTWH((index % cols) * w, (index ~/ cols) * h, w, h);
  }

  @override
  Path getClip(Size size) =>
      Path()..addRect(cellRect(size, index, cols, rows));

  @override
  bool shouldReclip(_GridClipper old) =>
      old.index != index || old.cols != cols || old.rows != rows;
}

/// 圆窗遮罩：粒子聚散的每一枚粒子（格子内切一个圆）
class _DotClipper extends CustomClipper<Path> {
  final int index;
  final int cols;
  final int rows;

  const _DotClipper(this.index, {required this.cols, required this.rows});

  @override
  Path getClip(Size size) {
    final cell = _GridClipper.cellRect(size, index, cols, rows);
    // 圆切到格子边的一半，点与点之间留出缝隙才看得出一颗一颗
    final r = cell.shortestSide * 0.5;
    return Path()
      ..addOval(Rect.fromCircle(center: cell.center, radius: r));
  }

  @override
  bool shouldReclip(_DotClipper old) =>
      old.index != index || old.cols != cols || old.rows != rows;
}

/// 三角碎片遮罩：每格沿对角线切成两块，[index] 是第几块三角形
///
/// 每格的两块合起来正好是整格，所以碎片全部归位后数字是完整的、没有洞。
class _ShardClipper extends CustomClipper<Path> {
  final int index;
  final int cols;
  final int rows;

  const _ShardClipper(this.index, {this.cols = 2, this.rows = 2});

  @override
  Path getClip(Size size) {
    final quad = index ~/ 2;
    final half = index % 2;
    final cell = _GridClipper.cellRect(size, quad, cols, rows);
    final tl = cell.topLeft, tr = cell.topRight;
    final br = cell.bottomRight, bl = cell.bottomLeft;
    // 交替换一条对角线，碎片才不全是同一个朝向
    final alt = (quad + half) % 2 == 0;
    final points = half == 0
        ? (alt ? [tl, tr, br] : [tl, tr, bl])
        : (alt ? [tl, br, bl] : [tr, br, bl]);
    return Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..close();
  }

  @override
  bool shouldReclip(_ShardClipper old) =>
      old.index != index || old.cols != cols || old.rows != rows;
}

/// 13 像素洗牌：数字切成方格先打散，再各自滑回原位拼成新数字
///
/// 实验室是整屏 6×8 = 48 格；我们一格一字，所以每字 3×4 = 12 块，
/// 整个钟头的碎片总量与实验室同一量级。
class PixelShuffleRenderer extends FlipRenderer {
  const PixelShuffleRenderer();

  static const int cols = 3;
  static const int rows = 4;
  static const int count = cols * rows;

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final gone = _phase(t, 0, 0.35, Curves.easeIn);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - gone,
            child: Transform.scale(scale: 1 + 0.12 * gone, child: oldChild),
          ),
        for (var i = 0; i < count; i++)
          ClipPath(
            clipper: _GridClipper(i, cols, rows),
            // 每块自己排队归位：错开起点才是「洗牌」，不是一起滑回原位
            child: _flyHome(
              newChild,
              progress: _phase(
                  t, 0.05 + i * 0.045, 0.65 + i * 0.045, Curves.easeOutCubic),
              scatter: Offset((_rand(i + 1) - 0.5) * 4 / cols,
                  (_rand(i + 31) - 0.5) * 4 / rows),
              spin: (_rand(i + 61) - 0.5) * 0.9,
            ),
          ),
      ],
    );
  }
}

/// 12 粒子聚散：旧数字散成一群点，新数字的点从四周聚回原位
///
/// 实验室用 Canvas 逐像素采样字形，Flutter 没有同步拿到字形位图的入口，所以每枚
/// 粒子改成一枚「圆窗」：窗子停在哪儿，透出来的就是数字的哪一块——散开与聚回的
/// 读法一致，代价是点之间会露出底色。实验室标「仅收尾」，别挂进每秒轮换的池子。
class ParticleScatterRenderer extends FlipRenderer {
  const ParticleScatterRenderer();

  static const int cols = 3;
  static const int rows = 5;
  static const int count = cols * rows;

  Offset _scatterOf(int i) => Offset((_rand(i + 7) - 0.5) * 3,
      (_rand(i + 97) - 0.5) * 3);

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final blow = _phase(t, 0, 0.55, Curves.easeInCubic);
    final gather = _phase(t, 0.3, 1, Curves.easeOutCubic);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - _phase(t, 0.2, 0.7, Curves.easeIn),
            child: Stack(
              fit: StackFit.loose,
              children: [
                for (var i = 0; i < count; i++)
                  ClipPath(
                    clipper: _DotClipper(i, cols: cols, rows: rows),
                    child: _flyHome(oldChild,
                        scatter: _scatterOf(i), progress: 1 - blow),
                  ),
              ],
            ),
          ),
        // 聚拢之前整块先不画：否则新数字会透过点缝先亮出来
        if (gather > 0)
          Opacity(opacity: 0.15 + 0.85 * gather, child: newChild),
        for (var i = 0; i < count; i++)
          ClipPath(
            clipper: _DotClipper(i, cols: cols, rows: rows),
            child: _flyHome(newChild,
                scatter: _scatterOf(i + 140), progress: gather),
          ),
      ],
    );
  }
}

/// 14 三角碎片：数字剖成三角碎片向外飞散，再由碎片拼回新数字
///
/// 实验室标「绘制成本最高、只适合结束时刻」：每格两块三角形，
/// 两块合起来是整格，所以拼完不会留洞。
class ShardBurstRenderer extends FlipRenderer {
  const ShardBurstRenderer();

  static const int cols = 2;
  static const int rows = 2;
  static const int count = cols * rows * 2;

  /// 沿「碎片质心 → 牌子中心」的连线往外炸，再叠一点随机角度
  Offset _burstOf(int index) {
    final quad = index ~/ 2;
    final dx = (quad % cols + 0.5) / cols - 0.5;
    final dy = (quad ~/ cols + 0.5) / rows - 0.5;
    final reach = 1.6 + _rand(index + 211) * 0.9;
    return Offset(dx, dy) * reach +
        Offset((_rand(index + 307) - 0.5) * 0.5,
            (_rand(index + 401) - 0.5) * 0.5);
  }

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final burst = _phase(t, 0, 0.5, Curves.easeInCubic);
    final assemble = _phase(t, 0.35, 1, Curves.easeOutCubic);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - _phase(t, 0.15, 0.65, Curves.easeIn),
            child: Stack(
              fit: StackFit.loose,
              children: [
                for (var i = 0; i < count; i++)
                  ClipPath(
                    clipper: _ShardClipper(i, cols: cols, rows: rows),
                    child: _flyHome(oldChild,
                        scatter: _burstOf(i), progress: 1 - burst, spin: 0.7),
                  ),
              ],
            ),
          ),
        if (assemble > 0)
          Opacity(opacity: 0.15 + 0.85 * assemble, child: newChild),
        for (var i = 0; i < count; i++)
          ClipPath(
            clipper: _ShardClipper(i, cols: cols, rows: rows),
            child: _flyHome(newChild,
                scatter: _burstOf(i), progress: assemble, spin: 0.7),
          ),
      ],
    );
  }
}

/// 横向切片，每片各自水平位移：流体溶解与液态玻璃都靠它近似「逐行错位」
///
/// 实验室用 Canvas 逐行重绘 / Fragment Shader 做折射，Flutter 端不上 shader，
/// 就用 [bands] 条横带 + 正弦横移顶上去；位移单位是「整张牌子宽度的占比」，
/// 所以 amp 归零时一定回到完全平铺，静止态不会残留错位。
Widget _shearBands(
  Widget child, {
  required double amp,
  required double phase,
  int bands = 8,
}) {
  if (amp.abs() < 0.002) return child;
  return Stack(
    fit: StackFit.loose,
    children: [
      for (var i = 0; i < bands; i++)
        ClipRect(
          clipper: _BandClipper(i, bands),
          child: FractionalTranslation(
            translation: Offset(amp * math.sin(phase + i * 0.8), 0),
            child: child,
          ),
        ),
    ],
  );
}

/// 一条横扫过高光：用 Alignment 的分数坐标挪，省掉按像素换算
Widget _sweepGlint(Widget child, double progress, double strength) => Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(0, -1.6 + 2.6 * progress),
                  end: Alignment(0, -1.0 + 2.6 * progress),
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.34 * strength),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

/// 老式显示器的行扫描覆层，[alpha] 为 0 时一层都不画
class _ScanlinePainter extends CustomPainter {
  final double alpha;

  const _ScanlinePainter(this.alpha);

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    final paint = Paint()..color = Colors.black.withValues(alpha: alpha);
    // 3 逻辑像素一条线：高 DPI 下也压得住，线太密会变成一块灰底
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.alpha != alpha;
}

/// 10 流体溶解：旧数字像墨一样被逐行拉散，新数字从错位里凝回原位
///
/// 实验室标「高频慎用」（dur=520 + 局部重绘），所以它只做单独可选，不进轮换池。
class FluidDissolveRenderer extends FlipRenderer {
  const FluidDissolveRenderer();

  static const double _amp = 0.22;

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final melt = _phase(t, 0, 0.55, Curves.easeIn);
    final condense = _phase(t, 0.3, 1, Curves.easeOutCubic);
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - _phase(t, 0.25, 0.8, Curves.easeIn),
            child: _motionBlur(
              _shearBands(oldChild, amp: _amp * melt, phase: t * 7),
              2.5 * melt,
            ),
          ),
        _shearBands(newChild,
            amp: _amp * (1 - condense), phase: 2 + t * 7, bands: 10),
      ],
    );
  }
}

/// 11 液态玻璃折射：透过晃动的厚玻璃看数字，一条高光扫过去后玻璃静止
///
/// 实验室标的短板是「数字边缘会糊、远距离可读性下降」，所以位移只在中段最大，
/// 两头都收干净；同样标「高频慎用」，不进轮换池。
class LiquidGlassRenderer extends FlipRenderer {
  const LiquidGlassRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    final gone = _phase(t, 0, 0.45, Curves.easeIn);
    // sin 半周期：t=0 与 t=1 都不晃，只有中段玻璃在动
    final wobble = math.sin(math.pi * t);
    return _sweepGlint(
      Stack(
        fit: StackFit.loose,
        children: [
          if (oldChild != null)
            Opacity(
              opacity: 1 - gone,
              child: _shearBands(oldChild, amp: 0.18 * gone, phase: t * 5),
            ),
          _shearBands(newChild, amp: 0.18 * wobble, phase: t * 9, bands: 10),
        ],
      ),
      t,
      wobble,
    );
  }
}

/// 23 CRT 扫描线：换数那一下画面横向抖，行扫描覆层随之熄灭
///
/// 实验室标的是「做主题皮肤比做默认更合适」，抖动走 steps（一格一格跳）而不是连续
/// 位移，才像老显像管；覆层只有几笔横线，成本比切片低，可以进轮换池。
class CrtScanlineRenderer extends FlipRenderer {
  const CrtScanlineRenderer();

  @override
  Widget flip({
    required Widget newChild,
    required double t,
    Widget? oldChild,
  }) {
    // steps：把 0→1 量化成 6 档，横向位移在档位之间跳
    final step = ((t * 6).floorToDouble() / 6 - 0.5) * 2;
    final shake = step * 0.05 * (1 - _phase(t, 0.7, 1, Curves.easeIn));
    final overlay = 0.35 * (1 - _phase(t, 0.6, 1, Curves.easeOut));
    return Stack(
      fit: StackFit.loose,
      children: [
        if (oldChild != null)
          Opacity(
            opacity: 1 - _phase(t, 0, 0.4, Curves.easeIn),
            child: FractionalTranslation(
                translation: Offset(shake, 0), child: oldChild),
          ),
        FractionalTranslation(
          translation: Offset(shake, 0),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              newChild,
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _ScanlinePainter(overlay)),
                ),
              ),
            ],
          ),
        ),
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
  // 翻折
  FlipAnimStyle.flipCard: FlipCardRenderer(),
  FlipAnimStyle.pageCurl: PageCurlRenderer(),
  FlipAnimStyle.diagFold: DiagFoldRenderer(),
  FlipAnimStyle.bounceFlip: BounceFlipRenderer(),
  FlipAnimStyle.cardFlip: CardFlipRenderer(),
  // 位移
  FlipAnimStyle.tickerRoll: TickerRollRenderer(),
  FlipAnimStyle.slideAcross: SlideAcrossRenderer(),
  FlipAnimStyle.cascade: CascadeRenderer(),
  // 遮罩
  FlipAnimStyle.blind: BlindRenderer(),
  FlipAnimStyle.iris: IrisRenderer(),
  FlipAnimStyle.polygon: PolygonRenderer(),
  // 形变
  FlipAnimStyle.crossfade: CrossfadeRenderer(),
  FlipAnimStyle.blurFocus: BlurFocusRenderer(),
  FlipAnimStyle.jelly: JellyRenderer(),
  // 碎片
  FlipAnimStyle.pixelShuffle: PixelShuffleRenderer(),
  FlipAnimStyle.particleScatter: ParticleScatterRenderer(),
  FlipAnimStyle.shardBurst: ShardBurstRenderer(),
  // 光学
  FlipAnimStyle.fluidDissolve: FluidDissolveRenderer(),
  FlipAnimStyle.liquidGlass: LiquidGlassRenderer(),
  FlipAnimStyle.crtScan: CrtScanlineRenderer(),
  // 本批之前就有
  FlipAnimStyle.slideFlip: SlideFlipRenderer(),
  FlipAnimStyle.segmentFlip: SegmentFlipRenderer(),
  FlipAnimStyle.fadeFlip: FadeFlipRenderer(),
  FlipAnimStyle.dropSettle: DropSettleRenderer(),
  // autoMix 由 _FlipBoard 先展开成具体动画，这里只是兜底
  FlipAnimStyle.autoMix: FlipCardRenderer(),
};

FlipRenderer getRenderer(FlipAnimStyle style) =>
    _renderers[style] ?? const FlipCardRenderer();

/// 需要逐格错开起跑的动画：每格时长 = 基础时长 + 步长 × 序号
const Set<FlipAnimStyle> staggeredStyles = {FlipAnimStyle.cascade};

/// 会把牌子推出自己格子的动画：格子必须裁切，否则糊到相邻格和底板外面
const Set<FlipAnimStyle> offCellStyles = {
  FlipAnimStyle.tickerRoll,
  FlipAnimStyle.slideAcross,
  FlipAnimStyle.slideFlip,
  FlipAnimStyle.cascade,
  FlipAnimStyle.dropSettle,
  FlipAnimStyle.iris,
  FlipAnimStyle.polygon,
  FlipAnimStyle.pixelShuffle,
  FlipAnimStyle.particleScatter,
  FlipAnimStyle.shardBurst,
  FlipAnimStyle.fluidDissolve,
  FlipAnimStyle.liquidGlass,
  FlipAnimStyle.crtScan,
};

/// 实验室标「仅收尾」的：冲击力强，但每秒都放会持续耗电并造成视觉疲劳
const Set<FlipAnimStyle> finaleOnlyStyles = {
  FlipAnimStyle.particleScatter,
  FlipAnimStyle.shardBurst,
};

/// 实验室标「高频慎用」的：逐行错位 / 滤镜叠上去，一秒一次太贵且边缘会糊
const Set<FlipAnimStyle> cautionStyles = {
  FlipAnimStyle.fluidDissolve,
  FlipAnimStyle.liquidGlass,
};

/// 不进混合轮换池的动画：仅收尾 + 高频慎用 + 逐字切片太贵的像素洗牌
///
/// 混合轮换是一秒一次的，池子里每多一种就多出「八格 × 十几种切片」的一帧成本；
/// 像素洗牌（12 块/字）与光学两档留成用户主动选的主题档。
const Set<FlipAnimStyle> poolExcludedStyles = {
  ...finaleOnlyStyles,
  ...cautionStyles,
  FlipAnimStyle.pixelShuffle,
};

/// 混合轮换的取序：相邻两次翻页拿到不同效果，同一次翻页里各位也错开
///
/// 只放实验室标了「每秒可用」的：碎片类（仅收尾 / 切片太贵）与流体、液态玻璃
/// （高频慎用）都登记在 [poolExcludedStyles] 里，它们只能被单独选中或挂结束档。
const List<FlipAnimStyle> flipMixCycle = [
  FlipAnimStyle.flipCard,
  FlipAnimStyle.tickerRoll,
  FlipAnimStyle.slideAcross,
  FlipAnimStyle.blind,
  FlipAnimStyle.dropSettle,
  FlipAnimStyle.pageCurl,
  FlipAnimStyle.iris,
  FlipAnimStyle.cascade,
  FlipAnimStyle.cardFlip,
  FlipAnimStyle.diagFold,
  FlipAnimStyle.bounceFlip,
  FlipAnimStyle.polygon,
  FlipAnimStyle.jelly,
  FlipAnimStyle.slideFlip,
  FlipAnimStyle.crossfade,
  FlipAnimStyle.blurFocus,
  FlipAnimStyle.segmentFlip,
  FlipAnimStyle.fadeFlip,
  FlipAnimStyle.crtScan,
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
