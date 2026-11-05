# 时笺 TimeNote

> 平板离线翻页时钟 · 专注计时 + 待办 + 倒计时彩蛋

一款面向 **Android 平板 / 华为鸿蒙平板 / iPad** 的纯离线时间管理 App。灵感来自 Fliqlo 式待机翻页时钟，保持极简：**翻页时钟 + 待办抽屉**，倒计时结束会随机给出一句文案陪你继续。

## ✨ 功能

- ⏱️ 实时翻页时钟（每秒翻页）
- ⏳ 倒计时：快捷预设 5 / 10 / 25 / 45 分钟 + 自定义 1–600 分钟（弹窗校验非法输入），暂停 / 继续 / 停止
  - 自定义弹窗在横屏手机上不会软键盘一弹就塌掉：不自动抢焦点，且 `scrollable` + 收紧内边距，输入框和「开始」始终够得着（Pixel 7 横屏实测）
  - 走时锚定墙钟：息屏、切后台、系统挂起都不会漏时
  - 底部进度条显示已消耗比例
  - ⏳ **可选底层进度组件（8 种）**：沙漏 / 水位填充 / 环形 / 螺旋 / 灯带 / 年轮圆盘 / 蜡烛燃烧 / 日出日落，挂在数字下方那条进度带里（日出日落是唯一的环境层，垫在整屏背后、细进度条留着当读数）；默认「不使用」，一个像素都不多画
  - 结束后自动回到实时时钟，不留 `00:00:00` 死屏
- 🎞️ **24 种翻页动画 + 混合轮换**（默认滚筒走字），按动效实验室的六类分工：
  - **翻折 fold**：经典机场翻牌 / 书页卷曲翻页 / 对角斜折 / 弹跳翻牌 / 整卡翻面
  - **位移 roll**：滚筒走字（里程表直线下滑 + 运动模糊 + 暗角）/ 横向滑移 / 级联错位
  - **遮罩 mask**：百叶窗擦除 / 径向光圈 / 多边形遮罩
  - **形变 morph**：交叉淡入 / 模糊对焦 / 果冻挤压
  - **碎片 grain**：像素洗牌 / 粒子聚散 / 三角碎片（后两件标「仅收尾」，见下）
  - **光学 light**：流体溶解 / 液态玻璃折射 / CRT 扫描线（前两件高频慎用）
  - 另有下方推入 / 分段碎裂 / 渐变溶解 / 落体回弹四种早期样式；**混合轮换**每次翻页换一种，池子里排掉粒子聚散、三角碎片（只适合收尾）、流体溶解、液态玻璃（高频慎用）与像素洗牌（每字 12 块切片，一秒一次太贵）这五种，它们留作用户主动选的主题档
  - **逐格翻**：时钟串拆成一格一格，只有数值真的变了的那一格才动，`:` 和未变的数字位保持静止；一格一个动画控制器，相邻两位同时变化时各翻各的
  - **绕中缝铰链**：翻牌的上半片绕数字底板的中缝转（不是整块绕画面中心转），翻到 42% 换下半片承接；上半用 `easeInCubic` 加速下落、下半用 `easeOutBack` 回弹收尾，随翻起的角度按 `|sin θ|` 加深那面的阴影
- 🔢 **10 种计时画面风格**：苹果极简 / 复古机械 / 软圆角 / 高对比窄版 / 手写文艺 / 粗黑力量 / 纤细思源 / 得意黑潮流 / 点阵 / 镂空描边
  - 风格差异由字重、字距、字号倍率、描边、底板、圆角、中缝、等宽数字等 10 个维度实现，**没打包字体也两两可辨**
- 🖼 **11 套整屏界面风格**：无装饰（原样）/ 编辑部 / 软胶拟物 / 便当格 / 自然有机 / 复古印刷 / 暗色分层 / 系统毛玻璃 / 超现实 / 哥特洛丽塔 / 视觉小说
  - 分工：**界面风格管「环境」**（背景、数字底板的填充/描边/光影/圆角、标签字体与字距），**数字风格管「字形」**，两层正交、互不覆盖
  - 每套自带亮/暗两版，跟随下面的黑白底色开关；取色逐条标注是参考页原值（`page:`）还是同族推导（`derived:`）
- ⚫⚪ 黑白两色底色切换（同时选中当前界面风格的亮版或暗版）
- 🚀 翻页速度三档：慢（900ms）/ 标准（450ms）/ 快（220ms）
- ✅ **待办抽屉**：右上角汉堡唤起右侧抽屉，新增 / 勾选 / 删除 / 一键清除已完成，显示「未完成/总数」，Hive 本地持久化（乐观更新，落盘不阻塞 UI）
- 💌 **倒计时彩蛋**：归零后时钟区域整体替换为随机文案（无弹窗），5 秒自动切回，点任意处立即返回；可开关，与提示音互不影响
- 🔆 屏幕常亮默认开启，设置里关掉**立即生效**（不需要重启）
- 🔇 提示音开关（本地 `assets/audio/alert.wav`，缺失或解码失败时静默降级）
- 🖥 **整屏沉浸式**：状态栏与导航条默认隐藏（`SystemUiMode.immersiveSticky`），数字占满屏幕；从边缘滑动可临时唤回系统栏，Android 与鸿蒙都走同一条通道（鸿蒙侧 `flutter_ohos` 的 `PlatformPlugin` 显式实现了这个模式）
- 🫥 **沉浸式待机**：无操作 6 秒后，底部倒计时按钮和右上角入口一起淡出，`IgnorePointer` 同步挡住误触；点屏幕任意处立刻唤回。待机画面回到纯数字，倒计时中唯一保留的是底部的进度读数——默认那根细进度条，选了进度组件就是它（同一份信息不画两遍）；它是「还在计时」的凭据，按钮才是噪声
- ⚙️ 设置页左侧实时预览：用真的翻页组件每 2 秒轮换样张，改一项马上看到效果
  - 分栏按「宽 + 高」双条件判定：横屏手机（Pixel 7 逻辑 914×411）高度不足时改成上下叠放，预览按 42% 收放（下限 140、上限 240），选项区拿剩下的空间；窄屏那一版预览矮于一整屏时会挤掉半列表，已修
  - 选项卡片之间有间距、长标签省略号截断，11 套界面风格的选择项带迷你底板色块
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
├── progress_decor/        # 底层进度组件（CustomPainter 8 件 + 连续相位只在需要时挂）
├── theme/                 # 界面风格令牌（11 套 × 亮/暗）+ UiScope/UiLayer 注入
├── todo/                  # 待办抽屉与单项
├── settings/              # 设置页、风格选择器
├── egg/                   # 倒计时彩蛋展示
└── main.dart
assets/
├── data/quotes.json       # 彩蛋文案库（520 条，已入库）
├── audio/alert.wav        # 提示音（已入库）
├── icon/                  # 启动图标源图（1024×1024，不打进包）
└── fonts/                 # 免费商用字体（按需放入）
ohos/                      # 鸿蒙工程（Flutter-OH 模板，33 个文件入库）
tool/
├── ohos_env.sh            # 鸿蒙构建的本机环境变量正本
├── build_hap.sh           # 一键出 HAP（绕开 bin/flutter 的 OS 污染）
├── pubspec_overrides.ohos.yaml  # 只在鸿蒙构建期注入的依赖覆盖
└── make_icons.py          # 源图 → 各 dpi 启动图标
test/
├── app_widget_test.dart   # 主屏 / 抽屉 / 常亮 / 倒计时结束 / 沉浸式隐藏 / 设置（22 例）
├── ui_style_test.dart     # 令牌完整性 + 风格真生效 + 11×2 全矩阵冒烟（11 例）
├── flip_rendering_test.dart # 24 种动画静止/半途/入场 + 混合轮换池 + 批次登记 + 级联错开 + 10 种数字样式 + 自适应缩放（86 例）
├── progress_decor_test.dart # 进度组件：像素级光栅核对 + 主屏挂载规则 + 设置持久化（18 例）
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
flutter test      # 160 tests passed
```

160 例只管「形态对不对」；翻页铰链、倒计时中按钮隐去、横屏手机设置分栏这三件事另外在模拟器上逐条截图看过（AVD `trace_pixel7`，1080×2400@420dpi → 横屏逻辑 914×411，装本轮 x86_64 release 包）。图证、启动参数与「软渲染帧率不代表真机」这条限制见 [REVIEW.md](./REVIEW.md) §9.8。**动画观感与进度组件好不好看要人眼判**，24 种动画 + 8 种进度组件的实机效果由用户在 dev-build 直链上自测。

三个可注入的测试缝让「测过」这件事真的成立：

| 依赖 | 生产 | 测试 |
| --- | --- | --- |
| 时间 | `DateTime.now` | `clockSourceProvider` 覆盖 + `fakeAsync`；实时时钟与倒计时共用这一个缝 |
| 屏幕常亮 | wakelock_plus 平台通道 | `wakelockPlusPlatformInstance` 换 fake |
| 存储 | Hive 磁盘后端 | widget 测试用 Hive 内存后端；真实落盘由普通 `test()` 覆盖 |

> 提示音在 widget 测试里固定关闭：audioplayers 6 需要「资源 → 临时文件」的真实 IO，在 fake-async 区无法等待。因此「彩蛋先于提示音上屏」目前只有源码结构保证，未自动化覆盖（详见 [REVIEW.md](./REVIEW.md) 第五节）。

## 🖥 本机出包（鸿蒙）

鸿蒙要用 Flutter-OH 的 SDK（标准 Flutter 没有 `ohos` 目标），命令收在 `tool/build_hap.sh`：

```bash
tool/build_hap.sh            # 默认 --debug --no-codesign，动画重做后复测：64.2 s → 125,814,260 字节（+37,456）
tool/build_hap.sh --release  # AOT，复测：107.2 s → 22,748,875 字节（`libapp.so` 5,325,744 B，无 kernel_blob）
```

脚本里三件事是有原因的，别手工替换成 `flutter build hap`：

1. 走 `flutter.bat` 而不是 bash 启动器 `bin/flutter` —— 后者第 54 行 `OS="$(uname -s)"` 会把 `OS` 污染成 `MINGW64_NT-...` 并一路传给华为 `ohpm.bat`，而 `ohpm.bat` 用 `%OS%` 决定要不要开延迟展开，关掉之后它自己无限递归爆栈（`BATCH RECURSION ... Recursion Count=234`）。
2. 构建期把 `tool/pubspec_overrides.ohos.yaml` 复制成 `pubspec_overrides.yaml`（已 gitignore），结束后删掉 —— audioplayers 的鸿蒙适配版用了 `TargetPlatform.ohos`，标准 SDK（含 CI）编译不过，所以覆盖只能在鸿蒙链路上注入。
3. `tool/ohos_env.sh` 负责 `DEVECO_SDK_HOME` / `PUB_CACHE` 同盘 / `.exe` shim 那套本机环境。

产物是**未签名**的 `entry-default-unsigned.hap`，装不上真机；签名要在 DevEco Studio 里用华为账号生成调试证书。⚠️ 取产物别拿错文件：debug 会被复制到 `build/ohos/hap/`，`--release` 只落在 `ohos/entry/build/default/outputs/default/`（release 分支工具只打印签名提示，不复制也不报 `√ Built`，所以 `build/ohos/hap/` 里可能还躺着上一次 debug 的 120 MB 包）。完整进度与坑见 [HANDOFF-OHOS.md](./HANDOFF-OHOS.md)。

## 📱 本机出包（Android）

```bash
D:\dev\flutter\bin\flutter.bat build apk --release   # → build/app/outputs/flutter-apk/
```

实测大小（2026-11-05 本机重新出包，含全部 ABI 拆分）：`app-arm64-v8a-release.apk` 17,917,607 / `app-armeabi-v7a-release.apk` 15,255,041 / `app-x86_64-release.apk` 19,343,534 / `app-release.apk`（fat，三个 ABI 全带）51,423,838 / `app-debug.apk` 182,984,197 字节。

**为什么「功能这么简单」也要 17MB？** 把 arm64 那个包拆开看（`unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`，未压缩字节，合计 18,268,158 / 66 个文件）：

| 条目 | 字节 | 是什么 |
| --- | --- | --- |
| `lib/arm64-v8a/libflutter.so` | 11,763,360 | Flutter 引擎本体。任何 Flutter App 都带这一份，跟你写了几个功能无关 |
| `lib/arm64-v8a/libapp.so` | 5,440,392 | AOT 编译出来的 Dart 机器码：自己的代码 + riverpod / hive / wakelock_plus / audioplayers 的 Dart 侧 |
| `classes.dex` | 573,424 | 插件的 Android 侧 Java/Kotlin 胶水 |
| `lib/arm64-v8a/libdartjni.so` | 131,400 | Dart ↔ Java 桥 |
| `assets/flutter_assets/NOTICES.Z` | 111,200 | 开源许可清单，Flutter 强制打包 |
| `assets/flutter_assets/assets/data/quotes.json` + `assets/audio/alert.wav` | 27,867 + 30,912 | **这款 App 自己塞进去的全部内容**（520 条文案 + 一段提示音） |

引擎 + Dart 机器码 = 17,203,752 字节，占 94%；自己的素材 58,779 字节，占 0.3%。

拿一个同版本 SDK 出的**空壳 Flutter Demo**（`flutter create` 后原样 `build apk --release --split-per-abi`）对照，同样的 arm64 release：

| | 空壳 Demo | 时笺 | 差值 |
| --- | --- | --- | --- |
| APK | 15,503,242 | 17,917,607 | +2,414,365 |
| `libflutter.so`（引擎） | 11,763,360 | 11,763,360 | **0**（逐字节相同） |
| `libapp.so`（Dart AOT） | 3,212,168 | 5,440,392 | +2,228,224 |
| `classes.dex` | 520,160 | 573,424 | +53,264 |
| `NOTICES.Z` | 98,182 | 111,200 | +13,018 |
| 图标字体合计 | 258,996（含 Demo 自带的 `CupertinoIcons.ttf` 257,628） | 2,352（tree-shake 后的 `MaterialIcons`，从 1,645,184 压到 99.9%↓） | −256,644 |

结论：17MB 里 11.8MB 是 Flutter 引擎的固定成本（空壳也要），2.2MB 是 4 个插件 + 自己全部 Dart 代码的 AOT 产物，素材 5.9 万字节 —— 体积不是「功能做大了」，是框架底价。

真正能省的是**装对包**：平板装 `app-arm64-v8a-release.apk`（17.0 MB），别装 49MB 的 fat 包，`app-debug.apk`（174MB，带 JIT 与全部 ABI）只用于开发。要走 Google Play 就得改发 AAB，由商店按设备下发单 ABI + 资源压缩，用户侧还能再小一截。换掉 `audioplayers` 之类的减重没做：插件的原生胶水在 dex 里，实测拆不出单独归属，收益是几十 KB 量级，不值得为它牺牲提示音。依赖清单本身也没有赘肉 —— `pubspec.yaml` 的 6 个非鸿蒙依赖逐个用 `grep -rl "package:<依赖>/"` 查过 `lib/`，全部真被 import（riverpod 8 个文件、hive/hive_flutter 与 wakelock_plus/audioplayers 各 1 个），没有可以「删了就直接小一点」的死依赖。

这两条是**本机 `~/.gradle` 的前置，不在仓库里**，换机器要照做（否则分别卡在依赖下载和 Kotlin 增量缓存，见 HANDOFF 坑 I / 坑 J）：

| 文件 | 内容 | 为什么 |
| --- | --- | --- |
| `~/.gradle/init.d/cn-mirror.gradle` | 把 `repo.maven.apache.org` / `plugins.gradle.org` 两个 URL **原地**换成 `maven.aliyun.com/repository/{public,gradle-plugin}` | 这两个源在 Cloudflare 上，本机会被静默挂住十几分钟。注意只能改 URL，新增仓库会撞 `settings.gradle.kts` 的 `repositoriesMode` 校验 |
| `~/.gradle/gradle.properties` | `kotlin.incremental=false` | 中途 kill 掉的构建会留下损坏的 Kotlin 增量缓存，`flutter clean` / 停 daemon / 腾内存 / 单 worker 四种办法实测都救不回来 |

## 🤖 云端构建可安装包（GitHub Actions）

推送 main 或手动触发都会跑 `pub get` → `analyze` → `test` → `build apk`，产物有两个去处：

| 平台 | 能不能装 | 在哪拿 |
| --- | --- | --- |
| **Android 平板** | ✅ 可直接安装 | Release 页的 `dev-build` 预发布（公开直链，免登录、不过期）：`app-arm64-v8a-release.apk`（平板优先）、`app-armeabi-v7a-release.apk`、`app-x86_64-release.apk`（模拟器/Chromebook）、`app-release.apk`（通用包）；另附 `apk-sha256.txt` 校验和（4 行，run #10 起含通用包） |
| Android（同批产物） | ✅ | 每次 run 的 Artifacts `timenote-release-apk`（要登录 GitHub，默认保留 90 天） |
| **iPad** | ❌ 装不上真机 | 只在手动触发勾选 `ios` 时构建（`flutter build ios --no-codesign`），产物是未签名 `Runner.app.zip`。要能装必须在仓库 secrets 里放 Apple 签名凭据，走 Xcode 签好再上 TestFlight/Ad Hoc |
| **华为鸿蒙平板** | ⚠️ 本机能出包，云端出不了 | 本机 `tool/build_hap.sh` → `build/ohos/hap/entry-default-unsigned.hap`（**未签名，装不上真机**；调试证书要华为账号在 DevEco 里申请）。GitHub Runner 拿不到 Flutter-OH SDK + 华为 Command Line Tools（在华为账号墙后），所以 CI 不构建鸿蒙 |

```bash
git push   # 云端构建完自动覆盖 dev-build 预发布的附件
```

- APK 用 **debug keystore 签名**（`android/app/build.gradle.kts` 的 release 构建沿用 debug 签名配置）：允许「未知来源应用」后点开即装，可自用与分发测试，但**不能上传 Google Play**。
- 应用图标 PNG 已经在仓库里（`android/app/src/main/res/mipmap-*/ic_launcher.png`，5 个 dpi），提示音 `alert.wav` 也在。`gradle-wrapper.jar` / `gradlew` **故意不入库**：Flutter 把 wrapper 归在 `DevelopmentArtifact.universal` 缓存产物里，每次构建 Android 前都会注入且**不覆盖已存在的文件**（`gradle_utils.dart:261-264`），所以 CI 原来那段 `curl` 下载步骤已删。本机验证方式：把 `gradlew`/`gradlew.bat`/jar/`local.properties` 四个移走模拟干净检出，`flutter build apk --release --split-per-abi` 仍然 23.9 s 出包并把四个文件补回来。
- `dev-build` 这个 tag 由 CI 自己创建并复用，每次推 main 覆盖同名附件，所以永远只有一个「最新开发版」，不会攒一堆 release。

**首轮真实验证（run #9，`cdceae9`）**：构建链全绿，`dev-build` 预发布被创建并发布出来，但 run 结论是 `failure` —— 挂的是最后一步里那句纯打印的自检（步骤只跑了 6 秒，附件那时已经传完），所以是「红叉但包已经发出去了」。要区分「没发出去」和「发出去后自检语句挂了」，看 run 的 steps 表而不是看红叉。

**第二轮真实验证（run #10，`e628133`，2026-11-05）**：android job **13 步全 `success`**（446 秒，其中构建 APK 306 秒），ios 按设计 skipped。`dev-build` 现在是 5 个附件，免登录就能拿（本机直链会被截，稳妥走法见下面「字节级核过一遍」那条）：

| 附件 | 字节 |
| --- | --- |
| `app-arm64-v8a-release.apk`（平板优先） | 17,909,554 |
| `app-armeabi-v7a-release.apk`（很老的 32 位机） | 15,263,372 |
| `app-x86_64-release.apk`（模拟器 / Chromebook） | 19,335,481 |
| `app-release.apk`（通用包） | 51,432,169 |
| `apk-sha256.txt` | 357（4 行，通用包也在内） |

- ✅ run #9 那句拖红的打印**已修且已生效**：现在包在 `if summary=$(… 2>&1)` 里，失败时发一行 `::warning::` annotation（值先 `tr '\r\n' '  '` 压单行、再 `sed 's/%/%25/g'`），第 10 步 5 秒 `success`。选 annotation 而不是丢日志，是因为日志下载接口要 admin 权限（实测 403），`/check-runs/{id}/annotations` 免登录就能读。
- ✅ **顺带把 run #9 的根因挖了出来**：那条 annotation 把 gh 的原文带出来了 —— `Unknown JSON field: "prerelease" … Available fields: … isPrerelease …`。所以不是打印玄学失败，是 `--json` 字段名写错，gh 的字段叫 `isPrerelease`。改对之后 **run #11（head `94ddb91`）android 13 步全 `success`**（构建 APK 289 秒、发布步 6 秒），annotations 只剩 GitHub 自己的 2 条 boilerplate，dev-build 那条 warning 不再出现 —— 两个分支必走其一，没 warning 就等于摘要日志打出来了。日志正文要 admin 才能下载（实测 403），所以「摘要长什么样」属于推断，没亲眼看过。
- ✅ `apk-sha256.txt` 从 275 字节 3 行变成 357 字节 4 行。根因不是笔误而是 glob：`app-*-release.apk` 匹配不到 `app-release.apk`（`app-` 之后还要一个字面的 `-release.apk`，`*` 匹配空也只凑得出 `app--release.apk`）—— 本机 `touch` 出 5 个 apk 跑 `ls` 实测过，现在改成逐个点名。Artifacts 也同步确认：`timenote-release-apk` 从 24,897,396 涨到 48,773,766 字节（接近翻倍，与 3 包→4 包的比例一致）。
- ⚠️ **同一个包每轮构建的 sha256 都不同**：run #10 的 arm64 是 `9e03d469cb66…`，run #11 是 `357d9e82c16b…`，而字节数完全一样（17,909,554）。原因是 debug keystore 在 Runner 上每轮现生成，签名块变长不变 —— 所以 sha256 只能用来核对「**同一次 run** 的附件 == 同一次 run 的清单」，不能当版本标识、也不能跨轮比较。要确认装上去的是哪次提交，看 `dev-build` 正文首行的「最新提交：`xxxxxxx`」（实测 run #10=`e628133`、run #11=`94ddb91`）。同理别拿本机 arm64（17,917,607）去核对云端附件。
- ✅ **字节级核过一遍**：run #11 的 `app-arm64-v8a-release.apk` 整份下回来 `sha256sum` = `357d9e82c16b…`，与**同一轮** `apk-sha256.txt` 第一行逐字相同，`wc -c` = 17,909,554，文件头尾也是合法 ZIP（`504b0304` + `504b0506`）。下载只能走 `api.github.com/.../releases/assets/{id}` + `Accept: application/octet-stream` + `curl -sL -C -` 断点续传（实测 8 轮才凑满，单轮增量 0.34 MB～5.9 MB 都不等）；`releases/download/...` 直链在本机停在 3,134,272 字节而 `-w` 仍报 HTTP=200，所以**别信状态码，要比字节数**。
- ⚠️ `gh release upload --clobber` 是删了重建附件，asset id 每轮换（arm64 `712511360`→`712600392`）。旧 id 并不会下载失败，坏在**错配**：拿上一轮的字节核这一轮的清单，会得到「哈希被改」的假信号 —— 下之前重新取一次 `releases/tags/dev-build`。

## 🖼 界面风格（11 套整屏令牌）

参考 [luckymaomi/ui-styles](https://luckymaomi.github.io/ui/styles/) 的 10 套风格页移植而来，令牌集中在 `lib/theme/ui_style.dart`（`uiStyleSpecs`，每套 `(亮, 暗)` 两版）。

| 设置里的名字 | 参考页 | 哪一版是页面原值 |
| --- | --- | --- |
| 无装饰（原样） | — | 两版都是引入令牌层之前的外观，回归基线 |
| 编辑部 | [/editorial/](https://luckymaomi.github.io/ui/styles/editorial/) | 亮版（米白 + 墨黑 + 0 圆角细线，衬线大字距） |
| 软胶拟物 | [/neumorphism/](https://luckymaomi.github.io/ui/styles/neumorphism/) | 亮版（`#e0e5ec` + 一暗一亮双影） |
| 便当格 | [/bento-grid/](https://luckymaomi.github.io/ui/styles/bento-grid/) | 两版（`#fafafa` / `#18181b`，暗版卡片描边按 zinc 色阶推导） |
| 自然有机 | [/natural-organic/](https://luckymaomi.github.io/ui/styles/natural-organic/) | 亮版（土色族 + 团块 + 颗粒） |
| 复古印刷 | [/retro-vintage/](https://luckymaomi.github.io/ui/styles/retro-vintage/) | 亮版（`#f5e6d3` + 3px 线框 + 大写衬线） |
| 暗色分层 | [/dark-mode/](https://luckymaomi.github.io/ui/styles/dark-mode/) | 暗版（slate 色阶 + 上缘内高光） |
| 系统毛玻璃 | [/macos-vibrancy/](https://luckymaomi.github.io/ui/styles/macos-vibrancy/) | 暗版（`1c1c1e/2c2c2e/3a3a3c` 分层 + 1px 亮线） |
| 超现实 | [/surrealism/](https://luckymaomi.github.io/ui/styles/surrealism/) | 两版（`#1a1a3e→#c38d94` 渐变 / `#f0ece4`） |
| 哥特洛丽塔 | [/gothic-lolita/](https://luckymaomi.github.io/ui/styles/gothic-lolita/) | 暗版（黑紫渐变 + `#e5e5e5`） |
| 视觉小说 | [/visual-novel/](https://luckymaomi.github.io/ui/styles/visual-novel/) | 亮版（天空四段渐变 + 白 70% 面板） |

- 表里没有标出的那一版按「同族色阶反转」补齐，每条令牌的 `provenance` 字段用 `page:` / `derived:` 区分了来源，测试会检查这个标记非空。
- **正交**：界面风格只换「环境」（背景、数字底板的填充/描边/光影/圆角、标签字体与字距），10 种数字风格仍决定「字形」；`无装饰（原样）` 下渲染路径与之前完全一致。
- **性能**：颗粒/团块/花纹是静态 `CustomPaint` + `RepaintBoundary`，与每秒重建的时钟子树分离，随机数按固定种子生成，不逐帧重算。
- **已实机验证**：11 套风格在 Android 模拟器（Pixel 7 AVD，density 420，横屏 914x411 逻辑像素）逐套切过，整屏底色与数字底板确实随风格变化，切换前后截图对过；widget 侧另有 800×600 全矩阵冒烟（无异常、无溢出）。
- **未验证**：鸿蒙侧 —— release HAP 未签名装不上真机，`serif`/`monospace` 在 HarmonyOS 的字体族映射因此没实测过（Android 侧已实测正常）。

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

- [x] 连设备验证常亮 / 横屏 / 提示音 / 倒计时与抽屉 —— Android 模拟器（Pixel 7 AVD）已逐项目视 + `dumpsys` 验过，详见 [HANDOFF-OHOS.md](./HANDOFF-OHOS.md) §6.6；顺带抓出并修掉一个只有真机才暴露的缺陷（横屏软键盘把自定义倒计时弹窗压瘪，输入框整块不可见），补了 2 条回归测试。**待补**：实体平板 + 华为鸿蒙真机。
  - ⚠️ 边缘滑动开抽屉没单独实测（点按钮 `openEndDrawer()` 那条路径验过，滑动本身是 Scaffold 自带）。
- [ ] 下载并打包 5 款免费商用字体
- [x] 定下 `gradle-wrapper.jar` 与图标是否纳入版本库 —— 图标 5 个 dpi 已入库；wrapper 决定**不入库**，改为删掉 CI 的下载步骤（Flutter 自己会注入，已按干净检出实测），少一个 `raw.githubusercontent.com` 依赖。
- [ ] 华为鸿蒙（Flutter-OH）适配：**已打通本机出包，debug 与 `--release` 都跑过，翻页动画重做后又各复跑一次（两次 `EXIT=0`）** —— `tool/build_hap.sh` 一键出未签名 HAP（AOT release 22,748,875 字节），平板/横屏声明、「时笺」文案、图标已入库并在包内复验。剩下的只有签名（要华为账号在 DevEco 申请调试证书）与装到真机上的运行验证。细节、复现命令与待办见 [HANDOFF-OHOS.md](./HANDOFF-OHOS.md)
- [ ] iOS 签名与上架

## 📄 License

[MIT](./LICENSE)
