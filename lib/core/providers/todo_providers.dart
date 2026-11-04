import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage_service.dart';
import '../../todo/todo_model.dart';

final todoListNotifierProvider =
    NotifierProvider<TodoListNotifier, List<TodoItem>>(
  TodoListNotifier.new,
);

class TodoListNotifier extends Notifier<List<TodoItem>> {
  static const int maxTitleLength = 60;

  @override
  List<TodoItem> build() => StorageService.getTodoList();

  Future<void> addTodo(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final capped = trimmed.length > maxTitleLength
        ? trimmed.substring(0, maxTitleLength)
        : trimmed;
    final now = DateTime.now();
    final items = [
      ...state,
      TodoItem(
        id: '${now.microsecondsSinceEpoch}',
        title: capped,
        createAt: now,
      ),
    ];
    // 乐观更新：先刷新 UI，再后台持久化
    state = items;
    await StorageService.saveTodoList(items);
  }

  Future<void> toggleTodo(String id) async {
    final items = [
      for (final item in state)
        if (item.id == id) item.copyWith(isCompleted: !item.isCompleted) else item,
    ];
    state = items;
    await StorageService.saveTodoList(items);
  }

  Future<void> deleteTodo(String id) async {
    final items = state.where((e) => e.id != id).toList();
    state = items;
    await StorageService.saveTodoList(items);
  }

  /// 清掉已完成的条目，未完成项保持原顺序
  Future<void> clearCompleted() async {
    if (!state.any((e) => e.isCompleted)) return;
    final items = state.where((e) => !e.isCompleted).toList();
    state = items;
    await StorageService.saveTodoList(items);
  }
}
