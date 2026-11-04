import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/providers/app_providers.dart';
import 'package:timenote/core/providers/clock_providers.dart';
import 'package:timenote/core/storage_service.dart';
import 'package:timenote/egg/egg_display.dart';
import 'package:timenote/flip_clock/clock_controller.dart';
import 'package:timenote/flip_clock/flip_card_widget.dart';
import 'package:timenote/main.dart';
import 'package:timenote/settings/settings_page.dart';

import 'support/fake_storage.dart';
import 'support/fake_wakelock.dart';

/// 应用级回归测试：抽屉真的滑入、待办真的进列表并写进 box、常亮即时生效、
/// 倒计时归零的彩蛋/停止/暂停行为正确。
///
/// 三条环境约束（都实测踩过）：
/// 1. fake-async 区内不能 await 真实文件 IO，所以存储用 Hive 内存后端
///    （见 support/fake_storage.dart），落盘回归在 storage_service_test.dart；
/// 2. 抽屉/路由动画按帧推进，单次 `pump(500ms)` 只会停在起始值，
///    所以要连续小步 pump（见 [pumpFrames]）；
/// 3. audioplayers 需要真实资源落盘，测试环境把 soundEnable 关掉，
///    彩蛋与声音互不阻塞的顺序改由代码审查保证。
///
/// 倒计时走时通过 clockSourceProvider 注入假时间源，实时时钟仍读真实时间，
/// 因此断言只看控件类型或倒计时专属字符串。
void main() {
  late ProviderContainer container;
  late DateTime fakeNow;
  late FakeWakelock wakelock;

  setUp(() async {
    wakelock = installFakeWakelock();
    await useMemoryStorage();
    await StorageService.writeSettings({'soundEnable': false});
    fakeNow = DateTime(2026, 11, 4, 10, 0, 0);
    container = ProviderContainer(
      overrides: [clockSourceProvider.overrideWithValue(() => fakeNow)],
    );
  });

  tearDown(() async {
    container.dispose();
    await releaseMemoryStorage();
  });

  Future<void> pumpFrames(WidgetTester tester, int count, Duration each) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(each);
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TimeNoteApp(),
      ),
    );
    await pumpFrames(tester, 3, const Duration(milliseconds: 50));
  }

  /// 同时推进注入的时间源与测试帧，让倒计时按预期的秒数走
  Future<void> tick(WidgetTester tester, Duration d) async {
    fakeNow = fakeNow.add(d);
    await tester.pump(d);
    await pumpFrames(tester, 2, const Duration(milliseconds: 50));
  }

  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.menu));
    await pumpFrames(tester, 8, const Duration(milliseconds: 60));
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings));
    await pumpFrames(tester, 10, const Duration(milliseconds: 60));
  }

  /// 点底部胶囊按钮：命中的是 ActionChip 整体，点文字中心会触发 hit-test 警告
  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.tap(find.ancestor(
      of: find.text(label),
      matching: find.byType(ActionChip),
    ));
    await pumpFrames(tester, 3, const Duration(milliseconds: 50));
  }

  AppSettingsState settings() => container.read(appSettingsNotifierProvider);
  AppSettingsNotifier appSettings() =>
      container.read(appSettingsNotifierProvider.notifier);

  /// flutter_test 在用例 body 结束时检查「不许遗留 Timer」，而 ClockNotifier 的
  /// 250ms ticker 要到 tearDown 的 container.dispose 才取消，所以跑过倒计时的
  /// 用例必须在 body 里先停表。
  Future<void> stopTicker(WidgetTester tester) async {
    container.read(clockNotifierProvider.notifier).stopCountdown();
    await pumpFrames(tester, 2, const Duration(milliseconds: 50));
  }

  group('主屏', () {
    testWidgets('展示 HH:MM:SS 翻页数字', (tester) async {
      await pumpApp(tester);
      expect(find.byType(ClockTimeDisplay), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d{2}:\d{2}:\d{2}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('右上角有设置与待办入口', (tester) async {
      await pumpApp(tester);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
    });

    testWidgets('无操作 6 秒后控件不可点，点一下唤回后仍能进设置', (tester) async {
      await pumpApp(tester);
      expect(find.byIcon(Icons.settings), findsOneWidget);

      await tester.pump(const Duration(seconds: 7));
      await pumpFrames(tester, 4, const Duration(milliseconds: 100));

      // 隐藏态下按钮被 IgnorePointer/Opacity 屏蔽：这次点击命不中按钮，
      // 只会经由最外层 Listener 把控件唤回（warnIfMissed 关掉，miss 是预期）
      await tester.tap(find.byIcon(Icons.settings), warnIfMissed: false);
      await pumpFrames(tester, 4, const Duration(milliseconds: 100));
      expect(find.byType(SettingsPage), findsNothing,
          reason: '控件隐藏时不应响应设置按钮');

      await openSettings(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
    });
  });

  group('待办抽屉', () {
    testWidgets('点击汉堡后抽屉真的滑入可视区域', (tester) async {
      await pumpApp(tester);
      expect(find.byType(Drawer), findsNothing, reason: '未打开时不该在树上');

      await openDrawer(tester);
      final drawer = tester.getRect(find.byType(Drawer));
      final screen = tester.getRect(find.byType(Scaffold));
      expect(drawer.right, closeTo(screen.right, 1));
      expect(drawer.left, greaterThanOrEqualTo(screen.left));
      expect(drawer.top, greaterThanOrEqualTo(screen.top));
      expect(drawer.bottom, lessThanOrEqualTo(screen.bottom));
      expect(drawer.width, greaterThan(100));
    });

    testWidgets('新增待办出现在列表里，输入框被清空', (tester) async {
      await pumpApp(tester);
      await openDrawer(tester);

      await tester.enterText(find.byType(TextField), '写周报');
      await tester.tap(find.byIcon(Icons.add));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));

      expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('写周报'),
        ),
        findsOneWidget,
      );
      expect(find.text('1/1'), findsOneWidget);
    });

    testWidgets('勾选完成后出现清除入口，清除后列表与存储都空', (tester) async {
      await pumpApp(tester);
      await openDrawer(tester);

      await tester.enterText(find.byType(TextField), '背单词');
      await tester.tap(find.byIcon(Icons.add));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));

      await tester.tap(find.byType(Checkbox));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));
      expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('背单词'),
        ),
        findsNothing,
      );
      expect(find.text('暂无待办，添加一条吧'), findsOneWidget);
      expect(StorageService.getTodoList(), isEmpty);
    });

    testWidgets('删除单条待办', (tester) async {
      await pumpApp(tester);
      await openDrawer(tester);
      await tester.enterText(find.byType(TextField), '删掉我');
      await tester.tap(find.byIcon(Icons.add));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));

      await tester.tap(find.byIcon(Icons.delete_outline));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));
      expect(find.text('暂无待办，添加一条吧'), findsOneWidget);
      expect(StorageService.getTodoList(), isEmpty);
    });
  });

  group('屏幕常亮', () {
    testWidgets('默认开启，关闭开关后立即下发 disable（不必重启）', (tester) async {
      await pumpApp(tester);
      expect(wakelock.toggles, [true]);

      appSettings().update(settings().copyWith(keepScreenOn: false));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(wakelock.toggles.last, isFalse);

      appSettings().update(settings().copyWith(keepScreenOn: true));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(wakelock.toggles.last, isTrue);
    });
  });

  group('倒计时结束行为', () {
    testWidgets('归零展示彩蛋，点任意处返回时钟', (tester) async {
      await pumpApp(tester);
      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 3));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(find.textContaining('00:00:03'), findsOneWidget);

      await tick(tester, const Duration(seconds: 3));
      await pumpFrames(tester, 6, const Duration(milliseconds: 80));
      expect(find.byType(EggDisplay), findsOneWidget);

      await tester.tapAt(const Offset(400, 300));
      await pumpFrames(tester, 6, const Duration(milliseconds: 80));
      expect(find.byType(EggDisplay), findsNothing);
      expect(find.byType(ClockTimeDisplay), findsOneWidget,
          reason: '彩蛋收尾就是本次计时结束，应该回到实时时钟而不是停在 00:00:00');
    });

    testWidgets('彩蛋停留 5 秒后自动切回实时时钟', (tester) async {
      await pumpApp(tester);
      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 2));
      await tick(tester, const Duration(seconds: 2));
      await pumpFrames(tester, 6, const Duration(milliseconds: 80));
      expect(find.byType(EggDisplay), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      await pumpFrames(tester, 6, const Duration(milliseconds: 80));
      expect(find.byType(EggDisplay), findsNothing);
      expect(find.byType(ClockTimeDisplay), findsOneWidget);
    });

    testWidgets('关闭彩蛋后归零保留 00:00:00 结束态', (tester) async {
      await pumpApp(tester);
      appSettings().update(settings().copyWith(eggEnable: false));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));

      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 2));
      await tick(tester, const Duration(seconds: 2));
      await pumpFrames(tester, 6, const Duration(milliseconds: 80));
      expect(find.byType(EggDisplay), findsNothing);
      expect(find.byType(CountdownDisplay), findsOneWidget);
      expect(find.textContaining('00:00:00'), findsOneWidget);
    });

    testWidgets('停止倒计时回到实时时钟，不留 00:00:00 死屏', (tester) async {
      await pumpApp(tester);
      final clock = container.read(clockNotifierProvider.notifier);
      clock.startCountdown(const Duration(seconds: 30));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(find.byType(CountdownDisplay), findsOneWidget);

      clock.stopCountdown();
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      expect(find.byType(CountdownDisplay), findsNothing);
      expect(find.byType(ClockTimeDisplay), findsOneWidget);
    });

    testWidgets('暂停期间时间冻结，点继续后接着走', (tester) async {
      await pumpApp(tester);
      final clock = container.read(clockNotifierProvider.notifier);
      clock.startCountdown(const Duration(seconds: 20));
      await tick(tester, const Duration(seconds: 5));
      expect(find.textContaining('00:00:15'), findsOneWidget);

      await tapChip(tester, '暂停');
      fakeNow = fakeNow.add(const Duration(minutes: 3));
      await pumpFrames(tester, 3, const Duration(milliseconds: 50));
      expect(find.textContaining('00:00:15'), findsOneWidget,
          reason: '暂停期间不应消耗墙钟时间');

      await tapChip(tester, '继续');
      await tick(tester, const Duration(seconds: 2));
      expect(find.textContaining('00:00:13'), findsOneWidget);
      await stopTicker(tester);
    });

    testWidgets('进度条随剩余时间增长', (tester) async {
      await pumpApp(tester);
      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 20));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
        closeTo(0, 0.01),
      );

      await tick(tester, const Duration(seconds: 10));
      expect(
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
        closeTo(0.5, 0.06),
      );
      await stopTicker(tester);
    });

    testWidgets('自定义弹窗校验非法输入，合法值真的启动倒计时', (tester) async {
      await pumpApp(tester);
      await tapChip(tester, '自定义');
      await pumpFrames(tester, 8, const Duration(milliseconds: 60));
      expect(find.text('自定义倒计时'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '999');
      await tester.tap(find.text('开始'));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      expect(find.textContaining('请输入 1-600 之间的分钟数'), findsOneWidget);
      expect(find.byType(CountdownDisplay), findsNothing,
          reason: '非法输入不应启动倒计时');

      await tester.enterText(find.byType(TextField), '2');
      await tester.tap(find.text('开始'));
      await pumpFrames(tester, 8, const Duration(milliseconds: 60));
      expect(find.byType(CountdownDisplay), findsOneWidget);
      expect(find.textContaining('00:02:00'), findsOneWidget);
      await stopTicker(tester);
    });
  });

  group('设置', () {
    testWidgets('切换数字样式后主屏字重变化并落盘', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      expect(find.byType(SettingsPage), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('粗黑力量体'),
        find.byType(ListView),
        const Offset(0, -120),
      );
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      await tester.tap(find.text('粗黑力量体'));
      await pumpFrames(tester, 6, const Duration(milliseconds: 50));
      expect(StorageService.getSetting('clockVisualStyle', ''), 'boldPower');

      await tester.pageBack();
      await pumpFrames(tester, 10, const Duration(milliseconds: 60));

      final digits = tester.widget<Text>(
          find.textContaining(RegExp(r'\d{2}:\d{2}:\d{2}')).first);
      expect(digits.style?.fontWeight, FontWeight.w900);
    });

    testWidgets('设置页预览用当前风格实时渲染', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      expect(find.byType(StylePreview), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StylePreview),
          matching: find.byType(FlipCardWidget),
        ),
        findsOneWidget,
      );
    });
  });
}
