import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/app_providers.dart';
import '../core/providers/todo_providers.dart';
import '../settings/enum_def.dart';
import '../theme/ui_style.dart';
import 'todo_item.dart';

/// 右侧滑出待办抽屉
class TodoDrawer extends ConsumerStatefulWidget {
  const TodoDrawer({super.key});

  @override
  ConsumerState<TodoDrawer> createState() => _TodoDrawerState();
}

class _TodoDrawerState extends ConsumerState<TodoDrawer> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _addTodo() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    ref.read(todoListNotifierProvider.notifier).addTodo(t);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(todoListNotifierProvider);
    final notifier = ref.read(todoListNotifierProvider.notifier);
    final doneCount = list.where((e) => e.isCompleted).length;
    final theme = Theme.of(context);
    final themeBase = ref.watch(
        appSettingsNotifierProvider.select((s) => s.themeBase));
    final tokens = UiScope.maybeOf(context) ??
        UiTokens.classic(themeBase == ThemeBase.dark);

    return Drawer(
      width: 360,
      backgroundColor: tokens.surface ?? tokens.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      uiLabelText(tokens, '待办清单'),
                      style: uiLabelStyle(context, tokens, size: 20),
                    ),
                  ),
                  if (list.isNotEmpty)
                    Text('${list.length - doneCount}/${list.length}',
                        style: theme.textTheme.labelMedium),
                  if (doneCount > 0)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      tooltip: '清除已完成（$doneCount）',
                      onPressed: notifier.clearCompleted,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      maxLength: TodoListNotifier.maxTitleLength,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: '新增待办…',
                        counterText: '',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addTodo(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.add),
                    tooltip: '添加',
                    onPressed: _addTodo,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(
                          '暂无待办，添加一条吧',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.hintColor),
                        ),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: theme.dividerColor),
                        itemBuilder: (ctx, idx) =>
                            TodoItemWidget(item: list[idx]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
