import '../settings/enum_def.dart';

/// 全局常量
class AppConstants {
  /// 倒计时快捷预设（分钟）
  static const List<int> countdownPresets = [5, 10, 25, 45];

  /// 彩蛋文案停留时长（秒）
  static const int eggStaySeconds = 5;

  /// 翻页动画速度 → 时长映射
  static Map<AnimSpeed, Duration> animDurationMap = {
    AnimSpeed.slow: const Duration(milliseconds: 900),
    AnimSpeed.normal: const Duration(milliseconds: 450),
    AnimSpeed.fast: const Duration(milliseconds: 220),
  };

  /// 数字样式 → 字体 family 映射
  /// 说明：字体文件放入 assets/fonts 并在 pubspec 声明后生效；
  /// 未安装字体时 Flutter 自动回退默认字体，不影响运行。
  static Map<ClockVisualStyle, String> styleFontMap = {
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
}
