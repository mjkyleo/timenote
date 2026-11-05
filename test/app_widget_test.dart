import 'dart:convert';
import 'dart:io';

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
import 'package:timenote/settings/enum_def.dart';
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
/// 倒计时走时与实时时钟都通过 clockSourceProvider 注入假时间源，秒数只有在
/// 测试主动 tick 时才会前进，所以翻页动画不会出现「新旧两份 HH:MM:SS 同时在场」。
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

  /// 翻页板把时间拆成一格一格的 Text，按屏幕顺序拼回完整字符串
  String clockText(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(
          of: find.byType(FlipCardWidget), matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .join();

  /// 翻页中途旧牌和新牌同时在树里，拼出来的字符串会多几位；读数值要先过了动画时长
  Future<String> readClock(WidgetTester tester) async {
    await pumpFrames(tester, 6, const Duration(milliseconds: 100));
    return clockText(tester);
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
      expect(await readClock(tester), '10:00:00');
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
      expect(await readClock(tester), '00:00:03');

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

    testWidgets('选「停留 00:00:00」时归零留屏，不切回实时时钟', (tester) async {
      await pumpApp(tester);
      appSettings()
          .update(settings().copyWith(onFinish: FinishBehavior.stayZero));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));

      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 2));
      await tick(tester, const Duration(seconds: 2));
      await pumpFrames(tester, 6, const Duration(milliseconds: 80));
      expect(find.byType(EggDisplay), findsNothing);
      expect(find.byType(CountdownDisplay), findsOneWidget);
      expect(await readClock(tester), '00:00:00');

      // 这一档的约定就是「不动」：彩蛋超时切回那条路径不能偷偷跑起来
      await tester.pump(const Duration(seconds: 6));
      await pumpFrames(tester, 6, const Duration(milliseconds: 80));
      expect(find.byType(CountdownDisplay), findsOneWidget,
          reason: '停留档不该在几秒后自己回实时时钟');
      expect(await readClock(tester), '00:00:00');
    });

    testWidgets('选「自动重新开始」时用上一轮的时长直接重开', (tester) async {
      await pumpApp(tester);
      appSettings()
          .update(settings().copyWith(onFinish: FinishBehavior.autoRestart));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));

      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 3));
      await tick(tester, const Duration(seconds: 3));
      await pumpFrames(tester, 6, const Duration(milliseconds: 80));

      expect(find.byType(EggDisplay), findsNothing,
          reason: '重开档不该弹彩蛋');
      final state = container.read(clockNotifierProvider);
      expect(state.workMode, ClockWorkMode.countdown);
      expect(state.total, const Duration(seconds: 3),
          reason: '重开用的必须是上一次选的那个时长，不是预设默认值');
      expect(state.isRunning, isTrue);
      expect(await readClock(tester), '00:00:03');

      // 第二轮也得照常归零再重开，不然只循环一次
      await tick(tester, const Duration(seconds: 3));
      await pumpFrames(tester, 6, const Duration(milliseconds: 80));
      expect(await readClock(tester), '00:00:03');
      expect(container.read(clockNotifierProvider).isRunning, isTrue);

      // 用户点停止就是真停：不能因为这一档「会自动重开」而停不下来
      await stopTicker(tester);
      await tick(tester, const Duration(seconds: 4));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      expect(find.byType(ClockTimeDisplay), findsOneWidget,
          reason: '停止后不该再被自动重开拉回倒计时');
    });

    testWidgets('三档默认是弹彩蛋，改档后落盘；没进过设置页时不写这条', (tester) async {
      await pumpApp(tester);
      expect(settings().onFinish, FinishBehavior.showEgg,
          reason: '原 eggEnable 默认 true，改成枚举后默认档必须还是彩蛋');
      expect(StorageService.getSetting('onFinish', '<缺>'), '<缺>',
          reason: '没动过设置就不该有这条键');

      appSettings()
          .update(settings().copyWith(onFinish: FinishBehavior.stayZero));
      expect(StorageService.getSetting('onFinish', ''), 'stayZero');
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

    testWidgets('文案库最长那条在 800x600 也不溢出', (tester) async {
      final pool = (jsonDecode(
              File('assets/data/quotes.json').readAsStringSync()) as List)
          .cast<String>();
      final longest = pool.reduce((a, b) => a.length >= b.length ? a : b);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: EggDisplay(text: longest, themeBase: ThemeBase.dark)),
      ));
      await tester.pump();

      expect(find.text(longest), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: '520 条里最长的「$longest」不应触发渲染异常');
    });

    testWidgets('暂停期间时间冻结，点继续后接着走', (tester) async {
      await pumpApp(tester);
      final clock = container.read(clockNotifierProvider.notifier);
      clock.startCountdown(const Duration(seconds: 20));
      await tick(tester, const Duration(seconds: 5));
      expect(await readClock(tester), '00:00:15');

      await tapChip(tester, '暂停');
      fakeNow = fakeNow.add(const Duration(minutes: 3));
      await pumpFrames(tester, 3, const Duration(milliseconds: 50));
      expect(await readClock(tester), '00:00:15',
          reason: '暂停期间不应消耗墙钟时间');

      await tapChip(tester, '继续');
      await tick(tester, const Duration(seconds: 2));
      expect(await readClock(tester), '00:00:13');
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

    testWidgets('起表 6 秒后倒计时按钮一并隐去，点屏幕唤回后仍可操作', (tester) async {
      await pumpApp(tester);
      final clock = container.read(clockNotifierProvider.notifier);
      clock.startCountdown(const Duration(seconds: 30));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(find.text('暂停'), findsOneWidget);

      await tester.pump(const Duration(seconds: 7));
      await pumpFrames(tester, 4, const Duration(milliseconds: 100));

      // 控件层只剩 _chrome 的两处（底部按钮 + 右上角入口），一起淡出
      expect(find.byType(AnimatedOpacity), findsNWidgets(2));
      for (final layer in tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))) {
        expect(layer.opacity, 0, reason: '沉浸式待机应只剩数字');
      }
      expect(find.text('暂停'), findsOneWidget, reason: '隐藏不等于移出树，移出就回不来了');
      expect(find.byType(LinearProgressIndicator), findsOneWidget,
          reason: '进度条是「还在计时」的唯一凭据，不该跟着藏');

      // 隐藏态下点按钮位置不能真的生效：IgnorePointer 要同步挡住
      await tester.tap(find.text('暂停'), warnIfMissed: false);
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(container.read(clockNotifierProvider).isRunning, isTrue,
          reason: '按钮看不见时也不该被点到');

      await tester.tapAt(const Offset(400, 150));
      await pumpFrames(tester, 4, const Duration(milliseconds: 100));
      await tapChip(tester, '暂停');
      expect(container.read(clockNotifierProvider).isRunning, isFalse,
          reason: '点屏幕唤回后要立刻能暂停');
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
      expect(await readClock(tester), '00:02:00');
      await stopTicker(tester);
    });

    testWidgets('手机横屏 自定义弹窗完整可见，且不会一打开就弹键盘', (tester) async {
      // Pixel7 横屏 2400x1080 物理 / density 2.625（逻辑 914x411）。
      const screen = Size(2400 / 2.625, 1080 / 2.625);
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpApp(tester);
      await tapChip(tester, '自定义');
      await pumpFrames(tester, 8, const Duration(milliseconds: 60));
      expect(find.text('自定义倒计时'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 输入框 + 4 个快捷键 + 开始按钮都得完整落在屏内
      for (final target in [
        find.byType(TextField),
        find.text('60'),
        find.text('开始'),
      ]) {
        final rect = tester.getRect(target);
        expect(rect.right, lessThanOrEqualTo(screen.width), reason: '$target 横向溢出');
        expect(rect.bottom, lessThanOrEqualTo(screen.height), reason: '$target 纵向溢出');
      }

      // 一打开就抢焦点会立刻弹键盘，把弹窗压瘪（真机踩过），所以初始不能自动唤起键盘
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('键盘已弹出时自定义弹窗不塌成 0 高', (tester) async {
      // AlertDialog 的外边距 = viewInsets + insetPadding，键盘吃掉 570 物理像素时
      // 弹窗只剩 ~150 逻辑像素高；content 必须靠 scrollable + 收紧内边距活下来。
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.625;
      tester.view.viewInsets = const FakeViewPadding(bottom: 570);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await pumpApp(tester);
      await tapChip(tester, '自定义');
      await pumpFrames(tester, 8, const Duration(milliseconds: 60));
      expect(find.text('自定义倒计时'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'content 被压瘪会抛 RenderFlex overflow');

      final fieldRect = tester.getRect(find.byType(TextField));
      expect(fieldRect.height, greaterThan(0), reason: '输入框不能塌成 0 高');
      expect(fieldRect.bottom, lessThanOrEqualTo(1080 / 2.625 - 570 / 2.625),
          reason: '输入框必须落在键盘上方');
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

      final digits = tester.widgetList<Text>(find.descendant(
          of: find.byType(FlipCardWidget), matching: find.byType(Text)));
      expect(digits, isNotEmpty);
      for (final d in digits) {
        expect(d.style?.fontWeight, FontWeight.w900,
            reason: '每一格数字都要跟着换字重，${d.data} 却没有');
      }
    });

    testWidgets('横屏手机（914×411 逻辑）设置页不溢出，预览与选项都留得住高度',
        (tester) async {
      // Pixel7 横屏：2400×1080 物理 / density 2.625 → 逻辑 914×411。
      // 这里原先只按宽度分栏，结果 411 高的屏幕被横切成两栏，
      // 预览吃掉固定 210 高，选项区只剩 145，一整屏都滚不出几行。
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const screenSize = Size(2400 / 2.625, 1080 / 2.625);

      await pumpApp(tester);
      await openSettings(tester);
      expect(find.byType(SettingsPage), findsOneWidget);

      final previewHeight = tester.getSize(find.byType(StylePreview)).height;
      final optionsHeight = tester.getSize(find.byType(ListView)).height;
      expect(previewHeight, greaterThanOrEqualTo(100),
          reason: '预览矮于此就看不清翻页了');
      expect(optionsHeight, greaterThan(previewHeight),
          reason: '选项区是主操作区，不该比预览还矮');
      expect(optionsHeight, lessThanOrEqualTo(screenSize.height),
          reason: '两栏加起来不能超出屏幕');

      // 滚到底逐屏确认：任何一张选项卡片都不许横向越界
      final options = find.byType(ListView);
      final listRect = tester.getRect(options);
      expect(listRect.top, greaterThanOrEqualTo(0), reason: '选项区顶部被顶出屏幕');
      expect(listRect.bottom, lessThanOrEqualTo(screenSize.height),
          reason: '选项区底部被顶出屏幕');
      for (var step = 0; step < 14; step++) {
        await tester.drag(options, const Offset(0, -220));
        await pumpFrames(tester, 2, const Duration(milliseconds: 50));
        final cards =
            find.descendant(of: options, matching: find.byType(InkWell));
        for (var i = 0; i < cards.evaluate().length; i++) {
          final rect = tester.getRect(cards.at(i));
          expect(rect.left, greaterThanOrEqualTo(0), reason: '卡片左侧溢出');
          expect(rect.right, lessThanOrEqualTo(screenSize.width),
              reason: '卡片右侧溢出');
        }
      }
      expect(tester.takeException(), isNull, reason: '设置页横屏不允许溢出报错');
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

    testWidgets('滚到最下面能选「结束行为」与「数字外框」，选完即落盘', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      final options = find.byType(ListView);

      await tester.dragUntilVisible(
          find.text('自动重新开始'), options, const Offset(0, -120));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      await tester.tap(find.text('自动重新开始'));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      expect(StorageService.getSetting('onFinish', ''), 'autoRestart');

      await tester.dragUntilVisible(
          find.text('粗外框'), options, const Offset(0, -120));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      await tester.tap(find.text('粗外框'));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      expect(StorageService.getSetting('plateFrame', ''), 'thick');

      // 预览是活的：选完外框，同一棵树上的底板就该带上 3px 描边
      final plate = tester.widget<Container>(find.descendant(
          of: find.byType(StylePreview), matching: find.byKey(const Key('flip-plate'))));
      final deco = plate.decoration as BoxDecoration;
      expect(deco.border?.top.width, 3,
          reason: '预览没跟着档位走，说明设置值没穿过 FlipCardWidget');
      expect(deco.border?.top.color, isNotNull);
    });
  });
}
