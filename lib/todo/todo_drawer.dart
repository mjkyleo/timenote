import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/todo_providers.dart';
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
    return SizedBox(
      width: 320,
      child: Drawer(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text(
                '待办清单',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        hintText: '新增待办…',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addTodo(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: '添加',
                    onPressed: _addTodo,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无待办，添加一条吧',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
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
