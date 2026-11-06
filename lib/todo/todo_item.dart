import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/todo_providers.dart';
import '../theme/ui_style.dart';
import 'todo_model.dart';

/// 待办单项：勾选 / 删除
class TodoItemWidget extends ConsumerWidget {
  final TodoItem item;

  const TodoItemWidget({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(todoListNotifierProvider.notifier);
    final tokens = UiScope.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: item.isCompleted,
        onChanged: (_) {
          HapticFeedback.lightImpact();
          notifier.toggleTodo(item.id);
        },
      ),
      title: Text(
        item.title,
        style: TextStyle(
          decoration:
              item.isCompleted ? TextDecoration.lineThrough : null,
          // 划线之外再收一档前景，完成态在 11 套皮肤里都读得出来；
          // 硬编码 Colors.grey/Colors.red 在暗风格卡面上会糊掉
          color: item.isCompleted ? tokens.labelInk : tokens.fg,
        ),
      ),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, color: tokens.accentInk),
        tooltip: '删除',
        onPressed: () {
          HapticFeedback.lightImpact();
          final index = ref
              .read(todoListNotifierProvider)
              .indexWhere((e) => e.id == item.id);
          notifier.deleteTodo(item.id);
          // 常见可撤销的动作不弹确认，撤销放在原地（undo-and-redo.md）
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已删除「${item.title}」'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => notifier.restoreTodo(item, index),
            ),
          ));
        },
      ),
    );
  }
}
