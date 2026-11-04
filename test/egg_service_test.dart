import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/egg_service.dart';

void main() {
  group('EggService', () {
    test('空池时返回兜底文案', () {
      // 未加载 quotes 时为空池
      final q = EggService.getRandomQuote();
      expect(q, 'Keep going.');
    });
  });
}
