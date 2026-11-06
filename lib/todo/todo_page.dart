import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/todo_providers.dart';
import '../theme/ui_style.dart';
import 'todo_item.dart';

/// 「待办」标签页：清单、进度与新增都在这一页。
///
/// 原来是主屏右上角图标拉出来的右侧抽屉：在平板横屏上还说得通，手机竖屏一拉
/// 盖住大半个屏幕，且清单和时钟挤在同一块画面里，谁都不是主角。
class TodoPage extends ConsumerStatefulWidget {
  const TodoPage({super.key});

  @override
  ConsumerState<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends ConsumerState<TodoPage> {
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

  void _addTodo(TodoListNotifier notifier) {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    notifier.addTodo(t);
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

    return UiLayer(
      tokens: tokens,
      solid: true,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 横屏手机弹键盘时这一页只剩 104–138 高（640×360 与 914×411 实测），
              // 进度标题那一行先退场，把高度留给输入行和清单；标题栏已经写着「待办」
              final tight = constraints.maxHeight < 160;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!tight) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            // 标题栏已经写了「待办」，这里只报进度，不重复一遍
                            list.isEmpty
                                ? '还没有待办'
                                : '还剩 ${list.length - doneCount} 件 · 共 ${list.length} 件',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: tokens.labelInk),
                          ),
                        ),
                        if (doneCount > 0)
                          TextButton.icon(
                            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                            label: Text('清除已完成（$doneCount）'),
                            onPressed: notifier.clearCompleted,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _inputFocus,
                          maxLength: TodoListNotifier.maxTitleLength,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: '新增待办…',
                            counterText: '',
                            filled: true,
                            fillColor: tokens.surface ??
                                tokens.fg.withValues(alpha: 0.05),
                            border: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addTodo(notifier),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.add),
                        tooltip: '添加',
                        onPressed: () => _addTodo(notifier),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: list.isEmpty
                        ? LayoutBuilder(
                            builder: (context, box) => SingleChildScrollView(
                              // 够高就居中，不够就滚：键盘顶起来时这块只剩几十像素，
                              // 用 FittedBox 缩字会把「下一步」缩到看不见
                              child: ConstrainedBox(
                                constraints:
                                    BoxConstraints(minHeight: box.maxHeight),
                                child: Center(
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
                                ),
                              ),
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
              );
            },
          ),
        ),
      ),
    );
  }
}
