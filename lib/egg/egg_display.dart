import 'package:flutter/material.dart';
import '../settings/enum_def.dart';
import '../theme/ui_style.dart';

/// 倒计时结束彩蛋：时钟区域整体替换为文案（无弹窗）
class EggDisplay extends StatelessWidget {
  final String text;
  final ThemeBase themeBase;

  const EggDisplay({super.key, required this.text, required this.themeBase});

  @override
  Widget build(BuildContext context) {
    final tokens =
        UiScope.maybeOf(context) ?? UiTokens.classic(themeBase == ThemeBase.dark);
    final color = tokens.fg;
    final hintColor = tokens.muted;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 长文案缩一点并允许滚动，避免截断或溢出
          final ratio = constraints.maxWidth;
          final fontSize = (ratio / 18).clamp(18.0, 40.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '专注结束',
                  style: TextStyle(
                      fontSize: fontSize * 0.45, color: hintColor, letterSpacing: 2),
                ),
                SizedBox(height: fontSize * 0.6),
                Expanded(
                  child: SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: fontSize,
                            color: color,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: fontSize * 0.6),
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
}
