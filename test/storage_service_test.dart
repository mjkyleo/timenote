import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/storage_service.dart';
import 'package:timenote/todo/todo_model.dart';

/// 磁盘持久化回归。
///
/// 只在普通 `test()` 里做：这里跑在真实 zone，Hive 的文件 IO 能正常完成。
/// widget 测试改用内存后端（见 support/fake_storage.dart 的注释），
/// 所以「重启后数据还在」这条必须由本文件守住。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('timenote_disk_');
  });

  tearDown(() async {
    await StorageService.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// 必须排在任何 init 之前：box 还没打开时的降级路径
  test('存储不可用时读默认值、写操作静默跳过', () async {
    expect(StorageService.settings, isNull);
    expect(StorageService.getSetting('themeBase', 'dark'), 'dark');
    expect(StorageService.getTodoList(), isEmpty);

    await StorageService.writeSettings({'themeBase': 'light'});
    await StorageService.saveTodoList(const []);
    expect(StorageService.getSetting('themeBase', 'dark'), 'dark');
  });

  test('设置与待办落盘，关箱重开后原样读出', () async {
    final created = DateTime(2026, 11, 4, 10, 30);
    await StorageService.init(hivePath: dir.path);
    await StorageService.writeSettings({
      'clockVisualStyle': 'boldPower',
      'soundEnable': false,
      'animSpeedMs': 420,
    });
    await StorageService.saveTodoList([
      TodoItem(id: 'a', title: '复习线性代数', createAt: created),
      TodoItem(id: 'b', title: '写周报', isCompleted: true, createAt: created),
    ]);
    await StorageService.close();

    expect(File('${dir.path}/${StorageService.boxTodo}.hive').existsSync(), isTrue,
        reason: '待办 box 应该真的写出磁盘文件');

    await StorageService.init(hivePath: dir.path);
    expect(StorageService.getSetting('clockVisualStyle', ''), 'boldPower');
    expect(StorageService.getSetting('soundEnable', true), isFalse);
    expect(StorageService.getSetting('animSpeedMs', 0), 420);

    final list = StorageService.getTodoList();
    expect(list.map((e) => e.title), ['复习线性代数', '写周报']);
    expect(list.first.isCompleted, isFalse);
    expect(list.last.isCompleted, isTrue);
    expect(list.first.createAt, created);

    // 覆盖写：空列表落盘后重开应为空
    await StorageService.saveTodoList(const []);
    await StorageService.close();
    await StorageService.init(hivePath: dir.path);
    expect(StorageService.getTodoList(), isEmpty);
  });

  test('脏数据条目被丢弃，只保留合法条目；类型不符的设置退回默认值', () async {
    await StorageService.init(hivePath: dir.path);
    await StorageService.todos?.put('items', [
      {'id': 'ok', 'title': '合法', 'isCompleted': false, 'createAt': 1},
      {'id': '', 'title': '空 id'},
      {'title': '没有 id'},
      {'id': 'x', 'title': 42},
      {'id': 'y', 'title': '缺 createAt'},
      'not a map',
    ]);
    await StorageService.settings?.put('weird', 5);

    expect(StorageService.getTodoList().map((e) => e.id), ['ok', 'y']);
    expect(StorageService.getTodoList().last.createAt,
        DateTime.fromMillisecondsSinceEpoch(0));
    expect(StorageService.getSetting('weird', '默认'), '默认');
  });
}
