import 'package:hive_flutter/hive_flutter.dart';
import '../todo/todo_model.dart';

/// Hive 本地存储封装
class StorageService {
  static const String _boxSetting = 'app_settings';
  static const String _boxTodo = 'todo_list';

  static Box? _settingBox;
  static Box? _todoBox;

  static Future<void> init({String? hivePath, String boxPrefix = ''}) async {
    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      await Hive.initFlutter();
    }
    _settingBox = await Hive.openBox('$boxPrefix$_boxSetting');
    _todoBox = await Hive.openBox('$boxPrefix$_boxTodo');
  }

  static Box get settings => _settingBox!;
  static Box get todos => _todoBox!;

  /// 关闭全部 Hive box（主要用于测试隔离）
  static Future<void> close() => Hive.close();

  // ---- 设置读写 ----
  static T getSetting<T>(String key, T defaultValue) {
    final box = settings;
    return box.get(key, defaultValue: defaultValue) as T;
  }

  static Future<void> setSetting<T>(String key, T value) async {
    await settings.put(key, value);
  }

  // ---- 待办读写（存 List<Map>）----
  static List<TodoItem> getTodoList() {
    final raw = todos.get('items', defaultValue: <dynamic>[]) as List;
    return raw
        .map((e) => TodoItem.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  static Future<void> saveTodoList(List<TodoItem> items) async {
    await todos.put('items', items.map((e) => e.toMap()).toList());
  }

  static Future<void> clearAll() async {
    await todos.clear();
  }
}
