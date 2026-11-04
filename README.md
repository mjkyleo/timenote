# 时笺 TimeNote

> 平板离线翻页时钟 · 专注计时 + 待办 + 倒计时彩蛋

一款面向 **Android 平板 / 华为鸿蒙平板 / iPad** 的纯离线时间管理 App。灵感来自 Fliqlo 式待机翻页时钟，保持极简：**翻页时钟 + 待办抽屉**，倒计时结束会随机给出一句文案陪你继续。

## ✨ 功能

- ⏱️ 实时翻页时钟（每秒翻页）
- ⏳ 倒计时：快捷预设 5 / 10 / 25 / 45 分钟 + 自定义 1–600 分钟（弹窗校验非法输入），暂停 / 继续 / 停止
  - 走时锚定墙钟：息屏、切后台、系统挂起都不会漏时
  - 底部进度条显示已消耗比例
  - 结束后自动回到实时时钟，不留 `00:00:00` 死屏
- 🎞️ **5 种翻页动画**：经典机场翻牌 / 书页卷曲 / 滑动 / 分段碎裂 / 渐变溶解
- 🔢 **10 种计时画面风格**：苹果极简 / 复古机械 / 软圆角 / 高对比窄版 / 手写文艺 / 粗黑力量 / 纤细思源 / 得意黑潮流 / 点阵 / 镂空描边
  - 风格差异由字重、字距、字号倍率、描边、底板、圆角、中缝、等宽数字等 10 个维度实现，**没打包字体也两两可辨**
- ⚫⚪ 黑白两色底色切换
- 🚀 翻页速度三档：慢（900ms）/ 标准（450ms）/ 快（220ms）
- ✅ **待办抽屉**：右上角汉堡唤起右侧抽屉，新增 / 勾选 / 删除 / 一键清除已完成，显示「未完成/总数」，Hive 本地持久化（乐观更新，落盘不阻塞 UI）
- 💌 **倒计时彩蛋**：归零后时钟区域整体替换为随机文案（无弹窗），5 秒自动切回，点任意处立即返回；可开关，与提示音互不影响
- 🔆 屏幕常亮默认开启，设置里关掉**立即生效**（不需要重启）
- 🔇 提示音开关（本地 `assets/audio/alert.wav`，缺失或解码失败时静默降级）
- 🫥 无操作 6 秒自动隐藏入口按钮，点任意处唤回，待机画面回到纯数字
- ⚙️ 设置页左侧实时预览：用真的翻页组件每 2 秒轮换样张，改一项马上看到效果
- 📴 **纯离线**：无登录、无广告、无网络请求

## 🛠 技术栈

- Flutter 3.47.8 / Dart
- flutter_riverpod（状态管理，时间源与插件都留了可注入的测试缝）
- hive + hive_flutter（本地存储）
- wakelock_plus（屏幕常亮）
- audioplayers（提示音）

## 📁 目录结构

```
lib/
├── core/                  # 常量、存储封装、彩蛋文案服务、Provider（clock/app/todo）
├── flip_clock/            # 翻页时钟：动画渲染 + 外观表 + 主屏
├── todo/                  # 待办抽屉与单项
├── settings/              # 设置页、风格选择器
├── egg/                   # 倒计时彩蛋展示
└── main.dart
assets/
├── data/quotes.json       # 彩蛋文案库（占位样例，正式文案待填充）
├── audio/alert.wav        # 提示音（已入库）
└── fonts/                 # 免费商用字体（按需放入）
test/
├── app_widget_test.dart   # 主屏 / 抽屉 / 常亮 / 倒计时结束 / 设置（17 例）
├── flip_rendering_test.dart # 动画静止态 + 风格可辨 + 自适应缩放（11 例）
├── clock_notifier_test.dart # 走时/暂停/继续/停止/生命周期（12 例，假时钟）
├── storage_service_test.dart # 真实磁盘落盘 + 脏数据容忍（3 例）
├── todo_model_test.dart   # 模型与非法数据（5 例）
├── egg_service_test.dart  # 文案库与随机不重复（3 例）
└── support/               # fake_storage（Hive 内存后端）/ fake_wakelock
```

## 🚀 运行

```bash
flutter pub get
flutter run
```

## 🧪 测试

```bash
flutter analyze   # No issues found!
flutter test      # 51 tests passed
```

三个可注入的测试缝让「测过」这件事真的成立：

| 依赖 | 生产 | 测试 |
| --- | --- | --- |
| 时间 | `DateTime.now` | `clockSourceProvider` 覆盖 + `fakeAsync` |
| 屏幕常亮 | wakelock_plus 平台通道 | `wakelockPlusPlatformInstance` 换 fake |
| 存储 | Hive 磁盘后端 | widget 测试用 Hive 内存后端；真实落盘由普通 `test()` 覆盖 |

> 提示音在 widget 测试里固定关闭：audioplayers 6 需要「资源 → 临时文件」的真实 IO，在 fake-async 区无法等待。因此「彩蛋先于提示音上屏」目前只有源码结构保证，未自动化覆盖（详见 [REVIEW.md](./REVIEW.md) 第五节）。

## 🤖 云端构建 APK（GitHub Actions）

推送 main 分支或手动触发即可在云端自动构建 Debug APK（`pub get` → `analyze` → `test` → `build apk --debug`），产物在 Actions 的 Artifacts 中下载：

```bash
git push origin main
```

> 说明：应用图标 PNG 与 `gradle-wrapper.jar` 是二进制且未纳入版本库，workflow 会在云端生成/下载；提示音 `alert.wav` 已经在仓库里。

## 🎨 字体（免费商用，放入 assets/fonts 并在 pubspec 声明）

| 样式 | 字体 |
| --- | --- |
| 思源黑体（细/常规） | Source Han Sans CN |
| 粗黑力量 | 站酷快乐体 ZCOOL KuaiLe |
| 手写文艺 | 仓耳渔阳体 |
| 得意黑潮流 | 得意黑 Smiley Sans |
| 点阵/普惠 | 阿里巴巴普惠体 |

`styleFontMap` 里的 family 名在字体未打包时是惰性的，Flutter 自动回退系统字体，不影响运行，也不会让 10 种风格退化成同一种画面。

## 📝 待办

- [ ] 连真机验证常亮 / 横屏 / 提示音 / 抽屉手势（本机无设备，尚未验证）
- [ ] 填充 520 条彩蛋文案（书籍 / 优质外文 / 社区摘录，英文原文无翻译）
- [ ] 下载并打包 5 款免费商用字体
- [ ] 决定 `gradle-wrapper.jar` 与图标是否纳入版本库（纳入后可删 CI 里的下载步骤）
- [ ] 华为 OpenHarmony（Flutter-OH）平台适配与打包
- [ ] iOS 签名与上架

## 📄 License

[MIT](./LICENSE)
