import 'package:flutter/material.dart';
import '../settings/enum_def.dart';
import '../theme/ui_style.dart';

/// 倒计时结束彩蛋：时钟区域整体替换为文案（无弹窗）
class EggDisplay extends StatelessWidget {
  final String text;
  final ThemeBase themeBase;

  const EggDisplay({super.key, required this.text, required this.themeBase});

  /// 渲染出来缩到这一档还放不下就交回滚动：再小待机时根本读不动，宁可让人滑
  static const double minFont = 14;

  @override
  Widget build(BuildContext context) {
    final tokens =
        UiScope.maybeOf(context) ?? UiTokens.classic(themeBase == ThemeBase.dark);
    final color = tokens.fg;
    final hintColor = tokens.muted;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final base = (constraints.maxWidth / 18).clamp(18.0, 40.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '专注结束',
                  style: TextStyle(
                      fontSize: base * 0.45, color: hintColor, letterSpacing: 2),
                ),
                SizedBox(height: base * 0.6),
                Expanded(
                  // 又一层 LayoutBuilder：文案区真正能占的高宽只有这里知道
                  child: LayoutBuilder(builder: (context, box) {
                    final wrapWidth = box.maxWidth.clamp(0.0, 900.0);
                    final style = TextStyle(
                        color: color, height: 1.6, fontWeight: FontWeight.w500);
                    final fontSize = _fitFontSize(text, style, wrapWidth,
                        box.maxHeight, base, MediaQuery.textScalerOf(context));
                    return SingleChildScrollView(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Text(
                            text,
                            textAlign: TextAlign.center,
                            style: style.copyWith(fontSize: fontSize),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                SizedBox(height: base * 0.6),
                Text(
                  '轻触任意处返回时钟',
                  style: TextStyle(fontSize: 13, color: hintColor),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 从基准字号一档档往下试，取「整块文案能在可用高宽里放完」的最大那一档。
  ///
  /// 蛋屏是待机屏：倒计时结束后没人会去滑动屏幕找后半句，所以长文案要靠缩字号
  /// 而不是靠滚动整块看完。实测三类都栽过——一整段带空格的英文、中英混排夹 URL、
  /// 手机横屏 914×411 上 150 字的中文，基准字号（按屏宽算，横屏能到 40）都会把
  /// 文本顶出可视区两三倍高。
  /// 量宽度同样要紧：不可断行的长 URL 会在斜杠处折行，光管高度拦不住横向溢出。
  ///
  /// `scaler` 必须一起喂给 TextPainter：`Text` 显示时会自己乘系统字号，
  /// TextPainter 却不乘。少了这一参数，用户在系统里把字体拉到最大（Android
  /// 上限 2.0x）后，这里按「没缩放」判定放得下、实际渲染出来顶出可视区一倍多。
  ///
  /// 可读下限 [minFont] 管的是「渲染出来多大」，不是 style 里那个数字：2x 时
  /// 按 style=14 收手等于把下限抬到 28，横屏窄高（914×411）上整段英文正好卡死。
  double _fitFontSize(String text, TextStyle style, double maxWidth,
      double maxHeight, double start, TextScaler scaler) {
    var size = start;
    while (true) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: null,
      )..layout(maxWidth: maxWidth);
      final fits = painter.height <= maxHeight && painter.width <= maxWidth;
      painter.dispose();
      // 收手条件看的是缩放后的实际字号：style=14 在 2x 系统里是 28，
      // 按 style 判就等于把可读下限抬高一倍，长文案会卡在视口外。
      if (fits || scaler.scale(size) <= minFont) return size;
      size *= 0.88;
    }
  }
}
