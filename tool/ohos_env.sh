# 鸿蒙构建环境变量（本机 E:\command-line-tools + Flutter-OH）
# 仓库内的正本；Temp 里那份会被系统清理，改动请改这里。
# 用法（Git Bash）：source tool/ohos_env.sh
export DEVECO_TOOLS_HOME="E:\\command-line-tools"
export DEVECO_SDK_HOME="E:\\command-line-tools\\sdk"
export OHOS_SHIM_HOME="C:\\Users\\86132\\AppData\\Local\\ohos-clt-shim"
# 注意顺序：CLT bin 在 shim 之前 —— cmd 会用 PATHEXT 找到真的 ohpm.bat/hvigorw.bat，
# 而 Dart 的 Process 只认 <name>.exe，才会落到 shim 目录里的 shim。
export PATH="/d/flutter_ohos/bin:/c/Users/86132/.jdks/temurin-17/bin:/e/command-line-tools/bin:/e/command-line-tools/tool/node:$OHOS_SHIM_HOME:/e/command-line-tools/sdk/default/openharmony/toolchains:$PATH"
export GIT_LFS_SKIP_SMUDGE=1
export GIT_CLONE_PROTECTION_ACTIVE=false
# hvigor 要求插件 srcPath 是相对路径；flutter 工具用 path.relative 计算，
# 跨盘符（工程在 D:、pub 缓存在 C:）会退化成绝对路径 → 必须把缓存放同盘。
export PUB_CACHE="D:\\dev\\pub-cache"
