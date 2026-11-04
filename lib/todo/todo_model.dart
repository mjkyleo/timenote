/// 待办数据模型（普通类，配合 Hive 以 Map 形式存储，无需代码生成）
class TodoItem {
  final String id;
  final String title;
  bool isCompleted;
  final DateTime createAt;

  TodoItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
    required this.createAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
      'createAt': createAt.millisecondsSinceEpoch,
    };
  }

  factory TodoItem.fromMap(Map<dynamic, dynamic> map) {
    return TodoItem(
      id: map['id'] as String,
      title: map['title'] as String,
      isCompleted: map['isCompleted'] as bool? ?? false,
      createAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
