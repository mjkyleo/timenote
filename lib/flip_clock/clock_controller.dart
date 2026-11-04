import 'package:flutter/material.dart';
import 'flip_card_widget.dart';
import '../settings/enum_def.dart';
import '../core/constants.dart';

/// 实时时钟显示（HH:MM:SS，每秒翻页）
class ClockTimeDisplay extends StatefulWidget {
  final DateTime time;
  final FlipAnimStyle animStyle;
  final ClockVisualStyle visualStyle;
  final AnimSpeed speed;
  final ThemeBase themeBase;

  const ClockTimeDisplay({
    super.key,
    required this.time,
    required this.animStyle,
    required this.visualStyle,
    required this.speed,
    required this.themeBase,
  });

  @override
  State<ClockTimeDisplay> createState() => _ClockTimeDisplayState();
}

class _ClockTimeDisplayState extends State<ClockTimeDisplay> {
  String _curr = '';

  @override
  void initState() {
    super.initState();
    _curr = _fmt(widget.time);
  }

  @override
  void didUpdateWidget(covariant ClockTimeDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _curr = _fmt(widget.time);
  }

  String _fmt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final dur = AppConstants.animDurationMap[widget.speed]!;
    return FlipCardWidget(
      content: _curr,
      isNew: true,
      animDur: dur,
      animStyle: widget.animStyle,
      visualStyle: widget.visualStyle,
      themeBase: widget.themeBase,
    );
  }
}

/// 倒计时显示（HH:MM:SS，每秒翻页）
class CountdownDisplay extends StatefulWidget {
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
  State<CountdownDisplay> createState() => _CountdownDisplayState();
}

class _CountdownDisplayState extends State<CountdownDisplay> {
  String _curr = '';

  @override
  void initState() {
    super.initState();
    _curr = _fmt(widget.remain);
  }

  @override
  void didUpdateWidget(covariant CountdownDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _curr = _fmt(widget.remain);
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final dur = AppConstants.animDurationMap[widget.speed]!;
    return FlipCardWidget(
      content: _curr,
      isNew: true,
      animDur: dur,
      animStyle: widget.animStyle,
      visualStyle: widget.visualStyle,
      themeBase: widget.themeBase,
    );
  }
}
