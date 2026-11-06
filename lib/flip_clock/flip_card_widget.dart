import 'package:flutter/material.dart';
import 'flip_renderer.dart';
import '../core/constants.dart';
import '../settings/enum_def.dart';
import '../theme/ui_style.dart';

/// 翻页卡片：负责自适应尺寸、底板与逐格翻页
class FlipCardWidget extends StatelessWidget {
  final String content;
  final Duration animDur;
  final FlipAnimStyle animStyle;
  final ClockVisualStyle visualStyle;
  final ThemeBase themeBase;
  final PlateFrame plateFrame;

  const FlipCardWidget({
    super.key,
    required this.content,
    required this.animDur,
    required this.animStyle,
    required this.visualStyle,
    required this.themeBase,
    this.plateFrame = PlateFrame.follow,
  });

  @override
  Widget build(BuildContext context) {
    final look = appearanceFor(visualStyle);
    final isDark = themeBase == ThemeBase.dark;
    // 系统「减弱动态效果」：翻页是本 App 唯一自动、反复的动画（每分钟自己走一次），
    // Apple 要求这种情况换成不位移的淡入，而不是继续播
    // （accessibility.md › Cognitive、motion.md › Make motion optional）
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final motion = reduceMotion
        ? const (FlipAnimStyle.crossfade, Duration(milliseconds: 150))
        : (animStyle, animDur);
    // 没有 UiScope（单独 pump 本组件做测试）时退回本组件自己的黑白底，
    // 而不是按 Theme.brightness 猜，否则会跟传入的 themeBase 打架
    final tokens =
        UiScope.maybeOf(context) ?? UiTokens.classic(isDark);
    final foreground = tokens.fg;
    final style = clockTextStyle(
      look: look,
      foreground: foreground,
      fontFamily: AppConstants.fontOf(visualStyle),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 数字占可用高度的 70%，其余交给 FittedBox 按宽度等比缩放
        final maxHeight = constraints.maxHeight;
        final boxHeight = maxHeight.isFinite ? maxHeight * 0.7 : null;
        return SizedBox(
          height: boxHeight,
          width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
          child: FittedBox(
            fit: BoxFit.contain,
            child: RepaintBoundary(
              // 拆成一格一格之后逐字朗读会变成「1、0、冒号、0…」，
              // 所以整块牌子对外只报一个完整时间
              child: Semantics(
                label: content,
                child: ExcludeSemantics(
                  child: _Plate(
                    look: look,
                    tokens: tokens,
                    plateFrame: plateFrame,
                    plateColor:
                        foreground.withValues(alpha: look.plateOpacity),
                    seamColor: isDark
                        ? Colors.white.withValues(alpha: 0.28)
                        : Colors.black.withValues(alpha: 0.22),
                    child: _FlipBoard(
                      content: content,
                      animDur: motion.$2,
                      animStyle: motion.$1,
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 数字底板 + 可选翻页中缝
///
/// 底板的「环境」（填充/描边/光影/圆角）来自界面风格令牌；令牌没提供装饰时
/// （classic）完全退回数字样式自己的 plateOpacity/radius，与历史行为一致。
class _Plate extends StatelessWidget {
  final ClockLook look;
  final UiTokens tokens;
  final PlateFrame plateFrame;
  final Color plateColor;
  final Color seamColor;
  final Widget child;

  const _Plate({
    required this.look,
    required this.tokens,
    required this.plateFrame,
    required this.plateColor,
    required this.seamColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // 界面风格给了底板但数字样式没留内边距时，兜一点「土」，否则字会贴边
    final plain = look.padding == EdgeInsets.zero;
    final pad = plain && tokens.hasPlateDecor
        ? const EdgeInsets.symmetric(horizontal: 36, vertical: 18)
        : look.padding;
    Widget result = Padding(padding: pad, child: child);
    if (look.seam) {
      result = Stack(
        fit: StackFit.passthrough,
        children: [
          result,
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(height: 2, color: seamColor),
              ),
            ),
          ),
        ],
      );
    }
    final fill = tokens.plateFill ??
        (look.plateOpacity > 0 ? plateColor : null);
    final (stroke, strokeWidth) = resolvePlateFrame(plateFrame, tokens);
    if (fill == null && stroke == null && tokens.plateShadow.isEmpty) {
      return result;
    }
    return Container(
      // 有底板装饰时才存在这个节点，测试用它验证「界面风格真的画到了数字上」
      key: const Key('flip-plate'),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(tokens.radiusOr(look.radius)),
        border: stroke == null
            ? null
            : Border.all(color: stroke, width: strokeWidth),
        boxShadow:
            tokens.plateShadow.isEmpty ? null : tokens.plateShadow,
      ),
      child: result,
    );
  }
}

/// 外框档位 → 实际描边（颜色 + 线宽）。
///
/// 只管描边这一层：底板的填充、圆角、光影仍由界面风格令牌决定，两层不打架。
/// [PlateFrame.thin]/[PlateFrame.thick] 在风格没给描边色时退成前景的淡版，
/// 否则在纯黑/纯白底上会画出一条生硬的原色线。
(Color?, double) resolvePlateFrame(PlateFrame frame, UiTokens tokens) {
  switch (frame) {
    case PlateFrame.follow:
      return (tokens.plateStroke, tokens.plateStrokeWidth);
    case PlateFrame.none:
      return (null, tokens.plateStrokeWidth);
    case PlateFrame.thin:
    case PlateFrame.thick:
      final color = tokens.plateStroke ?? tokens.fg.withValues(alpha: 0.42);
      return (color, frame == PlateFrame.thin ? 1.5 : 3);
  }
}

/// 逐格翻页板：一个字符一张牌子，只有真的变了的格子才翻
///
/// 整串一起翻是「生硬」的另一半根因：秒个位每秒都变，整块板子跟着一起动，
/// 看起来是屏幕在抽而不是数字在翻。
class _FlipBoard extends StatefulWidget {
  final String content;
  final Duration animDur;
  final FlipAnimStyle animStyle;
  final TextStyle style;

  const _FlipBoard({
    required this.content,
    required this.animDur,
    required this.animStyle,
    required this.style,
  });

  @override
  State<_FlipBoard> createState() => _FlipBoardState();
}

class _FlipBoardState extends State<_FlipBoard> {
  /// 累计翻过几轮；混合轮换用它把同一轮里的不同格子错开到不同动画
  int _tick = 0;

  @override
  void didUpdateWidget(_FlipBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) _tick++;
  }

  FlipAnimStyle _styleAt(int index) =>
      widget.animStyle == FlipAnimStyle.autoMix
          ? flipMixCycle[(_tick + index) % flipMixCycle.length]
          : widget.animStyle;

  @override
  Widget build(BuildContext context) {
    final chars = widget.content.split('');
    final cellWidth = _digitCellWidth();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, char) in chars.indexed)
          _FlipCell(
            key: ValueKey('cell$index'),
            char: char,
            style: widget.style,
            animDur: widget.animDur,
            index: index,
            cellCount: chars.length,
            minWidth: _isDigit(char) ? cellWidth : 0,
            pick: () => _styleAt(index),
          ),
      ],
    );
  }

  /// 比例字体里 '0' 通常最宽，用它的宽度当格宽下限
  double _digitCellWidth() {
    final painter = TextPainter(
      text: TextSpan(text: '0', style: widget.style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

bool _isDigit(String char) {
  final code = char.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

/// 单格翻页：自己的控制器 + 上一次停住的字符，互不干扰
class _FlipCell extends StatefulWidget {
  final String char;
  final TextStyle style;
  final Duration animDur;

  /// 这一格在整串里的序号与总格数（级联错位用它算起跑偏移）
  final int index;
  final int cellCount;

  /// 格子宽度下限（数字格锁宽，符号格传 0）
  final double minWidth;

  /// 开始翻页时才决定用哪种动画（混合轮换每轮都不同）
  final FlipAnimStyle Function() pick;

  const _FlipCell({
    super.key,
    required this.char,
    required this.style,
    required this.animDur,
    required this.index,
    required this.cellCount,
    required this.minWidth,
    required this.pick,
  });

  @override
  State<_FlipCell> createState() => _FlipCellState();
}

class _FlipCellState extends State<_FlipCell>
    with SingleTickerProviderStateMixin {
  /// 级联错位的总错开量占基础时长的比例。
  ///
  /// 实验室原样是「每位错开 78ms」，那是四位数字的量；这里是 HH:MM:SS 八格，
  /// 78ms × 7 = 546ms 会让秒位贴着下一次变化才落位，所以改成按时长比例摊。
  static const double _spreadRatio = 0.4;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.animDur,
    value: 1,
  );

  /// 上一次翻完停在哪个字符：旧牌按它画，中途连续变化也不会串位
  late String _shown;
  Widget? _outgoing;
  late FlipAnimStyle _flipStyle;

  /// 这一格的起跑偏移（占本次时长的比例），只有级联一类会用到
  double _delay = 0;

  @override
  void initState() {
    super.initState();
    // 必须在 initState 里赋值，不能写成 `late String _shown = widget.char`：
    // late 字段的初始化表达式要到第一次「读」时才执行，而第一次读发生在
    // didUpdateWidget，那时 widget 已经是新数字了，旧牌会画成新数字，
    // 第一次翻页就变成「新数字自己翻自己」
    _shown = widget.char;
    _flipStyle = widget.pick();
    _controller.addStatusListener((status) {
      // 收尾就把旧牌摘掉：留着的话下一次翻页会把两帧前的字符当成旧牌
      if (status == AnimationStatus.completed && _outgoing != null) {
        setState(() => _outgoing = null);
      }
    });
  }

  @override
  void didUpdateWidget(_FlipCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 时长可能被设置页改过，即使这格没变也要跟上；变了才重新算错开量
    _controller.duration = widget.animDur;
    _delay = 0;
    if (oldWidget.char == widget.char) return;
    _flipStyle = widget.pick();
    _applyTiming(_flipStyle);
    setState(() {
      _outgoing = _glyph(_shown);
      _shown = widget.char;
    });
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 按本格选中的动画决定要不要拉长时长并推迟起跑
  void _applyTiming(FlipAnimStyle style) {
    if (!staggeredStyles.contains(style) || widget.cellCount <= 1) {
      _controller.duration = widget.animDur;
      _delay = 0;
      return;
    }
    final stepUs = (widget.animDur.inMicroseconds * _spreadRatio /
            (widget.cellCount - 1))
        .round();
    final total = widget.animDur + Duration(microseconds: stepUs * widget.index);
    _controller.duration = total;
    _delay = (stepUs * widget.index) / total.inMicroseconds;
  }

  Widget _glyph(String text) => Text(
        text,
        maxLines: 1,
        // 锁宽后 glyph 要在格子里居中，否则上半/下半和整张会错开半格
        textAlign: TextAlign.center,
        style: widget.style,
      );

  @override
  Widget build(BuildContext context) {
    final current = _glyph(widget.char);
    final outgoing = _outgoing;
    Widget? face;
    if (outgoing != null) {
      face = AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => getRenderer(_flipStyle).transition(
          newChild: current,
          oldChild: outgoing,
          t: _controller.value,
          delay: _delay,
        ),
      );
      // 会把牌子推出格子的动画必须逐格裁，否则数字会糊到相邻格和底板外面
      if (offCellStyles.contains(_flipStyle)) {
        face = ClipRect(child: face);
      }
    }
    final content = face ?? current;
    if (widget.minWidth <= 0) return content;
    // 格宽锁到最宽的那位数字：换成窄的「1」时整排牌子不会左右抖
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: widget.minWidth),
      child: content,
    );
  }
}
