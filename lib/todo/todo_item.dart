import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/todo_providers.dart';
import 'todo_model.dart';

/// 待办单项：勾选 / 删除
class TodoItemWidget extends ConsumerWidget {
  final TodoItem item;

  const TodoItemWidget({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(todoListNotifierProvider.notifier);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: item.isCompleted,
        onChanged: (_) => notifier.toggleTodo(item.id),
      ),
      title: Text(
        item.title,
        style: TextStyle(
          decoration:
              item.isCompleted ? TextDecoration.lineThrough : null,
          color: item.isCompleted ? Colors.grey : null,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        tooltip: '删除',
        onPressed: () => notifier.deleteTodo(item.id),
      ),
    );
  }
}
