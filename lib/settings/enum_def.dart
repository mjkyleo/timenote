// 时笺 TimeNote 全局枚举定义
library;

/// 底色模式：黑 / 白
enum ThemeBase { light, dark }

/// 翻页动画样式（8 种，其中 [FlipAnimStyle.autoMix] 会在其余 7 种之间轮换）
enum FlipAnimStyle {
  flipCard, // 经典机场翻牌（真·split-flap，绕中缝铰链）
  pageCurl, // 书页卷曲
  slideFlip, // 滑动翻页
  segmentFlip, // 分段碎裂
  fadeFlip, // 渐变溶解
  tickerRoll, // 滚筒走字
  dropSettle, // 落体回弹
  autoMix, // 混合轮换（每次翻页换一种）
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

/// 界面风格（整层「环境」设计令牌：背景 / 数字底板光影 / 控件 / 标签排版）
///
/// [classic] 是黑白底 + 无装饰，等价于本层引入之前的样子；
/// 其余 10 套取自 https://luckymaomi.github.io/ui/styles/ 的实测 token。
/// 数字的字形仍由 [ClockVisualStyle] 决定，两者正交。
enum UiStyle {
  classic, // 无装饰（原样）
  editorial, // 编辑部：暖纸白 + 细线，禁阴影圆角
  neumorphism, // 软胶：同色底 + 一明一暗双投影
  bentoGrid, // 便当格：小圆角卡片 + 统一间隙
  naturalOrganic, // 自然有机：土色 + 颗粒 + 柔形体
  retroVintage, // 复古印刷：粗双线框 + 纸纹 + 大写疏排
  darkMode, // 暗色分层：深蓝板 + 上缘内高光 + 深阴影
  macosVibrancy, // 毛玻璃分层：半透明面板 + 1px 亮线，禁渐变
  surrealism, // 超现实：双色熔接渐变 + 光晕
  gothicLolita, // 哥特洛丽塔：黑紫渐变 + 装饰角 + 衬线疏排
  visualNovel, // 视觉小说：天空渐变 + 半透明对话框面板
}

/// 时钟工作模式
enum ClockWorkMode { realtime, countdown }
