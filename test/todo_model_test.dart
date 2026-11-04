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
      expect(restored?.id, '1');
      expect(restored?.title, '背单词');
      expect(restored?.isCompleted, true);
      expect(restored?.createAt, DateTime(2026, 11, 4, 9, 30));
    });

    test('fromMap 缺省字段有默认值', () {
      final restored = TodoItem.fromMap({'id': 'x', 'title': 't'});
      expect(restored?.isCompleted, false);
      expect(restored?.createAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('fromMap 丢弃损坏条目而不是崩溃', () {
      expect(TodoItem.fromMap({'title': '没有 id'}), isNull);
      expect(TodoItem.fromMap({'id': '', 'title': '空 id'}), isNull);
      expect(TodoItem.fromMap({'id': 'x'}), isNull);
      expect(TodoItem.fromMap({'id': 1, 'title': 'id 类型错误'}), isNull);
    });

    test('isCompleted 只认真值 true', () {
      final restored = TodoItem.fromMap(
          {'id': 'x', 'title': 't', 'isCompleted': 'yes'});
      expect(restored?.isCompleted, false);
    });

    test('copyWith 返回新对象，原对象不变', () {
      final item = TodoItem(
        id: '1',
        title: 't',
        createAt: DateTime(2026, 11, 4, 9, 30),
      );
      final done = item.copyWith(isCompleted: true);
      expect(item.isCompleted, false);
      expect(done.isCompleted, true);
      expect(done.id, item.id);
      expect(done.title, item.title);
      expect(done.createAt, item.createAt);
      expect(done, isNot(same(item)));
    });
  });
}
