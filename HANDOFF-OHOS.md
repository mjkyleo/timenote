# 鸿蒙（HarmonyOS / OHOS）构建 —— 进度交接

> 记录时间：2026-11-05 01:35 初版；09:55 更新（递归根因已定位并修好）；**11:20 更新（release HAP 出包 + 包内配置复验 + Android 模拟器真机冒烟 + 修掉横屏键盘压瘪弹窗，测试 62 → 64）**；**16:02 更新（CI run #10 真绿：android 13 步全 success、dev-build 5 个附件、`apk-sha256.txt` 4 行；顺带挖出 run #9 红叉的根因是 `gh release view --json prerelease` 字段名写错，正确叫 `isPrerelease`）**；**16:25 更新（run #11 复跑同样全绿、dev-build 那条 warning 注解消失 = 摘要日志推断已能打；并实测 `--clobber` 会换 asset id、同名附件字节相同但 sha256 每轮都变）**；**16:33 更新（run #11 的 arm64 包整份下载成功，sha256 与同一轮清单逐字相同 = 字节级完整性核对补上了；本机直链会被截，要走 assets API 断点续传，实测 8 轮）**；**23:50 更新（第八/九轮代码之后本机 Android 与鸿蒙两条出包链全部重跑一遍，数字换到 `52e4bf3`：arm64 APK 18,245,379 / release HAP 23,093,027 / debug HAP 125,984,972；并实测 `tool/build_hap.sh` 那句新加的 `--dart-define=BUILD_SHA` 真的落进了包：release 的 `libapp.so` 与 debug 的 `kernel_blob.bin` 里各查到 1 次当前 commit）**；**03:0x 更新（run #17 把 dev-build 传成 4 个附件的残缺已修好：CI 改成「上传 + 点名核对 + 最多 3 轮重试」，`b771a10` 推上去触发 run #18 `success`，6 个附件同源同一轮）**；**14:01 更新（第十二轮 R4：不再强制横屏，新增开始页与横/竖二选，测试 209 → 214，版本 `1.2.0+3`；`module.json5:24` 的 orientation 改成 `auto_rotation`，本轮 HAP 与 APK 都没重出包，见 §5 待办 1 的追加）**；**14:45 更新（第十二轮收尾：`5c2722c` 提交 → `v1.2.0` 标签发布（run #22/#23 全绿）→ 本机四个 APK + release HAP 全部重出（产物时间戳 14:13–14:20）。release HAP 23,191,729 B、`libapp.so` 5,768,112 B，包内 `module.json` 的 `orientation` 复验为 `auto_rotation`；顺带纠正一条老结论：`--release` 不带 `--no-codesign` 会 `EXIT=1` 且不复制到 `build/ohos/hap/`，带上了才是 `EXIT=0` + `√ Built`，见 §0 与 §5 待办 1）**。下面的每一条数字/路径都是当场跑出来的。

---

## 0. 一句话现状

**`tool/build_hap.sh` 一键直出已打通，debug 与 `--release` 都跑过了**：第八/九轮代码之后（2026-11-05 23:41 / 23:43 两个产物时间戳，工作副本 `52e4bf3`，代码 == `947ecaf`）两条链路又各复跑一次，release（AOT）264.5 s / 23,093,027 B、debug 71.9 s / 125,984,972 B，两次 `EXIT=0`。这一轮还顺带验证了脚本里那句新增的 `--dart-define=BUILD_SHA`（此前从未跑过）：构建接受该参数并且 SHA 真的进了包（证据见下表「BUILD_SHA 进包」那一行）。

**第十二轮（R4）之后在 `5c2722c` 又重出一次 release**：14:13–14:17 那次 `tool/build_hap.sh --release`（不带 `--no-codesign`）冷缓存 240.1 s，`assembleHap` 成功、`.hap` 生成，但签名步骤拿不到证书 → **`EXIT=1` 且没复制到 `build/ohos/hap/`**；14:41 再跑 `tool/build_hap.sh --release --no-codesign`，hvigor 命中增量 13.1 s、产物没重写，`EXIT=0` 且报 `√ Built build\ohos\hap\entry-default-unsigned.hap (22.1MB)`，两个落点 md5 相同（`7ee78c2a…`）。结果：`entry-default-unsigned.hap` **23,191,729 B**（比 `52e4bf3` 的 23,093,027 多 98,702），`libs/arm64-v8a/libapp.so` **5,768,112 B**（+98,304，全在 Dart 侧），`libflutter.so` 16,416,376 / `ets/modules.abc` 725,136 逐字节没动，21 个文件、未压缩合计 23,188,479，包内 `module.json` 的 `orientation` 已是 `auto_rotation`。
剩下的不是构建问题，而是**签名**：`*-unsigned.hap` 装不上真机，调试证书要华为账号在 DevEco 里申请（见 §5 待办 6）。

唯一的技术障碍（§3 的 `BATCH RECURSION exceeds STACK limits, Recursion Count=234`）根因是
**`D:\flutter_ohos\bin\flutter` 这个 bash 启动器里的 `OS="$(uname -s)"` 污染了子进程树**，与参数长度、管道、shim 都无关。

产物（已存在，勿删）—— 两个落点用的是**同一个文件名** `entry-default-unsigned.hap`，所以后跑的那条会覆盖前一条在该目录的产物：23:43 的 debug 复跑之后，`outputs/default/` 和 `build/ohos/hap/` 躺的是同一份 debug（都是 125,984,972 B，时间戳一致），release 那份 23,093,027 B 已被就地覆盖 —— 要同时留两份，得在 release 跑完立刻改名收走。

⚠️ 这一段以前写的「debug 由工具复制到 `build/ohos/hap/`，**release 不复制**」**结论错了**，`5c2722c` 这轮实测出来：复制与不复制的分界不是 debug/release，而是 `--no-codesign` 有没有传。`--release` 单独跑 → 签名步骤非零退出，复制那步没走到；`--release --no-codesign` → `√ Built build\ohos\hap\...`，两处落点同一份。现在（14:41 之后）`build/ohos/hap/` 与 `outputs/default/` 都是那份 23,191,729 B 的 release，debug 的 125,984,972 B 已被覆盖。

| 项 | 实测值 |
| --- | --- |
| 路径 | 两处同名互盖，谁后跑谁留下。当前（`5c2722c`，14:41 之后）`build/ohos/hap/entry-default-unsigned.hap` 与 `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap` 是同一份 release（md5 `7ee78c2a…`）。以前记的「release 只落在 `outputs/default/`，`build/ohos/hap/` 不会被更新」实为 `--release` 没带 `--no-codesign` → 非零退出、复制没执行，见上一段 |
| 大小（release，当前 = `5c2722c`） | 23,191,729 字节（产物 14:17，14:41 复制到两个落点），包内 21 个文件、未压缩合计 23,188,479（`unzip -l` 实测）；`libs/arm64-v8a/libapp.so` 5,768,112 B（AOT，比上一轮 5,669,808 多 98,304，就是本轮新增的开始页 + 排向那条设置）+ `libflutter.so` 16,416,376 B（逐字节没动）、`ets/modules.abc` 725,136 B（同样没动，ArkTS 侧只改了 `module.json5` 的配置不是代码），**无 `kernel_blob.bin`**。上一轮（`52e4bf3`，2026-11-05 23:41）：23,093,027 B / 未压缩 23,089,777 / `libapp.so` 5,669,808 B。⚠️ 路径见上面「路径」那一行：release 落哪、有没有复制，取决于 `--no-codesign` |
| release 包是不是当前代码 | 这条以前要靠符号名反推（上一轮 release 和改动前**字节数恰好相同**，只能用 `libapp.so` 里查 `autoMix` / `_hingedLeaf` 来证明不是没重编）。这一轮不用推了：包大小本身变了（22,748,875 → 23,093,027），而且直接把本轮 `git rev-parse HEAD` 的完整 SHA 拿去 `grep -ac` —— 见下面「BUILD_SHA 进包」那一行。旧取证保留：`build/ohos/intermediates/flutter/defaultRelease/arm64-v8a/app.so` 时间戳 = 本次构建。 |
| BUILD_SHA 进包 | `tool/build_hap.sh` 现在会给 `flutter build hap` 追加 `--dart-define=BUILD_SHA=$(git rev-parse HEAD)`（和 CI 出 APK 同口径，设置页「检查更新」在鸿蒙包里有得比）。这句加进去之后一直没实跑过，本轮补上：**release** 解包 `unzip -o` 后 `grep -ac 52e4bf38fdaaa3b64daaaf7bdfcd219a541be980 libs/arm64-v8a/libapp.so` = **1**；**debug** 解出 `resources/rawfile/flutter_assets/kernel_blob.bin` 同样 `grep -ac` = **1**。两次构建都 `EXIT=0`，脚本里没有别的改动。**`5c2722c` 这轮再测一次**：日志里那行就是 `--dart-define=BUILD_SHA=5c2722cf14a9c2275eaa2545804daafd069d4b43`，解包 `grep -c 5c2722cf14a9c2275eaa2545804daafd069d4b43 libs/arm64-v8a/libapp.so` = **1**（release；debug 包这轮没重跑，`kernel_blob.bin` 那条仍是 `52e4bf3` 的取证）。 |
| 大小（debug） | 125,984,972 字节（23:43，`52e4bf3`；≈120 MB，24 个文件、未压缩合计 125,981,204），含 `kernel_blob.bin` 72,010,880 B（上一轮 71,840,168，+170,712）+ `libflutter.so` 38,896,320 B（没动）、`ets/modules.abc` 1,251,580 B（debug 版没压缩，比 release 的 725,136 大得多），`tool/build_hap.sh` 71.9 s `EXIT=0` |
| 构建耗时 | 本轮：release 264.5 s（日志 23:41:37 收尾）/ debug 71.9 s（23:43:20）（`tool/build_hap.sh [--release]`；release 那轮慢是因为它撞上了 `pub get` 重新解析 11 个依赖 + hvigor 冷缓存，上一轮热缓存下是 107.2 s。此前一轮：debug 64.2 s / release 107.2 s） |
| bundleName | `com.timenote.timenote`，versionName 1.0.0，`pack.info` 里 `"code":1` |
| apiVersion | compatible 17 / target 26（`pack.info`），`runtimeOS HarmonyOS` |
| deviceType | `["phone", "tablet"]`，ability `orientation` —— **`5c2722c` 这轮的 release 包内复验**：`unzip -p build/ohos/hap/entry-default-unsigned.hap module.json` 交出 `"orientation":"auto_rotation"`，`pack.info` 的 `deviceType` 是 `["phone","tablet"]`（`packages[0].deviceType` 同值）。以前那一版（2026-11-05 23:41 重建）包内是 `auto_rotation_landscape`，源码从第十二轮（R4）起改成 `auto_rotation`（`module.json5:24`），现在包内值与源码对上了 |
| 图标 | 包内 `resources/base/media/{icon,app_icon}.png` 各 21,357 B，144×144 RGBA（源图 `assets/icon/timenote-launcher-icon-1024.png` 经 `tool/make_icons.py` 缩出） |
| 资源 | 包内 `resources/rawfile/flutter_assets/` 有 `assets/data/quotes.json` 27,867 B、`assets/audio/alert.wav` 30,912 B、`NOTICES.Z`、2 个 shader —— 彩蛋文案与提示音确实入包 |
| 签名 | 无（`build-profile.json5` 里 `signingConfigs: []`，产物是 `*-unsigned.hap`，`SignHap` 任务 3 ms 空跑） |


---

## 1. 本机工具链（明天照抄即可）

| 组件 | 位置 / 版本 |
| --- | --- |
| Flutter-OH SDK | `D:\flutter_ohos`，`3.41.9+ohos-1.0.2`，framework `62357a93d6`，engine `42d3d75a56`，Dart `3.11.5` |
| 主 Flutter（Android/iOS 用） | `D:\dev\flutter`，3.47.8 |
| 华为 Command Line Tools | `E:\command-line-tools`（windows-x64 26.0.0.865） |
| ohpm | 26.0.0.630（`E:\command-line-tools\ohpm\bin\ohpm.bat`） |
| hvigorw | `E:\command-line-tools\bin\hvigorw.bat`，hvigor 6.26.9 |
| Node（CLT 自带） | v24.14.1，在 `E:\command-line-tools\tool\node` |
| SDK | `E:\command-line-tools\sdk\default`，`available api versions has [26:default]` |
| hdc | `E:\command-line-tools\sdk\default\openharmony\toolchains` |
| JDK（必须前置，见 §4 坑 C） | `C:\Users\86132\.jdks\temurin-17\bin`，Temurin 17.0.20.1+1 |

**出包只需一条命令：`tool/build_hap.sh`** —— 它自己 source `tool/ohos_env.sh`、注入 `pubspec_overrides.yaml`、走 `flutter.bat`（**不是** bash 启动器，见 §3）、结束后清理覆盖文件。
`tool/ohos_env.sh` 是正本（Temp 里那份会被系统清理），单独手工跑 hvigor 时才需要手动 source；实测 `source` 后 `DEVECO_TOOLS_HOME` / `DEVECO_SDK_HOME` / `PUB_CACHE` 能正常传给 cmd。

```bash
tool/build_hap.sh                          # = flutter.bat build hap --debug --no-codesign --dart-define=BUILD_SHA=<HEAD>
tool/build_hap.sh --release --no-codesign  # AOT，`5c2722c` 实测 23,191,729 B、EXIT=0，并同时复制到 build/ohos/hap/（两个落点同名互盖，后跑的覆盖前跑的）
tool/build_hap.sh --release                # ⚠️ 少了 --no-codesign 会走去签名：产物照样生成但 EXIT=1，且不复制到 build/ohos/hap/（脚本的默认值 `--debug --no-codesign` 只在完全不传参数时生效）
```

里面 4 件事不能少：
1. `DEVECO_SDK_HOME=E:\command-line-tools\sdk`、`DEVECO_TOOLS_HOME=E:\command-line-tools`
2. **PATH 顺序**：CLT `bin`（`.bat`）在 shim 目录**之前** —— `cmd` 靠 PATHEXT 找到真 `.bat`，而 Dart 的 `Process` 只认 `<name>.exe`，才会落到 shim。顺序反了其中一条链就断。
3. `PUB_CACHE=D:\dev\pub-cache` —— hvigor 要求插件 `srcPath` 是**相对路径**，flutter 工具用 `path.relative` 算；工程在 D:、pub 缓存默认在 C:，跨盘符会退化成绝对路径 → `AdaptorError 00303231`。
4. `GIT_LFS_SKIP_SMUDGE=1` + `GIT_CLONE_PROTECTION_ACTIVE=false` —— audioplayers 的 git fork 里 `example/ohos/dta/icudtl.dat` 的 LFS 对象远端缺失，且仓库自带 post-checkout hook 会被 cmd 拒。

`.exe` shim（已编译好，`C:\Users\86132\AppData\Local\ohos-clt-shim\{hvigorw.exe,ohpm.exe}`，源码 `Shim.cs` 同目录）：读自身文件名 → `cmd /d /s /c "%DEVECO_TOOLS_HOME%\bin\<name>.bat" <args>` 并透传退出码。**它不是递归的元凶**（§3），只是 Dart 认 `.exe` 才需要的垫片；换机器时要重新编译，否则 `hvigorw` 这一步找不到。

`flutter doctor` 的鸿蒙工具链一栏全绿（`[✓] HarmonyOS toolchain`，Ohpm 26.0.0.630 / Node v24.14.1 / Hvigorw 定位到 `bin\hvigorw.bat`）。

---

## 2. 工程接线状态（已完成，别重复做）

- `ohos/` 已生成并跑通：模板来自 Flutter-OH `templates/app/ohos.tmpl`，共 **33 个文件**会被纳入版本库（`git add -An --dry-run ohos` 实测），其余由 `ohos/.gitignore` 挡掉（`node_modules/ oh_modules/ local.properties **/build/ .hvigor/ package.json oh-package-lock.json5 flutter_assets/ libapp.so libflutter.so`）。
  - **入库清单已扫过本机泄露**：对这 33 个文件 `grep -lE "[A-Za-z]:\\\\|[A-Za-z]:/|/c/Users|command-line-tools|temurin|86132"` → **零命中**，即仓库里没有华为 CLT 路径、盘符或本机用户名。`ohos/entry/src/main/resources/rawfile/buildinfo.json5` 是唯一由构建写出的跟踪文件，内容是常量（`enable_impeller = "true"`，无时间戳），不会产生提交噪音。
  - `rawfile/` 下 `git status` 会整目录显示未跟踪，但 `git add -An` 只列出 `buildinfo.json5` —— 同目录的 `flutter_assets/` 被 .gitignore 正确挡住（实测过滤生效，别被 `??` 骗到）。
- `.metadata` 手工修回来了：`flutter create --platforms ohos .` 会**顶掉 android/ios 条目**并塞 `test/widget_test.dart`、`timenote.iml` —— 已恢复（migration.platforms 同时含 root/android/ios/ohos）并删掉样板文件。**这条坑明天还会再咬一次，别再跑 `flutter create`。**
- `pubspec.yaml` 鸿蒙接线（2026-11-05 收敛后）：
  - 新增 `path_provider_ohos: ^2.2.1`、`wakelock_plus_ohos: ^0.0.3`（这两个对 android/ios 构建无副作用，实测标准 SDK 编译通过）
  - `wakelock_plus_platform_interface` 从 `^1.7.0` 降到 `^1.6.0`（1.7.0 要 Dart ≥3.12，Flutter-OH 只有 3.11.5）
  - `audioplayers` 的 git fork 覆盖**不在 pubspec.yaml 里**，改放 `tool/pubspec_overrides.ohos.yaml`，构建 hap 时才注入（原因见 §3.5）
- `flutter pub get` 两个 SDK 都通过。带覆盖时 `.flutter-plugins-dependencies` 的 ohos 段有 3 个插件：`audioplayers_ohos`、`path_provider_ohos-2.2.1`、`wakelock_plus_ohos-0.0.3`。
- 这 3 个插件真的注册进了 `ohos/entry/src/main/ets/plugins/GeneratedPluginRegistrant.ets`（第 2-4 行 `import WakelockPlugin from 'wakelock_plus_ohos'` / `PathProviderPlugin from 'path_provider_ohos'` / `AudioplayersPlugin from 'audioplayers_ohos'`）；该文件在 `src/` 下、不在 `**/build/` 忽略范围里，会入库。
- **`lib/` 里没有任何平台判断**（`grep -rn "Platform\.is\|TargetPlatform\|defaultTargetPlatform\|kIsWeb" lib/` → 0 处），所以鸿蒙侧不需要改 Dart 代码；反过来也意味着**别在 `lib/` 写 `TargetPlatform.ohos`** —— 标准 SDK（含 CI）没有这个枚举成员，会像 §3.5 的 audioplayers 那样直接编不过。

---

## 3. 已解决：hvigor → ohpm 的批处理递归（根因 + 证据）

### 现象（当时的确定性复现）

```
$ flutter build hap --debug          # env 已 source
start hap build...
Running Hvigor task assembleHap...
> hvigor start to execute ohpm install
0 task in total: 0 executed, 0 up-to-date.
******  B A T C H   R E C U R S I O N  exceeds STACK limits ******
Recursion Count=234, Stack Usage=90 percent
> hvigor ERROR: 00306053 Specification Limit Violation
Error Message: ohpm install failed.
> hvigor ERROR: BUILD FAILED in 3 s 34 ms
```

崩溃报告：`flutter_03.log`、`flutter_04.log`、`flutter_11.log`（`.gitignore` 已忽略 `flutter_*.log`）。

### 根因（实测，两条日志对得上）

`E:\command-line-tools\ohpm\bin\ohpm.bat` 第 1 行附近：

```bat
if "%OS%"=="Windows_NT" setlocal enabledelayedexpansion
```

华为这个脚本**把延迟展开挂在 `%OS%` 上**。而在 Dart 驱动的链路里子进程拿到的 `OS` 不是 `Windows_NT`：

```
PROBE1 EL[0] FIRST1[i] NAME["ohpm"] OS[MINGW64_NT-10.0-26200] DT["!OHPM_FIRST_PARAM!"]
CALC P["!OHPM_FIRST_PARAM!"] LEN[0]
CALC P["!OHPM_FIRST_PARAM!"] LEN[1]
... 一直自增，直到爆栈
```

`DT["!OHPM_FIRST_PARAM!"]` = 延迟展开没开，`!VAR!` 保持字面量 → `if "!OHPM_FIRST_PARAM!"==""` 永远不成立 → `:calculateFirstParamLen` 无限自我 `call`。

`OS` 被污染的地方是 **flutter 自己的 bash 启动器**：

```bash
# D:\flutter_ohos\bin\flutter:54
OS="$(uname -s)"
if [[ $OS =~ MINGW.* || $OS =~ CYGWIN.* || $OS =~ MSYS.* ]]; then exec "${BIN_DIR}/flutter.bat" "$@"; fi
```

`OS` 是从 Windows 环境继承来的**已导出**变量（bash 里 `echo $OS` = `Windows_NT`），对已导出变量赋值会保留导出属性，于是 `MINGW64_NT-10.0-26200` 一路传进 `flutter.bat` → Dart → `hvigorw` → node → `ohpm.bat`。
工程级探针实测（`ohos/hvigorw.bat` 里 `echo OS=[%OS%]`）：flutter 传下来的是 `OS=[MINGW64_NT-10.0-26200]`，而同一台机器手敲 `cmd //c "set OS=Windows_NT&& ohpm.bat ..."` 走的是 `ENVTEST` 分支、**不递归**。

### 修法（已落地，两处，都不动华为 SDK 本体）

1. **绕开 bash 启动器**：直接调同目录的 `flutter.bat`（纯批处理，不碰 `OS`）。`tool/build_hap.sh` 已经这么写，并带 `trap` 清理。
   ```bash
   tool/build_hap.sh                 # 默认 --debug --no-codesign
   tool/build_hap.sh --release       # 传参可覆盖
   ```
2. **`pubspec_overrides.yaml` 注入**（见 §3.5）：这个和递归无关，但同一条链路上必须处理。

验证记录（2026-11-05 09:41–09:42）：删掉 `build/ohos` 与 `ohos/entry/build/default/outputs` 后重跑，`Running Hvigor task assembleHap... 41.0s` → `√ Built build\ohos\hap\entry-default-unsigned.hap.`，`EXIT=0`。

### 3.5 顺带修掉的 Android/iOS 阻断（重要，别回退）

之前 `pubspec.yaml` 里把 `audioplayers` 整包覆盖成 CPF-Flutter 的鸿蒙 fork。该 fork 的 Dart 源码用了 `TargetPlatform.ohos`：

```
/C:/.../flutter_audioplayers-.../packages/audioplayers/lib/src/audioplayer.dart:178:51:
Error: Member not found: 'ohos'.
```

标准 Flutter SDK 没有这个枚举成员 → **`flutter test` 有 2 个文件编译失败（+34 −2），Android/iOS 构建和 CI 同样会挂**。
改法：覆盖从 `pubspec.yaml` 挪到 `tool/pubspec_overrides.ohos.yaml`（提交），由 `tool/build_hap.sh` 在构建 hap 时复制成 `pubspec_overrides.yaml`（已加进 `.gitignore`），构建完 `trap` 删除。
实测：主 flutter `pub get` 通过、`flutter test` **64 例全绿**、`flutter analyze` No issues found。

### 已排除的假设（都留档，别再走一遍）

- ~~超长 `-p DART_DEFINES` 触发递归~~ → 值实测 317 字符，cmd 手跑成功。
- ~~`.exe` shim 的参数拼接有问题~~ → shim 直调成功。
- ~~管道 stdout 触发~~ → `cmd | cat` 跑完整链路 `BUILD SUCCESSFUL in 1 min 47 s`。
- ~~递归深度 ≈ 2 × len(`%1`)~~ → **已被 argv 探针推翻**：真实 `%1` 就是 `i`（1 字符），`FIRST1[i]`，递归与参数长度无关。
- ~~PATH 顺序~~ → 两种顺序手跑都成功。

调用方（已读，留档）：`hvigor/hvigor-ohos-plugin/src/plugin/hooks/ohpm-load-install.js`

```js
const o = process.env.ohpmBin || "ohpm";
r = a ? `"${o}" i --all --target_path ${t} --parameterFile=${a}`
      : `"${o}" i --all --target_path ${t}`;
RunCommandUtil.run(r, undefined, true)   // spawnSync(cmd, ["/d","/c", r], {windowsVerbatimArguments:true, stdio:"inherit"})
```

`ohpmBin` 由 `hvigor/bin/hvigorw.js:32190–32191` 无条件设成 `resolve(__dirname,"../../ohpm/bin/ohpm.bat")`。

⚠️ 调试期间给 `E:\command-line-tools\ohpm\bin\ohpm.bat` 插过探针，**已还原**：`md5 = 3481f1c9ec50a2e05fa4ad42ca6b8dc6`、权限回到只读 `-r--r--r--`、`ohpm-probe.bat` / `ohpm-real.bat` 已删。华为 SDK 目录现在是原始状态。


---

## 4. 本机环境已踩平的坑（别再踩）

- **坑 A｜Dart `Process.run` 不吃 PATHEXT**：裸名只补 `.exe`，所以 `ohpm`/`hvigorw` 这种 `.bat` 要靠 shim `.exe`（`.cmd` shim 也不行，必须真 `.exe`）。但**绝对路径的 `.bat` 可以直接执行**（实测），所以放一个工程级 `ohos/hvigorw.bat` 也能替掉 shim —— 只是那会把本机路径写进仓库，现在没这么做，仍用 shim。
- **坑 B｜hvigor 要求 srcPath 为相对路径**：见 §1 第 3 条 `PUB_CACHE` 同盘。
- **坑 C｜`java` 被 Oracle javapath 别名桩劫持**：`PackageHap` 报 exit `3221226505`（0xC0000409），`java -version` 无输出 → PATH 前置 `C:\Users\86132\.jdks\temurin-17\bin` 已解决。
- **坑 D｜`flutter create` 顶掉 `.metadata`**：见 §2。
- **坑 E｜iOS `GeneratedPluginRegistrant.{h,m}` 每次命令后变成 CRLF-only diff**：用 `git diff --stat --ignore-cr-at-eol -- ios` 证实零内容差异，**提交前 `git checkout -- ios`**。
- **坑 F｜`~/.npmrc`**：已备份为 `C:\Users\86132\.npmrc.bak-timenote`，追加了 `@ohos:registry=https://repo.harmonyos.com/npm/`（原 `registry=https://registry.npmmirror.com` 保留）。
- **坑 G｜`bin/flutter` 的 `OS="$(uname -s)"` 会污染整棵子进程树**：见 §3。任何"从 Git Bash 调 flutter 之后华为 `.bat` 行为异常"都先怀疑这条；判据是在 `.bat` 里 `echo OS=[%OS%]`，正确值必须是 `Windows_NT`。
- **坑 H｜`.bat` 文件里别写 UTF-8 中文注释**：cmd 按 OEM/GBK 解码，注释字节会被当成命令执行，产生完全误导的假象（曾据此误判 `DEVECO_TOOLS_HOME` 未定义）。调试用批处理一律纯 ASCII。
- **坑 I｜Android 侧 Gradle 卡在 Maven Central / Plugin Portal**：`repo.maven.apache.org`、`plugins.gradle.org` 都在 Cloudflare 上，本机连接被静默挂住 —— 症状是 `Running Gradle task 'assembleDebug'...` 十几分钟不动，jstack 看到 `ParallelResolveArtifactSet.visit → waitForWorkToComplete`，`netstat` 一堆 `CLOSE_WAIT`，`~/.gradle/caches/modules-2` 零增长。解法：`C:\Users\86132\.gradle\init.d\cn-mirror.gradle` 把这两个 URL **原地**换成 `maven.aliyun.com/repository/{public,gradle-plugin}`。
  ⚠️ 只能改 URL，不能 `repos.maven { ... }` 新增仓库 —— 会撞工程 `settings.gradle.kts` 的 `repositoriesMode` 校验，报 `Build was configured to prefer settings repositories over project repositories but repository 'maven' was added by settings file`。实测换源后 3m45s 走完依赖。
- **坑 J｜中途 kill 掉的 Gradle 构建会留下损坏的 Kotlin 增量缓存**：下次构建报 `Could not close incremental caches in build\<plugin>\kotlin\compileDebugKotlin\cacheable\caches-jvm\jvm\kotlin: *.tab`（`package_info_plus`、`audioplayers_android` 两个任务各炸一次），异常链末端是 `IllegalStateException: Storage for [...class-fq-name-to-source.tab] is already registered`。
  ⚠️ **`flutter clean` 没用**（实测：clean、`gradlew --stop`、taskkill 掉 Kotlin daemon 16632、把可用内存从 2.2 GB 腾到 7.4 GB、`--max-workers=1 --no-parallel` 四种都试过，全部照炸）。真正的解法是**关掉 Kotlin 增量编译**：`C:\Users\86132\.gradle\gradle.properties`（此前不存在，本次新建）里写 `kotlin.incremental=false`，之后 38.3 s 正常出包。代价是 Kotlin 每次全量编译，换来的是不再卡死。
- **坑 K｜`adb shell input tap` 用的是横屏（旋转后）坐标**：App 在 `lib/main.dart:15` 锁了横屏，屏幕物理是 1080x2400 但 `screencap` 出 2400x1080，`input tap 2000 500` 能命中右上角齿轮 —— 说明注入坐标就是横屏那套。按截图估坐标时别按竖屏换算。（`lib/main.dart:15` 是当时那一版的行号；第十二轮（R4）起启动不再锁向，方向由开始页选、进时钟才下发，见 §5 待办 1。）
- **坑 L｜`gh release upload --clobber` 不是原子的**：同名附件是**先删干净、再逐个上传**（这个顺序由 run #17 的现场反推，见 REVIEW §17.1），中途任何一次失败都会让**已经删掉的那几个永久缺件**。run #17 实测：删 `app-armeabi-v7a-release.apk`（asset `713954948`）时 GitHub 回 `HTTP 500`，`set -e` 让整步退出，此前已删的 arm64 与 x86_64 没机会传回来。判据不看红叉、看 `releases/tags/dev-build` 的 asset 名字列表；本轮已在 CI 里改成「上传 → 点名核对 6 个附件 → 缺则 20 秒后整轮重来，最多 3 次」。


---

## 5. 待办清单（鸿蒙部分，按优先级）

1. [x] `ohos/entry/src/main/module.json5`：`deviceTypes` → `["phone", "tablet"]`；ability 加 `"orientation": "auto_rotation_landscape"`（2026-11-05 改）。合法值已从 SDK schema `toolchains/modulecheck/module.json` 核对：`unspecified / landscape / portrait / follow_recent / landscape_inverted / portrait_inverted / auto_rotation / auto_rotation_landscape / auto_rotation_portrait / … / locked / auto_rotation_unspecified / follow_desktop`。App 本身当时（2026-11-05）在 `lib/main.dart:15` 已用 `SystemChrome.setPreferredOrientations` 锁横屏，两边一致。
   - ✅ 已在 2026-11-05 重建后的包内复验：`unzip -p build/ohos/hap/entry-default-unsigned.hap module.json` 交出 `"orientation":"auto_rotation_landscape"`，`pack.info` 的 `deviceType` 是 `["phone","tablet"]`（`packages[0].deviceType` 同值）。
   - ⚠️ 【2026-11-06 第十二轮（R4）】这一条的「两边一致」已经作废：`lib/main.dart` 不再锁方向（现在是开始页问一次横/竖，点「开始」后由 `lib/flip_clock/clock_view.dart:46` 下发），`ohos/entry/src/main/module.json5:24` 也相应从 `"auto_rotation_landscape"` 改成 `"auto_rotation"`，让运行时的 `setPreferredOrientations` 说了算。embedder 侧的换算读过源码：`PlatformChannel.ets:473-476` 收 `SystemChrome.setPreferredOrientations` → `decodeOrientations`（`:71`）按位或，横屏两档（`0x08|0x02=0x0a`）落到 `AUTO_ROTATION_LANDSCAPE`（`:115`）、竖屏两档（`0x01|0x04=0x05`）落到 `AUTO_ROTATION_PORTRAIT`（`:108`），最后 `PlatformPlugin.ets:240-243` 调 `mainWindow.setPreferredOrientation`。**包内复验已在 2026-11-06 14:41 补上**：`5c2722c` 的 release 包重新出后，`unzip -p build/ohos/hap/entry-default-unsigned.hap module.json` 交出 `"orientation":"auto_rotation"`，`pack.info` 的 `deviceType` 仍是 `["phone","tablet"]` —— 包内值与源码对上了。剩下的只有「真机上转屏行为」要华为账号签好再装。
2. [x] 文案：`EntryAbility_label` / `EntryAbility_desc` / `module_desc` → 「时笺」，`AppScope/.../string.json` 的 `app_name` → 「时笺」，`vendor` `example` → `mjkyleo`。与 Android 的 `android:label="时笺"`、`applicationId="com.timenote.timenote"` 对齐。
   - `versionCode` 疑点已核实：`AppScope/app.json5` 写 `1000000`，`pack.info` 里是 `"code":1`（等于 pubspec `1.0.0+1` 的 build 号）→ **hvigor 没按 app.json5 取值**，版本以 pubspec 为准。2026-11-05 重建后复验仍是 `"code":1`，没被改回。
3. [x] 图标：源图从 `vibe_images/` 挪进仓库并改名 `assets/icon/timenote-launcher-icon-1024.png`（1024×1024 RGB，777,354 字节，深板岩底 + 琥珀翻页板；`assets/icon` 没写进 pubspec 的 `assets:`，不会打进包）。生成脚本收进 **`tool/make_icons.py`**（`py tool/make_icons.py`，Python 3.11.9 + Pillow 12.2.0），实测重跑产出 md5 稳定：
   - Android：`android/app/src/main/res/mipmap-{mdpi 48,hdpi 72,xhdpi 96,xxhdpi 144,xxxhdpi 192}/ic_launcher.png`（此前仓库里**一个 mipmap 都没有**，`AndroidManifest.xml` 的 `@mipmap/ic_launcher` 全靠 CI 现编占位图）
   - 鸿蒙：`ohos/entry/src/main/resources/base/media/icon.png`、`ohos/AppScope/resources/base/media/app_icon.png`（模板原图 144×144，保持同尺寸）
4. [x] 递归问题：根因 = `bin/flutter` 污染 `OS`，见 §3。`tool/build_hap.sh` 一键直出 —— 本日实跑两次均 `EXIT=0`（debug、`--release`），不再有 `Recursion Count` 报错。（⚠️ 2026-11-06 更正：那次 `--release` 的 `EXIT=0` 说明当时带了 `--no-codesign` 或走的默认参数；`--release` **单独**跑在 `5c2722c` 两次都是 `EXIT=1`，见 §0 与 README「本机出包（鸿蒙）」。递归这条本身仍然成立。）
5. [x] `--release` 构建（AOT）：`tool/build_hap.sh --release` → 264.5 s（23:41，工作副本 `52e4bf3`），`entry-default-unsigned.hap` 23,093,027 字节（对比 debug 125,984,972 字节）。包内换成了 `libs/arm64-v8a/libapp.so` 5,669,808 B + `libflutter.so` 16,416,376 B，`kernel_blob.bin` 不再存在，文件数 24 → 21。上一轮（14:29–14:31，当时工作树内容 == `cdceae9`，那批改动 14:50 才落成提交）的同一项是 107.2 s / 22,748,875 B / `libapp.so` 5,325,744 B，当时的「字节数恰好相同」靠符号名反推 —— 这一轮大小与 AOT 产物都随代码变了，且新增的 `--dart-define=BUILD_SHA` 在两种包里都查得到（见 §0「BUILD_SHA 进包」）。
   - ⚠️ 仍未做：release HAP 的**真机运行验证** —— 未签名包装不上去，这条要等华为调试证书（待办 6）。
6. [ ] 签名边界（**诚实写进 README，不能假装能装**）：调试证书/Profile 需要华为账号登录 DevEco 申请；`signingConfigs: []` 出来的 `*-unsigned.hap` **装不上真机**。另外 `ohos/build-profile.json5` 第 4 行 `signingConfigs: []` 与第 8 行 `products[0].signingConfig: "default"` **名字对不上**（指向一个不存在的配置名）—— 实测这**不会**让构建失败（debug/release 两次都 `EXIT=0`，hvigor 只是不签），但配好签名时必须要在 `signingConfigs` 里补一个同名（`"default"`）条目。
   - 同一处顺带核对过：`compatibleSdkVersion "5.0.5(17)"` / `targetSdkVersion "26.0.0"` 与包内 `pack.info` 的 `apiVersion.compatible 17 / target 26` 一致。
7. [x] 回归：主 flutter（`D:\dev\flutter`，3.47.8）`flutter analyze` → `No issues found! (ran in 9.9s)`（分析缓存已热；冷缓存那次是 71.8 s），`flutter test` → **64 例全绿**（`00:20 +64: All tests passed!`）。前提是把 audioplayers 的 git 覆盖挪出 `pubspec.yaml`（§3.5），否则编译直接失败。
8. [x] README 鸿蒙章节：见 README.md「🖥 本机出包（鸿蒙）」—— 命令、`OS` 污染根因、覆盖注入、`tool/ohos_env.sh`、未签名边界、CI 拿不到鸿蒙工具链的原因都写了，平台表里鸿蒙那行标成「本机能出包，云端出不了」。**每条数字都用命令实测过**（本节 §0/§5 就是实测记录）。
   - 待办 8 剩下的只有 §7 的**提交推送**（需用户授权）与待办 6 的签名。
9. [ ] **新默认底色「跟随系统」在鸿蒙上有没有真信号**（第十一轮 HIG 改造带来，见 REVIEW.md §18.3）：`lib/main.dart:55` 把 `ThemeBase.system` 翻成 `ThemeMode.system`，暗色与否取决于引擎向 `platformDispatcher` 回传的平台亮度。Android 侧这条走标准通道、无需担心。**鸿蒙侧源码查过了，通道是通的**（2026-11-06 在 `D:\flutter_ohos\engine\src\flutter\shell\platform\ohos\flutter_embedding\flutter\src\main\ets` 逐行读过，行号以下均为该目录内相对行号）：
   - 冷启动：`view/FlutterView.ets:999` 与 `:1104` 都调 `sendSettings()` → `:1114` → `embedding/ohos/Settings.ets:35`，其中 `:40` `.setPlatformBrightness(this.getThemeMode(mediaQuery))`；`getThemeMode`（`Settings.ets:50-60`）用 `mediaQuery.matchMediaSync('(dark-mode: true)')` 判暗色。
   - 热启动/系统设置中途改动：`embedding/ohos/FlutterAbility.ets:519` `onConfigurationUpdate(config)` → `:525` 按 `config.colorMode != COLOR_MODE_DARK` 落 LIGHT/DARK；`embedding/ohos/FlutterEntry.ets:106` `onConfigurationUpdated` → `:112` 同一套（这两处还顺带 `setTextScaleFactor(config.fontSizeScale)`，即系统字号缩放也是通的）。
   - 落到线上：`embedding/engine/systemchannels/SettingsChannel.ets:29` `const PLATFORM_BRIGHTNESS = "platformBrightness"`，`:123` `setPlatformBrightness()` 写进 settings 消息（`:124`）。
   - ⚠️ **仍缺真机确认**：以上是读源码，不是运行时取证 —— 未签名 HAP 装不上真机，没法验证 `config.colorMode` 在平板上是否随系统深色真的变。签名搞定后要在鸿蒙上开/关一次系统深色，看 App 底色跟不跟着切；不跟着切就把手动两档（`enum_def.dart:11` 的 `light` / `dark`）当兜底写进 README。


## 6. 待办清单（仓库其它未收口项）

- [x] CI：run #8（head `bd05071`，job `android`）失败在第 5 步「生成占位应用图标」，根因 `ubuntu-latest` 没有 ImageMagick `convert`。真实图标已入库，`.github/workflows/build-apk.yml` 里那 9 步中的图标步骤**已删除**。
  - ⚠️ 顺带提醒：即使图标步骤过了，那次 run 也会在 `flutter test` 挂 —— 当时 `pubspec.yaml` 带着 audioplayers 的 git 覆盖，标准 SDK 编不过（§3.5）。两个问题一起解决了。
- [x] CI **首轮真实验证：run #9（head `cdceae9`，2026-11-05）**。用 `api.github.com/.../actions/runs/41983168374/jobs` 逐步骤查过：
  - 前 9 步全 `success`：Set up job / Checkout / Setup Flutter / 拉取依赖 / **静态分析** / **运行测试** / **构建 Release APK** / 记录产物校验和 / 上传 Actions 产物。也就是说图标步骤删除 + wrapper 步骤删除 + audioplayers 覆盖移出这三处改动，在干净 Runner 上真的成立。
  - 第 10 步「更新公开预发布 dev-build」`failure`，但**发布其实成功了**：`releases/tags/dev-build` 交出 prerelease `true`、4 个附件全在（`app-arm64-v8a-release.apk` 17,909,554 / `app-armeabi-v7a-release.apk` 15,263,372 / `app-release.apk` 51,432,169 / `apk-sha256.txt` 275），`published_at` 与附件 `updated_at` 都落在第 10 步那 6 秒窗口（06:57:05–11）内，公开直链 `curl -sIL` 三个 APK 全 `200`。
  - 挂的是这一步**最后那句纯打印**：`gh release view "$TAG" --json … --jq '{tag:.tagName, …}'`。前面 `gh release create`/`upload` 都过了，所以是自检输出语句本身非零，不影响产物。**红叉 ≠ 包没发出去**，判断要看 steps 表和 `releases/tags/dev-build`，不能只看 run 的绿/红。
  - ~~待办（不影响使用，只影响 run 变绿）：把那最后一行改成不会失败的写法~~ —— **已改**（见下一条）。
- [x] run #9 之后对 `.github/workflows/build-apk.yml` 的四处修补（**已提交 `e628133` 推送，并被 run #10 真实验证**）：
  - 最后一句自检改成 `if summary=$(gh release view "$TAG" --json tagName,prerelease,assets --jq '…' 2>&1); then echo "$summary"; else msg=$(printf '%s' "$summary" | tr '\r\n' '  ' | sed 's/%/%25/g'); echo "::warning::…$msg"; fi`。一句纯打印不再能把整个 run 拖红；失败原因走 annotation，因为 `.../logs` 要 admin（本轮实测 403），而 `/check-runs/{id}/annotations` 免登录可读。
  - `apk-sha256.txt` 改成逐个点名 4 个 APK。glob 的坑是实测的：本机 `touch` 出 5 个 apk 后 `ls app-*-release.apk` 只回 3 个分 ABI 包 —— `app-` 之后要一个字面的 `-release.apk`，`*` 匹配空也只能得到 `app--release.apk`。
  - `gh release upload` 的附件清单补上 `app-x86_64-release.apk`（run #9 公开页只有 3 个 APK，x86_64 只在 Artifacts 里），release 正文同步加了一行说明。
  - `upload-artifact` 的 `path:` 拆成 `app-*-release.apk` + `app-release.apk` 两行，`if-no-files-found: error` 保留（两个 pattern 各自都匹配得到文件）。
  - 推送前的本地校验程度（当时只能到这个级）：`node` 按缩进抽出 4 个 `run:` 块（2/7/37/3 行）逐个 `bash -n` 全过，读回内容与 YAML 一致；`yaml 3.1.3` 解析全文件 → android 9 步 / ios 6 步，各 `run` 块行数 1/1/1/3/8/38；转义管道用 `{"100%":"ok"}` + CRLF 的样例实测成单行，已含 `%25` 的串会变成 `%2525`（GitHub 解回来正好是原样，所以顺序是先 `tr` 后 `sed`，反了会二次转义）。两套行数来源不同（解析器把块尾换行多算一行），只各自内部一致，不互相核对。
  - 提交前基线：`flutter analyze` → `No issues found! (ran in 40.7s)`，`flutter test` → `00:19 +86: All tests passed!`。
- [x] CI **第二轮真实验证：run #10（head `e628133`，2026-11-05，id `41987694469`）—— 真绿**。
  - `actions/runs/41987694469/jobs`：android job **13 步全 `success`**（含 Set up job / 3 个 Post / Complete job），446 秒（07:30:28→07:37:54），其中「构建 Release APK」独占 306 秒；「记录产物校验和」0 秒、「上传 Actions 产物」6 秒、「更新公开预发布 dev-build」**5 秒 success**。ios `skipped`（按设计，只有手动触发勾选才跑）。
  - `releases/tags/dev-build` 现在 **5 个附件**（`updated_at` 07:37:31–32）：arm64 17,909,554 / arm32 15,263,372 / **x86_64 19,335,481（新增）** / 通用包 51,432,169 / **`apk-sha256.txt` 357 字节 = 4 行**（run #9 是 275 字节 3 行；差值 82 正好是 `app-release.apk` 那行的长度）。
  - Artifacts 侧证：`timenote-release-apk` 从 24,897,396 → **48,773,766** 字节，接近翻倍，与「3 分包 52,508,407 → 4 包 103,940,576、压缩率两次都约 47%」一致，所以通用包确实进了 Artifacts，不是巧合。
  - **run #9 的根因由这次新加的 annotation 交出来**（`/check-runs/127112266223/annotations` 3 条之一）：`Unknown JSON field: "prerelease" / Available fields: apiUrl assets author body createdAt databaseId id isDraft isImmutable isPrerelease name publishedAt tagName tarballUrl targetCommitish uploadUrl url zipballUrl`。即 `gh release view --json` 的字段名是 **`isPrerelease`**，`prerelease` 不存在 —— 红叉从来不是打印玄学，是这一步的 `--json` 参数写错。改之前拿不到这个信息（日志 403），加了兜底第一轮就读到了，annotation 的设计价值被实测验证；gh 的报错本身是多行，也正好走了一遍 `tr`+`sed` 压单行的真场景。
  - 据此把 `--json tagName,prerelease,assets` / `--jq '{… prerelease: .prerelease …}'` 改成 `isPrerelease`（warning 兜底保留不动）。推送前的行数是 run 块 2/7/38/3、解析器 1/1/1/3/8/39（同一套抽取脚本复跑过，`bash -n` 与 YAML 解析均通过）。
- [x] CI **第三轮真实验证：run #11（head `94ddb91`，2026-11-05，id `41991694782`）—— 字段名修对后彻底干净**。
  - 提交 `94ddb91`「ci: 自检改回真实字段名 isPrerelease，并记录 run #10 实测」，`4 files changed, 57 insertions(+), 15 deletions(-)`；作者 noreply、SSH 443 推送 `e628133..94ddb91`，`git ls-remote` 与 `git rev-parse main` 都是 `94ddb913d081e1f95bb9eefbf8a266dfe42951ad`。
  - android job 13 步全 `success`，逐步用时：Setup Flutter 17s / 拉取依赖 1s / 静态分析 13s / 运行测试 25s / **构建 Release APK 289s** / 校验和 0s / Artifacts 5s / **发布 dev-build 6s**；ios `skipped`。
  - **证据性质要说清（是反证，不是看日志）**：`/check-runs/127125179043/annotations` 只剩 GitHub 自己的 2 条（Node 20 deprecation `warning`、ubuntu-latest 迁移 `notice`），run #10 那条 dev-build warning 不见了。`if summary=$(…)` 两个分支必走其一 ⇒ 没 warning 就等于 then 分支跑成 ⇒ 摘要行确实打了。日志正文仍读不到（`.../logs` 要 admin，实测 403），所以 `{tag,prerelease,assets}` 的具体内容**没亲眼看**。
  - ⚠️ **`gh release upload --clobber` 是删了重建附件**：run #11 五个附件的字节数与 run #10 完全相同（arm64 17,909,554 / arm32 15,263,372 / x86_64 19,335,481 / 通用包 51,432,169 / 校验和 357），但 `updated_at` 刷到 08:10:19–20，且 **asset id 全换了**（arm64 `712511360`→`712600392`、`apk-sha256.txt` `712511369`→`712600397`）。危险不在旧 id 下载报错（实测对着 run #10 的 id 一路续到 15,251,947 都没失败），在**错配** —— 旧 id 给的是上一轮的字节，和本轮清单天生对不上，会伪装成「哈希被人改了」；核对前重新取一次 `releases/tags/dev-build`，让 id 与清单同属一轮。
  - ✅ **字节级完整性核对（把上一轮没做成的口子填上）**：run #11 的 arm64 包整份下回来，`sha256sum` = `357d9e82c16bf069ff24ba6d49190a4b1f7c79f3cf682348fa7c831eb6bbe14d`，与**同一轮** `apk-sha256.txt` 第一行逐字相同，`wc -c` = 17,909,554，头尾是合法 ZIP（magic `504b0304` / EOCD `504b0506`）。通道只能是 `api.github.com/repos/mjkyleo/timenote/releases/assets/{id}` + `Accept: application/octet-stream` + `curl -sL -C -`，130 秒一轮跑了 **8 轮**才凑满（4,297,408 → 4,635,979 → 5,995,851 → 7,552,331 → 13,491,520 → 13,988,569 → 16,036,569 → 17,909,554）。判读规则：**先看 `wc -c` 够不够，再看哈希** —— 第 5 轮差 4.4 MB 时哈希是 `7593332f…`，那是本地截断不是云端被换；同一条直链 `releases/download/...` 停在 3,134,272 而 `-w` 仍报 HTTP=200，状态码证明不了拿全。清单形式另核过：357 字节 / 4 行 / 每行 `^[0-9a-f]{64}␣␣\S+$` / 文件名集合 == 该轮 4 个 APK。
- [x] `gradle-wrapper.jar` 这条**已收口，走的是「不提交 jar、删掉 CI 下载步骤」**。理由是从 Flutter 工具源码读出来的，不是猜的：
  - `flutter_cache.dart:539` → `GradleWrapper(Cache cache) : super('gradle_wrapper', cache, DevelopmentArtifact.universal)` —— wrapper 属于 **universal** 产物集，任何跑过命令的 Flutter 安装（含 CI runner）都在 `bin/cache/artifacts/gradle_wrapper/` 里有它，不存在「CI 缓存里没这个 artifact」的失败模式。
  - `gradle_utils.dart:237-239` `getExecutable()` 每次构建 Android 前都会调 `injectGradleWrapperIfNeeded(androidDir)`，把 jar + `gradlew`/`gradlew.bat` 一起拷进 `android/`。
  - `gradle_utils.dart:261-264` 的 `shouldCopyFile` 是 `!destinationFile.existsSync()` —— **已存在的文件绝不覆盖**，所以工程里那份 `gradle-wrapper.properties`（钉死的 Gradle 版本）不会被工具的版本顶掉。
  - 顺带量过本机那份注入产物和 SDK 里的是**同一个文件**：`sha256 = 16caeaf66d57a0d1d2087fef6a97efa62de8da69afa5b908f40db35afc4342da`（`android/gradle/wrapper/gradle-wrapper.jar` 与 `D:\dev\flutter\bin\cache\artifacts\gradle_wrapper\gradle\wrapper\gradle-wrapper.jar` 相同，53,636 字节）。
  - `.github/workflows/build-apk.yml` 里的「恢复 gradle wrapper jar」步骤**已删** —— 少一个 `raw.githubusercontent.com` 的隐性依赖。jar 依旧由 `android/.gitignore:1` 挡在版本库外（`gradlew`/`gradlew.bat` 同理在第 4-5 行），**这就是设计如此，不是待修**。
  - ⚠️ 如果哪天想把 jar 也纳库（为了脱离 Flutter 直接 `./gradlew`）：得先删 `android/.gitignore:1`，而且必须连 `gradlew`/`gradlew.bat` 一起提交，否则 `getExecutable()` 仍要注入脚本，单独提交 jar 省不掉缓存依赖。
  - ✅ **这条不是纸上推理，本机做过等价实验**：把 `android/gradlew`、`android/gradlew.bat`、`android/gradle/wrapper/gradle-wrapper.jar`、`android/local.properties` 四个（= CI 干净检出后实际缺的那四个，`git ls-files android` 里只有 `gradle-wrapper.properties` 入库）移走，`android/` 就和 runner 上的工作树一致；跑 CI 用的同一条命令 `flutter build apk --release --split-per-abi` → `Running Gradle task 'assembleRelease'... 23.9s`，`EXIT=0`，三个 APK 照常出，四个文件全部被重新注入。注入前后 jar 的 `sha256` 相同（`16caeaf…42da`），产物字节数也与移走前完全一致（17,852,071 / 15,238,657 / 19,343,534）。
- [x] 第四轮改动（CI 修复 + 文档同步，**已提交并推送**）：提交 `e628133`「ci: 修掉 run #9 那句把红叉挂上发布步骤的纯打印自检」，`4 files changed, 62 insertions(+), 14 deletions(-)`（`.github/workflows/build-apk.yml` 21/4、`HANDOFF-OHOS.md` 17/7、`README.md` 9/3、`REVIEW.md` 15/0）。
  - CRLF 假差异又出现一次：`ios/Runner/GeneratedPluginRegistrant.{h,m}` 在 `git add` 前用 `git checkout -- ios` 还原（依据 `git diff --ignore-cr-at-eol --stat -- ios` 只吐 warning、零行 stat），暂存后 `git status --short | grep -vE "^[MA]  "` 为空，`git diff --cached --name-only | wc -l` = 4。
  - 作者与推送：`git -c user.name=Ky -c user.email=125885091+mjkyleo@users.noreply.github.com commit` → `git log -1` 交出 `Ky <125885091+mjkyleo@users.noreply.github.com>`（没触发 GH007）；SSH 443 推 → `cdceae9..e628133 main -> main`；`git ls-remote` 的 `refs/heads/main` = `e6281336fcc0876f0ab5c9a42651d5a4e290590d` = 本地 `git rev-parse main`。
  - ⚠️ 推送后要盯的轮询坑：`api.github.com` 连打 4 次就吃 403（二级限流，`/rate_limit` 当时还剩 47/60，说明不是配额而是频率），改成 45 秒一轮 + 落盘再 `node` 解析才稳定。
- [x] 第五轮改动（字段名修复 + run #10 记录，**已提交并推送**）：提交 `94ddb91`「ci: 自检改回真实字段名 isPrerelease，并记录 run #10 实测」，`4 files changed, 57 insertions(+), 15 deletions(-)`（逐文件 +/−：workflow 5/4、HANDOFF 15/4、README 15/5、REVIEW 22/2）。作者 noreply（`git log -1 --pretty='%h %ae %an'` 交出 `94ddb91 Ky <125885091+mjkyleo@users.noreply.github.com>`），SSH 443 推 `e628133..94ddb91`，远端 ref = `94ddb913d081e1f95bb9eefbf8a266dfe42951ad` = 本地 `git rev-parse main`；暂存前照例 `git checkout -- ios` 清掉那 2 个 CRLF 假差异，暂存后 `git status --short | grep -vE "^[MA]  "` 为空。
- [x] 第八轮（手动检查更新 R21）+ 第九轮（首个正式版 v1.0.0），**已提交并推送**：`947ecaf`「feat: 设置页手动「检查更新」+ 推 v* 标签发正式版 Release」（9 文件 `569/13`，作者 noreply 邮箱，SSH 443 推 `2c6d5f4..947ecaf`）与 `52e4bf3`（文档）。注解标签 `v1.0.0`（tag 对象 `9b9409f`，tagger 同邮箱）单独推送 `refs/tags/v1.0.0`，触发的 run #15 只跑 `release` 作业。取证细节见 REVIEW §十四 / §十五。
  - ⚠️ **CRLF 假差异这次没还原、改成明确不入库**：`ios/Runner/GeneratedPluginRegistrant.{h,m}` 依旧 `git diff` 零 hunk，这次没跑 `git checkout -- ios`，所以它们仍留在工作区未暂存（`git status` 会一直显示 2 个 `M`）。下次提交前照例要么还原要么确认不带。
  - ⚠️ **发版说明不要写在 workflow 里**：`run: |` 是块标量，缩进由第一行非空内容决定，正文里冒出列 0 的行会直接把 YAML 截断（实测 `yaml.safe_load` 报 `could not find expected ':'`）。现在正文放仓库根 `RELEASE-NOTES.md`，CI 只做 `cat`。
  - 本机取证工具：这台机器没有 `gh`、没有 `python`（只有 `py` 启动器 + PyYAML），`py` 里写 `/tmp` 会按 Windows 路径解析而 `FileNotFoundError`。校验三连：`py` 解析 YAML → 取出 `run` 脚本落盘 → `bash -n`。

- [x] 第十轮（文档校准，2026-11-05 23:20–23:5x）：用户说「这次改动比较大，说明文档好像有点落后了」，于是把文档里每条数字对着当前代码/当前产物重测一遍。**鸿蒙两条链在 `52e4bf3` 各复跑一次**：release 264.5 s / 23,093,027 B、debug 71.9 s / 125,984,972 B，两次 `EXIT=0`；Android 五个包同时重出（arm64 18,245,379 / v7a 15,648,349 / x86_64 19,736,842 / fat 52,538,042 / debug 183,056,489）。逐项对账与增量拆解见 REVIEW §十六。
  - ✅ **补验了第九轮那句没跑过的 `--dart-define=BUILD_SHA`**：release 解包 `grep -ac <40位SHA> libs/arm64-v8a/libapp.so` = 1、debug 对 `kernel_blob.bin` 同样 = 1，鸿蒙包确认带构建号（装不上真机，所以「App 里能用」仍只是理论）。
  - ⚠️ **两条链的产物会同名互盖**：`ohos/entry/build/default/outputs/default/entry-default-unsigned.hap` 是 debug 与 release 共用的输出路径，本轮 debug 后跑，release 那份 23 MB 被就地覆盖 —— 以前文档写的「release 不复制到 `build/ohos/hap/`，两处各留一份」并不成立，现在 §0 改成「要同时留两份就在 release 跑完先改名」。
  - 本轮改动仍只有文档（`README.md` / `REVIEW.md` / `HANDOFF-OHOS.md`），`flutter analyze` = `No issues found!`（79.7 s）、全量 `flutter test` = `+202: All tests passed!`；`pubspec.yaml` 的 `assets:` 只声明 `quotes.json` + `alert.wav`，所以文档确实不进编译输入。
  - ✅ 推 main 之后 run #16（id `42059504934`）`android` 作业每步 `success`、annotations 只剩 GitHub 的 2 条 boilerplate；`dev-build-sha.txt` 变成 `d4c8d66…`（== 本地 main），四个 APK 字节数与 run #14 逐个相同而 sha256 全不同 —— 又一次印证 debug keystore 每轮现生成，见 REVIEW §16.6。

- [x] 第十一轮（run #17 残缺 + 文档行号对账，2026-11-06）：用户只发了一张 Actions 截图（`android` 红、第 10 步 `更新公开预发布 dev-build` 10 秒失败、`HTTP 500 .../releases/assets/713954948`）。免登录 API 取证确认这次和 run #9 相反 —— **附件真的少了**：`dev-build` 只剩 4 个，`app-arm64-v8a-release.apk`（平板优先装那个）与 `app-x86_64-release.apk` 已被 `--clobber` 删掉又没传回来，幸存者的 `updated_at` 还停在 run #16 的 15:59，而正文首行已写 `2552bad`。机制与新 CI 逻辑见 REVIEW §十七 / 坑 L。
  - CI 改动：`.github/workflows/build-apk.yml:105-142`（单条上传 → 最多 3 轮「上传 + 点名核对 6 个附件」）。本机验证三连：PyYAML `safe_load` 通过 → 抽出 `run` 落盘 `bash -n` 通过 → 桩 `gh` 跑四种情形，其中「第 1 轮只报 4 个件」精确复刻 run #17 并在第 2 轮恢复。
  - ✅ **残缺已恢复（`b771a10` 推上去，run #18 id `42153387930` `conclusion=success`）**：本机没有 `gh`、没有可调 Actions 的 token，所以 `Rerun failed jobs` 这条路走不通，恢复只能靠再推一次 main —— 已按这个执行。`android` 作业无一步非 success（`ios`/`release` 按设计 skipped），annotations 只剩 GitHub 自己那 2 条 boilerplate；`dev-build` 回到 6 个附件，`updated_at` 全在 `03:00:49–03:00:51` 同一轮，`apk-sha256.txt` 四行与 API 每个 asset 的 `digest` 逐字相同，`dev-build-sha.txt` == `b771a10749447c0ba356ed0965658307cee017cc`（本地与远端 main 一致），正文首行也写「对应提交：`b771a10`」= 说明文字与附件重新同源。⚠️ 分不清是第 1 轮就过还是重试后过（日志正文要 admin，实测 403），能确认的只有「6 件齐全 + 没有 `::error::`」。
  - 文档行号逐条对账（第十轮只校了数字，这轮校 `path:NNN`）：改掉 10 处失效引用 —— `clock_view.dart:253→319`、`flip_renderer.dart:37→flip_card_widget.dart:359`（`_FlipTransform` 这个类已不存在）、`:177→1451`、`:14→19`、`:56→164`、`:40→148`、`:399→1424`、`flip_card_widget.dart:149/223/272/205→172/245/283/228`、`settings_page.dart:47/51/183/52/144→51/55/244/55/143`、`build-apk.yml:48-53/65/106→55-58/70/119-124`、`clock_view.dart:154→169`。另外「卡片标签 `Flexible` + 省略号」早已不在 `settings_page.dart`，现址 `style_picker.dart:52`。
  - 核对后**没改**的：`clock_providers.dart:78/96/97`、`app_providers.dart:139`、`enum_def.dart:13`、`style_picker.dart:217`、`flip_card_widget.dart:155`、`clock_view.dart:100/106/326/357/363/370`、`egg_display.dart:33/61`、`settings_page.dart:177-186/349-440/383-393`、`main.dart:15`、`build_hap.sh:31`、SDK 侧 `dialog.dart:268`、`gradle_utils.dart:237-239/261-264`、`flutter_cache.dart:539`。带轮次标签的历史引用（`git show 7abb6fd:...`、`app_widget_test.dart:384` 那个已删的 `.first`、`egg_display.dart:23` 的旧公式）保持原样，改了就是造假。

- [x] 第十二轮（R4 开始页 + 发布 v1.2.0，2026-11-06）：用户原话「不要强制横屏，可以设置一个开始按钮，点击后（设置了可选横屏还是竖屏，默认横屏），然后开始，记得根据改动大小升级版本」→ 做的是两档（横/竖），R4 原清单的「自动」档没落地。代码与测试见 REVIEW §十九；这一条记发布链与产物复验。
  - 流程：`main`（`216f7e9`）开 `feat/start-screen-orientation` → 提交 `5c2722c`（19 文件 `514/39`，作者与 committer 都是 noreply）→ 推分支 → `git checkout main && git merge --ff-only`（`Updating 216f7e9..5c2722c`，无合并提交）→ 推 main → 推注解标签 `v1.2.0`（tag 对象 `222cfd9`，tagger 同邮箱）→ 远端 + 本地删分支。推送一律 `GIT_SSH_COMMAND='ssh -i ~/.ssh/git_ssh_key -o IdentitiesOnly=yes -p 443' git push ssh://git@ssh.github.com:443/mjkyleo/timenote.git <ref>`，`origin` 没动。
  - `ios/Runner/GeneratedPluginRegistrant.{h,m}` 这次**没有** `git checkout --` 还原，而是留在工作树里不进 add（依据同样是 `git diff --ignore-cr-at-eol --stat -- ios` 空）；`git diff --cached --stat` 落在 19 行，与计划一致。
  - `git ls-remote` 对账：`refs/heads/main` = `5c2722c…`、`refs/tags/v1.2.0^{}` = `5c2722c…`、`refs/heads/feat/*` 已空；本地 `refs/remotes/origin/{main,feat/...}` 用 `git update-ref` 手工对齐（推送走的是显式 URL，不会自动更新跟踪引用）。
  - 云端：run #22（推 main，`android` 13 步 success）+ run #23（推标签，`release` 12 步 success）；Release `v1.2.0` id `436167598`、`prerelease=false`、5 个附件、`published_at=06:15:37`；`dev-build` 6 附件、`dev-build-sha.txt` == 本地 HEAD。逐条见 REVIEW §二十 / README「第五轮真实验证」。
  - 本机产物在提交之后重出（`--dart-define=BUILD_SHA` 才拿得到当轮 commit）：APK 四个 + release HAP 23,191,729 B，包内 `module.json` = `auto_rotation`、`pack.info.deviceType` = `["phone","tablet"]`、`libapp.so` 里 SHA 命中 1 次。

- [x] 当前工作树（2026-11-05 第三轮改动，**已提交并推送**）：提交 `cdceae9`「feat: 翻页动画重做（8 种·绕中缝铰链）+ 沉浸式待机，鸿蒙工程入库」，`59 files changed, 2188 insertions(+), 275 deletions(-)`。
  - 提交前实测：`git status --short` = 17 `M` + 9 `??`；`ios/Runner/GeneratedPluginRegistrant.{h,m}` 这 2 个 CRLF 假差异在 `git add` 前用 `git checkout -- ios` 还原（依据：`git diff --stat --ignore-cr-at-eol -- ios` 零行 stat，只吐 warning），所以最终提交是 **15 个 M + 44 个新文件 = 59**，与 `git diff --cached --name-only | wc -l` 一致；暂存后 `git status --short | grep -vE "^[MA]  "` 为空，确认没漏也没多。
  - 入库前扫过密钥：对**将要 add 的 44 个文件**（不是整个目录，`ohos/entry/build/**` 的缓存不在内）`grep -niE "password|secret|token|BEGIN (RSA|OPENSSH)|api[_-]?key"`，只有 `assets/icon/*.png` 因二进制字节撞词命中，`ohos/build-profile.json5` 是 `"signingConfigs": []` 空数组，无凭据。⚠️ `tool/ohos_env.sh` 里有本机路径（含 Windows 用户名 `86132` 与盘符），是设计如此（当作「仓库内正本」），不是泄露。
  - 作者与推送（都按上面的约定实测过）：`git -c user.name=Ky -c user.email=125885091+mjkyleo@users.noreply.github.com commit` → `git log -1` 交出 `Ky <125885091+mjkyleo@users.noreply.github.com>`（qq 邮箱会被 GH007 拒，这次没触发）；`GIT_SSH_COMMAND='ssh -i ~/.ssh/git_ssh_key -o IdentitiesOnly=yes -p 443' git push ssh://git@ssh.github.com:443/mjkyleo/timenote.git main:main` → `bd05071..cdceae9`；`git ls-remote` 的 `refs/heads/main` = `cdceae9951a3d1b600ac0951e4223caa0674d1ba` = 本地 `git rev-parse main`。
  - 逐文件 +/− 不再抄录（`git show --stat cdceae9` 即得）：渲染层 `flip_renderer.dart` 342/71、`flip_card_widget.dart` 186/11、`clock_view.dart` 43/32、`settings_page.dart` 69/63、测试 197/49 与 157/10，CI 那步删 16 行。
  - 提交前基线（已实测）：`flutter analyze` → `No issues found! (ran in 9.6s)`，`flutter test` → `00:21 +86: All tests passed!`。
  - ⚠️ **提交时必须逐次覆盖邮箱**：`git config --local user.email` 实测为空，`--global` 是 `437257976@qq.com`，而 GitHub 那边开了邮箱隐私保护（qq 邮箱会被 GH007 拒）。`bd05071`/`29a03e9`/`b187ee8` 三个提交的作者都是 `125885091+mjkyleo@users.noreply.github.com / Ky`，是靠命令行 `-c` 覆盖做到的，不是仓库配置。所以提交用
    `git -c user.name=Ky -c user.email=125885091+mjkyleo@users.noreply.github.com commit ...`
    推用 SSH 443（HTTPS 443 常被重置，`origin` 本身是 HTTPS，所以要写全 URL）：
    `GIT_SSH_COMMAND='ssh -i ~/.ssh/git_ssh_key -o IdentitiesOnly=yes -p 443' git push ssh://git@ssh.github.com:443/mjkyleo/timenote.git main:main`
    （`~/.ssh/git_ssh_key` 是 GitHub 认得的那把，`id_ed25519`/`id_rsa` 都不被接受）。推完 `git log -1 --pretty=%ae` + `git ls-remote origin main` 双向自检。**不要改 git config**。

## 6.5 Android 安装包（本机产物，给用户测试用）

| 项 | 实测值 |
| --- | --- |
| 构建命令 | `D:\dev\flutter\bin\flutter.bat build apk --debug` / `--release`（标准 SDK，3.47.8） |
| 产物目录 | `build/app/outputs/flutter-apk/`（每个 apk 旁边都有 `.sha1`） |
| 公开分发 | **当前状态（2026-11-05 第八轮，run #14 + run #15，head `947ecaf`）**：`dev-build` 已是 **6 个附件**（新增 `dev-build-sha.txt`，41 字节 = 那一轮 `$GITHUB_SHA`，实测 == 本地 `git rev-parse HEAD`），并且多了一条**正式版通道**：推 `v*` 标签由 `release` 作业单独构建，`v1.0.0` 已发布（`prerelease=false`、`draft=false`、`/releases/latest` 返回它，5 附件；arm64 18,237,326）。两个作业用 `if` 互斥，标签推送不会覆盖 `dev-build`（实测 #14 skip `release`、#15 skip `android`）。**同一提交两轮构建：字节数完全相同、sha256 全不同**（#14 arm64 `69145927…` vs #15 `855a0688…`），所以跨版本覆盖安装会被签名拒（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`），发布说明已写「先卸载再装」；同轮互证可以只看 API 在 asset 上给的 `digest` 与 `apk-sha256.txt` 是否逐字相同，不必下载 100MB。以下保留 run #11 那次的原始取证 —— **已真实验证（run #11，`94ddb91`）**：`dev-build` 由 CI 更新，**5 个附件全在** —— `app-arm64-v8a-release.apk` 17,909,554 / `app-armeabi-v7a-release.apk` 15,263,372 / `app-x86_64-release.apk` 19,335,481 / `app-release.apk` 51,432,169 / `apk-sha256.txt` 357 字节（4 行，通用包已在内，run #9 那份是 275 字节 3 行）。run #11 的 android job 13 步全 `success`，「更新公开预发布 dev-build」6 秒过，annotations 只剩 GitHub 自己的 2 条 boilerplate。清单形式核过：4 行、每行 `^[0-9a-f]{64}␣␣文件名$`、文件名集合 == 该轮 4 个 APK。✅ **字节级核对做完了**：run #11 的 arm64 包整份下回来 `sha256sum` = `357d9e82c16bf069ff24ba6d49190a4b1f7c79f3cf682348fa7c831eb6bbe14d`，与**同一轮**清单第一行逐字相同，`wc -c` = 17,909,554，头尾是合法 ZIP（`504b0304` / EOCD `504b0506`）。通道：`api.github.com/repos/mjkyleo/timenote/releases/assets/{id}` + `Accept: application/octet-stream` + `curl -sL -C -`，实测 **8 轮**才凑满（4,297,408 → 4,635,979 → 5,995,851 → 7,552,331 → 13,491,520 → 13,988,569 → 16,036,569 → 17,909,554，单轮 130 秒上限）。⚠️ 判读规则：第 5 轮差 4.4 MB 时 `sha256sum` 是 `7593332f…`，与清单不同 —— 那是**本地截断**不是云端被换；`releases/download/...` 直链同理会停在 3,134,272 而 `-w` 仍报 HTTP=200。**先看大小再看哈希**。⚠️ **每次 run 的 sha256 都不同**（run #10 的 arm64 是 `9e03d469cb66…`，run #11 是 `357d9e82c16b…`，字节数却一模一样）：Runner 每轮现生成 `~/.android/debug.keystore`，签名块变长不变 —— sha256 只能核「同一轮附件 == 同一轮清单」，不能当版本标识；本机 arm64 是 17,917,607，也别拿本机哈希去对云端。判断装了哪次提交看 `dev-build` 正文首行的「最新提交：`xxxxxxx`」（实测 run #10=`e628133`、run #11=`94ddb91`）。⚠️ 且 `gh release upload --clobber` 是删了重建，asset id 每轮换（arm64 `712511360`→`712600392`）。⚠️ 但**旧 id 不会下载失败**（实测对着 run #10 的 id 一路续到 15,251,947 都没报错），真正的危险是**错配**：旧 id 的字节 == 上一轮的产物，拿这轮的清单去核必然「哈希不符」，会误判成发布被人动过。核对前重新取一次 `releases/tags/dev-build`，让 id 与清单同属一轮。 |
| 签名 | Release 用 debug keystore，能装能自用，不能上 Google Play |

本次重建（2026-11-05 11:10–11:12，已含 §6.6 的弹窗修复）实测大小：

| APK | 字节 |
| --- | --- |
| `app-arm64-v8a-release.apk` | 17,852,071 |
| `app-armeabi-v7a-release.apk` | 15,238,657 |
| `app-x86_64-release.apk` | 19,343,534 |
| `app-release.apk`（fat，全 ABI） | 51,341,918 |
| `app-debug.apk` | 182,965,108 |

**本机出 Android 包的两个环境前置**（都是本机 `~/.gradle` 改动，仓库里没有；换机器要照做，否则见坑 I / 坑 J）：
- `C:\Users\86132\.gradle\init.d\cn-mirror.gradle` —— 把 Maven Central / Plugin Portal 两个 URL 原地换成阿里云镜像。
- `C:\Users\86132\.gradle\gradle.properties` —— `kotlin.incremental=false`（此前该文件不存在，本次新建）。

## 6.6 Android 真机（AVD）冒烟 + 本轮修掉的键盘压瘪弹窗

设备：AVD `trace_pixel7`，density 420，App 锁横屏 → 逻辑视口 914x411。装了 `app-debug.apk` 逐屏截图点验，**已通过**的项：
启动 / 走时 / 倒计时开始·暂停·停止 / 设置页 / **11 套风格切一套真的换掉整屏底色与底板**（截了切换前后两张）/ 待办抽屉 / 翻页动画 / 彩蛋（倒计时归零先上文案，停留 ≈5 s）/ 提示音（`dumpsys audio` 见 AudioTrack 播放）/ 屏幕常亮（wakelock 生效）。

**修掉的真机缺陷（模拟器截图里抓出来的，widget 测试原先测不到）**：
自定义倒计时弹窗在横屏 + 软键盘下，输入框整块不可见。根因是 `AlertDialog` 的外边距 = `viewInsets` + `insetPadding` 之和
（`D:\dev\flutter\packages\flutter\lib\src\material\dialog.dart:268`）—— 横屏键盘一弹，content 的 `Column` 拿到 `h<=3.0`，抛
`A RenderFlex overflowed by 177 pixels on the bottom.`。
`lib/flip_clock/clock_view.dart` 的 `_CustomCountdownDialogState.build` 三处一起改才留得住输入区：
`scrollable: true` + `contentPadding: fromLTRB(24,8,24,8)` + `actionsPadding: fromLTRB(24,0,24,12)`，并把 `TextField.autofocus` 关掉
（一抢焦点就弹键盘，弹窗立刻塌；15/30/45/60 快捷键本来不需要键盘）。只加 `scrollable` 在测试里能过、**真机没修好**，这是实测出来的差别。

反向验证（确认新测试能钉住原 bug，不是恒真）：临时把三处改回原样 → 两条新测试分别红（`RenderFlex overflowed` / 输入框高度塌成 0），恢复修改 → 64 例全绿。新增测试在 `test/app_widget_test.dart`：
- 「手机横屏 自定义弹窗完整可见，且不会一打开就弹键盘」—— 2400x1080@2.625，断言 `TextField`/`60`/`开始` 三块矩形不越屏 + `tester.testTextInput.isVisible` 为 false。
- 「键盘已弹出时自定义弹窗不塌成 0 高」—— `FakeViewPadding(bottom: 570)`，断言无异常、`TextField` 高度 > 0 且落在键盘上方。

另外两条实测发现（不是 bug，记下来别再困惑）：
- **Android 窗口没被 `adjustResize`**：`dumpsys window com.timenote.timenote` 显示 `frame=[0,0][2400,1080]`（全尺寸），键盘是覆盖层，Flutter 侧靠 `viewInsets` 而不是视口缩小 —— 所以坑就是 `viewInsets` 直接加进外边距。
- **split-per-abi 会给每个 ABI 分配不同 versionCode**：设备上是 arm64（4001），再装纯 `--target-platform android-x64` 的包（versionCode 1）报 `INSTALL_FAILED_VERSION_DOWNGRADE`，`-d` 参数没用，要 `adb uninstall com.timenote.timenote` 后重装。

## 6.7 待机屏沉浸式（本轮新增，模拟器已实机验证）

冒烟时从截图里看到的第二个真机问题：**状态栏一直在**（`i02_countdown_started.png` 左上角 `3:05`、右上角 `LTE` + 电量，底部还有手势条），而这是个 Fliqlo 式待机翻页时钟，状态栏直接破坏整屏观感。

改法只有一行，当时写在 `lib/main.dart:15` 的锁横屏之后（第十二轮（R4）起这两句都搬进了 `lib/flip_clock/clock_view.dart` 的 `initState`：排向在 `:46`，沉浸是 `:50`）：

```dart
await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
```

**为什么这一行在鸿蒙上不是空调用**（读的是 har 里的真实实现，不是猜）：`ohos/oh_modules/.ohpm/@ohos+flutter_ohos@…/src/main/ets/plugin/PlatformPlugin.ets:427-465` 的 `setSystemChromeEnabledSystemUIMode(mode)` 对 `IMMERSIVE_STICKY` 有显式分支 —— `setUseFullScreen(true)` + `showBarOrNavigation = []` → `mainWindow.setWindowSystemBarEnable([])`，并把 `flutterView.setPaddingTop(0)`。

模拟器实测（`k01`–`k11` 一串截图）：
- 状态栏与手势条消失，数字占满整屏（`k03_after_gotit.png`）。
- Android 首次进入会弹系统提示「Viewing full screen / To exit, swipe down from the top of your screen」，点掉之后不再出现（`k01`/`k02` 抓到）。
- 应用自己的 chrome（齿轮 + 菜单）仍按 6 s 自动隐藏，**点屏幕任意处重新唤出**（`Listener.onPointerDown → _pokeChrome`，`clock_view.dart:206`），唤出后齿轮位置随 `SafeArea` 上移到真正的顶边（`k04`）。
- 设置页在沉浸式下正常打开、布局无异常（`k06`）；返回键仍能把路由弹回主屏（`k07`）。
- 自定义倒计时弹窗端到端复测：打开时不弹键盘（`k09`）→ 点输入框弹键盘，弹窗滚动后输入框与「取消/开始」都可见（`k10`，`scrollable: true` 起作用，15/30/45/60 需要滚一下才看到）→ 输入 `25` 点「开始」真的起表（`k11`，`00:24:58`）。

坐标标定补一条（修正坑 K 的用法）：`adb shell input tap` 的坐标空间**就是 `screencap` 出来的那张 2400x1080**，别拿预览图（约 2000x900）的读数直接填 —— 本轮按预览读数连点两次 `自定义` 都落在数字区（y=790 vs 实际 y=960）。用 PIL 按行扫亮像素定位控件比肉眼估可靠。

未验证：鸿蒙真机的沉浸式（未签名装不上）；iOS 侧 `immersiveSticky` 的行为（本机无模拟器/真机跑过 iOS）。


## 7. 提交/推送约定（沿用既有授权语境）

- 对外动作（commit/push/发布）**先提议**，拿到一句授权后一次跑完并自检邮箱与远端 ref。
- 必须用 GitHub 的 **noreply 邮箱**（mjkyleo 开了邮箱隐私保护，qq 邮箱会被 GH007 拒）；仓库级已配好。
- 推送走 **ssh.github.com:443**（HTTPS 443 常被重置），用 `git_ssh_key`；别把网络问题误判成权限问题。
- **绝不修改 git config**，只用 `git -c` 逐次覆盖。

## 8. 开机 60 秒自检

```bash
cd /d/Phase3/Projects/timenote
ls -la ohos/entry/build/default/outputs/default/         # 当前是 5c2722c 的 release = 23,191,729 B（14:17 产物；同名覆盖，见 §0）
ls -la build/ohos/hap/                                   # 与上面同一份（md5 7ee78c2a…）；只有带 --no-codesign 的那次才会写到这里
md5sum /e/command-line-tools/ohpm/bin/ohpm.bat           # 应为 3481f1c9ec50a2e05fa4ad42ca6b8dc6（探针已还原）
ls /e/command-line-tools/ohpm/bin/                       # 只该有 init init.bat ohpm ohpm.bat pm-cli.js，无 probe/real
tool/build_hap.sh 2>&1 | tail -4                         # 应 √ Built build\ohos\hap\entry-default-unsigned.hap.
ls -la build/app/outputs/flutter-apk/                    # arm64 18,376,683 / v7a 15,763,273 / x86_64 19,802,610 / fat 52,849,574（`5c2722c` 本机 14:13–14:20 重出）+ debug 183,056,489（`52e4bf3`，本轮没重跑）
```

**别再用 `flutter build hap`（bash 启动器）验证递归** —— 那条路必然复现 `Recursion Count=234`，是 `OS` 污染，不是回归。
Android 侧自检：`/d/dev/flutter/bin/flutter.bat analyze`（No issues found）+ `/d/dev/flutter/bin/flutter.bat test`（第十二轮起 **214 例**；64 例是 2026-11-05 上午那一版）。

