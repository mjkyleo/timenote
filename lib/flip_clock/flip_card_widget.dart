import 'package:flutter/material.dart';
import 'flip_renderer.dart';
import '../settings/enum_def.dart';

/// 翻页卡片容器：根据动画样式选择渲染器
class FlipCardWidget extends StatelessWidget {
  final String content;
  final bool isNew;
  final Duration animDur;
  final FlipAnimStyle animStyle;
  final ClockVisualStyle visualStyle;
  final ThemeBase themeBase;

  const FlipCardWidget({
    super.key,
    required this.content,
    required this.isNew,
    required this.animDur,
    required this.animStyle,
    required this.visualStyle,
    required this.themeBase,
  });

  @override
  Widget build(BuildContext context) {
    final renderer = getRenderer(animStyle);
    return renderer.buildWidget(
        context, content, isNew, animDur, visualStyle, themeBase);
  }
}
