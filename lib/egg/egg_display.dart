import 'package:flutter/material.dart';
import '../settings/enum_def.dart';

/// 倒计时结束彩蛋：时钟区域整体替换为文案（无弹窗）
class EggDisplay extends StatelessWidget {
  final String text;
  final ThemeBase themeBase;

  const EggDisplay({super.key, required this.text, required this.themeBase});

  @override
  Widget build(BuildContext context) {
    final color = themeBase == ThemeBase.dark ? Colors.white : Colors.black;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 36,
            color: color,
            height: 1.6,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
