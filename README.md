# 时笺 TimeNote

> 平板离线翻页时钟 · 专注计时 + 待办 + 倒计时彩蛋

一款面向 **Android 平板 / 华为鸿蒙平板 / iPad** 的纯离线时间管理 App。灵感来自 Fliqlo 式待机翻页时钟，保持极简：**翻页时钟 + 待办抽屉**，倒计时结束会随机弹出一句有意义的文案陪你继续学习。

## ✨ 功能

- ⏱️ 实时翻页时钟（每秒翻页动画）
- ⏳ 倒计时：快捷预设 5 / 10 / 25 / 45 分钟，暂停 / 继续 / 停止
- 🎞️ **5 种翻页动画**：经典机场翻牌 / 书页卷曲 / 滑动 / 分段碎裂 / 渐变溶解
- 🔢 **10 种计时画面风格**：苹果极简 / 复古机械 / 软圆角 / 高对比窄版 / 手写文艺 / 粗黑力量 / 纤细思源 / 得意黑潮流 / 点阵 / 镂空描边
- ⚫⚪ 黑白两色底色自由切换
- 🚀 翻页速度三档：慢 / 标准 / 快
- ✅ **待办抽屉**：右上角汉堡唤起右侧抽屉，新增 / 勾选 / 删除，Hive 本地持久化
- 💌 **倒计时彩蛋**：归零后时钟区域整体替换为随机文案（无弹窗），5 秒自动切回，点击任意处立即返回；可开关
- 🔆 屏幕常亮默认开启（设置可关）
- 🔇 提示音开关
- 📴 **纯离线**：无登录、无广告、无网络请求

## 🛠 技术栈

- Flutter 3.47.8 / Dart
- flutter_riverpod（状态管理）
- hive + hive_flutter（本地存储）
- wakelock_plus（屏幕常亮）
- audioplayers（提示音）

## 📁 目录结构

```
lib/
├── core/                  # 常量、存储、彩蛋服务、全局 Provider
├── flip_clock/            # 翻页时钟核心（5 种动画渲染 + 主界面）
├── todo/                  # 待办抽屉与单项
├── settings/              # 设置页、风格选择
├── egg/                   # 倒计时彩蛋展示
└── main.dart
assets/
├── data/quotes.json       # 彩蛋文案库（占位样例，正式文案待填充）
├── audio/alert.wav        # 提示音
└── fonts/                 # 免费商用字体（按需放入）
test/                      # 单元测试 + Widget 测试
```

## 🚀 运行

```bash
flutter pub get
flutter run
```

## 🧪 测试

```bash
flutter analyze
flutter test
```

## 🤖 云端构建 APK（GitHub Actions）

推送 main 分支或手动触发即可在云端自动构建 Debug APK，产物在 Actions 的 Artifacts 中下载：

```bash
git push origin main
```

> 说明：图标 / 提示音 / gradle wrapper jar 为二进制，GitHub API 无法直接推送，workflow 会在云端自动重建，无需本地上传。

## 🎨 字体（免费商用，放入 assets/fonts 并在 pubspec 声明）

| 样式 | 字体 |
| --- | --- |
| 思源黑体（细/常规） | Source Han Sans CN |
| 粗黑力量 | 站酷快乐体 ZCOOL KuaiLe |
| 手写文艺 | 仓耳渔阳体 |
| 得意黑潮流 | 得意黑 Smiley Sans |
| 点阵/普惠 | 阿里巴巴普惠体 |

未安装字体时自动回退系统默认字体，不影响运行。

## 📝 待办

- [ ] 填充 520 条彩蛋文案（书籍 / 优质外文 / 社区摘录，英文原文无翻译）
- [ ] 下载并打包 5 款免费商用字体
- [ ] 华为 OpenHarmony（Flutter-OH）平台适配与打包
- [ ] iOS 签名与上架

## 📄 License

[MIT](./LICENSE)
