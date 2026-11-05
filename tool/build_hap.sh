#!/bin/sh
# 出鸿蒙包：flutter build hap 的一键脚本（本机）。
#
# 两个必须绕开的坑，详见 HANDOFF-OHOS.md：
#   1. bin/flutter 这个 bash 启动器里有 `OS="$(uname -s)"`，OS 是从 Windows 环境
#      继承来的已导出变量，赋值后会把 MINGW64_NT-... 一路传给 ohpm.bat；
#      ohpm.bat 用 `if "%OS%"=="Windows_NT" setlocal enabledelayedexpansion` 决定
#      要不要开延迟展开，于是 !OHPM_FIRST_PARAM! 变成字面量、
#      :calculateFirstParamLen 无限自我 call → BATCH RECURSION exceeds STACK limits。
#      解法：直接调同目录的 flutter.bat（纯批处理启动器），不经过 bash 启动器。
#   2. audioplayers 的鸿蒙适配版用了 TargetPlatform.ohos，标准 SDK 编不过，
#      所以覆盖只在这条链路上注入 pubspec_overrides.yaml（已 gitignore）。
set -e
cd "$(dirname "$0")/.."

. tool/ohos_env.sh

FLUTTER_BAT="$(dirname "$(command -v flutter)")/flutter.bat"
if [ ! -f "$FLUTTER_BAT" ]; then
  echo "tool/build_hap.sh: 找不到 $FLUTTER_BAT（先 source tool/ohos_env.sh 或把 Flutter-OH 放进 PATH）" >&2
  exit 1
fi

cp tool/pubspec_overrides.ohos.yaml pubspec_overrides.yaml
trap 'rm -f pubspec_overrides.yaml' EXIT

args="${*:---debug --no-codesign}"
echo "== $FLUTTER_BAT build hap $args"
# 签名需要 DevEco/AGC 下发的调试证书，命令行拿不到；--no-codesign 出未签名包，
# 装到真机前要在 DevEco Studio 里配 signing configs（见 HANDOFF-OHOS.md §5）。
cmd //c "$(cygpath -w "$FLUTTER_BAT")" build hap $args
