// 时笺 TimeNote 全局枚举定义
library;

import 'dart:ui' show Brightness;

/// 底色模式：跟随系统 / 黑 / 白
///
/// Apple 不鼓励 App 自备外观开关（dark-mode.md），但待机钟属于「让 UI 退到画面之后」
/// 的沉浸场景，同一页给了常驻暗档的例外。所以三档都在：默认跟随系统，
/// 想钉死黑白的人仍然钉得死。
enum ThemeBase { system, light, dark }

String themeBaseName(ThemeBase b) {
  switch (b) {
    case ThemeBase.system:
      return '跟随系统';
    case ThemeBase.light:
      return '亮色（白）';
    case ThemeBase.dark:
      return '暗色（黑）';
  }
}

/// 设置里存的是「用户选的那一档」，可能是跟随系统；渲染层要的是这一刻到底黑不黑。
/// 用 [platform]（Material 已解析过的亮度）收口，避免每处再判一遍枚举。
ThemeBase resolveThemeBase(ThemeBase choice, Brightness platform) => choice ==
        ThemeBase.system
    ? (platform == Brightness.dark ? ThemeBase.dark : ThemeBase.light)
    : choice;

/// 翻页动画样式（24 种 + 混合轮换）
///
/// 取自动效实验室的 32 件样本：翻折 fold / 位移 roll / 遮罩 mask / 形变 morph /
/// 碎片 grain / 光学 light 六类，标签按实验室原样保留（仅收尾、高频慎用、可选主题）。
/// 机械仪表（七段管/表盘/步进）与进度组件（aux 8 件）另批实现，
/// 顺序按实验室分类排，[FlipAnimStyle.autoMix] 固定在末尾。
enum FlipAnimStyle {
  // ---- 翻折 fold ----
  flipCard, // 01 机械翻牌（真·split-flap，绕中缝铰链）
  pageCurl, // 02 单侧书页翻页（绕左缘竖轴）
  diagFold, // 03 对角斜折（绕 (1,1,0) 轴掀起）
  bounceFlip, // 04 弹跳翻牌（翻折收尾多一次落位回弹）
  cardFlip, // 24 整卡翻面（绕中心竖轴，双面互斥）
  // ---- 位移 roll ----
  tickerRoll, // 05 滚筒里程表（直线下滑 + 运动模糊 + 暗角）★默认
  slideAcross, // 06 横向滑移（左出右入，交叠 30%）
  cascade, // 07 级联错位（逐格错开落下）
  // ---- 遮罩 mask ----
  blind, // 08 百叶窗擦除（7 条横向带依次收起）
  iris, // 09 径向光圈（圆形遮罩从中心张开）
  polygon, // 22 多边形遮罩（菱形冲出）
  // ---- 形变 morph ----
  crossfade, // 17 交叉淡入（兜底：低端机/省电模式降到这里）
  blurFocus, // 18 模糊对焦（虚化散掉再对上焦）
  jelly, // 16 果冻挤压（压扁的那一帧换数再弹回）
  // ---- 碎片 grain ----
  pixelShuffle, // 13 像素洗牌（切成方格打散再各自归位）
  particleScatter, // 12 粒子聚散（旧数字吹散，新数字聚回）仅收尾
  shardBurst, // 14 三角碎片（三角碎片飞散再拼回）仅收尾
  // ---- 光学 light ----
  fluidDissolve, // 10 流体溶解（逐行拉成墨）高频慎用
  liquidGlass, // 11 液态玻璃折射（晃动厚玻璃 + 高光扫过）高频慎用
  crtScan, // 23 CRT 扫描线（换数时横向抖一下 + 行扫描覆层）
  // ---- 本批之前就有 ----
  slideFlip, // 下方推入并过冲
  segmentFlip, // 分段碎裂（带倾角砸下）
  fadeFlip, // 渐变溶解
  dropSettle, // 落体回弹
  autoMix, // 混合轮换（每次翻页换一种）
}

/// 底层进度组件（动效实验室 aux 8 件 + 不使用）
///
/// 它们不是「数字怎么换」，而是「还剩多少」的体感层：默认 [ProgressDecor.none]
/// 沿用那根细进度条，选中其中一种时用它顶掉进度条（同一个信息不画两遍）。
/// [ProgressDecor.sky] 是唯一的环境层，不顶掉进度条，只垫在整屏底下。
enum ProgressDecor {
  none, // 不用（保留底部细进度条）
  hourglass, // 沙漏：沙量映射剩余时长
  water, // 水位填充：两条正弦叠出水面
  ring, // 环形进度：外圈按剩余比例填充
  spiral, // 螺旋进度：一圈圈往外长
  led, // 灯带进度：22 颗灯珠依次熄灭
  annualRings, // 年轮圆盘：五圈同心逐层点亮
  candle, // 蜡烛燃烧：越烧越短，火苗轻抖
  sky, // 日出日落：背景和太阳位置随剩余时间推移
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

/// 倒计时归零后的行为（三档，取代原来的「彩蛋开关」）
///
/// [stayZero] 留在 `00:00:00` 等用户自己点；
/// [autoRestart] 用上一次选的时长直接重开，适合一轮接一轮地坐；
/// [showEgg] 整屏换成随机文案，收尾回到实时时钟。
enum FinishBehavior { stayZero, autoRestart, showEgg }

/// 数字底板外框
///
/// 底板的填充与光影仍归界面风格令牌管，本档只覆盖描边那一层：
/// [follow] 风格自带几细是几细（没给就不画）；[none] 一律去掉；
/// [thin] 与 [thick] 一律画上，风格没给描边色时取前景色的淡版。
enum PlateFrame { follow, none, thin, thick }
