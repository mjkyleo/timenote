import 'package:flutter/services.dart';
import '../settings/enum_def.dart';
import 'constants.dart';

/// 两种显示模式各自要的系统栏与旋转策略。
///
/// App 外壳三页（时间 / 待办 / 设置）跟随系统、系统栏可见；待机屏按用户选的
/// 排向锁死并沉浸。两处都调这两个单向通道，集中一份免得各写各的。
class AppSystemUi {
  const AppSystemUi._();

  /// 不 await：`setPreferredOrientations` 与 `setEnabledSystemUIMode` 是发出即完事
  /// 的单向通道，await 它们在测试的 fake-async 里会挂住，真机也没必要让按钮等回执。
  static void enterApp() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  static void enterStandby(AppOrientation orientation) {
    SystemChrome.setPreferredOrientations(
        AppConstants.orientationsOf(orientation));
    // immersiveSticky：边缘滑动临时唤回系统栏后会自动再隐藏；
    // 鸿蒙侧 flutter_ohos 的 PlatformPlugin 显式实现了这个模式，不是空调用。
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
}
