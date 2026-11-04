import 'package:hive_flutter/hive_flutter.dart';
import '../todo/todo_model.dart';

/// Hive 本地存储封装
///
/// box 未初始化（启动失败/测试未准备）时读接口返回默认值、写接口静默跳过，
/// 让待机时钟降级为「不持久化」而不是白屏崩溃。
class StorageService {
  const StorageService._();

  static const String boxSetting = 'app_settings';
  static const String boxTodo = 'todo_list';

  static Box? _settingBox;
  static Box? _todoBox;

  static Future<void> init({String? hivePath, String boxPrefix = ''}) async {
    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      await Hive.initFlutter();
    }
    _settingBox = await Hive.openBox('$boxPrefix$boxSetting');
    _todoBox = await Hive.openBox('$boxPrefix$boxTodo');
  }

  static Box? get settings => _settingBox;
  static Box? get todos => _todoBox;

  /// 关闭全部 Hive box（主要用于测试隔离）
  static Future<void> close() => Hive.close();

  // ---- 设置读写 ----
  static T getSetting<T>(String key, T defaultValue) {
    final box = _settingBox;
    if (box == null) return defaultValue;
    final value = box.get(key);
    return value is T ? value : defaultValue;
  }

  static Future<void> writeSettings(Map<String, Object> values) async {
    await _settingBox?.putAll(values);
  }

  // ---- 待办读写（存 List<Map>）----
  static List<TodoItem> getTodoList() {
    final raw = _todoBox?.get('items');
    if (raw is! List) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(TodoItem.fromMap)
        .nonNulls
        .toList();
  }

  static Future<void> saveTodoList(List<TodoItem> items) async {
    await _todoBox?.put('items', items.map((e) => e.toMap()).toList());
  }
}
