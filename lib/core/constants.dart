import 'package:flutter/services.dart';
import '../settings/enum_def.dart';

/// 全局常量
class AppConstants {
  const AppConstants._();

  /// 全应用锁定横屏（平板待机时钟场景）
  static const List<DeviceOrientation> landscapeOrientations = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  /// 倒计时快捷预设（分钟）
  static const List<int> countdownPresets = [5, 10, 25, 45];

  /// 自定义倒计时的允许范围（分钟）
  static const int minCountdownMinutes = 1;
  static const int maxCountdownMinutes = 600;

  /// 彩蛋文案停留时长（秒）
  static const int eggStaySeconds = 5;

  /// 数字基准字号（渲染时由 FittedBox 按可用区域等比缩放）
  static const double baseFontSize = 100;

  /// 翻页动画速度 → 时长映射
  static const Map<AnimSpeed, Duration> animDurationMap = {
    AnimSpeed.slow: Duration(milliseconds: 900),
    AnimSpeed.normal: Duration(milliseconds: 450),
    AnimSpeed.fast: Duration(milliseconds: 220),
  };

  /// 数字样式 → 字体 family 映射
  /// 说明：字体文件放入 assets/fonts 并在 pubspec 声明后生效；
  /// 未打包时返回 null，Flutter 自动回退系统字体，不影响运行。
  static const Map<ClockVisualStyle, String> styleFontMap = {
    ClockVisualStyle.appleMinimal: 'SourceHanSansCN',
    ClockVisualStyle.retroMechanical: 'ZCOOLKuaiLe',
    ClockVisualStyle.softRoundCard: 'SourceHanSansCN',
    ClockVisualStyle.narrowHighContrast: 'SourceHanSansCN',
    ClockVisualStyle.handwritten: 'CangErYuYang',
    ClockVisualStyle.boldPower: 'ZCOOLKuaiLe',
    ClockVisualStyle.thinSourceHan: 'SourceHanSansCN',
    ClockVisualStyle.deyiTrend: 'DeYiHei',
    ClockVisualStyle.dotMatrix: 'AlibabaPuHuiTi',
    ClockVisualStyle.hollowStroke: 'SourceHanSansCN',
  };

  static Duration animDurationOf(AnimSpeed speed) =>
      animDurationMap[speed] ?? const Duration(milliseconds: 450);

  static String? fontOf(ClockVisualStyle style) => styleFontMap[style];
}
