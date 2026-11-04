import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/egg_service.dart';

/// 顺序敏感：第一个用例必须在未加载文案池时跑，用来验证兜底路径。
void main() {
  List<String> readPool() =>
      (jsonDecode(File('assets/data/quotes.json').readAsStringSync()) as List)
          .cast<String>();

  group('EggService', () {
    test('空池时返回兜底文案', () {
      // 未加载 quotes 时为空池
      final q = EggService.getRandomQuote();
      expect(q, 'Keep going.');
    });

    test('文案库本身合法：非空且无重复', () {
      final pool = readPool();
      expect(pool.length, greaterThanOrEqualTo(520));
      expect(pool.every((s) => s.trim().isNotEmpty), isTrue);
      expect(pool.toSet().length, pool.length, reason: '重复文案会让随机显得坏掉');
    });

    test('加载后抽取的是池内文案，且不连续重复', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await EggService.loadQuotes();
      final pool = readPool();

      for (var i = 0; i < 12; i++) {
        final a = EggService.getRandomQuote();
        final b = EggService.getRandomQuote();
        expect(pool, contains(a));
        expect(b, isNot(a), reason: '连续两次不应给出同一条');
      }
    });
  });
}
