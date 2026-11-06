import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../flip_clock/flip_renderer.dart';
import '../theme/ui_style.dart';
import '../settings/enum_def.dart';

/// 选项卡片（选中态高亮边框）
///
/// [labelStyle] 传入某个数字样式的文字样式时，标签本身就用该样式渲染，
/// 于是 10 种风格在选择阶段就已经可辨认。
/// [swatch] 传入某套界面风格的令牌时，左侧画一块迷你底板，
/// 让「背景 + 底板光影 + 强调色」在选择阶段就能直接比对，不必靠名字想象。
Widget buildStyleItem(
  BuildContext context,
  String label,
  bool selected,
  VoidCallback onTap, {
  TextStyle? labelStyle,
  UiTokens? swatch,
}) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.all(4),
    child: InkWell(
      // 命中区撑到 44 以上（原来到 38 就停了），触感与点击同时给反馈
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            if (swatch != null) ...[
              _UiSwatch(tokens: swatch),
              const SizedBox(width: 8),
            ],
            if (selected) ...[
              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
            ],
            // 窄屏 + 大字号数字样式（镂空描边/纤细思源的 label 用自己的样式渲染）
            // 时，芯片会比可用宽还宽；不兜住就是一排黄黑溢出条
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (labelStyle ?? theme.textTheme.bodyMedium)
                    ?.copyWith(fontWeight: selected ? FontWeight.w700 : null),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 一枚 34×22 的迷你预览：底 + 数字底板 + 强调色点
class _UiSwatch extends StatelessWidget {
  final UiTokens tokens;

  const _UiSwatch({required this.tokens});

  @override
  Widget build(BuildContext context) {
    final gradient = tokens.bgGradient;
    return Container(
      width: 34,
      height: 22,
      decoration: BoxDecoration(
        gradient: gradient != null && gradient.length >= 2
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradient)
            : null,
        color: gradient != null && gradient.length >= 2 ? null : tokens.bg,
        border: Border.all(color: tokens.muted.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Container(
          width: 20,
          height: 12,
          decoration: BoxDecoration(
            color: tokens.plateFill ?? tokens.fg.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(tokens.plateRadius ?? 2),
            border: tokens.plateStroke == null
                ? null
                : Border.all(
                    color: tokens.plateStroke!,
                    width: tokens.plateStrokeWidth > 2
                        ? 1.5
                        : tokens.plateStrokeWidth),
            // 阴影按 1/4 缩放，否则 16px 模糊在一枚小色块上会糊成一团
            boxShadow: [
              for (final s in tokens.plateShadow.take(2))
                BoxShadow(
                  color: s.color,
                  offset: s.offset / 4,
                  blurRadius: s.blurRadius / 4,
                ),
            ],
          ),
        ),
      ),
    );
  }
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
    case FlipAnimStyle.diagFold:
      return '对角斜折';
    case FlipAnimStyle.bounceFlip:
      return '弹跳翻牌';
    case FlipAnimStyle.cardFlip:
      return '整卡翻面';
    case FlipAnimStyle.tickerRoll:
      return '滚筒走字';
    case FlipAnimStyle.slideAcross:
      return '横向滑移';
    case FlipAnimStyle.cascade:
      return '级联错位';
    case FlipAnimStyle.blind:
      return '百叶窗擦除';
    case FlipAnimStyle.iris:
      return '径向光圈';
    case FlipAnimStyle.polygon:
      return '多边形遮罩';
    case FlipAnimStyle.crossfade:
      return '交叉淡入';
    case FlipAnimStyle.blurFocus:
      return '模糊对焦';
    case FlipAnimStyle.jelly:
      return '果冻挤压';
    case FlipAnimStyle.pixelShuffle:
      return '像素洗牌';
    case FlipAnimStyle.particleScatter:
      return '粒子聚散';
    case FlipAnimStyle.shardBurst:
      return '三角碎片';
    case FlipAnimStyle.fluidDissolve:
      return '流体溶解';
    case FlipAnimStyle.liquidGlass:
      return '液态玻璃折射';
    case FlipAnimStyle.crtScan:
      return 'CRT 扫描线';
    case FlipAnimStyle.slideFlip:
      return '下方推入';
    case FlipAnimStyle.segmentFlip:
      return '分段碎裂';
    case FlipAnimStyle.fadeFlip:
      return '渐变溶解';
    case FlipAnimStyle.dropSettle:
      return '落体回弹';
    case FlipAnimStyle.autoMix:
      return '混合轮换';
  }
}

/// 24 种翻页动画 + 混合轮换，按实验室原样分成可扫读的小类。
///
/// 设置页原先把 25 枚芯片摊成一面墙，找「滚筒走字」得逐行读——这里按类分组，
/// 顺序就是 [FlipAnimStyle] 的声明顺序。新增动画必须在这里登记，
/// 否则 `test/flip_rendering_test.dart` 的分类完整性用例会红（漏登记 = 设置页里没有这一项）。
const Map<String, List<FlipAnimStyle>> flipAnimFamilies = {
  '翻折': [
    FlipAnimStyle.flipCard,
    FlipAnimStyle.pageCurl,
    FlipAnimStyle.diagFold,
    FlipAnimStyle.bounceFlip,
    FlipAnimStyle.cardFlip,
  ],
  '位移': [
    FlipAnimStyle.tickerRoll,
    FlipAnimStyle.slideAcross,
    FlipAnimStyle.cascade,
  ],
  '遮罩': [
    FlipAnimStyle.blind,
    FlipAnimStyle.iris,
    FlipAnimStyle.polygon,
  ],
  '形变': [
    FlipAnimStyle.crossfade,
    FlipAnimStyle.blurFocus,
    FlipAnimStyle.jelly,
  ],
  '碎片': [
    FlipAnimStyle.pixelShuffle,
    FlipAnimStyle.particleScatter,
    FlipAnimStyle.shardBurst,
  ],
  '光学': [
    FlipAnimStyle.fluidDissolve,
    FlipAnimStyle.liquidGlass,
    FlipAnimStyle.crtScan,
  ],
  '基础': [
    FlipAnimStyle.slideFlip,
    FlipAnimStyle.segmentFlip,
    FlipAnimStyle.fadeFlip,
    FlipAnimStyle.dropSettle,
  ],
  '混合': [FlipAnimStyle.autoMix],
};

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

String progressDecorName(ProgressDecor d) {
  switch (d) {
    case ProgressDecor.none:
      return '不使用';
    case ProgressDecor.hourglass:
      return '沙漏';
    case ProgressDecor.water:
      return '水位填充';
    case ProgressDecor.ring:
      return '环形进度';
    case ProgressDecor.spiral:
      return '螺旋进度';
    case ProgressDecor.led:
      return '灯带进度';
    case ProgressDecor.annualRings:
      return '年轮圆盘';
    case ProgressDecor.candle:
      return '蜡烛燃烧';
    case ProgressDecor.sky:
      return '日出日落（背景）';
  }
}

String finishBehaviorName(FinishBehavior b) {
  switch (b) {
    case FinishBehavior.stayZero:
      return '停留 00:00:00';
    case FinishBehavior.autoRestart:
      return '自动重新开始';
    case FinishBehavior.showEgg:
      return '弹彩蛋';
  }
}

String plateFrameName(PlateFrame f) {
  switch (f) {
    case PlateFrame.follow:
      return '跟随界面风格';
    case PlateFrame.none:
      return '去掉外框';
    case PlateFrame.thin:
      return '细外框';
    case PlateFrame.thick:
      return '粗外框';
  }
}

String appOrientationName(AppOrientation o) {
  switch (o) {
    case AppOrientation.landscape:
      return '横屏';
    case AppOrientation.portrait:
      return '竖屏';
  }
}
