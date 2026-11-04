import 'dart:async';
import 'package:flutter/material.dart';
import 'flip_card_widget.dart';
import '../core/constants.dart';
import '../settings/enum_def.dart';

/// HH:MM:SS 文本（实时时钟与倒计时共用）
String formatHms(int hours, int minutes, int seconds) {
  final h = hours.toString().padLeft(2, '0');
  final m = minutes.toString().padLeft(2, '0');
  final s = seconds.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// 实时时钟显示
///
/// 每秒刷新只重建这个子树，主屏按钮与抽屉不参与重建。
class ClockTimeDisplay extends StatefulWidget {
  final FlipAnimStyle animStyle;
  final ClockVisualStyle visualStyle;
  final AnimSpeed speed;
  final ThemeBase themeBase;

  /// 时间源来自 clockSourceProvider，与倒计时共用同一个可注入 seam；
  /// 直接读 DateTime.now() 会让测试跨到真实秒边界，翻页动画双份文本同时在场。
  final DateTime Function() now;

  const ClockTimeDisplay({
    super.key,
    required this.now,
    required this.animStyle,
    required this.visualStyle,
    required this.speed,
    required this.themeBase,
  });

  @override
  State<ClockTimeDisplay> createState() => _ClockTimeDisplayState();
}

class _ClockTimeDisplayState extends State<ClockTimeDisplay> {
  Timer? _align;
  Timer? _ticker;
  late DateTime _now = widget.now();

  @override
  void initState() {
    super.initState();
    // 先对齐到下一个整秒，再按秒周期刷新，避免多实例之间相位漂移
    final msToNextSecond = 1000 - _now.millisecondsSinceEpoch % 1000;
    _align = Timer(Duration(milliseconds: msToNextSecond), () {
      _tick();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    });
  }

  void _tick() {
    final next = widget.now();
    if (!mounted || next.second == _now.second) return;
    setState(() => _now = next);
  }

  @override
  void dispose() {
    _align?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlipCardWidget(
      content: formatHms(_now.hour, _now.minute, _now.second),
      animDur: AppConstants.animDurationOf(widget.speed),
      animStyle: widget.animStyle,
      visualStyle: widget.visualStyle,
      themeBase: widget.themeBase,
    );
  }
}

/// 倒计时显示（HH:MM:SS），时间源在 ClockNotifier
class CountdownDisplay extends StatelessWidget {
  final Duration remain;
  final FlipAnimStyle animStyle;
  final ClockVisualStyle visualStyle;
  final AnimSpeed speed;
  final ThemeBase themeBase;

  const CountdownDisplay({
    super.key,
    required this.remain,
    required this.animStyle,
    required this.visualStyle,
    required this.speed,
    required this.themeBase,
  });

  @override
  Widget build(BuildContext context) {
    return FlipCardWidget(
      content: formatHms(
        remain.inHours,
        remain.inMinutes % 60,
        remain.inSeconds % 60,
      ),
      animDur: AppConstants.animDurationOf(speed),
      animStyle: animStyle,
      visualStyle: visualStyle,
      themeBase: themeBase,
    );
  }
}
