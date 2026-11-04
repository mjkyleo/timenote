import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

/// 彩蛋文案服务：加载本地 quotes.json，随机抽取且不连续重复
class EggService {
  const EggService._();

  /// 文案池缺失/损坏时的兜底
  static const String fallbackQuote = 'Keep going.';

  static List<String> _quotes = [];
  static final Random _random = Random();
  static int _lastNameIndex = -1;

  static Future<void> loadQuotes() async {
    try {
      final raw = await rootBundle.loadString('assets/data/quotes.json');
      final decoded = json.decode(raw);
      if (decoded is List) {
        _quotes = decoded.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {
      // 文件缺失 / json 异常时兜底为空池，不崩溃
      _quotes = [];
    }
  }

  static String getRandomQuote() {
    if (_quotes.isEmpty) return fallbackQuote;
    if (_quotes.length == 1) return _quotes.first;
    var idx = _random.nextInt(_quotes.length);
    while (idx == _lastNameIndex) {
      idx = _random.nextInt(_quotes.length);
    }
    _lastNameIndex = idx;
    return _quotes[idx];
  }
}
