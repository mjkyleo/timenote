import 'dart:io';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:timenote/core/storage_service.dart';

/// widget 测试用 Hive 内存后端，不碰磁盘。
///
/// 磁盘后端在 `testWidgets` 的 fake-async 区里不可用：写请求的真实 IO 完成回调
/// 会被投递到测试结束后已销毁的 zone，于是 keystore 事务悬空、后续 `Hive.close()`
/// 永远等不到，整个测试进程挂死（实测超时 6 分钟以上）。内存后端的
/// writeFrames / close 都只返回 `Future.value()`，续体在下一次 pump 就冲完。
///
/// 先按名字开箱，[StorageService.init] 里的 `openBox` 会直接复用这些已开的箱。
/// 真正的落盘回归见 `test/storage_service_test.dart`（普通 test，跑在真实 zone）。
Future<void> useMemoryStorage() async {
  await Hive.openBox(StorageService.boxSetting, bytes: Uint8List(0));
  await Hive.openBox(StorageService.boxTodo, bytes: Uint8List(0));
  await StorageService.init(hivePath: Directory.systemTemp.path);
}

/// 关闭全部 box，让下一个用例从空箱重新开始
Future<void> releaseMemoryStorage() => Hive.close();
