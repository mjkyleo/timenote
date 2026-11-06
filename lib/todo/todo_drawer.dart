import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/todo_providers.dart';
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
  final FocusNode _inputFocus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 空状态那颗按钮：把焦点交给输入框，键盘跟着起来，用户直接打字就行
  void _focusInput() {
    HapticFeedback.selectionClick();
    _inputFocus.requestFocus();
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
    // 令牌由 MaterialApp 的 builder 注入，这里不再自己从设置里猜黑白
    // （选「跟随系统」时 themeBase 只是意图，不是结果）
    final tokens = UiScope.of(context);

    return Drawer(
      // 竖屏手机上固定 360 会把整屏盖住，留出一条约 15% 的缝当「还能点回去」的提示
      width: (MediaQuery.sizeOf(context).width * 0.85).clamp(0.0, 360.0),
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
                      focusNode: _inputFocus,
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
                        // 空状态给得出下一步：一句话 + 一颗能按的按钮，
                        // 而不是一句「添加一条吧」让人自己找输入框（writing.md）
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '暂无待办，添加一条吧',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: tokens.labelInk),
                            ),
                            const SizedBox(height: 12),
                            // 只写文字不配图：上面输入行已经有一颗加号，
                            // 同一个屏幕上两颗一样的加号会让人分不清按哪个
                            FilledButton.tonal(
                              onPressed: _focusInput,
                              child: const Text('添加待办'),
                            ),
                          ],
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
