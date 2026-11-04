import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

/// 彩蛋文案服务：加载本地 quotes.json，纯随机抽取（不做当日去重）
class EggService {
  static List<String> _quotes = [];

  static Future<void> loadQuotes() async {
    try {
      final raw = await rootBundle.loadString('assets/data/quotes.json');
      final List<dynamic> list = json.decode(raw);
      _quotes = list.map((e) => e.toString()).toList();
    } catch (_) {
      // 文件缺失 / json 异常时兜底为空池，不崩溃
      _quotes = [];
    }
  }

  static String getRandomQuote() {
    if (_quotes.isEmpty) return 'Keep going.';
    final idx = Random().nextInt(_quotes.length);
    return _quotes[idx];
  }
}
