import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// 记录每次 toggle 的平台实现，替换掉需要 method channel 的真插件。
class FakeWakelock extends WakelockPlusPlatformInterface {
  final List<bool> toggles = [];

  bool _enabled = false;

  @override
  Future<void> toggle({required bool enable}) async {
    toggles.add(enable);
    _enabled = enable;
  }

  @override
  Future<bool> get enabled async => _enabled;
}

FakeWakelock installFakeWakelock() {
  final fake = FakeWakelock();
  wakelockPlusPlatformInstance = fake;
  return fake;
}
