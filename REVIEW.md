# TimeNote 代码评审报告（Flutter Reviewer）

> 评审方式：Flutter Reviewer（skillmd.com/phoroth/flutter-reviewer）预发布评审清单
> 评审对象：时笺 TimeNote v1.0.0（lib/ 全量源码 + 平台配置 + 测试）
> 评审日期：2026-11-04
> 结论：**0 CRITICAL · 3 HIGH（已修复）· 4 MEDIUM（已修复）**

## 🔴 CRITICAL（0）

无阻断发布问题。

## 🟡 HIGH（3，均已修复）

| # | 问题 | 状态 |
| --- | --- | --- |
| H1 | `_triggerEgg` 中 await 音频播放后缺少 `mounted` 校验，页面销毁时 setState 会抛异常 | ✅ 已加 `if (!mounted) return;` |
| H2 | pubspec.yaml 未声明 assets / 字体资源，运行时资源缺失报错 | ✅ 已声明 `assets/data/quotes.json`、`assets/audio/alert.wav` |
| H3 | AudioPlayer 播放无异常捕获，alert.wav 缺失会崩溃 | ✅ 已加 try/catch 静默降级 |

## 🟠 MEDIUM（4，均已修复）

| # | 问题 | 状态 |
| --- | --- | --- |
| M1 | 自定义旋转动画无 RepaintBoundary，整页重绘 | ✅ 5 个渲染器统一包裹 RepaintBoundary |
| M2 | 待办输入无长度/脏字符过滤 | ✅ TextField maxLength=60 + trim 空值拦截 |
| M3 | `eggStaySeconds` 常量未定义 | ✅ 已加入 AppConstants |
| M4 | 设置页未同步横屏约束 | ✅ SettingsPage 已锁定横屏 |

## 🟢 LOW / NIT（已处理或留档）

- ✅ 魔法数字已尽量收敛（字体字号仍按组件局部设置，属视觉参数）
- ✅ 增加 `analysis_options.yaml`（flutter_lints + prefer_const）
- ✅ 待办空态提示「暂无待办，添加一条吧」
- ℹ️ 字体 family 与文件名强绑定：README 已列出字体清单，未安装字体自动回退系统字体
- ℹ️ quotes.json 当前为占位样例，正式 520 条文案待填充（用户确认暂缓）

## ✅ 评审通过项

- Riverpod 用法规范，Notifier 不含 UI 逻辑
- Timer / ProviderSubscription / Wakelock / AudioPlayer 均成对清理
- quotes.json 加载 try-catch + 空池兜底，不崩溃
- ListView.builder 懒加载待办
- 倒计时 running / pause / resume / stop / 归零边界完整
- 空安全无滥用 `!`
- 架构分层：core / flip_clock / todo / settings / egg 职责清晰

## 🧪 测试执行记录

```
flutter analyze  → No issues found!
flutter test     → 14 tests passed (unit + widget)
```

修复过程中发现并解决的工程问题：

1. **待办持久化阻塞 UI**：原实现先 await Hive 落盘再更新 state，改为乐观更新（先刷新 UI 再持久化）
2. **Widget 测试与常驻时钟动画冲突**：`pumpAndSettle` 会被每秒时钟动画无限挂起，改为有限时间推进
3. **测试间 Hive 数据串扰**：Hive box 全局缓存复用同名 box，测试改为每次独立 box 前缀隔离
