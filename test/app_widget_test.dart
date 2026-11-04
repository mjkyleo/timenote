import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timenote/main.dart';
import 'package:timenote/core/storage_service.dart';

void main() {
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('timenote_test');
    await StorageService.init(
        hivePath: dir.path, boxPrefix: 'wt_${DateTime.now().microsecondsSinceEpoch}_');
  });

  tearDown(() async {
    await StorageService.close();
  });

  testWidgets('启动后展示翻页时钟主体', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TimeNoteApp()));
    // 时钟每秒翻页动画常驻，不能用 pumpAndSettle，改为有限时间推进
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('右上角存在设置与待办入口', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TimeNoteApp()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  testWidgets('点击汉堡可打开待办抽屉', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TimeNoteApp()));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('待办清单'), findsOneWidget);
  });

  testWidgets('新增待办后列表出现', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TimeNoteApp()));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), '写周报');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('写周报'), findsOneWidget);
  });
}
