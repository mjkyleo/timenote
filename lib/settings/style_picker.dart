import 'package:flutter/material.dart';
import '../settings/enum_def.dart';

/// 风格 / 选项卡片（选中态高亮边框）
Widget buildStyleItem(
  BuildContext context,
  String label,
  bool selected,
  VoidCallback onTap,
) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? Colors.blueAccent : Colors.grey.shade400,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
        color: selected ? Colors.blue.withValues(alpha: 0.08) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    ),
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
