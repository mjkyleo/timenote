import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../flip_clock/flip_renderer.dart';
import '../settings/enum_def.dart';

/// 选项卡片（选中态高亮边框）
///
/// [labelStyle] 传入某个数字样式的文字样式时，标签本身就用该样式渲染，
/// 于是 10 种风格在选择阶段就已经可辨认。
Widget buildStyleItem(
  BuildContext context,
  String label,
  bool selected,
  VoidCallback onTap, {
  TextStyle? labelStyle,
}) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.all(4),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.grey.shade400,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: (labelStyle ?? theme.textTheme.bodyMedium)
                  ?.copyWith(fontWeight: selected ? FontWeight.w700 : null),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 供选择器使用的标签文字样式（比主屏字号小，描边按比例收细）
TextStyle labelStyleFor(ClockVisualStyle style, Color foreground) {
  final look = appearanceFor(style);
  return clockTextStyle(
    look: look,
    foreground: foreground,
    fontFamily: AppConstants.fontOf(style),
    fontSize: 22,
  );
}

String visualStyleName(ClockVisualStyle s) {
  switch (s) {
    case ClockVisualStyle.appleMinimal:
      return '苹果极简';
    case ClockVisualStyle.retroMechanical:
      return '复古机械粗牌';
    case ClockVisualStyle.softRoundCard:
      return '软圆角卡片';
    case ClockVisualStyle.narrowHighContrast:
      return '高对比窄版';
    case ClockVisualStyle.handwritten:
      return '手写文艺';
    case ClockVisualStyle.boldPower:
      return '粗黑力量体';
    case ClockVisualStyle.thinSourceHan:
      return '纤细思源';
    case ClockVisualStyle.deyiTrend:
      return '得意黑潮流';
    case ClockVisualStyle.dotMatrix:
      return '点阵风';
    case ClockVisualStyle.hollowStroke:
      return '镂空描边';
  }
}

String flipAnimName(FlipAnimStyle s) {
  switch (s) {
    case FlipAnimStyle.flipCard:
      return '经典机场翻牌';
    case FlipAnimStyle.pageCurl:
      return '书页卷曲翻页';
    case FlipAnimStyle.slideFlip:
      return '滑动翻页';
    case FlipAnimStyle.segmentFlip:
      return '分段碎裂翻';
    case FlipAnimStyle.fadeFlip:
      return '渐变溶解翻';
  }
}

String speedName(AnimSpeed s) {
  switch (s) {
    case AnimSpeed.slow:
      return '慢';
    case AnimSpeed.normal:
      return '标准';
    case AnimSpeed.fast:
      return '快';
  }
}
