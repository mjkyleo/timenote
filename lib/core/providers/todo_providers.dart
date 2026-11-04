import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage_service.dart';
import '../../todo/todo_model.dart';

final todoListNotifierProvider =
    NotifierProvider<TodoListNotifier, List<TodoItem>>(
  TodoListNotifier.new,
);

class TodoListNotifier extends Notifier<List<TodoItem>> {
  @override
  List<TodoItem> build() {
    return StorageService.getTodoList();
  }

  Future<void> addTodo(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final items = [...state];
    items.add(TodoItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: trimmed,
      createAt: DateTime.now(),
    ));
    // 乐观更新：先刷新 UI，再后台持久化
    state = items;
    await StorageService.saveTodoList(items);
  }

  Future<void> toggleTodo(String id) async {
    final items = [...state];
    for (final item in items) {
      if (item.id == id) {
        item.isCompleted = !item.isCompleted;
      }
    }
    state = items;
    await StorageService.saveTodoList(items);
  }

  Future<void> deleteTodo(String id) async {
    final items = state.where((e) => e.id != id).toList();
    state = items;
    await StorageService.saveTodoList(items);
  }
}
