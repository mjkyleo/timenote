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

唯一挂的是第 10 步「更新公开预发布 dev-build」，而**发布实际成功了**：`releases/tags/dev-build` 交出 prerelease `true` + 4 个附件全在，`published_at`（06:57:06）与附件 `updated_at`（06:57:08–10）都落在那一步 6 秒窗口（06:57:05–11）内，公开直链 `curl -sIL` 三个 APK 全 `200`。失败点是这一步**最后那句纯打印** `gh release view --json … --jq …`，前面的 `gh release create`/`upload` 都过了。

结论与教训：
- **红叉 ≠ 包没发出去**。判断要看 steps 表和 `releases/tags/dev-build`，不能只看 run 的绿/红。
- 云端包与本机包**字节数与 sha256 都不同**（云端 arm64 17,909,554 / 本机 17,917,607），因为 Runner 用的是它自己现生成的 `~/.android/debug.keystore`，签名块不一样。别拿本机哈希去核对云端附件，要比只比 `apk-sha256.txt` 里云端自己算的那组。
- ~~小瑕疵：`apk-sha256.txt` 里只有三个分 ABI 包，没有通用包 `app-release.apk`~~ —— 已修，根因是 glob 而不是笔误，并且实测过：本机建 `app-arm64-v8a-release.apk`/`app-armeabi-v7a-release.apk`/`app-x86_64-release.apk`/`app-release.apk`/`app-debug.apk` 五个空文件，`ls app-*-release.apk` 只回前三个。`app-` 之后要求一个字面的 `-release.apk`，`*` 匹配空也只能凑出 `app--release.apk`，所以通用包永远进不去。现在那一步改成逐个点名 4 个文件。
- 待修（不影响使用，只影响 run 变绿）→ **已修**：最后一行自检改成 `if summary=$(gh release view … --jq … 2>&1); then echo; else echo "::warning::…$msg"; fi`，一句打印不再能把整个 run 拖红，失败原因以 annotation 呈现。选 annotation 而不是 `::error::` 是因为它天然只当警告；而写 annotation 而非丢进日志，是因为 `actions/runs/{id}/logs` 要 admin 权限（本轮 403 过），`/check-runs/{id}/annotations` 免登录就能读。
  - workflow command 的值是**单行**协议，所以 `$summary` 先 `tr '\r\n' '  '` 再 `sed 's/%/%25/g'`（顺序不能反，反了会把刚插进的 `%25` 又转一遍）。这条管道用 `{"100%":"ok"}` + CRLF 混排做过实样验证，输出为单行且 `%`→`%2525` 这种已转义内容能正确保持。
- 同时把 `app-x86_64-release.apk` 补进了 `gh release upload` 的附件清单（run #9 只公开了 3 个 APK，x86_64 只在 Artifacts 里），`upload-artifact` 的 `path:` 改成 `app-*-release.apk` + `app-release.apk` 两行，`if-no-files-found: error` 保持不动（两个 pattern 各自都至少匹配一个文件，不会误报）。
- 本轮 workflow 改动的验证只到「本地静态」这一级：4 个 `run:` 块逐个抽出跑 `bash -n` 全过（2/7/37/3 行，抽取脚本按缩进去重，读回内容与 YAML 逐行一致），整文件用 `yaml 3.1.3` 解析出 android 9 步 / ios 6 步、各 `run` 步行数 1/1/1/3/8/38。两套行数来源不同（解析器把块尾换行多算一行），只做各自内部一致性检查，不互相核对。**真实跑一次要等 run #10**。
