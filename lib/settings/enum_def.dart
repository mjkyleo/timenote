// 时笺 TimeNote 全局枚举定义
library;

/// 底色模式：黑 / 白
enum ThemeBase { light, dark }

/// 翻页动画样式（5 种）
enum FlipAnimStyle {
  flipCard, // 经典机场翻牌
  pageCurl, // 书页卷曲
  slideFlip, // 滑动翻页
  segmentFlip, // 分段碎裂
  fadeFlip, // 渐变溶解
}

/// 计时画面数字样式（10 种）
enum ClockVisualStyle {
  appleMinimal, // 苹果极简
  retroMechanical, // 复古机械粗牌
  softRoundCard, // 软圆角卡片
  narrowHighContrast, // 高对比窄版
  handwritten, // 手写文艺
  boldPower, // 粗黑力量体
  thinSourceHan, // 纤细思源
  deyiTrend, // 得意黑潮流
  dotMatrix, // 点阵风
  hollowStroke, // 镂空描边
}

/// 翻页动画速度
enum AnimSpeed { slow, normal, fast }

/// 时钟工作模式
enum ClockWorkMode { realtime, countdown }
