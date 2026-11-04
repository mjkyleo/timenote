/// 待办数据模型（普通类，配合 Hive 以 Map 形式存储，无需代码生成）
class TodoItem {
  final String id;
  final String title;
  final bool isCompleted;
  final DateTime createAt;

  const TodoItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
    required this.createAt,
  });

  TodoItem copyWith({bool? isCompleted}) {
    return TodoItem(
      id: id,
      title: title,
      isCompleted: isCompleted ?? this.isCompleted,
      createAt: createAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
      'createAt': createAt.millisecondsSinceEpoch,
    };
  }

  /// 容忍旧版本/损坏数据：缺少 id 或 title 的条目返回 null，由调用方丢弃
  static TodoItem? fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'];
    final title = map['title'];
    if (id is! String || id.isEmpty || title is! String) return null;
    return TodoItem(
      id: id,
      title: title,
      isCompleted: map['isCompleted'] == true,
      createAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
