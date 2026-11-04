# TimeNote 架构与代码质量评审报告

- 评审基线：`main` @ `7abb6fd`（修复前）→ 本报告同时记录修复后状态
- 评审方式：逐条读源码 + 跑工具验证，每个结论都附可复现命令
- 工具链：Flutter 3.47.8 stable / Dart 3.13.7（`D:\dev\flutter`），Windows 10 26200
- 结论：**HEAD 无法编译、无法构建资源包**，因此原先「0 CRITICAL / 评审通过」的结论不成立。本次共确认 12 项问题（3 个 P0；其中 R12 是本次新增代码自查发现，其余 11 项为存量缺陷）。

## 一、实测记录

| 命令 | 修复前（HEAD） | 修复后（工作区） |
| --- | --- | --- |
| `flutter analyze` | 语法错误阻断（见 R1），无法给出干净结果 | `No issues found!` |
| `flutter test` | 资源缺失直接失败（见 R2） | `+51: All tests passed!`（6 个测试文件） |
| 临时移走 `assets/audio/` 再跑 `flutter test` | — | `Error detected in pubspec.yaml: No file or variants found for asset: assets/audio/alert.wav. / Error: Failed to build asset bundle` |

测试分布：`app_widget_test.dart` 17、`flip_rendering_test.dart` 11、`clock_notifier_test.dart` 12、`todo_model_test.dart` 5、`storage_service_test.dart` 3、`egg_service_test.dart` 3。

## 二、缺陷清单与处置

严重度定义：P0 = 阻断构建/核心画面不可用；P1 = 功能与用户可见行为错误；P2 = 体验、一致性或工程健康度。

### R1 · P0 · 编译不过：`clock_view.dart` 里有一段被截断的扩散运算符

- 证据：`git show HEAD:lib/flip_clock/clock_view.dart | grep -n '\[n'` → `205: if (clockState.workMode == ClockWorkMode.countdown) ...[n   const SizedBox(width: 10),`
- 影响：整个 app 无法编译，「暂停/继续/停止」三个按钮所在的 `if` 列表写法被写坏（`...[n`）。
- 处置：主屏控制区重写为 `_controls()` + `_chip()` 列表（`lib/flip_clock/clock_view.dart:253`）。

### R2 · P0：`pubspec.yaml` 声明了不存在的资源

- 证据：`git show HEAD:pubspec.yaml` 声明 `assets/audio/alert.wav`；`git ls-tree -r HEAD --name-only assets` 只有 `assets/data/quotes.json`。
- 影响：新克隆后 `flutter test` / `flutter build` 全部失败（上面第三条实测就是这个报错），并非「运行时才降级」。
- 处置：补入本地生成的占位提示音 `assets/audio/alert.wav`（44.1kHz / 单声道 / 16bit PCM，30912 字节，指数衰减 880Hz 短音），并纳入版本库；CI 里原来「云端重建 wav」的步骤随之删除（`.github/workflows/build-apk.yml`）。图标与 `gradle-wrapper.jar` 仍由 CI 生成。

### R3 · P0：书页卷曲翻页把数字永久冻在侧立态（看不见）

- 证据：`git show HEAD:lib/flip_clock/flip_renderer.dart` 的 `PageCurlRenderer` 在 `transitionBuilder` 里直接 `rotateY(1.57 * (1 - anim.value))`。`transitionBuilder` 只在建子节点时执行一次，不监听 `animation`，所以 `anim.value` 永远是入场瞬间的 0 → 角度停在 1.57rad。
- 可观测结果：矩阵 `y` 基向量分量 `cos(π/2) = 6.12e-17`，即数字变成一条边，等于消失。
- 处置：`_FlipTransform` 改为 `AnimatedBuilder` 监听动画（`lib/flip_clock/flip_renderer.dart:37`），5 种动画统一「value==1 回到平铺」的约定。
- 回归测试与反向验证：`test/flip_rendering_test.dart` 的「切换数字后仍会回到静止态」。把 `AnimatedBuilder` 还原成一次性读 `anim.value` 后，该用例报错 `Expected: a value greater than <0.9> / Actual: <6.123233995736766e-17>`，确认测试真能钉住这个 bug。

### R4 · P1：10 种数字风格实际画面上完全一样

- 证据：`git show HEAD:lib/core/constants.dart` 的 `styleFontMap` 把 10 个风格映射到 5 个字体 family；`git show HEAD:pubspec.yaml` 里**没有 `fonts:` 段**，`assets/` 只有 quotes/audio。未打包的 family 会静默回退系统字体。
- 影响：风格差异只剩 `fontFamily` 这一个维度，而它本身失效 → 用户切 10 次设置，画面一动不动。其余渲染参数（字号 120、`FontWeight.bold`）在所有渲染器里写死。
- 处置：新增 `ClockLook` 外观表（字重 / 斜体 / 字距 / 字号倍率 / 描边宽度 / 底板不透明度 / 圆角 / 内边距 / 中缝 / 等宽数字 10 个维度），字体降级为其中一个可选维度（`lib/flip_clock/flip_renderer.dart:177` 起）。
- 回归测试：「两两之间至少有一个可见维度不同」「镂空描边样式只描边不填充」。反向验证：把 `appearanceFor` 改成恒返回 `const ClockLook()` 后这两条同时变红。

### R5 · P1：倒计时用 `Timer.periodic` 自减，与真实时间脱钩

- 证据：`git show HEAD:lib/core/providers/clock_providers.dart:62` → `Timer.periodic(1s)` 里 `state.remainTime - 1s`。
- 影响：平板息屏/切后台/系统挂起期间 timer 不触发或不精确，倒计时会「漏走」；专注计时器的核心正确性问题。同一逻辑在 `resumeCountdown` 里被复制了一遍。
- 处置：改为**墙钟 deadline 锚定**（`lib/core/providers/clock_providers.dart:78`），250ms 轮询、剩余时间向上取整到整秒、只有整秒变化才发布状态；时间源通过 `clockSourceProvider` 注入，测试用假时钟精确驱动。

### R6 · P1：手动「停止」误触发彩蛋，并把画面留在 `00:00:00`

- 证据：HEAD 的 `stopCountdown()` 只把 `remainTime` 置 0、`isRunning` 置 false，不改 `workMode`；而主屏监听的条件是 `prev.remainTime > 0 && next.remainTime == 0 && next.workMode == countdown`。
- 影响：点「停止」= 归零 → 弹出彩蛋文案 + 提示音，且主屏停在 `00:00:00` 死屏。
- 处置：`stopCountdown()` 现在等价于 `switchRealtime()`（回到实时时钟）；彩蛋的收尾同样回到实时时钟，不留 `00:00:00`。关掉彩蛋时保留 `00:00:00` 结束态（有明确的停止/时钟按钮），这是刻意区分开的两种状态。
- 回归测试：`app_widget_test.dart` 的「停止倒计时回到实时时钟，不留 00:00:00 死屏」「归零展示彩蛋，点任意处返回时钟」「关闭彩蛋后归零保留 00:00:00 结束态」。

### R7 · P1：彩蛋被提示音 `await` 挡在后面，且计时不可取消

- 证据：`git show HEAD:lib/flip_clock/clock_view.dart:77-96` → `await _audioPlayer.play(...)` 在 `setState(egg)` 之前；隐藏用的是 `Future.delayed(...)`，没有 `Timer` 句柄，既不能取消也不在 `dispose` 里清理。
- 影响：音频链路（平台通道 + 资源解码）慢或卡住时，视觉反馈跟着延迟；提前点掉彩蛋后，旧的 delayed 回调仍会在 5 秒后回来改状态。
- 处置：彩蛋先上屏，再尽力播提示音（`AudioPlayer` 懒创建，失败静默降级）；隐藏改用可取消的 `Timer`（`lib/flip_clock/clock_view.dart:102`）。
- 未自动化覆盖，见第五节边界说明。

### R8 · P2：`keepScreenOn` 关掉后不生效，要重启

- 证据：HEAD 只在 `initState` 的 `addPostFrameCallback` 里读一次设置并 `WakelockPlus.enable()`，没有跟随设置变化；`dispose` 里无条件 `disable()`。
- 处置：用 `ref.listenManual(appSettingsNotifierProvider.select((s) => s.keepScreenOn))` 即时下发 enable/disable。
- 回归测试：通过 `wakelock_plus_platform_interface` 的测试缝注入 fake platform，断言调用序列（`test/support/fake_wakelock.dart`）。

### R9 · P2：功能缺口（不是 bug，但影响可用性）

本次补齐：自定义倒计时分钟数（1–600，带非法输入校验与 15/30/45/60 快选）、倒计时进度条、设置页实时预览（用真正的 `FlipCardWidget` 每 2 秒轮换样张）、无操作 6 秒自动隐藏控件且一点即回、待办「清除已完成」、待办计数 `未完成/总数`、空态文案、输入长度 60 限制与乐观更新。

### R10 · P2：原 `REVIEW.md` 的结论与代码事实冲突

- 证据：HEAD 的 `REVIEW.md` 写着「0 CRITICAL · 无阻断发布问题」和「`flutter analyze → No issues found!`、`flutter test → 14 tests passed`」；而 HEAD 实际存在 R1（编译不过）与 R2（构建产物缺失），`test/` 下只有 4 个文件、8 个用例。它还把 H1 描述为「await 音频后缺少 `mounted` 校验」，但 HEAD 源码 `clock_view.dart:87` 明明有 `if (!mounted) return;`。
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

`git diff --stat HEAD -- lib` = 18 个文件、+1298/−657。属于「按严重度触发」的重构只有两处：

1. `lib/flip_clock/flip_renderer.dart` 整体重写（R3 + R4 的根因都在这一层：过渡构建与外观参数原先混在各渲染器内部写死）。现在 `FlipRenderer.transition(child, anim)` 只管过渡，外观由 `clockLooks` 表 + `clockTextStyle()` 统一产出，`FlipCardWidget` 单点负责自适应与底板。
2. `lib/core/providers/clock_providers.dart` 重写（R5 + R6）：状态多了 `total`（进度用），走时改为 deadline 锚定，pause/resume/stop 语义各自单独定义。

其余为局部修改，没有引入新分层，`core / flip_clock / todo / settings / egg` 五层结构保持不变。

## 四、质量属性场景（后续要守住的）

- **正确性**：倒计时在后台/挂起后仍与墙钟一致 → 由 `clock_notifier_test.dart`（12 例，`fakeAsync` + 注入时间源）守住。
- **可辨识性**：10 种风格两两可辨、5 种动画静止态可见 → `flip_rendering_test.dart` 11 例。
- **持久化**：待办/设置跨重启读回、脏数据丢弃 → `storage_service_test.dart` 3 例（真实磁盘）。
- **交互真实性**：抽屉真的滑进可视区、按钮真的能点、控件隐藏后点击不误开设置 → `app_widget_test.dart` 17 例。

## 五、验证边界（没做到的部分，明确声明）

1. **没有在真机或模拟器上运行过**。本机没有连接 Android 设备，因此以下都只有代码与单元测试层面的保证：Android/iOS 上的 wakelock 实际效果、横屏锁定、Hive 在设备数据目录的读写、音频真实播放、APK 产物安装。
2. **提示音路径未被自动化测试覆盖**：audioplayers 6 需要「资源→临时文件」的真实 IO，在 fake-async 区不可等待，所以 widget 测试统一关掉 `soundEnable`。「彩蛋先于提示音上屏、音频失败不影响视觉」这条顺序目前只有源码结构保证。
3. `assets/fonts` 仍是空的：风格差异不依赖字体文件，但 README 里列的 5 款字体尚未打包，`styleFontMap` 的 family 名在当前构建里是惰性的（回退系统字体）。
4. `quotes.json` 仍是 5 条占位文案（正式 520 条待填充），`egg_service_test.dart` 只验证了「合法、非空、不重复、抽取不连续重复」这几点。
5. CI（`.github/workflows/build-apk.yml`）改动未经 GitHub 实跑验证——analyze/test/build 三步的本地等价命令已跑通。

## 六、建议的后续动作（按性价比排序）

1. 连一台 Android 设备跑 `flutter run`，人工确认常亮、横屏、提示音、抽屉手势；把结论补进本文件。
2. 决定 `gradle-wrapper.jar` 与应用图标是否纳入版本库；纳入后可以删掉 CI 里两段生成逻辑（现在是 CI 从 `raw.githubusercontent.com` 下载 jar，属于隐性供应链面）。
3. 若要真正兑现「10 种画面风格」，打包 5 款免费商用字体并在 `pubspec.yaml` 声明 `fonts:`，同时把 `styleFontMap` 的 family 名与字体文件名校对一遍。
4. 填充正式彩蛋文案库；`EggService` 目前是静态可变状态，若以后要支持多语言/用户自定义，再考虑改成 Provider 注入。

## 七、复现本次评审的命令

```bash
export PATH="/d/dev/flutter/bin:$PATH"
flutter analyze            # No issues found!
flutter test               # +51: All tests passed!

# 存量缺陷取证（相对 HEAD）
git show HEAD:lib/flip_clock/clock_view.dart | grep -n '\[n'
git show HEAD:pubspec.yaml | sed -n '24,30p'
git ls-tree -r HEAD --name-only assets
git show HEAD:lib/core/providers/clock_providers.dart | grep -n -A8 'Timer.periodic'
```
