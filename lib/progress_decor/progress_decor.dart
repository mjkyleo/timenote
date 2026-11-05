import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../settings/enum_def.dart';

/// 底层进度组件层（取自动效实验室 aux 8 件）
///
/// 这一层不回答「数字怎么换」，只回答「还剩多少」：要么挂在数字下方，要么
/// （[ProgressDecor.sky]）垫在整屏背后。默认 [ProgressDecor.none] 一个像素都不画，
/// 主屏继续用原来那根细进度条。
class ProgressDecorView extends StatefulWidget {
  /// [progress] 是「已消耗比例」0..1，与 `ClockState.progress` 同一个定义
  final double progress;
  final ProgressDecor decor;
  final Color fg;
  final Color accent;

  /// 界面底色：只给 [ProgressDecor.sky] 用，天空压一层底色才压得住数字
  final Color bg;

  const ProgressDecorView({
    super.key,
    required this.decor,
    required this.progress,
    required this.fg,
    required this.accent,
    this.bg = Colors.black,
  });

  @override
  State<ProgressDecorView> createState() => _ProgressDecorViewState();
}

class _ProgressDecorViewState extends State<ProgressDecorView>
    with SingleTickerProviderStateMixin {
  /// 只有沙漏/水波/火苗需要连续动；环、灯带这类按进度画一次就够，
  /// 挂个 60fps 的 Ticker 纯属费电
  late final AnimationController _tick =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void initState() {
    super.initState();
    // Ticker 自己不会让这棵树重建：不加监听，沙粒/水波/火苗会停在同一帧，
    // 只有进度变化（每秒一次）时才动一下
    _tick.addListener(_onTick);
    _syncTicker();
  }

  void _onTick() {
    if (mounted) setState(() => {});
  }

  @override
  void didUpdateWidget(ProgressDecorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    if (animatedProgressDecors.contains(widget.decor)) {
      if (!_tick.isAnimating) _tick.repeat();
    } else if (_tick.isAnimating) {
      _tick.stop();
    }
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.decor == ProgressDecor.none) return const SizedBox.shrink();
    return CustomPaint(
      size: Size.infinite,
      painter: ProgressDecorPainter(
        decor: widget.decor,
        progress: widget.progress,
        tick: _tick.value,
        fg: widget.fg,
        accent: widget.accent,
        bg: widget.bg,
      ),
    );
  }
}

/// 需要逐帧动的进度组件；测试用这条约定决定能不能 pumpAndSettle
const Set<ProgressDecor> animatedProgressDecors = {
  ProgressDecor.hourglass,
  ProgressDecor.water,
  ProgressDecor.candle,
};

/// 已消耗 → 剩余，全层唯一定义处
double remainOf(double progress) => (1 - progress).clamp(0.0, 1.0);

class ProgressDecorPainter extends CustomPainter {
  final ProgressDecor decor;
  final double progress;

  /// 0..1 的循环相位，给沙粒/水波/火苗用
  final double tick;
  final Color fg;
  final Color accent;
  final Color bg;

  const ProgressDecorPainter({
    required this.decor,
    required this.progress,
    required this.tick,
    required this.fg,
    required this.accent,
    this.bg = Colors.black,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.isFinite || size.width <= 0 || size.height <= 0) return;
    switch (decor) {
      case ProgressDecor.none:
        break;
      case ProgressDecor.hourglass:
        _hourglass(canvas, size);
      case ProgressDecor.water:
        _water(canvas, size);
      case ProgressDecor.ring:
        _ring(canvas, size);
      case ProgressDecor.spiral:
        _spiral(canvas, size);
      case ProgressDecor.led:
        _led(canvas, size);
      case ProgressDecor.annualRings:
        _annualRings(canvas, size);
      case ProgressDecor.candle:
        _candle(canvas, size);
      case ProgressDecor.sky:
        _sky(canvas, size);
    }
  }

  Paint _stroke(double width, [Color? color]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..color = color ?? fg.withValues(alpha: 0.32);

  Paint _fill([Color? color]) => Paint()..color = color ?? fg;

  Rect _inner(Size size, double pad) =>
      Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);

  // ---- 25 沙漏：上仓变空、下仓变满，中间有沙粒落下 ----
  void _hourglass(Canvas canvas, Size size) {
    final box = _inner(size, 2);
    final neck = box.top + box.height / 2;
    final half = box.height / 2;
    final cx = box.center.dx;
    // 宽度跟着高度收，否则在又扁又宽的进度带里沙漏会被拉成两个扁 V
    final w = math.min(box.width / 2, box.height * 0.55);
    final remain = remainOf(progress);
    final sand = _fill(fg.withValues(alpha: 0.7));

    // 上仓是倒三角：剩下的沙贴着顶面，液面越往下沙越少
    final topDepth = half * remain;
    canvas.drawPath(
      Path()
        ..moveTo(cx - w, box.top)
        ..lineTo(cx + w, box.top)
        ..lineTo(cx + w * (1 - remain), box.top + topDepth)
        ..lineTo(cx - w * (1 - remain), box.top + topDepth)
        ..close(),
      sand,
    );

    // 下仓是正三角：沙从尖底往上堆，堆到的那一层宽度按比例
    final gone = 1 - remain;
    final surfY = neck + half * gone;
    canvas.drawPath(
      Path()
        ..moveTo(cx, neck)
        ..lineTo(cx + w * gone, surfY)
        ..lineTo(cx - w * gone, surfY)
        ..close(),
      sand,
    );

    // 细流 + 5 颗落沙：只在还在计时的中间段出现
    if (remain > 0 && remain < 1) {
      canvas.drawLine(Offset(cx, neck - 2), Offset(cx, surfY),
          _stroke(1.0, fg.withValues(alpha: 0.45)));
      for (var i = 0; i < 5; i++) {
        final p = (tick + i / 5) % 1;
        canvas.drawCircle(
            Offset(cx + math.sin(p * math.pi * 3) * 1.6,
                neck + (surfY - neck) * p),
            1.1,
            _fill(fg.withValues(alpha: 0.8)));
      }
    }

    final frame = _stroke(1.6);
    for (final chamber in [
      [Offset(cx - w, box.top), Offset(cx + w, box.top), Offset(cx, neck)],
      [Offset(cx - w, box.bottom), Offset(cx + w, box.bottom), Offset(cx, neck)],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(chamber[0].dx, chamber[0].dy)
          ..lineTo(chamber[1].dx, chamber[1].dy)
          ..lineTo(chamber[2].dx, chamber[2].dy)
          ..close(),
        frame,
      );
    }
  }

  // ---- 26 水位填充：两条正弦叠出水面 ----
  void _water(Canvas canvas, Size size) {
    final box = _inner(size, 2);
    final remain = remainOf(progress);
    final level = box.bottom - box.height * remain;
    final amp = (box.height * 0.05).clamp(0.5, 4.0);
    final phase = tick * 2 * math.pi;

    final surface = Path()..moveTo(box.left, box.bottom);
    surface.lineTo(box.left, level);
    // 步长 6 逻辑像素：够密看不出台阶，又不至于一条边上几百个点
    for (var x = 0.0; x <= box.width; x += 6) {
      final y = level +
          amp * math.sin(x * 0.05 + phase) +
          amp * 0.6 * math.sin(x * 0.021 - phase * 2);
      surface.lineTo(box.left + x, y);
    }
    surface.lineTo(box.right, box.bottom);
    surface.close();

    final container = RRect.fromRectAndRadius(box, const Radius.circular(10));
    canvas.save();
    canvas.clipRRect(container);
    canvas.drawPath(surface, _fill(accent.withValues(alpha: 0.55)));
    canvas.restore();
    canvas.drawRRect(container, _stroke(1.6));
  }

  // ---- 27 环形进度：外圈按剩余比例填充 ----
  void _ring(Canvas canvas, Size size) {
    final stroke = math.min(size.height * 0.16, 8.0);
    final r = math.min(size.width, size.height) / 2 - stroke / 2 - 1;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    canvas.drawArc(rect, 0, 2 * math.pi, false, _stroke(stroke));
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * remainOf(progress), false,
        _stroke(stroke, accent));
  }

  // ---- 28 螺旋进度：阿基米德螺旋按进度截断 ----
  void _spiral(Canvas canvas, Size size) {
    const turns = 3.0;
    final stroke = math.min(size.height * 0.12, 6.0);
    final maxR = math.min(size.width, size.height) / 2 - stroke - 1;
    const steps = 160; // 实验室 420 段是给整屏 canvas 的，这条带子用不到那么密
    const thetaMax = 2 * math.pi * turns;
    final center = size.center(Offset.zero);
    Path arc(double upto) {
      final p = Path()..moveTo(center.dx, center.dy);
      final n = (steps * upto).round();
      for (var i = 1; i <= n; i++) {
        final f = i / steps;
        final theta = thetaMax * f;
        final r = maxR * f;
        p.lineTo(
          center.dx + r * math.cos(theta - math.pi / 2),
          center.dy + r * math.sin(theta - math.pi / 2),
        );
      }
      return p;
    }

    canvas.drawPath(arc(1), _stroke(stroke));
    canvas.drawPath(arc(progress.clamp(0.0, 1.0)), _stroke(stroke, accent));
  }

  // ---- 29 灯带进度：22 颗灯珠按剩余比例依次熄灭 ----
  void _led(Canvas canvas, Size size) {
    const beads = 22;
    final step = size.width / beads;
    final r = math.min(size.height * 0.34, step * 0.4);
    final lit = (remainOf(progress) * beads).round();
    for (var i = 0; i < beads; i++) {
      canvas.drawCircle(
        Offset(step * (i + 0.5), size.height / 2),
        r,
        _fill(i < lit ? accent : fg.withValues(alpha: 0.16)),
      );
    }
  }

  // ---- 30 年轮圆盘：五圈同心逐层点亮 ----
  void _annualRings(Canvas canvas, Size size) {
    const layers = 5;
    final stroke = math.min(size.height * 0.08, 4.0);
    final maxR = math.min(size.width, size.height) / 2 - stroke - 1;
    final center = size.center(Offset.zero);
    for (var i = 0; i < layers; i++) {
      final r = maxR * (i + 1) / layers;
      final rect = Rect.fromCircle(center: center, radius: r);
      final layer = ((progress * layers) - i).clamp(0.0, 1.0);
      if (layer <= 0) continue;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * layer, false,
          _stroke(stroke, layer >= 1 ? accent : fg.withValues(alpha: 0.6)));
    }
  }

  // ---- 31 蜡烛燃烧：越烧越短，火苗两正弦轻抖 ----
  void _candle(Canvas canvas, Size size) {
    final remain = remainOf(progress);
    final bodyW = math.min(size.width * 0.12, size.height * 0.3);
    final cx = size.width / 2;
    final bottom = size.height - 2;
    final bodyTop = bottom - (size.height * 0.62) * remain;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - bodyW / 2, bodyTop, bodyW, bottom - bodyTop),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, _fill(fg.withValues(alpha: 0.18)));
    canvas.drawRRect(body, _stroke(1.6));

    if (remain <= 0) return;
    final flameH = size.height * 0.24;
    final flicker = math.sin(tick * 2 * math.pi) * 0.6 +
        math.sin(tick * 4 * math.pi + 1.1) * 0.4;
    final flameCenter =
        Offset(cx + flicker * bodyW * 0.12, bodyTop - flameH * 0.55);
    // 光晕：径向渐变垫在火苗后面，火苗本身是个拉长的椭圆
    final glowRect = Rect.fromCircle(
        center: flameCenter, radius: flameH * (1.6 + 0.2 * flicker));
    canvas.drawCircle(
      flameCenter,
      flameH * 1.6,
      Paint()
        ..shader = RadialGradient(colors: [
          accent.withValues(alpha: 0.32),
          accent.withValues(alpha: 0),
        ]).createShader(glowRect),
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: flameCenter, width: bodyW * 0.42, height: flameH),
      _fill(accent),
    );
  }

  // ---- 32 日出日落：环境层，太阳高度与天色都跟着剩余时间走 ----
  void _sky(Canvas canvas, Size size) {
    final consumed = progress.clamp(0.0, 1.0);
    const dayTop = Color(0xFF8FCBEE);
    const dayLow = Color(0xFFF6E3B4);
    const duskTop = Color(0xFF2B3A67);
    const duskLow = Color(0xFFF2762B);
    const nightTop = Color(0xFF101A2E);
    const nightLow = Color(0xFF2C3E63);
    // 白天→黄昏→夜里分两段插值，直接一根线插到底会中途变成脏色
    final Color top, low;
    if (consumed < 0.6) {
      final f = consumed / 0.6;
      top = Color.lerp(dayTop, duskTop, f) ?? dayTop;
      low = Color.lerp(dayLow, duskLow, f) ?? dayLow;
    } else {
      final f = (consumed - 0.6) / 0.4;
      top = Color.lerp(duskTop, nightTop, f) ?? duskTop;
      low = Color.lerp(duskLow, nightLow, f) ?? duskLow;
    }
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, low],
        ).createShader(rect),
    );

    // 太阳从左往右走，高度是一段正弦弧
    final sunR = math.min(size.width, size.height) * 0.07;
    final sunCenter = Offset(
      size.width * (0.16 + 0.68 * consumed),
      size.height * (0.62 - 0.42 * math.sin(math.pi * (1 - consumed))),
    );
    canvas.drawCircle(
        sunCenter, sunR * 2.4, _fill(const Color(0xFFFFF3C4).withValues(alpha: 0.18)));
    canvas.drawCircle(sunCenter, sunR, _fill(const Color(0xFFFFE9A8)));

    // 山脊剪影：贴底的一串三角，把「地平线」钉住
    final ridge = Path()..moveTo(0, size.height);
    for (var i = 0; i < 4; i++) {
      final x = size.width * (i + 0.5) / 4;
      ridge
        ..lineTo(x - size.width / 8, size.height * 0.82)
        ..lineTo(x, size.height * (0.66 + (i.isEven ? 0 : 0.06)))
        ..lineTo(x + size.width / 8, size.height * 0.82);
    }
    ridge.lineTo(size.width, size.height);
    ridge.close();
    canvas.drawPath(ridge, _fill(const Color(0xFF16213A).withValues(alpha: 0.85)));

    // 入夜才浮现的星星，位置由序号算出来，逐帧不动
    final starAlpha = ((consumed - 0.7) / 0.3).clamp(0.0, 1.0);
    if (starAlpha > 0) {
      for (var i = 0; i < 18; i++) {
        final x = (math.sin(i * 12.9898) * 0.5 + 0.5) * size.width;
        final y = (math.sin(i * 4.3127) * 0.5 + 0.5) * size.height * 0.6;
        canvas.drawCircle(Offset(x, y), 1.1,
            _fill(Colors.white.withValues(alpha: 0.7 * starAlpha)));
      }
    }

    // 压一层界面底色：天空再好看也只是背景，压不住数字就是失败的环境层
    canvas.drawRect(rect, _fill(bg.withValues(alpha: 0.45)));
  }

  @override
  bool shouldRepaint(ProgressDecorPainter old) =>
      old.decor != decor ||
      old.progress != progress ||
      old.tick != tick ||
      old.fg != fg ||
      old.accent != accent ||
      old.bg != bg;
}
