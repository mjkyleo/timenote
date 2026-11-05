# TimeNote 架构与代码质量评审报告

- 评审基线：`main` @ `7abb6fd`（修复前）→ 本报告同时记录修复后状态
- 评审方式：逐条读源码 + 跑工具验证，每个结论都附可复现命令
- 工具链：Flutter 3.47.8 stable / Dart 3.13.7（`D:\dev\flutter`），Windows 10 26200
- 结论：**7abb6fd 无法编译、无法构建资源包**，因此原先「0 CRITICAL / 评审通过」的结论不成立。本次共确认 12 项问题（3 个 P0；其中 R12 是本次新增代码自查发现，其余 11 项为存量缺陷）。

## 一、实测记录

| 命令 | 修复前（7abb6fd） | 修复后（工作区） |
| --- | --- | --- |
| `flutter analyze` | 语法错误阻断（见 R1），无法给出干净结果 | `No issues found!` |
| `flutter test` | 资源缺失直接失败（见 R2） | `+52: All tests passed!`（6 个测试文件） |
| 临时移走 `assets/audio/` 再跑 `flutter test` | — | `Error detected in pubspec.yaml: No file or variants found for asset: assets/audio/alert.wav. / Error: Failed to build asset bundle` |

测试分布（第一轮修复后）：`app_widget_test.dart` 18、`flip_rendering_test.dart` 11、`clock_notifier_test.dart` 12、`todo_model_test.dart` 5、`storage_service_test.dart` 3、`egg_service_test.dart` 3。第三轮之后为 86 例，逐文件分布见 §9.6。

## 二、缺陷清单与处置

严重度定义：P0 = 阻断构建/核心画面不可用；P1 = 功能与用户可见行为错误；P2 = 体验、一致性或工程健康度。

### R1 · P0 · 编译不过：`clock_view.dart` 里有一段被截断的扩散运算符

- 证据：`git show 7abb6fd:lib/flip_clock/clock_view.dart | grep -n '\[n'` → `205: if (clockState.workMode == ClockWorkMode.countdown) ...[n   const SizedBox(width: 10),`
- 影响：整个 app 无法编译，「暂停/继续/停止」三个按钮所在的 `if` 列表写法被写坏（`...[n`）。
- 处置：主屏控制区重写为 `_controls()` + `_chip()` 列表（`lib/flip_clock/clock_view.dart:253`）。

### R2 · P0：`pubspec.yaml` 声明了不存在的资源

- 证据：`git show 7abb6fd:pubspec.yaml` 声明 `assets/audio/alert.wav`；`git ls-tree -r 7abb6fd --name-only assets` 只有 `assets/data/quotes.json`。
- 影响：新克隆后 `flutter test` / `flutter build` 全部失败（上面第三条实测就是这个报错），并非「运行时才降级」。
- 处置：补入本地生成的占位提示音 `assets/audio/alert.wav`（44.1kHz / 单声道 / 16bit PCM，30912 字节，指数衰减 880Hz 短音），并纳入版本库；CI 里原来「云端重建 wav」的步骤随之删除（`.github/workflows/build-apk.yml`）。图标与 `gradle-wrapper.jar` 仍由 CI 生成。

### R3 · P0：书页卷曲翻页把数字永久冻在侧立态（看不见）

- 证据：`git show 7abb6fd:lib/flip_clock/flip_renderer.dart` 的 `PageCurlRenderer` 在 `transitionBuilder` 里直接 `rotateY(1.57 * (1 - anim.value))`。`transitionBuilder` 只在建子节点时执行一次，不监听 `animation`，所以 `anim.value` 永远是入场瞬间的 0 → 角度停在 1.57rad。
- 可观测结果：矩阵 `y` 基向量分量 `cos(π/2) = 6.12e-17`，即数字变成一条边，等于消失。
- 处置：`_FlipTransform` 改为 `AnimatedBuilder` 监听动画（`lib/flip_clock/flip_renderer.dart:37`），5 种动画统一「value==1 回到平铺」的约定。
- 回归测试与反向验证：`test/flip_rendering_test.dart` 的「切换数字后仍会回到静止态」。把 `AnimatedBuilder` 还原成一次性读 `anim.value` 后，该用例报错 `Expected: a value greater than <0.9> / Actual: <6.123233995736766e-17>`，确认测试真能钉住这个 bug。

### R4 · P1：10 种数字风格实际画面上完全一样

- 证据：`git show 7abb6fd:lib/core/constants.dart` 的 `styleFontMap` 把 10 个风格映射到 5 个字体 family；`git show 7abb6fd:pubspec.yaml` 里**没有 `fonts:` 段**，`assets/` 只有 quotes/audio。未打包的 family 会静默回退系统字体。
- 影响：风格差异只剩 `fontFamily` 这一个维度，而它本身失效 → 用户切 10 次设置，画面一动不动。其余渲染参数（字号 120、`FontWeight.bold`）在所有渲染器里写死。
- 处置：新增 `ClockLook` 外观表（字重 / 斜体 / 字距 / 字号倍率 / 描边宽度 / 底板不透明度 / 圆角 / 内边距 / 中缝 / 等宽数字 10 个维度），字体降级为其中一个可选维度（`lib/flip_clock/flip_renderer.dart:177` 起）。
- 回归测试：「两两之间至少有一个可见维度不同」「镂空描边样式只描边不填充」。反向验证：把 `appearanceFor` 改成恒返回 `const ClockLook()` 后这两条同时变红。

### R5 · P1：倒计时用 `Timer.periodic` 自减，与真实时间脱钩

- 证据：`git show 7abb6fd:lib/core/providers/clock_providers.dart:62` → `Timer.periodic(1s)` 里 `state.remainTime - 1s`。
- 影响：平板息屏/切后台/系统挂起期间 timer 不触发或不精确，倒计时会「漏走」；专注计时器的核心正确性问题。同一逻辑在 `resumeCountdown` 里被复制了一遍。
- 处置：改为**墙钟 deadline 锚定**（`lib/core/providers/clock_providers.dart:78`），250ms 轮询、剩余时间向上取整到整秒、只有整秒变化才发布状态；时间源通过 `clockSourceProvider` 注入，测试用假时钟精确驱动。

### R6 · P1：手动「停止」误触发彩蛋，并把画面留在 `00:00:00`

- 证据：7abb6fd 的 `stopCountdown()` 只把 `remainTime` 置 0、`isRunning` 置 false，不改 `workMode`；而主屏监听的条件是 `prev.remainTime > 0 && next.remainTime == 0 && next.workMode == countdown`。
- 影响：点「停止」= 归零 → 弹出彩蛋文案 + 提示音，且主屏停在 `00:00:00` 死屏。
- 处置：`stopCountdown()` 现在等价于 `switchRealtime()`（回到实时时钟）；彩蛋的收尾同样回到实时时钟，不留 `00:00:00`。关掉彩蛋时保留 `00:00:00` 结束态（有明确的停止/时钟按钮），这是刻意区分开的两种状态。
- 回归测试：`app_widget_test.dart` 的「停止倒计时回到实时时钟，不留 00:00:00 死屏」「归零展示彩蛋，点任意处返回时钟」「关闭彩蛋后归零保留 00:00:00 结束态」。

### R7 · P1：彩蛋被提示音 `await` 挡在后面，且计时不可取消

- 证据：`git show 7abb6fd:lib/flip_clock/clock_view.dart:77-96` → `await _audioPlayer.play(...)` 在 `setState(egg)` 之前；隐藏用的是 `Future.delayed(...)`，没有 `Timer` 句柄，既不能取消也不在 `dispose` 里清理。
- 影响：音频链路（平台通道 + 资源解码）慢或卡住时，视觉反馈跟着延迟；提前点掉彩蛋后，旧的 delayed 回调仍会在 5 秒后回来改状态。
- 处置：彩蛋先上屏，再尽力播提示音（`AudioPlayer` 懒创建，失败静默降级）；隐藏改用可取消的 `Timer`（`lib/flip_clock/clock_view.dart:102`）。
- 未自动化覆盖，见第五节边界说明。

### R8 · P2：`keepScreenOn` 关掉后不生效，要重启

- 证据：7abb6fd 只在 `initState` 的 `addPostFrameCallback` 里读一次设置并 `WakelockPlus.enable()`，没有跟随设置变化；`dispose` 里无条件 `disable()`。
- 处置：用 `ref.listenManual(appSettingsNotifierProvider.select((s) => s.keepScreenOn))` 即时下发 enable/disable。
- 回归测试：通过 `wakelock_plus_platform_interface` 的测试缝注入 fake platform，断言调用序列（`test/support/fake_wakelock.dart`）。

### R9 · P2：功能缺口（不是 bug，但影响可用性）

本次补齐：自定义倒计时分钟数（1–600，带非法输入校验与 15/30/45/60 快选）、倒计时进度条、设置页实时预览（用真正的 `FlipCardWidget` 每 2 秒轮换样张）、无操作 6 秒自动隐藏控件且一点即回、待办「清除已完成」、待办计数 `未完成/总数`、空态文案、输入长度 60 限制与乐观更新。

### R10 · P2：原 `REVIEW.md` 的结论与代码事实冲突

- 证据：7abb6fd 的 `REVIEW.md` 写着「0 CRITICAL · 无阻断发布问题」和「`flutter analyze → No issues found!`、`flutter test → 14 tests passed`」；而 7abb6fd 实际存在 R1（编译不过）与 R2（构建产物缺失），`test/` 下只有 4 个文件、8 个用例。它还把 H1 描述为「await 音频后缺少 `mounted` 校验」，但 7abb6fd 源码 `clock_view.dart:87` 明明有 `if (!mounted) return;`。
- 处置：本文件按实测重写。以后所有评审数字都应来自当场跑出来的命令输出。

### R11 · P2：测试基建无法覆盖真实依赖（导致「测过」不可信）

- 症状：直接在 `testWidgets` 里用 Hive 磁盘后端或 audioplayers，测试进程会挂死（实测 6 分钟不返回）。
- 根因：`testWidgets` 跑在 fake-async 区，真实文件/平台 IO 的完成回调被投到测试结束后已销毁的 zone，Hive 的写事务与 `Hive.close()` 永远等不到。
- 处置：三条注入缝 + 分层
  - 时间：`clockSourceProvider`（假时钟）
  - 常亮：`wakelockPlusPlatformInstance`（fake platform）
  - 存储：widget 测试用 Hive 内存后端（`test/support/fake_storage.dart`），**磁盘落盘改由普通 `test()` 验证**（`test/storage_service_test.dart`：写盘→关箱→重开→读回 + 脏数据容忍 + 未初始化降级）
  - 音频：widget 测试固定 `soundEnable=false`

### R12 · 本次新增代码里发现并修掉的缺陷（诚实记录）

`_askCustomCountdown` 原先在父组件里 `controller.dispose()`，弹窗退场动画期间 `TextField` 仍会重新监听 → 实测抛 `A TextEditingController was used after being disposed`，并级联出 `A RenderFlex overflowed by 99672 pixels`、`getTransformTo` 断言、`_dependents.isEmpty` 等一串错误，还会污染同文件后续用例（设置组两条用例被连带拖红）。改为由弹窗 State 自己持有并释放 controller 后，17 条用例全绿。这条也是「错误程度很高」的实际案例。

## 三、重构范围

`git diff --stat 7abb6fd -- lib` = 16 个文件、+1292/−657。属于「按严重度触发」的重构只有两处：

1. `lib/flip_clock/flip_renderer.dart` 整体重写（R3 + R4 的根因都在这一层：过渡构建与外观参数原先混在各渲染器内部写死）。现在 `FlipRenderer.transition(child, anim)` 只管过渡，外观由 `clockLooks` 表 + `clockTextStyle()` 统一产出，`FlipCardWidget` 单点负责自适应与底板。
2. `lib/core/providers/clock_providers.dart` 重写（R5 + R6）：状态多了 `total`（进度用），走时改为 deadline 锚定，pause/resume/stop 语义各自单独定义。

其余为局部修改，没有引入新分层，`core / flip_clock / todo / settings / egg` 五层结构保持不变。

## 四、质量属性场景（后续要守住的）

- **正确性**：倒计时在后台/挂起后仍与墙钟一致 → 由 `clock_notifier_test.dart`（12 例，`fakeAsync` + 注入时间源）守住。
- **可辨识性**：10 种风格两两可辨、5 种动画静止态可见 → `flip_rendering_test.dart` 11 例。
- **持久化**：待办/设置跨重启读回、脏数据丢弃 → `storage_service_test.dart` 3 例（真实磁盘）。
- **交互真实性**：抽屉真的滑进可视区、按钮真的能点、控件隐藏后点击不误开设置 → `app_widget_test.dart` 18 例（含「文案库最长那条不溢出」）。

## 五、验证边界（没做到的部分，明确声明）

1. **没有在真机或模拟器上运行过**。本机没有连接 Android 设备，因此以下都只有代码与单元测试层面的保证：Android/iOS 上的 wakelock 实际效果、横屏锁定、Hive 在设备数据目录的读写、音频真实播放、APK 产物安装。
2. **提示音路径未被自动化测试覆盖**：audioplayers 6 需要「资源→临时文件」的真实 IO，在 fake-async 区不可等待，所以 widget 测试统一关掉 `soundEnable`。「彩蛋先于提示音上屏、音频失败不影响视觉」这条顺序目前只有源码结构保证。
3. `assets/fonts` 仍是空的：风格差异不依赖字体文件，但 README 里列的 5 款字体尚未打包，`styleFontMap` 的 family 名在当前构建里是惰性的（回退系统字体）。
4. 彩蛋文案：`assets/data/quotes.json` 已由远端提交 `da4d43f` 补齐 520 条（本报告已 rebase 到其上）。本次实测该文件：JSON 可解析、520 条全为非空字符串、无重复、最长 89 字；`egg_service_test.dart` 断言「≥520 条 / 无重复 / 抽取必属池内且不连续重复」，`app_widget_test.dart` 用「最长那条」跑了一遍 800×600 渲染确认无异常。**没做的是人工审校**——文案出处、错别字、中英混排一致性未经核对，也不保证符合原「书籍 / 优质外文 / 社区摘录」的分类预期（文件是扁平数组，没有分类字段）。
5. CI（`.github/workflows/build-apk.yml`）改动未经 GitHub 实跑验证——analyze/test/build 三步的本地等价命令已跑通。

## 六、建议的后续动作（按性价比排序）

1. 连一台 Android 设备跑 `flutter run`，人工确认常亮、横屏、提示音、抽屉手势；把结论补进本文件。
   - ✅ 2026-11-05 做了：Android 模拟器（Pixel 7 AVD，density 420，横屏）逐项验过常亮/横屏/提示音/倒计时/抽屉/翻页/彩蛋停留，并因此抓出**两个只有真机尺寸才暴露的缺陷**：① 横屏软键盘把自定义倒计时弹窗压瘪（`AlertDialog` 外边距 = viewInsets + insetPadding），已修 + 2 条回归测试；② 待机屏带着状态栏（3:05 / LTE / 电量 / 手势条），破坏 Fliqlo 式整屏观感，已改为 `SystemUiMode.immersiveSticky`（鸿蒙侧 `flutter_ohos` 的 `PlatformPlugin` 有显式实现，不是空调用）。过程见 [HANDOFF-OHOS.md](./HANDOFF-OHOS.md) §6.6 / §6.7。边缘滑动开抽屉仍未单独实测。
2. 决定 `gradle-wrapper.jar` 与应用图标是否纳入版本库；纳入后可以删掉 CI 里两段生成逻辑（现在是 CI 从 `raw.githubusercontent.com` 下载 jar，属于隐性供应链面）。
   - ✅ 2026-11-05 做了，但选择**不提交 jar**：Flutter 把 wrapper 归为 `DevelopmentArtifact.universal` 缓存产物，构建前必注入且 `shouldCopyFile: !destinationFile.existsSync()` 不覆盖工程文件（`gradle_utils.dart:261-264`）—— 本机模拟干净检出（移走 `gradlew`/`gradlew.bat`/jar/`local.properties`）后同一条 CI 命令 23.9 s 正常出包。CI 的 curl 下载步骤已删，隐性供应链面照样消掉。图标 5 个 dpi 则真实入库。
3. 若要真正兑现「10 种画面风格」，打包 5 款免费商用字体并在 `pubspec.yaml` 声明 `fonts:`，同时把 `styleFontMap` 的 family 名与字体文件名校对一遍。
4. 逐条审校 520 条文案（出处、错别字、是否要按「惜时/学习/心动/向往/外文/国风」分类）；`EggService` 目前是静态可变状态，若以后要支持多语言/用户自定义，再考虑改成 Provider 注入。

## 七、复现本次评审的命令

```bash
export PATH="/d/dev/flutter/bin:$PATH"
flutter analyze            # No issues found!
flutter test               # 第一轮收尾 +52；第二轮（界面风格）后 +62

# 存量缺陷取证（相对 7abb6fd）
git show 7abb6fd:lib/flip_clock/clock_view.dart | grep -n '\[n'
git show 7abb6fd:pubspec.yaml | sed -n '24,30p'
git ls-tree -r 7abb6fd --name-only assets
git show 7abb6fd:lib/core/providers/clock_providers.dart | grep -n -A8 'Timer.periodic'
```

## 八、第二轮：11 套整屏「界面风格」

需求是给 App 换肤，参考 https://luckymaomi.github.io/ui/styles/ 的 10 套风格页。取舍与结论如下。

### 8.1 架构决定：与既有 10 种数字风格正交，而不是覆盖

- **界面风格管「环境」**：背景（纯色/渐变）、数字底板的填充/描边/光影/圆角、胶囊按钮圆角与描边、标签字族与字距。
- **数字风格仍管「字形」**：字重、字距、字号倍率、描边、中缝、等宽数字等 10 个维度不变。
- 落法：`UiTokens`（const 令牌袋）+ `uiStyleSpecs`（`Map<UiStyle, (亮, 暗)>`）+ `UiScope`（InheritedWidget，挂在 `MaterialApp.builder` 上，抽屉/弹窗/设置路由一次注入全覆盖）+ `UiLayer`（背景层 + 三张静态 `CustomPaint` 装饰层）。
- 没用 `ThemeExtension`：要写 20 个字段的 `copyWith`，而且主题对象语义上是「全局」，这里要的是「当前选中的一套」，InheritedWidget 更贴。
- 没打包字体：衬线/等宽走 Android 系统别名 `serif` / `monospace`，并带 `fontFamilyFallback`。

### 8.2 回归保护：`UiStyle.classic` 必须等于引入前

classic 的两版令牌没有任何底板装饰（`hasPlateDecor == false`），`flip_card_widget` 在「无填充/无描边/无阴影」时直接 early-return 原 subtree，`main.dart` 的 Material seed 也仍是 `#46586B`。因此第一轮那 52 例一字未改仍全绿，这条是刻意设计的验收线。

### 8.3 本轮修掉的三个真实缺陷

1. **实时时钟没走可注入时间源（测试 flaky 的根因）**。`ClockTimeDisplay` 直接读 `DateTime.now()`，而 `clockSourceProvider` 这个缝只有倒计时在用。于是任何按 `HH:MM:SS` 通配去数控件的用例，只要 pump 期间跨过一次真实秒边界，`AnimatedSwitcher` 就会同时挂着新旧两份文本，`find.textContaining(RegExp(r'\d{2}:\d{2}:\d{2}'))` 报 "is too many"。`app_widget_test.dart:384` 那个 `.first` 就是这个症状的历史绕法。改法：`ClockTimeDisplay` 增加 `now` 字段，由 `clock_view` 在 `initState` 阶段从 provider 取一次（这样覆盖值变化时会重建 State，测试注入新的假时钟会真的生效）。实测：修复前全量套件连跑 6 次红 3 次（失败用例在 `app_widget_test` 与 `ui_style_test` 之间漂移），修复后连跑 5 次 `+62 All tests passed!`。
2. **`UiLayer` 吞掉 ripple**。带底色的 `DecoratedBox` 成为 `ListTile` 的最近 Material 祖先，测试里出现 6 条 "this DecoratedBox will hide those effects"。补 `Material(type: MaterialType.transparency)` 作为 Stack 的最后一层。
3. **`(亮, 暗)` 顺序没有测试保护**。`uiStyleSpecs` 的 record 字段写反不会被「两版底色不同」抓住，补了不变量「亮版 bg 相对亮度必须高于暗版」，11 套全过；同时把 `_darkModeTokens` 改名 `_darkModeDark`，与其余 10 套的命名一致。

### 8.4 反向验证（确认测试不是恒真）

撤掉 `flip_card_widget.dart` 里 `tokens.plateFill ??` 这一处消费点 → 目标用例「带阴影的风格真的把阴影画到了数字底板上」立刻变红（`plate.color` 变成 `null`），其余用例不受影响；从备份 `cp` 还原后 md5 与备份一致，62 例重新全绿。

### 8.5 诚实边界

- **毛玻璃是模拟的**：真 `BackdropFilter` 需要可模糊的背景内容，待机屏是纯色/渐变，糊不出东西，所以用「半透明分层 + 1px 亮线」表达同一套视觉规则。
- **颗粒/团块/花纹是固定种子的静态绘制**，放在 `RepaintBoundary` 里且位于每秒重建的时钟子树之外，不逐帧重算随机数；但没有在真机上量过帧率。
- 11 套 × 黑白 = 22 组只做了 800×600 的 widget 冒烟（主屏 + 抽屉 + 设置页，`takeException` 为空即无异常无溢出），**观感未经人眼验收**，字体族在其他平台的回退也未实测。
  - 【2026-11-05 更新】观感这一条已经补上：Android 模拟器（Pixel 7 AVD，density 420，横屏）逐套切过并截图对比，`serif`/`monospace` 在 Android 的映射正常；顺带在真机尺寸下抓出一个 widget 测试测不到的缺陷（横屏软键盘把自定义倒计时弹窗压瘪，`dialog.dart:268` 的外边距 = viewInsets + insetPadding），修复 + 2 条回归测试见 [HANDOFF-OHOS.md](./HANDOFF-OHOS.md) §6.6，套件 62 → 64 例。仍未实测：鸿蒙（未签名装不上真机）、真机帧率。

### 8.6 本轮规模（实测）

`git diff --cached --stat`（含新文件）：**15 个文件，+1312 / −143**，其中 `lib/` 11 个文件、新增层次 `lib/theme/` 与 `test/ui_style_test.dart`。测试从 52 例增至 **62 例**（`ui_style_test.dart` 10 例：令牌完整性 5 例 + 风格真生效与全矩阵 5 例）。

## 九、第三轮：翻页动画重做 + 沉浸式待机 + 设置分栏 + 包体溯源

用户反馈原话：「翻页的动画太生硬了，而且开始以后没有隐藏那些倒计时的按钮，理想的效果是一种沉浸式的，点击开始以后才开始……设置中的一个布局不合理，还有这个软件为什么这么大呢，功能这么简单，不至于吧 / 关于动画不要局限在一种翻页效果，可以用不同的效果」。四条逐个记在下面。

### 9.1 「生硬」的根因是架构，不是调参

- 旧实现把整串 `HH:MM:SS` 交给一个 `AnimatedSwitcher`，`transitionBuilder` 给新旧两个 child **各自一份 0→1 的独立动画**，旋转轴在牌子几何中心。这种 API 形状**表达不了真实翻牌**：真实的中缝翻页是「上叶绕中缝倒下 → 翻到中途下叶接住继续 → 落平」，两半必须在同一个进度上协同，而 AnimatedSwitcher 只给每个 child 一条自己的曲线。所以无论怎么调 duration/curve 都还是「整块牌子绕中间转一下」，这就是生硬感的来源。
- 渲染层 API 改成 `FlipRenderer.transition(newChild:, oldChild:, t:)`（`lib/flip_clock/flip_renderer.dart:14`），并且**静止判定收进基类**：`t >= 1` 直接返回 `newChild`，只有 `< 1` 才进子类的 `flip()`。子类因此**不可能忘记回到平铺**——R3（书页卷曲把数字永久冻在侧立态）那一类缺陷的复发路径被结构性堵掉。
- **逐格翻**：`_FlipBoard` 把字符串拆成一格一个 `_FlipCell`（`lib/flip_clock/flip_card_widget.dart:149`、`:223`），只有 `char` 真的变化的那格起自己的 `AnimationController`（`:272`），`:` 和没变的位保持静止；格宽下限用 `TextPainter('0')` 量出来的宽度锁住（`:205`），否则走秒时整串会左右抖。
- **铰链与光影**：上叶用 `Align(heightFactor: 0.5, topCenter)` 裁出来后绕自己的下缘转（`alignment: bottomCenter`），下叶镜像绕上缘（`_hingedLeaf`，`lib/flip_clock/flip_renderer.dart:56`），四层 Stack 按「新牌在下、旧牌在上」叠，中缝不断裂；翻起的角度按 `|sin θ| × 0.62` 加深那面的渐变阴影（`:40`），靠缝受光、自由端进暗。
- **缓动分层**：0→0.42 用 `Curves.easeInCubic` 加速下落，0.42→1 用 `Curves.easeOutBack` 收尾（落下时有极小过冲＝回弹）；分段碎裂、滑动、滚筒也各自配了 `bounceOut`/`easeOutBack`，不再是线性。
- **动画从 5 种加到 8 种**：新增「滚筒走字」「落体回弹」「混合轮换」。混合轮换（`FlipAnimStyle.autoMix`，轮换表 `flipMixCycle` 见 `lib/flip_clock/flip_renderer.dart:399`）每次翻页换一种，把「不要局限一种」直接做成用户能选的一项，而不是替用户决定。

### 9.2 沉浸式待机：一处定义，按钮与入口一起退场

原先只有右上角两个 `IconButton` 被自动隐藏逻辑管着，底部倒计时胶囊不在其中——所以「点了开始之后屏幕上还是一排按钮」。现在 `_chrome()` 这个包装函数同时套在底部控件层和右上角入口上（`lib/flip_clock/clock_view.dart:99`）：淡出 250ms，同时 `IgnorePointer` 挡住误触，点屏幕任意处由最外层 `Listener` 唤回并重新计时 6 秒。**进度条不藏**——它是「还在计时」的唯一凭据，按钮才是噪声。

### 9.3 设置页分栏（那条没具体说的「布局不合理」）

用户没指明是哪一处，按实测定位到 `LayoutBuilder` 只看宽度：`constraints.maxWidth >= 760` 在横屏手机（Pixel 7 逻辑 914×411）也成立，于是走左右两栏，而预览高度写死 210、选项区只剩 145 高，一整屏滚不出几行。改成宽 + 高双条件判定（`lib/settings/settings_page.dart:47`），窄版按 42% 高度收放预览并夹在 140–240（`:51`）；选项 `Wrap` 补 `spacing/runSpacing`（`:183`），卡片标签 `Flexible` + 省略号，不再挤出越界。

### 9.4 「为什么这么大」——用空壳 Demo 对照实测

同版本 SDK 各出一个 arm64 release：空壳 `flutter create` Demo **15,503,242** 字节，时笺 **17,917,607** 字节，差 2,414,365。`libflutter.so` 两份**逐字节相同**（11,763,360），差值全在 `libapp.so`（Dart AOT，3,212,168 → 5,440,392，插件与自己的代码）和 dex 胶水（520,160 → 573,424）。自己的素材只有 `quotes.json` 27,867 + `alert.wav` 30,912 = 58,779 字节，占未压缩总量 18,268,158 的 0.3%。所以「功能这么简单却也 17MB」是 Flutter 的框架底价，不是包里有冗余。完整对照表在 README「本机出包（Android）」。

对照工程留在本机 `D:/scratch/sizeprobe`（`flutter create` 空壳，同 SDK 同参数出包，arm64 15,503,242 / arm32 12,709,602 / x86_64 16,945,556），随时可以重跑校验；它不属于仓库，不需要时可删。

### 9.5 反向验证（三条，改坏→必须变红→还原后全绿）

| 改坏的地方 | 应变红的用例 | 实测结果 |
| --- | --- | --- |
| 删掉 `_FlipCell.didUpdateWidget` 里「字符没变就 return」的判断 | 「只有变了的格子翻页，没变的格子保持静止」 | 红：`Found 2 widgets with type "Transform"…`，reason 打到 `1 这一格没变，不该被施加任何翻转变换` |
| 底部控件层不套 `_chrome()` | 「起表 6 秒后倒计时按钮一并隐去，点屏幕唤回后仍可操作」 | 红：`Expected: exactly 2 matching candidates / Actual: Found 1 widget with type "AnimatedOpacity"` |
| `_hingedLeaf` 的 `alignment` 从 `bottomCenter/topCenter` 改成 `center` | 「经典翻牌绕中缝铰链，而不是整块绕中心 tipping」 | 红：`实测铰链：[Alignment.center, Alignment.center]` |

三条还原后 `flutter analyze` → `No issues found!`，`flutter test` → `+86: All tests passed!`。

### 9.6 本轮数字（实测）

- 测试 64 → **86 例**：`app_widget_test.dart` 22、`flip_rendering_test.dart` 31、`ui_style_test.dart` 10、`clock_notifier_test.dart` 12、`storage_service_test.dart` 3、`todo_model_test.dart` 5、`egg_service_test.dart` 3（逐文件单独跑 `flutter test <file>` 取 `+N`，与全量 `+86` 一致）。
- 动画 5 种 → 8 种（含混合轮换）。
- APK（重新出包）：arm64 17,917,607 / arm32 15,255,041 / x86_64 19,343,534 / fat 51,423,838 / debug 182,984,197 字节。
- 出包时间对不上过，所以拿当前代码又重跑了一次 `--split-per-abi`（14:36）：三个 ABI 的字节数与 12:52 那次**逐个相同**（17,917,607 / 15,255,041 / 19,343,534）。13:04–13:08 对 `clock_view.dart`/`flip_renderer.dart` 的改动只是 §9.5 反向验证的「改坏→还原」，编译输入等价 —— 也就是说 §9.8 那批截图装的就是当前代码的包（这是**字节数级**的一致，不是 sha 级；fat 与 debug 两个包没重跑）。

### 9.7 边界（没做到的部分）

- 8 种动画与逐格翻页的正确性由 widget 测试保证（每个进度点都在动、t=1 只剩新数字、混合轮换 5 次翻页出现 >2 种不同中间态），**但「顺不顺眼」这件事测试给不出结论**；模拟器视验见 §9.8。
- 帧率没量过：新实现是每格一个 controller + 每帧若干 `Transform`/`DecoratedBox`，逻辑上只在真正变化的格子与动画期间重建，但未在设备上抓过 frame timeline。

### 9.8 模拟器实机视验（①动画 ②沉浸式 ③设置布局看图确认；④包体是数字对照，见 §9.4）

环境：AVD `trace_pixel7`，`hw.lcd.width/height = 1080×2400`、`hw.lcd.density = 420`（即 scale 2.625，横屏逻辑 **914.3×411.4**），system image `android-36 google_apis_playstore x86_64`；装的是本轮重出的 `app-x86_64-release.apk`（19,343,534 字节）。截图在 `C:\Users\86132\AppData\Local\Temp\shots\`。

第一次启动被坏快照卡住：`error while loading state for instance 0x0 of device 'kvm-tpr-opt'` / `Failed to load snapshot 'default_boot'`，设备一直停在 `offline`。杀掉 qemu 进程树后改用无头且不落快照的参数重启，44 秒进入桌面：

```
emulator -avd trace_pixel7 -no-window -no-snapshot-save -no-boot-anim -no-audio -gpu swiftshader_indirect
```

| 图 | 证的是哪一条 | 图里能看到什么 |
| --- | --- | --- |
| `24_cd_immersive.png` | ②沉浸式待机 | 倒计时 `00:24:50`，**底部控件与右上角入口全部不在**，只剩数字 + 一条进度条；末位正好被拍到翻落中的上半页（灰渐变 + 折线），说明隐藏不等于停表 |
| `22_countdown_hidden.png` | ②的副作用即证据 | chrome 已隐身后，一次「25 分」点击被系统吃掉（`IgnorePointer` 生效），数字没跳——按钮看不见时点不到 |
| `20_main_chips.png` | ②唤回 | 点屏幕一下，控件与入口立刻回来，可继续操作 |
| `13_scroll_up.png`、`burst_09.png` | ①动画不再生硬 | 经典翻牌的中缝铰链中间态：上半页带阴影向下折、下半页新数字渐显，缝隙连续不脱开（`burst_09` 抓到 `05:15:06` 末位正在落页） |
| `33_flip_styles.png` | ①8 种效果 | 设置页「翻页动画样式（8 种）」8 个 chip 全在（经典机场翻牌✓ / 书页卷曲翻页 / 滑动翻页 / 分段碎裂翻 / 渐变溶解翻 / 滚筒走字 / 落体回弹 / 混合轮换），预览条正停在翻页中间态 |
| `mix_1..8.png` | ①混合轮换真的换 | 连拍 8 帧（22,306–27,923 字节，逐帧大小不同 = 每帧画面真的在变）；`mix_5.png` 里 `00:20:38` 末位是两段字形交叠的旋转中间态，与经典翻牌的铰链形态不同 |
| `11_settings.png`、`12_scroll1.png`、`13_scroll_up.png` | ③设置布局 | 914×411 横屏走的是窄版：预览条压在上方、选项列表整宽铺在下面，翻页不再「一整屏滚不出几行」，也没有溢出红条。按 `settings_page.dart:52` 算：`maxHeight = 411.4 - 56 = 355.4`，预览 `355.4 × 0.42 = 149.3` 逻辑像素（旧版写死 210，选项只剩 145 高） |

视验的边界要讲清楚：`swiftshader_indirect` 是 CPU 软渲染，**帧率与流畅度不代表真机**，所以这里只能确认「形态对不对（铰链、逐格、隐藏、布局）」，不能确认「60fps 下顺不顺眼」；后者需要在真机上跑，§9.7 的帧率缺口依旧没被这张表填上。

### 9.9 鸿蒙链路同轮复跑（渲染层重写会不会打挂 ohos）

重写的是纯 Dart（`Transform`/`Matrix4`/`ClipRect`，没有新平台通道），逻辑上不该影响 ohos，但「不该」不等于验过，所以两条链路各复跑一次（14:28–14:31）：

- debug：`tool/build_hap.sh` → `Running Hvigor task assembleHap... 64.2s`，`√ Built build\ohos\hap\entry-default-unsigned.hap`，125,814,260 字节（比上一版 +37,456，其中 `kernel_blob.bin` +38,256），24 个文件。
- release：`tool/build_hap.sh --release` → 107.2s，`EXIT=0`，22,748,875 字节、21 个文件、`libapp.so` 5,325,744 B。
- 顺手抓到一个文档错误并改掉：**release 不往 `build/ohos/hap/` 复制**（日志只打印签名提示），之前 HANDOFF 写的「release 包躺在 build/ohos/hap/」是拿错文件得出的；现在两处落点分别写明。
- release 的字节数与重做前完全相同，看着像没重编。用符号否掉了：`app.so` 时间戳是本次的 14:29，二进制里 `grep -ac` 查到本轮才加的 `autoMix` 与 `_hingedLeaf`（两者在 `git diff` 里都是 `+` 行）→ 是当前代码，同大小是巧合。
- 仍未验：ohos 侧的运行表现（未签名装不上真机，§5 待办 6）。所以「8 种动画在鸿蒙上画得对不对」目前只有「编译进包 + Dart 层同一份代码」这一级保证。

### 9.10 云端首轮真实构建（run #9，head `cdceae9`）——红叉是假警报

推上去后 run #9 结论 `failure`，但逐步骤查（`actions/runs/41983168374/jobs`）发现**前 9 步全绿**，包括之前一直担心的三处改动：删图标步骤、删 gradle wrapper 下载步骤、audioplayers 覆盖移出 `pubspec.yaml`。干净 Runner 上 `flutter analyze` + `flutter test`（86 例）+ `build apk` 全过。

唯一挂的是第 10 步「更新公开预发布 dev-build」，而**发布实际成功了**：`releases/tags/dev-build` 交出 prerelease `true` + 4 个附件全在，`published_at`（06:57:06）与附件 `updated_at`（06:57:08–10）都落在那一步 6 秒窗口（06:57:05–11）内，公开直链 `curl -sIL` 三个 APK 全 `200`。失败点是这一步**最后那句纯打印** `gh release view --json … --jq …`，前面的 `gh release create`/`upload` 都过了。当时只能定位到「哪一句」，拿不到「为什么」（日志接口 403）；为什么是 run #10 的 annotation 交出来的，见 §9.11。

结论与教训：
- **红叉 ≠ 包没发出去**。判断要看 steps 表和 `releases/tags/dev-build`，不能只看 run 的绿/红。
- 云端包与本机包**字节数与 sha256 都不同**（云端 arm64 17,909,554 / 本机 17,917,607），因为 Runner 用的是它自己现生成的 `~/.android/debug.keystore`，签名块不一样。别拿本机哈希去核对云端附件，要比只比 `apk-sha256.txt` 里云端自己算的那组。
- ~~小瑕疵：`apk-sha256.txt` 里只有三个分 ABI 包，没有通用包 `app-release.apk`~~ —— 已修，根因是 glob 而不是笔误，并且实测过：本机建 `app-arm64-v8a-release.apk`/`app-armeabi-v7a-release.apk`/`app-x86_64-release.apk`/`app-release.apk`/`app-debug.apk` 五个空文件，`ls app-*-release.apk` 只回前三个。`app-` 之后要求一个字面的 `-release.apk`，`*` 匹配空也只能凑出 `app--release.apk`，所以通用包永远进不去。现在那一步改成逐个点名 4 个文件。
- 待修（不影响使用，只影响 run 变绿）→ **已修**：最后一行自检改成 `if summary=$(gh release view … --jq … 2>&1); then echo; else echo "::warning::…$msg"; fi`，一句打印不再能把整个 run 拖红，失败原因以 annotation 呈现。选 annotation 而不是 `::error::` 是因为它天然只当警告；而写 annotation 而非丢进日志，是因为 `actions/runs/{id}/logs` 要 admin 权限（本轮 403 过），`/check-runs/{id}/annotations` 免登录就能读。
  - workflow command 的值是**单行**协议，所以 `$summary` 先 `tr '\r\n' '  '` 再 `sed 's/%/%25/g'`（顺序不能反，反了会把刚插进的 `%25` 又转一遍）。这条管道用 `{"100%":"ok"}` + CRLF 混排做过实样验证，输出为单行且 `%`→`%2525` 这种已转义内容能正确保持。
- 同时把 `app-x86_64-release.apk` 补进了 `gh release upload` 的附件清单（run #9 只公开了 3 个 APK，x86_64 只在 Artifacts 里），`upload-artifact` 的 `path:` 改成 `app-*-release.apk` + `app-release.apk` 两行，`if-no-files-found: error` 保持不动（两个 pattern 各自都至少匹配一个文件，不会误报）。
- 本轮 workflow 改动的验证只到「本地静态」这一级：4 个 `run:` 块逐个抽出跑 `bash -n` 全过（2/7/37/3 行，抽取脚本按缩进去重，读回内容与 YAML 逐行一致），整文件用 `yaml 3.1.3` 解析出 android 9 步 / ios 6 步、各 `run` 步行数 1/1/1/3/8/38。两套行数来源不同（解析器把块尾换行多算一行），只做各自内部一致性检查，不互相核对。**真实跑一次要等 run #10**（见 §9.11）。后来为字段名修复又加了一行注释，改对之后的行数是 run 块 2/7/38/3、解析器 1/1/1/3/8/39 —— 那一版跑的是 run #11（见 §9.12），run #10 跑的仍是这里的 2/7/37/3 版。

### 9.11 run #10（head `e628133`）：真绿了，而且把 run #9 的根因挖了出来

推上去 446 秒（07:30:28→07:37:54，构建 APK 那步独占 306 秒）后 `android` job **13 步全 `success`**（含 Set up job / 3 个 Post / Complete job），`ios` 按设计 `skipped`。这轮 workflow 的三处修改在干净 Runner 上都成立：`记录产物校验和` 0 秒过、`上传 Actions 产物` 6 秒过、`更新公开预发布 dev-build` **5 秒 `success`**。

**发布结果实测**（`releases/tags/dev-build`，附件 `updated_at` 全部 07:37:31–32）：5 个附件 —— `app-arm64-v8a-release.apk` 17,909,554 / `app-armeabi-v7a-release.apk` 15,263,372 / `app-x86_64-release.apk` **19,335,481**（run #9 公开页没有它）/ `app-release.apk` 51,432,169 / `apk-sha256.txt` **357 字节 = 4 行**（run #9 那份 275 字节 3 行；357−275=82 正好是 `app-release.apk` 那一行的长度）。

**Artifacts 也真的多装了通用包**：`timenote-release-apk` 从 run #9 的 24,897,396 涨到 48,773,766 字节，接近翻倍 —— 与「3 个分包原始 52,508,407 → 4 个包 103,940,576」的比例吻合（两次的 zip 压缩率都稳定在 ~47%），所以不是巧合而是 `path:` 拆行起了作用。

**根因（这条是本轮最实的收获）**：`/check-runs/127112266223/annotations` 交出 3 条注解，其中一条正是新加的 warning，原文把 gh 的报错整段带出来了：

```
dev-build 已发布（附件见 Releases 页），但自检打印失败：Unknown JSON field: "prerelease"
Available fields: apiUrl assets author body createdAt databaseId id isDraft isImmutable
isPrerelease name publishedAt tagName tarballUrl targetCommitish uploadUrl url zipballUrl
```

所以 run #9 的红叉不是「打印语句玄学失败」，是 **`--json` 字段名写错**：gh 的字段叫 `isPrerelease`，没有 `prerelease`。这条错误在改之前无法知道（日志下载 403），加了 annotation 兜底之后第一轮就拿到了 —— 兜底设计的价值被实测证明了，转义管道也是真场景：gh 的错误是多行输出，经 `tr`+`sed` 压成单行才进得了 annotation。（上面这段是为了好看手动折的行，接口原样返回的是**一整行**，`/check-runs/{id}/annotations` 里 `message` 字段没有换行。）

据此把字段名改对（`--json tagName,isPrerelease,assets` + `--jq '{… prerelease: .isPrerelease …}'`），warning 分支保留不动 —— 它现在是「以后同类错误还能被读到」的保险，不是这次的补丁。

### 9.12 run #11（head `94ddb91`）：字段名修对之后，第 10 步干净通过

推送 `94ddb91` 后 run #11（id `41991694782`）`completed success`，android job 13 步全 `success`，逐步用时：Setup Flutter 17s / 拉取依赖 1s / 静态分析 13s / 运行测试 25s / **构建 Release APK 289s** / 记录产物校验和 0s / 上传 Actions 产物 5s / **更新公开预发布 dev-build 6s**，ios 依旧 `skipped`。

**这条算修好了的证据链**（注意它的性质是「反证」，不是直接看到日志）：`/check-runs/127125179043/annotations` 只剩 GitHub 自己的 2 条（Node 20 deprecation `warning` + ubuntu-latest 迁移 `notice`），**run #10 那条 dev-build warning 不见了**。因为 `if summary=$(…)` 的两个分支必走一个 —— 没有 warning 就等于走了 then 分支，也就等于 `gh release view --json tagName,isPrerelease,assets --jq '…'` 返回 0 并打出摘要。日志正文本身仍然读不到（`.../logs` 免下载要 admin，本机 403 过），所以「摘要长什么样」是**推断**，不是亲眼所见。

**附件复验**：`dev-build` 仍是 5 个附件，`updated_at` 全部刷新到 08:10:19–20，字节数与 run #10 完全一致（arm64 17,909,554 / arm32 15,263,372 / x86_64 19,335,481 / 通用包 51,432,169 / 校验和 357）。⚠️ `gh release upload --clobber` 是**删了重建**，资产 id 每轮换（arm64 `712511360` → `712600392`、校验和 `712511369` → `712600397`），这条的正确讲法见本节末尾。

**另一条实测出来的性质：同一份代码每轮构建的 sha256 都不同。** run #11 的 `apk-sha256.txt`（357 字节，和 run #10 同长度）里 arm64 是 `357d9e82c16b…`，run #10 是 `9e03d469cb66…`；四个包全部换哈希，而字节数一个都没变。这和 §9.10 那条「云端 ≠ 本机」是同一个根因的两面（Runner 每轮现生成 debug keystore，签名块内容随机器变但长度一致）。实际含义：**sha256 只能用来核对「同一次 run 的附件 == 同一次 run 的清单」，不能当版本标识，更不能跨 run 比较**。要判断装到平板上的到底是哪次提交，看 `dev-build` 正文里的 `GITHUB_SHA[0:7]`（workflow 每次 `gh release edit/create` 都会重写这行；实测 run #10 正文首行是「最新提交：`e628133`」，run #11 是「最新提交：`94ddb91`」）。

**字节级完整性核对：已做成**（把 §9.10 留的口子填上）。拿 run #11 那轮的 `app-arm64-v8a-release.apk` 整份下回来 `sha256sum`，结果 `357d9e82c16bf069ff24ba6d49190a4b1f7c79f3cf682348fa7c831eb6bbe14d` 与同一轮 `apk-sha256.txt` 第一行**逐字相同**，`wc -c` 也正好 17,909,554。两种下载通道实测对比：

- ❌ `https://github.com/.../releases/download/dev-build/app-arm64-v8a-release.apk` 直链：本机 `curl -sL` 停在 3,134,272 字节，而 `-w` 仍报 `HTTP=200` —— 状态码不能证明拿全了，必须比字节数。
- ✅ `https://api.github.com/repos/mjkyleo/timenote/releases/assets/{id}` + `Accept: application/octet-stream` + `curl -sL -C -` 断点续传：**能续满，但很慢很不稳** —— 130 秒一轮连跑 8 轮才凑齐（4,297,408 → 4,635,979 → 5,995,851 → 7,552,331 → 13,491,520 → 13,988,569 → 16,036,569 → 17,909,554），单轮增量从 0.34 MB 到 5.9 MB 完全不线性，每一轮都没能在 130 秒内拿完（要么撞 `--max-time`，要么中途断流，两者从外部区分不了）。小附件（`apk-sha256.txt`）一次就拿全 357 字节。
  - ⚠️ 中间踩到一条判读规则，值得单独记：跑到第 5 轮时文件还差 4.4 MB，此时 `sha256sum` 得到 `7593332f…`，与清单的 `357d9e82…` **不同** —— 那是**本地截断**，不是云端附件被换。所以核对顺序永远是 **先看 `wc -c` 够不够，再看哈希**；只看哈希会得出「发布被动过手脚」的错误结论。（我自己也差点犯一次：第 5 轮结束时就说过一句「凑满、逐字相同」，那是把清单里的期望值当成了实测值，撤回后重跑才拿到真结果。）
  - 清单自身的形式也核过：357 字节、4 行、每行 `^[0-9a-f]{64}␣␣\S+$`、文件名集合与该轮 4 个 APK 完全相同。

`--clobber` 换 id 这件事的正确讲法：旧 id **不会下载失败**（对着 run #10 的 id 一路续到 15,251,947 都没报错），风险只在**错配** —— 旧 id 拿到的是上一轮的字节，和本轮清单天生不匹配，会伪装成「哈希被改」。所以下之前重新取一次 `releases/tags/dev-build`，让 id 与清单同属一轮。（我中途重开过一轮，真实原因是自己的循环脚本把两个数字拼在一起 —— `sz=$(curl -w %{size_download}; wc -c)` 得到 `31940693194069` —— 加上主动停任务，不是 GitHub 报错。两件事别混着写。）

## 十、第四轮：动效实验室落地（24 种翻页动画 + 8 种底层进度组件）

需求出处：用户给的 `时间切换动效实验室.html`（32 件样本）＋「就是这个数字变化本身的种类，不是基于一种动画形式做颜色的变化」。分批决定由用户点头：T1+T2 先落地、aux 进度组件要（挂在数字下方/背景）、默认滚筒换成实验室版、T4 先用 `BackdropFilter`/painter 近似不上 shader。

### 10.1 登记与分类（实测数字）

- `FlipAnimStyle` 从 8 个值扩到 **24 种 + 混合轮换 = 枚举 25 个值**（`lib/settings/enum_def.dart:13`），按实验室原样分六类：翻折 fold 5 / 位移 roll 3 / 遮罩 mask 3 / 形变 morph 3 / 碎片 grain 3 / 光学 light 3，再加本批之前就有的 4 种。
- 混合轮换池 `flipMixCycle` **19 项**（`grep -c "FlipAnimStyle\." ` 实测），排除 **5 项**：粒子聚散、三角碎片（实验室标「仅收尾」）、流体溶解、液态玻璃（标「高频慎用」）、像素洗牌（每字 12 块切片，一秒一次太贵）。这条不是靠自觉：`test/flip_rendering_test.dart` 用集合等式 `flipMixCycle == values − {autoMix} − poolExcludedStyles` 钉住，新增动画不归类就红。
- 中文名两两不同有测试守着（25 个 chip，用户在设置页里要分得清）。
- 出厂默认 = **滚筒走字**（实验室版：直线下滑 + 正弦包络的运动模糊 + 暗角，静止态一定锐利），由 `test/ui_style_test.dart` 的「出厂默认动画是滚筒走字」钉住——setUp 只写过 `soundEnable`，效果类 key 全走默认分支，所以这条测的真的是「库里什么都没有时会怎么显示」。

### 10.2 哪些是近似，差在哪（不许写成原样复刻）

- **碎片类没有字形位图可采**（Flutter 不提供同步 glyph outline/位图 API）→ 改成「窗口切片」近似：`ClipPath` + `FractionalTranslation`（位移量是自身尺寸的比例，不用算像素）+ `Transform.rotate/scale`。像素洗牌每字 3×4=12 块（实验室那版 6×8 是给整屏 canvas 的）、粒子聚散每字 3×5=15 个圆点、三角碎片 2×2 四个方块各切两个三角 = 8 片。
- 散开方向由 `sin(seed)` 哈希按序号固定，所以逐帧只是「往回收」，不会抖成噪点——这条有测试逐帧比对（早期帧与中期帧的点积 ≥ 0、距离单调变小）。
- 流体溶解／液态玻璃 = 逐条带剪切（`_shearBands`）+ `ImageFiltered` 模糊 + `Alignment` 驱动的渐变高光扫过，**不是真 shader**；CRT = 量化抖（每 1/6 帧一档）+ `CustomPainter` 扫描线覆层。
- 对角斜折用 `..rotateX()..rotateY()` 近似绕 `(1,1,0)` 轴：material 导出的 `Matrix4` 没有 `rotate3d`，`Vector3` 也不在导出里。
- **描边生长（实验室 #15）没做**。同样卡在没有字形轮廓 API，硬做只能是假的，所以宁可不进池。
- 机械仪表三件（七段数码管 #19 / 指针表盘 #20 / 步进仪表 #21）属另一批，未动。

### 10.3 底层进度组件层（新增 `lib/progress_decor/`，432 行）

- `ProgressDecor` = 8 件 + `none`。默认 `none` 一个像素都不画，老用户升级不会突然多出一层；选中其中一种时**用它顶掉那根细进度条**（同一个信息不画两遍），`sky`（日出日落）是唯一的环境层，例外保留细条当读数、自己垫在整屏 Stack 第一层。
- 连续相位只在沙漏／水波／蜡烛三件挂 Ticker（`animatedProgressDecors`），环／螺旋／灯带／年轮按进度画一次就够——不然待机屏白挂一个 60fps 循环。
- `remainOf(progress) = 1 − progress` 是这一层唯一的「已消耗 → 剩余」映射，与 `ClockState.progress` 同一个定义。

### 10.4 本轮抓到的真实缺陷与测试基建事实

- **进度层的 60fps Ticker 不驱动重绘**：`ProgressDecorView` 起了 `repeat()`，但 `CustomPaint` 的 painter 没挂 `repaint`，widget 又只在每秒进度变化时重建 → 沙粒／水波／火苗实际停在同一帧。修法是 `initState` 里 `_tick.addListener(() => setState(...))`。反向验证做过：摘掉那行 `addListener`，用例「沙漏的沙粒逐帧在动」立刻红 `Expected: not <0.0> / Actual: <0.0>`；装回去 18 例全绿。
- **这个 SDK 的 `ui.Picture` 没有 `getBounds()`**（`flutter analyze` 直接报 `undefined_method`）。要量画面只能 `toImageSync` + `toByteData` 自己数像素——顺带这也比包围盒诚实：包围盒算不进裁剪，水面画到框外照样计入包围盒。
- **`ImageByteFormat.rawRgba` 是预乘缓冲**：半透明 accent（`Color(0xFF00FF00)` × 0.55）落成的字节是 `0,g,0,g` 而不是 `0,255,0,140`。第一次按未预乘比色，水体一个 accent 像素都没匹配上，测试假红；现在按「r、b 归零且绿通道有值」认 accent。
- 光栅化必须包在 `tester.runAsync` 里：`toByteData` 的完成回调走真实事件循环，fake-async 区永远等不到（和 §R11 那条 Hive 挂死是同一个坑的两面）。
- 找静止态残留的位移包装要**限定在自己的牌子内**：空的 `MaterialApp + Scaffold` 树里本来就挂着 4 个 `FractionalTranslation`（实测 `EMPTY tree FT=4`），不限定就分不清框架基线和我们的泄漏。

### 10.5 本轮数字（实测）

- 测试 86 → **160 例**：`app_widget_test.dart` 22、`flip_rendering_test.dart` 86、`ui_style_test.dart` 11、`progress_decor_test.dart` 18、`clock_notifier_test.dart` 12、`storage_service_test.dart` 3、`todo_model_test.dart` 5、`egg_service_test.dart` 3（逐文件单独跑 `flutter test <file>` 取 `+N`，与全量 `+160: All tests passed!` 一致）。
- `flutter analyze` → `No issues found!`。
- 改动面：`git diff --stat` 12 个文件 **+1524 / −87**，另有两个未入库的新文件（`lib/progress_decor/progress_decor.dart` 432 行、`test/progress_decor_test.dart` 429 行）。其中 `lib/flip_clock/flip_renderer.dart` 单文件 +1069 行——24 种动画全在这一个渲染层里，值得记一笔「下一个加动画的人要先接住这 1000 行」。
- ⚠️ `ios/Runner/GeneratedPluginRegistrant.{h,m}` 被 `flutter pub get` 重新生成过，属于工具产物，不是本轮的手写改动。

### 10.6 边界（这轮没做到的部分）

- **观感还是没有结论**。24 种动画 + 8 种进度组件「顺不顺眼」测试给不出答案，本轮也**没有重新出包、没有跑模拟器截图**——按约定这一条由用户在那条 dev-build 直链上自测判。
- **鸿蒙没复跑**：本轮改的全是纯 Dart（`ClipPath`/`Transform`/`ImageFiltered`/`CustomPainter`，没碰平台通道），逻辑上不该打挂 ohos，但没跑就是没跑；§9.9 那组 HAP 字节数不能当本轮数据的引用。
- **帧率仍未量过**，而且新加的逐帧 `setState` 只作用在进度带子树、只在那三件连续组件下才挂——「一秒一次的动画值不值得每帧重建」没有实测依据。
- 需求清单里的 R2/R3/R4/R6/R9/R10/R11/R12/R13/R14/R15/R17（整页排版与配色、手动横竖屏、显示单位、待办增强、纪念日提醒、结束三档、数字外框、隐藏系统栏、DIN 字体、包体）**还没动**，这批先把「数字怎么换」和「还剩多少怎么显示」做扎实。

## 十一、第五轮：R11 结束三档 + R12 数字外框

需求出处：2026-11-05 语音清单里的 R11（「倒计时结束行为改成三档可选」）与 R12（「数字外框要能选/能去掉」，参考 flipclocker 的「时间块有外框」）。这两条是纯设置驱动，接着上一轮的 `AppSettingsState` + key + 芯片组 + 主屏行为那条路径做，测试同样钉法。

### 11.1 登记（实测数字）

- `eggEnable`（bool）→ **`FinishBehavior` 三档枚举**：`stayZero` 停留 `00:00:00` / `autoRestart` 自动重开 / `showEgg` 弹彩蛋，存储 key `onFinish`，**默认 `showEgg`**（原 `eggEnable` 默认 `true`，所以默认档没变，这条由「三档默认是弹彩蛋」用例钉住）。
- 新增 **`PlateFrame` 四档**：`follow` 跟随界面风格 / `none` 去掉 / `thin` 1.5px / `thick` 3px，存储 key `plateFrame`，默认 `follow`（= 本行之前的行为）。
- 设置页成 10 个键：实测 `AppSettingsNotifier.update` 里 `writeSettings` 的键 **10 条**（`lib/core/providers/app_providers.dart`）；新增键走 `getSetting(key, 默认)` 的缺失回退，老库不会炸。
- 三档、四档的中文名两两不同各有测试；「倒计时结束」芯片组下面加了一行小字说明约定（`_hint`），因为「停留 / 重开 / 彩蛋」选完当场看不出差别。

### 11.2 三条约定落在哪

- 分发点在 `_ClockViewState._onCountdownFinished(next.total)`（`lib/flip_clock/clock_view.dart:106`），**没有下沉进 `ClockNotifier`**：notifier 只管走时，「归零之后屏幕怎么表现」属于界面；复用的还是上一轮那条 `justFinished` 钩子，`prev.remainTime > 0 && next.remainTime == 0`。
- 「自动重开用上一次选的时长」= 直接拿这一轮的 `ClockState.total`，不是任何预设默认值。用例特意起一个 **3 秒**的表——既不在快捷预设 5/10/25/45 里，也不在弹窗快捷键 15/30/45/60 里，所以只要 `total` 取错就一定露馅；并且第二轮也得照常归零再重开，以及**点停止就是真停**（`stopCountdown` 之后不再被自动重开拉回倒计时）。
- 停留档额外钉了一条「归零后再等 6 秒仍然显示 `00:00:00`」——防止彩蛋那条超时切回的路径偷偷跑起来。
- 外框档**只覆盖描边**：`resolvePlateFrame(frame, tokens)` 返回 `(Color?, double)` 记录（`lib/flip_clock/flip_card_widget.dart:155`），底板填充/圆角/光影仍归界面风格令牌。所以「去掉外框」不会顺手把软胶拟物的双影也去掉；风格没自带描边色时取 `fg.withValues(alpha: 0.42)`，不在黑底上画一条生硬的原色线。
- 档位从设置一路穿到主屏的链路是 `AppSettingsState.plateFrame` → `ClockTimeDisplay`/`CountdownDisplay` → `FlipCardWidget` → `_Plate`，四处都是显式入参（默认值 `follow`，单独 pump 组件的老测试不用改）。

### 11.3 反向验证（改坏一次、还原一次，都有实测）

- 把 `autoRestart` 分支短路成 `&& false` → `test/app_widget_test.dart` 只有「选『自动重新开始』时用上一轮的时长直接重开」这一例红，其余 24 例绿。
- 把 `_mainArea` 里 `ClockTimeDisplay` 的 `plateFrame` 写死成 `PlateFrame.follow` → `test/ui_style_test.dart` 出 `+15 -1`，红的正是「外框档位穿过设置一直打到主屏，不只是设置页预览动」；而设置页预览那条（`StylePreview` 自己接档位）**照样绿**。这两条必须同时存在：预览绿不代表主屏绿。
- 两处改动都已还原（还原后全量 `+168: All tests passed!`）。

### 11.4 本轮数字（实测）

- 测试 160 → **168 例**：`app_widget_test.dart` **25**、`flip_rendering_test.dart` 86、`ui_style_test.dart` **16**、`progress_decor_test.dart` 18、`clock_notifier_test.dart` 12、`storage_service_test.dart` 3、`todo_model_test.dart` 5、`egg_service_test.dart` 3（逐文件 `flutter test <file>` 取 `+N`，与全量 `+168: All tests passed!` 一致）。
- `flutter analyze` → `No issues found!`。
- 改动面：代码 9 个文件（lib 7 + test 2，不含 README/REVIEW）实测 `git diff --stat` **+330 / −25**，本轮没有新增文件。

### 11.5 已知代价与边界

- **`eggEnable` 这个 key 直接删了，没写迁移**：老库里若用户手动关过彩蛋，升级后会回到默认的「弹彩蛋」，得再去设置页点一次。当前只有 dev-build 一个真实测试者，为一条布尔养一段兼容代码不值——但这是明说的代价，不是无事发生。
- **停留档下「继续」按钮是死的**：`resumeCountdown` 在 `remainTime <= Duration.zero` 时直接 return（`lib/core/providers/clock_providers.dart:96`），用户要再点一次预设或自定义才起得了表。要不要把归零态的「继续」换成「重来」，等真机看观感时一并判。
- 没出包、没跑模拟器截图、鸿蒙没复跑（本轮全是纯 Dart：两个枚举 + 一个入参，没碰平台通道）。
- 需求清单剩下的：R2 页面居中 / R3 配色割裂 / R4 手动横竖 / R6 显示单位勾选 / R9 待办增强 / R10 纪念日提醒 / R14 DIN 数字字体子集化 / R15 掘金整页设计 / R17 包体积。R13（隐藏系统栏）上一轮已做；R7、R8 按用户原话暂缓。

## 十二、第六轮：彩蛋文案的长短与中英文显示

需求出处：用户说会自己导入一个文案文件，结束后以彩蛋形式弹出、设置里可选；并明确「你在显示文案的时候注意这个文案的英文和中文的显示情况」。这一批**只做「显示得下、看得清」这一半**——文件本身还没到（仓库里仍是 `assets/data/quotes.json` 那 520 条全中文），所以导入格式、设置里怎么选，等用户的文件与答复，不猜着写。

### 12.1 压出来的三个真实缺陷（都不是「加了测试」而是「测试抓到 bug」）

判据不写「不报错」，写**这一条文案不用滑动就能整块看完**：`expectFitsWholeCopy` 比 `Text` 自身的宽高 ≤ `SingleChildScrollView` 视口宽高，并断言无溢出异常。蛋屏是待机屏，倒计时结束后没人会去滑屏幕找后半句。

取证方式：把这 13 例对着 **HEAD 那版实现**（`git show HEAD:lib/egg/egg_display.dart`，只补一行公开 `minFont` 让它编译得过）跑一遍，**6 例红**——表里前两列是两次真实跑测的「文本块高 / 视口高」，不是推算。

| 场景（屏 × 文案 × 系统字号） | HEAD 只看宽度 | 测量不乘系统字号（摘 `textScaler`） | 现版本（三条都修） |
| --- | --- | --- | --- |
| 800×600 · 150 字中文 · 1x | 576.0 / 459.5 | 整块可见 | 整块可见 |
| 1280×800 · 整段英文 · 1x | 896.0 / 659.5 | 整块可见 | 整块可见 |
| 914×411 · 中英混排夹 #123 · 1x | 320.0 / 270.5 | 整块可见 | 整块可见 |
| 914×411 · 不可断行长 URL · 1x | 384.0 / 270.5 | 整块可见 | 整块可见 |
| 800×600 · 150 字中文 · **2x** | 2560.0 / 416.5 | **1386.0** / 416.5 | 整块可见 |
| 914×411 · 整段英文 · **2x** | 3840.0 / 227.5 | **826.0** / 227.5 | 整块可见 |

1. **只看宽度定字号**（HEAD `egg_display.dart:23` 是 `(屏宽/18).clamp(18.0, 40.0)`）：横向撑满了，竖向根本没人管，1x 那四条全被顶出可视区（最狠的整段英文要 896 高，屏只有 659.5）。改法：外层 `LayoutBuilder` 里再套一层，拿文案区**真实可用高宽**，`TextPainter` 从基准档按 ×0.88 逐档试，取第一个「整块放得下」的档。
2. **`TextPainter` 不乘系统字号**：`Text` 渲染时自己乘 `MediaQuery.textScalerOf(context)`，`TextPainter` 不乘。只修第 1 条时，2x 那两条仍然溢出（1386.0 / 826.0），因为测量按「没缩放」判定放得下。改法：`textScaler` 一起喂给 `TextPainter`，测量与渲染同一口径。
3. **可读下限钉的是 style 里的数字，不是渲染出来的大小**：`minFont = 14` 在 2x 系统下等于 28px 实高，循环提前收手——修完第 2 条后 914×411 + 2x + 英文仍然 410.0 > 227.5。改法：收手条件写成 `scaler.scale(size) <= minFont`，下限管的是渲染后的字号。

### 12.2 中文与英文的显示差异（这条需求的正解）

- 中文任意两字之间都能断行、每字等宽；英文只能在空格处断，一个长单词就是一整块不可分的最小单位。所以同样条长的两种文案，英文更容易顶破行宽 → 只能选更小那一档。测试用**关系断言**（`enSize <= cnSize`）钉这条，不用具体数值：`flutter_test` 把字形画成 1em 方块，拉丁文比真机 Roboto 宽得多，具体字号在测试里是悲观值，关系才不会反过来。
- 不可断行的超长 URL 会在斜杠处折行，**光管高度拦不住横向溢出**，所以宽高两个方向都要量（`urlToken` 那条 914×411 专测这个）。
- 极短文案不能被误伤：9 字短句在 1280×800 上就是基准 40 档，2x 系统字号下也还是 40——`closeTo(40, 0.51)` 钉死，防止「一律缩到下限」这种假安全。
- 长到缩不动时**明确交回滚动**：竖向溢出可接受（滑一下比整块消失好），横向溢出会把文字裁掉、那是真丢内容，所以那条只断言宽度不破 + 不异常。

### 12.3 反向验证（摘掉修好，逐条看是哪几例红）

- 摘 `TextPainter` 的 `textScaler: scaler` 一行 → **13 例里正好 2 例红**，且都是 2x 那两条：1386.0 vs 416.5、826.0 vs 227.5；1x 的 11 例全绿。说明这个参数只在缩放路径上起作用，测试没有连带误伤。
- 把收手条件从 `scaler.scale(size) <= minFont` 改回 `size <= minFont` → **13 例里正好 1 例红**（横屏窄高 + 2x 英文：410.0 vs 227.5），其余 12 例绿——默认缩放下两个条件等价，所以这条测试盯的就是「下限按谁算」。
- 两处还原后：`test/egg_display_test.dart` `+13: All tests passed!`，全量 `+181: All tests passed!`。

### 12.4 本轮数字（实测）

- 测试 168 → **181 例**：新增 `test/egg_display_test.dart` **13 例**（1em 方块字体下的形态判据），其余逐文件 `flutter test <file>`：`app_widget_test.dart` 25、`flip_rendering_test.dart` 86、`ui_style_test.dart` 16、`progress_decor_test.dart` 18、`clock_notifier_test.dart` 12、`storage_service_test.dart` 3、`todo_model_test.dart` 5、`egg_service_test.dart` 3；`+13` 与全量 `+181` 一致（25+12+13+3+86+18+3+5+16=181）。
- 改动面：`lib/egg/egg_display.dart` 66 → 103 行（`git diff --numstat` **+57 / −20**）+ 新文件 `test/egg_display_test.dart` 179 行；`flutter analyze` → `No issues found!`。
- `EggDisplay.minFont` 从私有 `_minFont` 提为公开常量：测试要能断言「不是靠缩成 14 了事」蒙过的，与其在测试里重抄 14，不如让源码只有一个出处。

### 12.5 这轮踩到的 SDK 事实

- **这个 SDK 的 `TextScaler` 没有 `scaleFontSize()`**（那是更新版本 Flutter 的 API），方法名是 `scale(double fontSize)`；`textScaleFactor` getter 存在但已 `@Deprecated`（v3.12.0-2.0.pre 起），用了会被 `flutter analyze` 挑出来，所以按 `scale()` 写。
- `MediaQuery.textScalerOf(context)` 是拿缩放系数的正路；`Text` 自己会乘，`TextPainter` 与 `RichText` 手写时必须显式传。

### 12.6 边界（没做到的部分）

- **观感仍由用户判**：这批只保证「不溢出、整块可见」，字变小之后好不好读、14px 在平板上是否偏小，测试给不出结论，也没重新出包、没跑模拟器截图。
- **鸿蒙没复跑**：改动全在纯 Dart 排版层（`TextPainter`/`LayoutBuilder`），没碰平台通道。
- **测试字体对拉丁文是悲观值**：`flutter_test` 把字形画成 1em 方块，比真机 Roboto 宽，所以英文在测试里选出的字号比真机更小一档；真机上英文会更宽松——这是偏安全的方向，但不能拿测试数值当"真机观感"。
- **导入文案这件事一行没写**：格式（JSON 数组 / 逐行 txt / CSV）、交付方式（打进 assets 重新构建，还是设备内选文件——后者要引 `file_picker`，会撞 R17 包体积）、设置里到底选什么（文案库 / 语言 / 展示形态），三个问题都还没答复，等文件到了再定。
- 本轮还留一个已知短板：只有正文参与自适应，两行辅助文字是各自的固定/半固定档——页眉 `base * 0.45`（`base` 已 clamp 到 18–40，所以页眉 8.1–18，`egg_display.dart:33`）、页脚硬编码 13（`egg_display.dart:61`）。长文案把正文一路压到下限 14 之后，正文只比页脚大 1px、和页眉差不多大，主次关系就只剩字色在分了。这条等真实文案进来再判要不要把辅助文字一起纳入同一套缩放。

## 十三、第七轮：归零「重来」+ 细进度条开关 + 设置页七张卡

用户这一轮的语音同时给了「四个问题的答复」和「三条新需求」，先把口径钉住（原话转写有噪声，按 §1 的方式复述确认过）：

| 事项 | 用户的决定 | 这轮怎么落的 |
| --- | --- | --- |
| 文案文件格式 | 「文件的格式你是用 json 格式」 | 维持 `assets/data/quotes.json` 那个 JSON 数组，**不新增格式** |
| 文案怎么进 App | 「你把它转成……文件直接存起来就行了」 | 由我把外部文案转成 JSON 预置文件、打进 assets 随包走；**不做设备内选文件**（不引 `file_picker`，也就不碰 R17 包体积） |
| 文案的设置项 | 「不用给任何权限，完全是随机的出现」 | 设置里**一个开关都不给**，`EggService` 现在的形态就是纯随机（只在卡片里留一句 hint 说明） |
| 第 4 个问题 | 「你就加上那个重来吧」 | 归零停留档那颗芯片换成「重来」，见 §13.1 |
| 新需求 A | 「下面的那个进度条也要放在设置里可以开或者可以关」 | 新增 `showProgressBar`，见 §13.2 |
| 新需求 B | 「设置里面的一个布局好好整理一下，不要那么乱」 | 设置页重排成七张分区卡 + 动画按族分组，见 §13.3 |

### 13.1 归零之后那颗「继续」是死的

- **根因**：`resumeCountdown()` 开头就是 `if (state.isRunning || state.remainTime <= Duration.zero) return;`（`lib/core/providers/clock_providers.dart:97`）。停留档 `00:00:00` 时 `remainTime` 正好是 zero，所以点「继续」什么都不发生——按钮在场、也亮着，但按了没反应。
- **落点**：判定放在视图层（`clock_view.dart:326` 的 `zeroed`），标签/图标/回调三处同步分叉（`:357`、`:363`、`:370`），「重来」走 `startCountdown(clockState.total)`，用上一轮的时长原地再起。
- **为什么不动 notifier**：下沉成「`resumeCountdown` 在归零时自动当重开用」会改掉那个方法的语义（暂停-继续是一对，重开是另一件事），而且三档结束行为本来就分发在视图层（见 §11.2），别再开第二个例外。
- 三档下这条的可见面不一样：停留档归零后画面就停在那，「重来」是唯一能原地再起的入口；自动重开档 `remainTime` 直接被上一轮 `total` 填回去，永远走不到 zero，看不到这颗；弹彩蛋档只替换中间那块时钟区域，**底下芯片条照旧在场**，所以彩蛋期间那颗也是「重来」——这条由「归零展示彩蛋」用例里新增的一行 `expect(find.text('重来'), findsOneWidget)` 钉住，不是推测。

### 13.2 细进度条开关（R18）

`showProgressBar` 默认 `true`（老版本一直有这根条，加开关不能顺手改变默认画面），`update()` 写的设置键从 10 个变成 11 个（新加的这条在 `lib/core/providers/app_providers.dart:139`）。与「底层进度组件」的优先级是实测过的一张表：

| `progressDecor` | 开关开 | 开关关 |
| --- | --- | --- |
| `none`（默认） | 细进度条 | 什么都不画 |
| 沙漏/水位/环形/螺旋/灯带/年轮/蜡烛（7 档） | 只有进度组件，**不画细条** | 同左（这 7 档本来就让位给组件） |
| `sky` 日出日落 | 背景层 + 细进度条 | 只有背景层 |

- 「选了组件就不再画细条」不是这条需求带的，是 §10.3 就定下的「同一份信息不画两遍」；这轮补的是**用户主动关**这一支：sky 不顶细条，但用户点了关，关必须算数。
- 关掉之后倒计时画面只剩数字本身，连「还在走」的凭据都没有——这正是用户要的形态（那行开关的副标题「倒计时时数字下方那一根；关掉画面只剩数字」就是把这句话写给用户看的，`settings_page.dart:144`），不是遗漏。

### 13.3 设置页：从一整面芯片墙到七张分区卡

`_options` 现在按「先看外观、再看数字、最后看行为」排七张卡：**外观**（底色 / 界面风格 / 数字外框）→ **数字样式**（计时画面 / 动画速度）→ **翻页动画**（按族铺 8 个小标题）→ **进度显示**（细进度条开关 + 底层进度组件）→ **倒计时结束** → **屏幕与声音** → **关于**。

- 四个小构件撑起这套结构：`_card`（带标题的分区卡）、`_group`（组内小标签 + `Wrap` 芯片）、`_switch`（`SwitchListTile`）、`_hint`（一句话说明）。原来的 `_sectionTitle` / `_chips` 删掉了，所有芯片文案一个字没改。
- 25 档翻页动画不再平铺：`flipAnimFamilies`（`lib/settings/style_picker.dart:217`）按实验室原样登记成 翻折(5) / 位移(3) / 遮罩(3) / 形变(3) / 碎片(3) / 光学(3) / 基础(4) / 混合(1) 八族，设置页循环这张表生成小标题。
- **卡里必须用 `Material` 不能用 `Container`+`BoxDecoration`**：进度显示与屏幕与声音两张卡内是 `SwitchListTile`，它把背景和水波纹画在最近的 Material 祖先上，中间垫一层带色 `DecoratedBox` 会把开关的点击反馈整个吃掉，Flutter 自己会断言报出来（`lib/settings/settings_page.dart` 的 `_card` 上方注释记着这条）。
- 测试侧配套两条：① 「七张分区卡从上到下都在」只**往下**滚（`scrollUntilVisible`），所以顺序错了就滚不到、直接超时，一趟同时验了「在不在」和「排在哪儿」；② 「25 档动画正好被分组卡盖住」是集合相等判据，新加一档动画忘了登记就红。

### 13.4 反向验证（三条，改坏→必须变红→还原后全绿）

| 改坏的地方 | 怎么改坏 | 变红 |
| --- | --- | --- |
| `clock_view.dart` 的 `zeroed` | 前面加 `false &&`（等于归零态不再单独识别） | 「归零后那颗芯片是『重来』」**1/1 例红** |
| `clock_view.dart` 的进度分支 | `return appSetting.showProgressBar` → `return true`（开关失效） | 「底部细进度条开关」**5 例里 3 例红**（默认在场+关掉消失、sky 档关掉必须算数、重启读回）；另两例（实时时钟不画条、沙漏不画两遍）本来就不依赖开关，保持绿是对的 |
| `style_picker.dart` 的分组表 | 删掉 `'混合': [autoMix]` 这一族 | 「25 档动画正好被分组卡盖住」**1 例红**，报「分组表少一档就有动画点不到」 |

### 13.5 本轮数字（实测）

- 测试 181 → **191 例**（`flutter test` → `+191: All tests passed!`）：`app_widget_test.dart` 25 → **34**（归零「重来」1 + 细进度条开关 5 + 设置页 3），`flip_rendering_test.dart` 86 → **87**（分组登记表）；逐文件相加 34+12+13+3+87+18+3+5+16 = **191**，与全量一致。
- 改动面（`git diff --numstat`，插入/删除）：`lib/flip_clock/clock_view.dart` **30/11**（文件 513 行）、`lib/core/providers/app_providers.dart` **13/6**（144 行，含第 11 个键）、`lib/settings/settings_page.dart` **173/124**（重排后 339 行）、`lib/settings/style_picker.dart` **51/3**（315 行，只多那张分组表）；测试 `test/app_widget_test.dart` **185/8**（807 行）、`test/flip_rendering_test.dart` **13/0**、`test/progress_decor_test.dart` **4/0**（只加 `ensureVisible`，例数不变）。
  - 注：这批和上一批（彩蛋排版，`lib/egg/egg_display.dart` 57/20 + 新文件 `test/egg_display_test.dart` 179 行）都还没提交，所以对着 HEAD `94ddb91` 的总 numstat 是两批叠加的；上面按文件拆开列的是各自那一份。
- `flutter analyze` → **`No issues found!`**。

### 13.6 这轮踩到的工具事实

- **`scrollUntilVisible` 的 `scrollable` 参数必须是 `Scrollable`**：传 `find.byType(ListView)` 直接 `_TypeError: ListView is not a subtype of Scrollable`。写法是 `find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable))`；而 `dragUntilVisible` 反而能吃任意祖先 finder，两者不一样，别照抄。
- `scrollUntilVisible` / `dragUntilVisible` 只保证「建出来了、快到视口」，不保证点得到：本轮 tap 前补了 5 处 `tester.ensureVisible(finder)`（`app_widget_test.dart` 4 处 + `progress_decor_test.dart` 1 处），否则会静默 miss 并报「derived an Offset ... outside the bounds of the root of the render tree」。
- `Finder.description` 这个 property 在本 SDK 已 `@Deprecated`（改用 `describeMatch`），测试的 `reason` 里别拼它，失败输出本来就会打印 finder。
- **这个 SDK 的 `dart format` 不能对本仓库全局跑**：把 HEAD 版本的 4 个文件拷出来跑 `--output=none`，`4 changed` —— 仓库现在这套排版本来就不满足它，全局格式化会顺手重写十几条没碰过的文件（`--output=none` 只报告不改盘）。所以只在手写的行上按周围风格对齐。
- Windows 检出是 CRLF：`perl -pi -e 's/xxx$//'` 里的 `$` 锚匹配不到行尾（`\r` 挡在前面），改代码要不用行尾锚或者用 `\b`。

### 13.7 边界（没做到的部分）

- **文案文件还是没到**：这轮只是把口径定死（JSON 数组、打进 assets、设置里不给开关），一句导入相关代码都没写；`EggService` 现在读的是仓库里已有的 `assets/data/quotes.json`。
- **没重新出包、没跑模拟器截图**：七张卡在 800×600 测试面与横屏 914×411 冒烟里都不报错，但「好看不好看、分组切得顺不顺」得人眼判，和动画观感一起留给用户在 dev-build 直链上自测。
- **「重来」只复用上一轮的 `total`**，不重新弹自定义输入框；要换时长还得再点一次时长档。
- **鸿蒙没复跑**：改动全在纯 Dart（视图分叉、Provider 一个键、设置页 widget 树），没碰平台通道。
- 编号说明：本轮新分配的 R19=归零「重来」、R20=设置页分区重排（R18=细进度条开关在会话里先用过），R16=扩充动画种类、R17=包体积不变。

## 十四、第八轮：手动「检查更新」（R21）

先说清用户这句需求原话的边界：问的是「有没有可以根据云端的版本判断要不要更新的功能」，我答「没有」之后追加的是「**加个手动检查更新按钮**」。所以这一轮的口径是——

| 事项 | 决定 | 落地 |
| --- | --- | --- |
| 自动不自动 | 手动。没点按钮**一次请求都不发** | 进设置页不预取；`called == 0` 有一条专门用例守着 |
| 要不要自动下载/安装 | 不做。只给一条可复制的地址 | 复制 `releases/tag/dev-build` 发布页，自己下 APK 装 |
| 比对基准 | 构建对应的 commit | APK 里烧进 `BUILD_SHA`，云端读 `dev-build-sha.txt` |
| 要不要引依赖 | 不引 `url_launcher`、不引 `package:http` | 剪贴板是 `flutter/services`，抓取用 `dart:io` 的 `HttpClient` |

### 14.1 为什么读 Release 附件而不是 GitHub API

两种写法都能拿到「main 最新提交」：`api.github.com/repos/mjkyleo/timenote/commits/main`，或 CI 每次发布都覆盖的纯文本附件。选了后者，三个理由按重要性排：

1. **匿名限流**。`api.github.com` 免登录 60 次/小时/IP（GitHub 公开文档口径，没实测撞过），平板和手机共用出口 IP 时容易排队；`releases/download/...` 走发布页直链，没有这层限制。另外它按 404 就能明确区分「还没发过包」，API 那条路拿到的永远是仓库状态。
2. **口径对齐**。API 给的是「仓库当前 HEAD」，附件给的是「**你手上这个包能装的那一版**对应的构建」。装了 dev-build 之后有人又推了 main 但云端构建失败，API 会说「有新版」而那个版本根本没有可安装的包；附件不会撒谎。
3. **解析成本**。API 要 JSON + `sha` 字段，附件是一行文本，`trim` 完就能比。

比的是**前 7 位小写**（`shortOf`），和 CI 在 Release 正文里写的短号同一口径；本地 `buildSha` 为空（本机 `flutter run` 的包没注构建号）时明确报「比不了」，**不**降级成「已是最新」——这是那 4 档状态里唯一容易被写歪的一条，单独立了一例。

### 14.2 实现的三处 + 一条注入缝

- `lib/core/update_check.dart`（新，88 行）：`buildSha` / `latestBuildUrl` / `devBuildReleaseUrl` 三个常量、`UpdateCheckStatus` 四档、`fetchLatestBuildSha`（带 10 秒超时，`HttpClient` 默认跟随 302，UA 见下面「实测补记」）、`checkForUpdate`。
- `lib/settings/settings_page.dart:177-186`：「关于」卡里加了一行当前构建短号，下面挂 `const UpdateCheckSection()`（`:349-440`）。两个 `OutlinedButton` 用 `Wrap` 摆，复制按钮只在「有新版 / 本地构建」两种结果下出现（`canCopy` 排除 `failed` 与 `upToDate`，`_message` 的四句中文见 `:383-393`）。
- `.github/workflows/build-apk.yml:48-53 / :65 / :106`：两条 `flutter build apk` 都加 `--dart-define=BUILD_SHA=$GITHUB_SHA`，校验和那一步顺手 `printf '%s\n' "$GITHUB_SHA" > dev-build-sha.txt`，`gh release upload` 的清单里点名带上它，Release 正文补了一句两份 txt 各干什么。
- `tool/build_hap.sh:31`：本机出鸿蒙包时注入 `git rev-parse HEAD`，拿不到就注空串（App 侧走「比不了」分支）。

两条缝是为测试留的，不是为了以后扩展：`latestShaFetcherProvider`（设置页只 `ref.read` 它，所以 UI 用例可以塞假抓取）和 `checkForUpdate(fetch, {String? localSha})`（`buildSha` 是编译期 `String.fromEnvironment`，测试进程里恒为空，不传参数就只能测「比不了」那一档）。

### 14.3 权限：release 清单不补 INTERNET，真机包直接连不出去

`android/app/src/main/AndroidManifest.xml` 只加了 3 行 `<uses-permission android:name="android.permission.INTERNET"/>`。这条此前只存在于 debug/profile 两份清单里，release 构建读的是 `main` 这份，**不补上「检查更新」在真机包里必然失败**（本地测试全绿发现不了，因为 flutter_test 根本不走真 socket）。顺带把 README 和「关于」里的「纯离线」改成实话：不登录、不广告、不上传数据，唯一出网的一次是你按下那个按钮。鸿蒙侧 `module.json5` 早就声明过 `ohos.permission.INTERNET`，不用动。

### 14.4 反向验证（四条，改坏→必须变红→还原后全绿）

| 改坏的地方 | 怎么改坏 | 变红 |
| --- | --- | --- |
| `fetchLatestBuildSha` 的正文 | 去掉 `.trim()`（附件末尾那个 `\n` 就不去了） | 「200 的正文按 trim 后原样返回」**1/1 例红** |
| `checkForUpdate` 的判等 | `final same = ...` → `final same = true` | 「云端换了提交就报有新版」**1 例红**，另 4 例（大小写、前 7 位、空本地、失败）不受影响 |
| `checkForUpdate` 的空守卫 | 整行删掉 `if (remote.isEmpty) ...` | 「远端空串与抛异常都归到 failed」**1 例红**（空串会掉进比对，判成「有新版」） |
| 复制按钮的文本 | `ClipboardData(text: devBuildReleaseUrl)` → `latestBuildUrl` | 「复制的是 dev-build 发布页，不是那条 .txt」**1 例红** |

四条都是当场改完就跑 `test/update_check_test.dart`，量完红再 `cp` 回原文件、`diff` 确认零差异、重跑 `+11: All tests passed!`；`git diff --numstat` 也回到改动前的 `105/3`，确认没把变异残留进工作区。

### 14.5 本轮数字（实测）

- 测试 191 → **202 例**（`flutter test` → `+202: All tests passed!`；`flutter analyze` → `No issues found!`）。新增全在 `test/update_check_test.dart`（172 行、11 例）：比对逻辑 5 + loopback 真实抓取 2 + 设置页接线 4。
- 逐文件相加 34+12+13+3+87+18+3+5+16+11 = **202**，与全量一致。
- 改动面（`git diff --numstat`，插入/删除）：`lib/settings/settings_page.dart` **105/3**（441 行）、`android/app/src/main/AndroidManifest.xml` **3/0**（50 行）、`.github/workflows/build-apk.yml` **11/3**（153 行）、`tool/build_hap.sh` **6/2**（35 行）、`README.md` **9/5**（266 行，7 个 hunk）；新文件 `lib/core/update_check.dart` 88 行、`test/update_check_test.dart` 172 行。
- `ios/Runner/GeneratedPluginRegistrant.{h,m}` 在 `git status` 里显示被改，但 `git diff` 没有任何 hunk —— 纯 CRLF/LF 抖动（flutter 工具链回写），内容零变化，所以不入库。

### 14.6 这轮踩到的工具事实

- **`flutter_test` 把 `HttpClient` 整个换成假实现**：真机代码走 `dart:io` 的 `HttpClient` 在测试里永远拿到 400，还会打一行「creates an HttpClient to instead of the one configured by HttpOverrides」的警告。要测真实抓取路径，`setUp` 里临时 `HttpOverrides.global = null`、`tearDown` 还原，再对 `127.0.0.1` 上现起的 `HttpServer` 发请求——这样既测到真实的 socket/UA/状态码处理，又不出本机。
- **这个 SDK 的 `flutter_test` 不 mock 剪贴板**：`await Clipboard.setData(...)` 在测试里**永不返回**，于是按钮卡在「检查中…」、`_copied` 永远为 false，用例表现为超时而不是报错，很难看出根因。正解是 `tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, handler)`，顺手把 `MethodCall` 捕获下来直接断言 `arguments['text']`——这样「复制的是发布页不是 .txt」这条判据才真的被测到。
- **编译期常量测不了就得留参数**：`String.fromEnvironment` 在测试进程里是空串，`checkForUpdate` 不接 `localSha` 就没法测「大小写不同但同一个提交」这类用例。这不是通用抽象，是这一条的具体解法。
- `HttpOverrides? original` 要写成可空：`HttpOverrides.global` 的 getter 本来就返回 null，写成非空直接编译不过。

### 14.7 边界（没做到的部分）

- **对外的三条 URL 今天本机实测过**（`curl -sL`，都是免登录）：① `releases/download/dev-build/apk-sha256.txt` 不带 UA = **200、357 字节**（和 README 记的那个数一致），带 UA 同为 200 —— 所以代码里那句「缺 UA 会 403」原先写错了，已改成注释说明**缺 UA 回 403 的是 `api.github.com`**（实测 403，正文写着 "Request forbidden by administrative rules… User-Agent header"），附件直链这条路上 UA 只是给以后换 API 时兜底；② `releases/download/dev-build/dev-build-sha.txt` 现在 **404**，符合预期（这轮没推 main，CI 还没生成过它），App 侧这种情形会归到「检查失败：没网络，或者云端还没发布过 dev-build 安装包」，文案不撒谎；③ 直链返回 302，`HttpClient` 默认跟随重定向，`followRedirects` 没改过。
- **没在真机点过一次**。CI 那一侧的 `dev-build-sha.txt` 要等下一次推 main 才会第一次出现，本轮没有跑云端构建，所以「App 里按下按钮 → 显示远端短号 → 复制地址」这条链路只有 loopback 用例覆盖，「6 个附件」在 README 里也标注成**预期而非取证**。
- **不做「谁新谁旧」的方向判断**。只比前 7 位是否相同，不同就报「云端有更新的构建」。如果本地其实比云端新（比如手动装过某轮之后的本地构建），这句话方向是反的；要严格判序得拉 commit 图，不值得为一个自用 dev-build 引这套复杂度。
- **前 7 位理论上有碰撞**（同一提交序列里出现相同前缀）。判据会当成「已是最新」，概率按 git 短号惯例可忽略，但确实是个已知不严谨点。
- **只有 Android 有意义**。iOS 侧 release 不构建、鸿蒙没签名，两处都装不上 dev-build 包，按钮在那些平台上只能告诉你「有新版」而没法装；代码不分平台，行为一致。
- 编号说明：本轮 R21=手动检查更新。R17（包体积）顺带有了新数据点：新增一个 88 行的 Dart 文件、两条按钮，APK 尺寸变化没实测（本轮没出包）。
