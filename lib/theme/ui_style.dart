import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../settings/enum_def.dart';

/// 界面风格的设计令牌。
///
/// 分工：本层管「环境」（背景、数字底板的光影与描边、控件形状、标签排版、色板），
/// 数字本身的字形仍由 `ClockLook`（10 种数字样式）决定，两者正交。
///
/// 取色来源：https://luckymaomi.github.io/ui/styles/ 的 10 个风格页。
/// 页面直接给出的值记在 `page` 字段；页面只给了一版明暗时，另一版按
/// 同一套规则推导（反转纸/墨、或换同族深浅），记在 `derived` 字段。
@immutable
class UiTokens {
  final Color bg;
  final Color fg;
  final Color muted;
  final Color accent;

  /// 面板（抽屉 / 设置页 / 弹窗）底色；null 表示沿用 [bg]
  final Color? surface;

  /// 背景渐变 stops（>=2 时生效，纵向）
  final List<Color>? bgGradient;

  /// 纸纹噪点 / 背景柔形体 / 四角装饰括号
  final bool grain;
  final bool blobs;
  final bool ornaments;

  /// 数字底板：null 表示「不装饰」，此时底板完全由 ClockLook 决定（classic 的行为）
  final Color? plateFill;
  final Color? plateStroke;
  final double plateStrokeWidth;
  final double? plateRadius;
  final List<BoxShadow> plateShadow;

  /// 控件胶囊：半径 / 描边宽度 / 选中态是否用 [accent]
  final double chipRadius;
  final double chipStrokeWidth;
  final bool accentSelection;

  /// 分区标题与标签的排版
  final List<String>? labelFamilies;
  final double labelTracking;
  final bool labelUppercase;
  final bool labelItalic;

  /// 出处：page = 参考页原文给出的值，derived = 页面没给、按同规则推导的值
  final String provenance;

  const UiTokens({
    required this.bg,
    required this.fg,
    required this.muted,
    required this.accent,
    this.surface,
    this.bgGradient,
    this.grain = false,
    this.blobs = false,
    this.ornaments = false,
    this.plateFill,
    this.plateStroke,
    this.plateStrokeWidth = 1,
    this.plateRadius,
    this.plateShadow = const [],
    this.chipRadius = 999,
    this.chipStrokeWidth = 1,
    this.accentSelection = true,
    this.labelFamilies,
    this.labelTracking = 0,
    this.labelUppercase = false,
    this.labelItalic = false,
    this.provenance = '',
  });

  /// 未注入 UiScope 时（例如单独 pump 一个组件做测试）的兜底：无装饰
  factory UiTokens.classic(bool isDark) =>
      uiTokensFor(UiStyle.classic, isDark);

  bool get hasPlateDecor =>
      plateFill != null || plateStroke != null || plateShadow.isNotEmpty;

  /// 底板圆角：令牌优先，否则交回数字样式
  double radiusOr(double fallback) => plateRadius ?? fallback;

  /// 标签/小字用的可读前景：[muted] 在亮色风格里常常只有 2.6–4.4:1，
  /// 撑不起卡片标题这一层；这里按 WCAG 兜到 4.5:1，色相尽量不动。
  Color get labelInk => _ensureInk(muted);

  /// 强调色能当文字用的那一版：皮肤给的 accent 常常是装饰色
  /// （哥特暗 2.07:1、超现实亮 2.36:1），直接写进按钮标签就是读不见。
  Color get accentInk => _ensureInk(accent);

  Color _ensureInk(Color ink) {
    final key = '${ink.toARGB32()}|$hashCode';
    final hit = _inkCache[key];
    if (hit != null) return hit;
    // 文字既可能压在底色上，也可能压在面板/卡面上，取更吃亏的那个
    var out = ensureContrast(ink, bg);
    final s = surface;
    if (s != null) out = ensureContrast(out, compositeOver(s, bg));
    _inkCache[key] = out;
    return out;
  }
}

/// labelInk/accentInk 的记忆化表：全应用只有 22 套令牌，一次算完常驻，
/// 不必每帧重算 50 次明度插值。
final Map<String, Color> _inkCache = {};

/// WCAG 对比度：[ink] 允许带透明度，先合成到 [back] 上再算。
/// [back] 必须是真正画在屏幕上的那一层不透明色（面板色要先用
/// [compositeOver] 合到底色上），不然算的是「不存在的背景」。
double contrastRatio(Color ink, Color back) {
  final la = compositeOver(ink, back).computeLuminance();
  final lb = back.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 把 [ink] 推到与 [back] 至少 4.5:1：先合成透明度，不够再朝「亮底压黑、暗底提白」
/// 的方向逐步调明度，色相与饱和度尽量留住。返回不透明色，
/// 这样同一个标签压在底色和卡面上都是同一读数。
Color ensureContrast(Color ink, Color back, {double min = 4.5}) {
  final base = compositeOver(ink, back);
  if (contrastRatio(base, back) >= min) return base;
  final anchor = back.computeLuminance() > 0.5
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
  for (var t = 0.02; t <= 1.0001; t += 0.02) {
    final candidate = Color.lerp(base, anchor, t)!;
    if (contrastRatio(candidate, back) >= min) return candidate;
  }
  return anchor;
}

/// 把带透明度的 [fg] 压到不透明 [bg] 上，得到屏幕上真正的那一层颜色
Color compositeOver(Color fg, Color bg) {
  if (fg.a >= 1.0) return fg;
  // r/g/b 是 0–1 的 double（新版 Color API），不能当 0–255 取整
  final a = fg.a;
  return Color.from(
    alpha: 1.0,
    red: a * fg.r + (1 - a) * bg.r,
    green: a * fg.g + (1 - a) * bg.g,
    blue: a * fg.b + (1 - a) * bg.b,
  );
}

/// 无装饰：与引入本层之前的渲染路径完全一致
const UiTokens _classicLight = UiTokens(
  bg: Color(0xFFFFFFFF),
  fg: Color(0xFF000000),
  muted: Color(0x99000000),
  accent: Color(0xDE000000),
  provenance: '内置，无参考页',
);

const UiTokens _classicDark = UiTokens(
  bg: Color(0xFF000000),
  fg: Color(0xFFFFFFFF),
  muted: Color(0x99FFFFFF),
  accent: Color(0xDEFFFFFF),
  provenance: '内置，无参考页',
);

const UiTokens _editorialLight = UiTokens(
  bg: Color(0xFFF9F8F6),
  fg: Color(0xFF1C1C1C),
  muted: Color(0x991C1C1C),
  accent: Color(0xFF1C1C1C),
  plateStroke: Color(0x1F1C1C1C),
  plateRadius: 0,
  chipRadius: 0,
  labelFamilies: _serif,
  provenance: 'page: bg #F9F8F6 / ink #1C1C1C / radius 0 / 无阴影 / 细线；'
      '页面明确禁止阴影、渐变、圆角',
);

const UiTokens _editorialDark = UiTokens(
  bg: Color(0xFF1C1C1C),
  fg: Color(0xFFF9F8F6),
  muted: Color(0x99F9F8F6),
  accent: Color(0xFFF9F8F6),
  plateStroke: Color(0x1FF9F8F6),
  plateRadius: 0,
  chipRadius: 0,
  labelFamilies: _serif,
  provenance: 'derived: 纸/墨反转，其余规则同亮版',
);

const UiTokens _neumorphismLight = UiTokens(
  bg: Color(0xFFE0E5EC),
  surface: Color(0xFFE0E5EC),
  fg: Color(0xFF333333),
  muted: Color(0xFF6B7280),
  accent: Color(0xFF6D5DFC),
  plateFill: Color(0xFFE0E5EC),
  plateRadius: 20,
  plateShadow: [
    BoxShadow(color: Color(0xFFB8BCC2), offset: Offset(8, 8), blurRadius: 16),
    BoxShadow(color: Color(0xFFFFFFFF), offset: Offset(-8, -8), blurRadius: 16),
  ],
  chipRadius: 20,
  provenance: 'page: bg #e0e5ec / 文本 #333333 / 弱文本 #6b7280 / '
      '强调 #6d5dfc·#ff6b6b·#4ecdc4·#ffe66d / 外影 8px 8px 16px #b8bcc2 + '
      '-8px -8px 16px #ffffff / 无边框 / rounded-xl~2xl',
);

const UiTokens _neumorphismDark = UiTokens(
  bg: Color(0xFF23272E),
  surface: Color(0xFF23272E),
  fg: Color(0xFFE6E9EF),
  muted: Color(0xFF8D96A5),
  accent: Color(0xFF6D5DFC),
  plateFill: Color(0xFF23272E),
  plateRadius: 20,
  plateShadow: [
    BoxShadow(color: Color(0xFF14171B), offset: Offset(8, 8), blurRadius: 16),
    BoxShadow(color: Color(0xFF2F353F), offset: Offset(-8, -8), blurRadius: 16),
  ],
  chipRadius: 20,
  provenance: 'derived: 同色底 + 一暗一亮双影的明暗值换成深色档，强调色不变',
);

const UiTokens _bentoLight = UiTokens(
  bg: Color(0xFFFAFAFA),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF18181B),
  muted: Color(0xFF71717A),
  accent: Color(0xFF3B82F6),
  plateFill: Color(0xFFFFFFFF),
  plateStroke: Color(0xFFE4E4E7),
  plateRadius: 18,
  plateShadow: [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 4), blurRadius: 12)
  ],
  chipRadius: 14,
  provenance: 'page: 亮 #fafafa / 暗 #18181b / zinc-900·500 / '
      '强调 #3b82f6·#8b5cf6·#ec4899·#f97316 / rounded-xl~3xl / '
      'border-zinc-100~200 / shadow-sm~lg / 统一 gap-4~6',
);

const UiTokens _bentoDark = UiTokens(
  bg: Color(0xFF18181B),
  surface: Color(0xFF27272A),
  fg: Color(0xFFFAFAFA),
  muted: Color(0xFFA1A1AA),
  accent: Color(0xFF3B82F6),
  plateFill: Color(0xFF27272A),
  plateStroke: Color(0xFF3F3F46),
  plateRadius: 18,
  plateShadow: [
    BoxShadow(color: Color(0x40000000), offset: Offset(0, 6), blurRadius: 16)
  ],
  chipRadius: 14,
  provenance: 'page: 暗档 #18181b（zinc-900）；卡片/描边具体值 derived 自 zinc 色阶',
);

const UiTokens _organicLight = UiTokens(
  bg: Color(0xFFFAF6F1),
  surface: Color(0xFFE9E0D4),
  fg: Color(0xFF5C4033),
  muted: Color(0xFF8B7355),
  accent: Color(0xFF8B9D77),
  plateFill: Color(0xFFE9E0D4),
  plateRadius: 36,
  plateShadow: [
    BoxShadow(color: Color(0x1A5C4033), offset: Offset(0, 6), blurRadius: 18)
  ],
  grain: true,
  blobs: true,
  chipRadius: 30,
  provenance: 'page: bg #faf6f1 / 填充 #e9e0d4 / 文本 #5c4033 / '
      '强调 #8b9d77·#d4a373·#e9e0d4·#75a191 / 圆角 rounded-full + 团块轮廓 / '
      '颗粒纹理 / 300-700ms；阴影与圆角数值页面只给了定性描述',
);

const UiTokens _organicDark = UiTokens(
  bg: Color(0xFF2A241F),
  surface: Color(0xFF33291F),
  fg: Color(0xFFEFE6D8),
  muted: Color(0xFFB8A894),
  accent: Color(0xFF8B9D77),
  plateFill: Color(0xFF33291F),
  plateRadius: 36,
  plateShadow: [
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 6), blurRadius: 18)
  ],
  grain: true,
  blobs: true,
  chipRadius: 30,
  provenance: 'derived: 土色族换深档（页面禁止纯黑，故用 #2A241F），强调色不变',
);

const UiTokens _retroLight = UiTokens(
  bg: Color(0xFFF5E6D3),
  surface: Color(0xFFF5E6D3),
  fg: Color(0xFF8B4513),
  muted: Color(0x998B4513),
  accent: Color(0xFFC94C4C),
  plateStroke: Color(0xFF8B4513),
  plateStrokeWidth: 3,
  plateRadius: 0,
  plateShadow: [
    BoxShadow(color: Color(0x268B4513), offset: Offset(0, 4), blurRadius: 8)
  ],
  grain: true,
  ornaments: true,
  chipRadius: 0,
  chipStrokeWidth: 2,
  labelFamilies: _serif,
  labelTracking: 3,
  labelUppercase: true,
  provenance: 'page: bg #f5e6d3 / 文本 #8b4513 / 强调 #c94c4c·#2e4a3f·#d4a373 / '
      'rounded-none / border-2~4 #8b4513 / 0 4px 8px rgba(139,69,19,.15) / '
      'SVG 噪点纸纹 / 大写 + tracking-[0.2em] / 明确禁止渐变·圆角·玻璃·动效缩放',
);

const UiTokens _retroDark = UiTokens(
  bg: Color(0xFF241A12),
  surface: Color(0xFF241A12),
  fg: Color(0xFFF5E6D3),
  muted: Color(0xB3F5E6D3),
  accent: Color(0xFFC94C4C),
  plateStroke: Color(0xFFD4A373),
  plateStrokeWidth: 3,
  plateRadius: 0,
  plateShadow: [
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 4), blurRadius: 8)
  ],
  grain: true,
  ornaments: true,
  chipRadius: 0,
  chipStrokeWidth: 2,
  labelFamilies: _serif,
  labelTracking: 3,
  labelUppercase: true,
  provenance: 'derived: 纸/墨反转（深棕纸 + 奶油墨），线框换成页面给的 #d4a373',
);

const UiTokens _darkModeDark = UiTokens(
  bg: Color(0xFF0F172A),
  surface: Color(0xFF1E293B),
  fg: Color(0xFFF1F5F9),
  muted: Color(0xFF94A3B8),
  accent: Color(0xFF3B82F6),
  plateFill: Color(0x801E293B),
  plateStroke: Color(0xFF334155),
  plateRadius: 14,
  plateShadow: [
    BoxShadow(color: Color(0x80000000), offset: Offset(0, 8), blurRadius: 30),
    BoxShadow(
        color: Color(0x26FFFFFF),
        offset: Offset(0, 1),
        blurRadius: 0,
        spreadRadius: -0.5),
  ],
  chipRadius: 12,
  provenance: 'page: bg #0f172a(slate-900) / surface slate-800·50 / '
      '文本 slate-100·400 / 边框 slate-700 / 强调 #3b82f6·#22c55e·#f59e0b / '
      '上缘内高光 0 1px 0 rgba(255,255,255,.15) + 外影 0 8px 30px rgba(0,0,0,.5) / '
      'rounded-lg~xl；页面禁止纯白文本与纯黑底',
);

const UiTokens _darkModeLight = UiTokens(
  bg: Color(0xFFF8FAFC),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF0F172A),
  muted: Color(0xFF475569),
  accent: Color(0xFF3B82F6),
  plateFill: Color(0xFFFFFFFF),
  plateStroke: Color(0xFFCBD5E1),
  plateRadius: 14,
  plateShadow: [
    BoxShadow(color: Color(0x140F172A), offset: Offset(0, 8), blurRadius: 30)
  ],
  chipRadius: 12,
  provenance: 'derived: 同一 slate 色阶反转成亮档，去掉上缘高光（亮底无意义）',
);

const UiTokens _vibrancyDark = UiTokens(
  bg: Color(0xFF1C1C1E),
  surface: Color(0x733A3A3C),
  fg: Color(0xF2FFFFFF),
  muted: Color(0x99FFFFFF),
  accent: Color(0xFF0A84FF),
  plateFill: Color(0x593A3A3C),
  plateStroke: Color(0x2EFFFFFF),
  plateRadius: 12,
  chipRadius: 10,
  labelFamilies: _mono,
  provenance: 'page: 分层 #1c1c1e·#2c2c2e·#3a3a3c / 文本白 95% 加 alpha 阶梯 / '
      '强调 #0a84ff·#30d158·#ff9f0a·#ff453a / 边框一律 1px（white/8~25） / '
      '圆角最大 rounded-xl / 明确禁止渐变、发光、装饰动画、模糊像素值未给',
);

const UiTokens _vibrancyLight = UiTokens(
  bg: Color(0xFFF5F5F7),
  surface: Color(0x73FFFFFF),
  fg: Color(0xFF1C1C1E),
  muted: Color(0x99000000),
  accent: Color(0xFF0A84FF),
  plateFill: Color(0x66FFFFFF),
  plateStroke: Color(0x1F000000),
  plateRadius: 12,
  chipRadius: 10,
  labelFamilies: _mono,
  provenance: 'derived: 苹果亮色分层（#f5f5f7 + 白面板），1px 亮线换成 1px 暗线',
);

const UiTokens _surrealDark = UiTokens(
  bg: Color(0xFF1A1A3E),
  bgGradient: [Color(0xFF1A1A3E), Color(0xFFC38D94)],
  fg: Color(0xFFF0ECE4),
  muted: Color(0x99F0ECE4),
  accent: Color(0xFFD4A574),
  plateFill: Color(0x33F0ECE4),
  plateStroke: Color(0x4DD4A574),
  plateRadius: 26,
  plateShadow: [
    BoxShadow(color: Color(0x4DC38D94), blurRadius: 50)
  ],
  blobs: true,
  chipRadius: 26,
  labelFamilies: _serif,
  labelItalic: true,
  provenance: 'page: 深 #1a1a3e / 浅 #f0ece4 / 渐变 #1a1a3e→#c38d94 / '
      '强调 #d4a574·#c38d94·#4a3f6b·#90ba6d / 光晕 0 0 50px rgba(195,141,148,.3) / '
      '团块半径 40% 60% 70% 30% / 衬线斜体、明确不用粗体 / 禁止纯白与霓虹',
);

const UiTokens _surrealLight = UiTokens(
  bg: Color(0xFFF0ECE4),
  bgGradient: [Color(0xFFF0ECE4), Color(0xCCF0ECE4)],
  fg: Color(0xFF1A1A3E),
  muted: Color(0x991A1A3E),
  accent: Color(0xFFC38D94),
  plateFill: Color(0x33FFFFFF),
  plateStroke: Color(0x4DC38D94),
  plateRadius: 26,
  plateShadow: [
    BoxShadow(color: Color(0x33C38D94), blurRadius: 50)
  ],
  blobs: true,
  chipRadius: 26,
  labelFamilies: _serif,
  labelItalic: true,
  provenance: 'page: 亮版 #f0ece4→#f0ece4/80 也在页面上，其余同暗版规则',
);

const UiTokens _gothicDark = UiTokens(
  bg: Color(0xFF0A0A0A),
  bgGradient: [Color(0xFF0A0A0A), Color(0xFF1A0A1A), Color(0xFF0A0A0A)],
  surface: Color(0xFF1A0A1A),
  fg: Color(0xFFE5E5E5),
  muted: Color(0x99E5E5E5),
  accent: Color(0xFF8B1A2A),
  plateFill: Color(0xCC1A0A1A),
  plateStroke: Color(0x804A1A4A),
  plateRadius: 4,
  plateShadow: [
    BoxShadow(color: Color(0x594A1A4A), offset: Offset(0, 4), blurRadius: 16)
  ],
  ornaments: true,
  chipRadius: 4,
  labelFamilies: _serif,
  labelTracking: 3,
  labelUppercase: true,
  provenance: 'page: 黑 #0a0a0a / 渐变 0a0a0a→1a0a1a→0a0a0a / 文本 #e5e5e5 / '
      '强调 #4a1a4a·#8b1a2a·#6b2d5b / rounded-sm / 影 0 4px 16px rgba(74,26,74,.35) / '
      '衬线 + tracking-[0.2em] + 大写标签 / 蕾丝·十字·对称装饰 / 禁止亮色与卡通',
);

const UiTokens _gothicLight = UiTokens(
  bg: Color(0xFFF3EFF2),
  surface: Color(0xFFFFFFFF),
  fg: Color(0xFF2A1A26),
  muted: Color(0x992A1A26),
  accent: Color(0xFF6B2D5B),
  plateFill: Color(0x66FFFFFF),
  plateStroke: Color(0x806B2D5B),
  plateRadius: 4,
  plateShadow: [
    BoxShadow(color: Color(0x336B2D5B), offset: Offset(0, 4), blurRadius: 16)
  ],
  ornaments: true,
  chipRadius: 4,
  labelFamilies: _serif,
  labelTracking: 3,
  labelUppercase: true,
  provenance: 'derived: 页面只有黑紫版；亮版按「浅蕾丝白 + 李紫」同族推导',
);

const UiTokens _vnLight = UiTokens(
  bg: Color(0xFFF7FAFC),
  bgGradient: [
    Color(0xFF4A6FA5),
    Color(0xFF7B9CC7),
    Color(0xFFC4A882),
    Color(0xFFE8C19A),
  ],
  surface: Color(0xB3FFFFFF),
  fg: Color(0xFF1A202C),
  muted: Color(0x801A202C),
  accent: Color(0xFF6366F1),
  plateFill: Color(0xB3FFFFFF),
  plateStroke: Color(0x336366F1),
  plateRadius: 12,
  plateShadow: [
    BoxShadow(color: Color(0x33000000), offset: Offset(0, 6), blurRadius: 18)
  ],
  ornaments: true,
  chipRadius: 8,
  labelFamilies: _serif,
  provenance: 'page: bg #f7fafc / 天空渐变 4a6fa5→7b9cc7→c4a882→e8c19a / '
      '对话框面板 #1a202c·85% + white/70 次级 / 文本 #4a5568 / '
      '强调 #6366f1·#ec4899·#10b981 / rounded-lg / 面板花角；描边宽度与模糊像素未给数值',
);

const UiTokens _vnDark = UiTokens(
  bg: Color(0xFF14161F),
  bgGradient: [
    Color(0xFF24304A),
    Color(0xFF33415C),
    Color(0xFF5A4A3C),
    Color(0xFF6B5138),
  ],
  surface: Color(0xD91A202C),
  fg: Color(0xFFE2E8F0),
  muted: Color(0x99E2E8F0),
  accent: Color(0xFFEC4899),
  plateFill: Color(0xD91A202C),
  plateStroke: Color(0x4DEC4899),
  plateRadius: 12,
  plateShadow: [
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 6), blurRadius: 18)
  ],
  ornaments: true,
  chipRadius: 8,
  labelFamilies: _serif,
  provenance: 'derived: 页面用白 70% 面板；亮版即页面值（页面面板为深色 #1a202c，'
      '故亮档底板用 white/70），暗档把天空渐变压暗一档、面板回到 #1a202c·85%',
);

/// (亮, 暗) 两版令牌的总表
const Map<UiStyle, (UiTokens light, UiTokens dark)> uiStyleSpecs = {
  UiStyle.classic: (_classicLight, _classicDark),
  UiStyle.editorial: (_editorialLight, _editorialDark),
  UiStyle.neumorphism: (_neumorphismLight, _neumorphismDark),
  UiStyle.bentoGrid: (_bentoLight, _bentoDark),
  UiStyle.naturalOrganic: (_organicLight, _organicDark),
  UiStyle.retroVintage: (_retroLight, _retroDark),
  UiStyle.darkMode: (_darkModeLight, _darkModeDark),
  UiStyle.macosVibrancy: (_vibrancyLight, _vibrancyDark),
  UiStyle.surrealism: (_surrealLight, _surrealDark),
  UiStyle.gothicLolita: (_gothicLight, _gothicDark),
  UiStyle.visualNovel: (_vnLight, _vnDark),
};

UiTokens uiTokensFor(UiStyle style, bool isDark) {
  final spec = uiStyleSpecs[style]!;
  return isDark ? spec.$2 : spec.$1;
}

const List<String> _serif = ['serif', 'Times New Roman'];
const List<String> _mono = ['monospace', 'Menlo'];

String uiStyleName(UiStyle s) {
  switch (s) {
    case UiStyle.classic:
      return '无装饰（原样）';
    case UiStyle.editorial:
      return '编辑部';
    case UiStyle.neumorphism:
      return '软胶拟物';
    case UiStyle.bentoGrid:
      return '便当格';
    case UiStyle.naturalOrganic:
      return '自然有机';
    case UiStyle.retroVintage:
      return '复古印刷';
    case UiStyle.darkMode:
      return '暗色分层';
    case UiStyle.macosVibrancy:
      return '系统毛玻璃';
    case UiStyle.surrealism:
      return '超现实';
    case UiStyle.gothicLolita:
      return '哥特洛丽塔';
    case UiStyle.visualNovel:
      return '视觉小说';
  }
}

/// 沿树注入当前令牌；单独 pump 子组件时自动回落到 classic
class UiScope extends InheritedWidget {
  final UiTokens tokens;
  final UiStyle style;

  const UiScope({
    super.key,
    required this.style,
    required this.tokens,
    required super.child,
  });

  static UiTokens of(BuildContext context) =>
      maybeOf(context) ?? UiTokens.classic(Theme.of(context).brightness == Brightness.dark);

  static UiTokens? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiScope>()?.tokens;

  @override
  bool updateShouldNotify(UiScope oldWidget) =>
      oldWidget.style != style ||
      oldWidget.tokens.fg != tokens.fg ||
      oldWidget.tokens.bg != tokens.bg;
}

/// 背景层：底色 / 渐变 / 纸纹 / 柔形体 / 四角装饰
class UiLayer extends StatelessWidget {
  final UiTokens tokens;
  final Widget child;

  /// true 时只铺纯色（surface ?? bg）：抽屉、设置页这类「有文字滚动」的面板
  /// 用渐变底会让上半屏对比度不足，主屏才用完整渐变
  final bool solid;

  const UiLayer({
    super.key,
    required this.tokens,
    required this.child,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = solid ? null : tokens.bgGradient;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient != null && gradient.length >= 2
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradient)
            : null,
        color: gradient != null && gradient.length >= 2
            ? null
            : (solid ? (tokens.surface ?? tokens.bg) : tokens.bg),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (tokens.blobs)
            const RepaintBoundary(
                child: CustomPaint(painter: _BlobPainter())),
          if (tokens.grain)
            const RepaintBoundary(
                child: CustomPaint(painter: _GrainPainter())),
          if (tokens.ornaments)
            RepaintBoundary(
                child: CustomPaint(painter: _OrnamentPainter(tokens.accent))),
          // 背景色由上面的 DecoratedBox 承担，但 ListTile/Ink 需要自己这一层
          // Material 做最近祖先，否则框架会报「DecoratedBox 挡住了 ink」
          Material(type: MaterialType.transparency, child: child),
        ],
      ),
    );
  }
}

/// 纸纹：固定种子的稀疏暗点，静态层，只在尺寸变化时重绘
class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  /// 每万个逻辑像素约 60 个点：800×600 约 29 个，够“有纸味”又不脏屏
  static const double _dotsPerTenThousandPx = 60;

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.isFinite || size.width <= 0 || size.height <= 0) return;
    final rnd = math.Random(7);
    final paint = Paint()..color = const Color(0x14000000);
    final count = (size.width * size.height / 10000 * _dotsPerTenThousandPx).round();
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        0.7,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) => false;
}

/// 柔形体：三块低透明圆形，用 MaskFilter 糊边（静态层，不跟随翻页重绘）
class _BlobPainter extends CustomPainter {
  const _BlobPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.isFinite || size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = const Color(0x22FFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 48);
    final w = size.width, h = size.height;
    canvas.drawCircle(Offset(w * 0.18, h * 0.22), h * 0.34, paint);
    canvas.drawCircle(Offset(w * 0.82, h * 0.72), h * 0.3, paint);
    canvas.drawCircle(Offset(w * 0.62, h * 0.12), h * 0.2, paint);
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) => false;
}

/// 四角装饰括号（复古印刷 / 哥特 / 视觉小说的共同签名元素）
class _OrnamentPainter extends CustomPainter {
  final Color color;

  const _OrnamentPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.isFinite || size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const inset = 18.0;
    const arm = 26.0;
    final right = size.width - inset;
    final bottom = size.height - inset;
    // 左上 / 右上 / 左下 / 右下 各一个 L 形
    canvas.drawPath(
        Path()
          ..moveTo(inset, inset + arm)
          ..lineTo(inset, inset)
          ..lineTo(inset + arm, inset), paint);
    canvas.drawPath(
        Path()
          ..moveTo(right - arm, inset)
          ..lineTo(right, inset)
          ..lineTo(right, inset + arm), paint);
    canvas.drawPath(
        Path()
          ..moveTo(inset, bottom - arm)
          ..lineTo(inset, bottom)
          ..lineTo(inset + arm, bottom), paint);
    canvas.drawPath(
        Path()
          ..moveTo(right - arm, bottom)
          ..lineTo(right, bottom)
          ..lineTo(right, bottom - arm), paint);
  }

  @override
  bool shouldRepaint(_OrnamentPainter old) => old.color != color;
}

/// 分区标题 / 小标签的排版：衬线、字距、斜体都由令牌决定
TextStyle uiLabelStyle(BuildContext context, UiTokens tokens, {double? size}) {
  final base = Theme.of(context).textTheme.titleMedium ?? const TextStyle();
  return base.copyWith(
    color: tokens.labelInk,
    fontSize: size ?? base.fontSize,
    letterSpacing: tokens.labelTracking,
    fontFamilyFallback: tokens.labelFamilies,
    fontStyle: tokens.labelItalic ? FontStyle.italic : FontStyle.normal,
    fontWeight: FontWeight.w600,
  );
}

/// 标签文本本身：部分风格（复古印刷 / 哥特）要求大写疏排的标签
/// —— 中文没有大小写，只有拉丁标签会真的变化
String uiLabelText(UiTokens tokens, String text) =>
    tokens.labelUppercase ? text.toUpperCase() : text;
