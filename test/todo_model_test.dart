import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/todo/todo_model.dart';

void main() {
  group('TodoItem', () {
    test('toMap / fromMap 往返一致', () {
      final item = TodoItem(
        id: '1',
        title: '背单词',
        isCompleted: true,
        createAt: DateTime(2026, 11, 4, 9, 30),
      );
      final map = item.toMap();
      final restored = TodoItem.fromMap(map);
      expect(restored.id, '1');
      expect(restored.title, '背单词');
      expect(restored.isCompleted, true);
      expect(restored.createAt, DateTime(2026, 11, 4, 9, 30));
    });

    test('fromMap 缺省字段有默认值', () {
      final restored = TodoItem.fromMap({'id': 'x', 'title': 't'});
      expect(restored.isCompleted, false);
      expect(restored.createAt, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });
}
