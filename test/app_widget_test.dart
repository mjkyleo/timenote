import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/app/app_shell.dart';
import 'package:timenote/core/constants.dart';
import 'package:timenote/core/providers/app_providers.dart';
import 'package:timenote/core/providers/clock_providers.dart';
import 'package:timenote/core/storage_service.dart';
import 'package:timenote/egg/egg_display.dart';
import 'package:timenote/flip_clock/clock_controller.dart';
import 'package:timenote/flip_clock/clock_page.dart';
import 'package:timenote/flip_clock/flip_card_widget.dart';
import 'package:timenote/flip_clock/standby_view.dart';
import 'package:timenote/main.dart';
import 'package:timenote/progress_decor/progress_decor.dart';
import 'package:timenote/settings/enum_def.dart';
import 'package:timenote/settings/settings_page.dart';
import 'package:timenote/settings/style_picker.dart';
import 'package:timenote/todo/todo_page.dart';

import 'support/app_harness.dart';
import 'support/fake_storage.dart';
import 'support/fake_wakelock.dart';

/// 应用级回归测试：三标签真的换页、待办真的进列表并写进 box、常亮即时生效、
/// 待机屏的排向/沉浸/控件自动隐藏、倒计时归零的彩蛋/停止/暂停行为正确。
///
/// 三条环境约束（都实测踩过）：
/// 1. fake-async 区内不能 await 真实文件 IO，所以存储用 Hive 内存后端
///    （见 support/fake_storage.dart），落盘回归在 storage_service_test.dart；
/// 2. 路由/标签动画按帧推进，单次 `pump(500ms)` 只会停在起始值，
///    所以要连续小步 pump（见 [pumpFrames]）；
/// 3. audioplayers 需要真实资源落盘，测试环境把 soundEnable 关掉，
///    彩蛋与声音互不阻塞的顺序改由代码审查保证。
///
/// 倒计时走时与实时时钟都通过 clockSourceProvider 注入假时间源，秒数只有在
/// 测试主动 tick 时才会前进，所以翻页动画不会出现「新旧两份 HH:MM:SS 同时在场」。
///
/// 两种画面要分清：[pumpShell] 停在外壳三标签（时间页那张读数卡也在里面），
/// [pumpApp] 再按「进入待机」进全屏大屏。归零彩蛋、进度层、控件自动隐藏都只
/// 属于待机屏；起表预设与自定义弹窗只属于时间页。
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await releaseMemoryStorage();
  });

  Future<void> pumpFrames(WidgetTester tester, int count, Duration each) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(each);
    }
  }

  /// 外壳三标签（时间 / 待办 / 设置）。第一屏就是它，没有开始页了
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TimeNoteApp(),
      ),
    );
    await pumpFrames(tester, 3, const Duration(milliseconds: 50));
  }

  /// 外壳 + 待机屏：全屏大数字那一层，归零行为与进度层都在这里验
  Future<void> pumpApp(WidgetTester tester) async {
    await pumpShell(tester);
    await enterStandby(tester);
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

  /// 待办与设置各自是一个标签，不再是抽屉/子路由：先退回外壳再点标签
  Future<void> openTodo(WidgetTester tester) async {
    await exitStandby(tester);
    await tapTab(tester, '待办');
  }

  Future<void> openSettings(WidgetTester tester) async {
    await exitStandby(tester);
    await tapTab(tester, '设置');
  }

  /// 设置页的滚动区。外壳用 IndexedStack 把三页都建出来了，没选中的那两页
  /// 在 Offstage 里（find 默认跳过），但按类型找 ListView 仍然容易撞到别页，
  /// 所以凡是设置页里的滚动都限定在它自己的子树内
  Finder settingsScrollable() => find.descendant(
      of: find.byType(SettingsPage), matching: find.byType(Scrollable));

  Finder settingsList() => find.descendant(
      of: find.byType(SettingsPage), matching: find.byType(ListView));

  /// 点胶囊按钮：命中的是 ActionChip 整体，点文字中心会触发 hit-test 警告。
  /// 时间页的起表芯片在懒建列表里，横屏手机（尤其键盘还弹着时）首屏装不下，
  /// 没建出来的要先滚到它，建出来但压在视口外的再 ensureVisible 拉进来
  Future<void> tapChip(WidgetTester tester, String label) async {
    await wakeChrome(tester);
    final chip = find.ancestor(
        of: find.text(label), matching: find.byType(ActionChip));
    if (chip.evaluate().isEmpty) {
      await tester.scrollUntilVisible(find.text(label), 120,
          scrollable: find.descendant(
              of: find.byType(ClockPage), matching: find.byType(Scrollable)));
    }
    await tester.ensureVisible(chip);
    await pumpFrames(tester, 2, const Duration(milliseconds: 50));
    await tester.tap(chip);
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

  /// `SystemChrome` 的两个调用在测试环境是无声的，装上 mock 才看得到真实参数。
  /// 参数按 Flutter 源码的线上格式收：方向是 `_stringify` 出来的
  /// `['DeviceOrientation.landscapeLeft', ...]`，沉浸是 `'SystemUiMode.immersiveSticky'`，
  /// 这里统一削成末段，断言写的就是 `AppConstants` 里那两档的顺序。
  final List<Object?> orientationCalls = <Object?>[];
  final List<Object?> uiModeCalls = <Object?>[];

  void recordSystemChrome() {
    orientationCalls.clear();
    uiModeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientationCalls.add([
          for (final raw in call.arguments as List<Object?>)
            raw.toString().split('.').last
        ]);
      } else if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        uiModeCalls.add(call.arguments.toString().split('.').last);
      }
      return null;
    });
  }

  group('外壳与排向', () {
    /// 外壳的门限是 760×600（宽高都要够）：手机横竖屏都走底部导航栏，
    /// 只有平板那种又宽又高的画面才换左侧导航栏 —— 横屏手机高度不够，
    /// 键盘一弹竖排三颗带文字的目的地就装不下（实测溢出 50px）。
    /// 默认测试画面是 800×600（宽屏那一支），要验底部栏得先把画面改成手机尺寸。
    Future<void> phoneSurface(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    const allOrientations = [
      'portraitUp',
      'landscapeLeft',
      'portraitDown',
      'landscapeRight',
    ];

    testWidgets('第一屏是外壳的时间页：不锁排向也不进沉浸', (tester) async {
      await phoneSurface(tester);
      recordSystemChrome();
      await pumpShell(tester);

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(ClockPage), findsOneWidget);
      expect(find.byType(StandbyView), findsNothing,
          reason: '进来就是全屏大数字，等于又回到强制横屏那一版');
      expect(settings().orientation, AppOrientation.landscape,
          reason: 'R4 默认横屏：待机屏的原始观感不能被顺手改掉');
      expect(orientationCalls.last, allOrientations,
          reason: '外壳三页跟随手机当前拿法，四向都要放开');
      expect(uiModeCalls.last, 'edgeToEdge',
          reason: '沉浸是待机屏的事，外壳还得留着系统栏');
    });

    testWidgets('窄屏给底部导航栏：时间 / 待办 / 设置三颗，贴在屏幕下沿', (tester) async {
      await phoneSurface(tester);
      await pumpShell(tester);

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations, hasLength(3), reason: '用户要的就是底下这三颗');
      expect(bar.selectedIndex, 0, reason: '进来先停在时间页');
      for (final label in ['时间', '待办', '设置']) {
        expect(
            find.descendant(
                of: find.byType(NavigationBar), matching: find.text(label)),
            findsOneWidget,
            reason: '底部少了「$label」这一颗');
      }
      final rect = tester.getRect(find.byType(NavigationBar));
      expect(rect.bottom, closeTo(844, 1), reason: '导航栏没贴在屏幕下沿');
      expect(rect.width, closeTo(390, 1));
      // 这条高度是外壳的「固定开销」：AppBar 56 + 导航条 80 = 136，
      // 横屏手机 411 高只剩 275 给页体，设置页分栏门限 260 就是照它定的
      expect(rect.height, closeTo(80, 1), reason: '导航条高度变了，页体预算要重算');
      expect(tester.getRect(find.byType(AppBar)).height, closeTo(56, 1),
          reason: '标题栏高度变了，页体预算要重算');
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('宽屏（平板 1180×820）换成左侧导航栏，底部不再占一条', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpShell(tester);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing,
          reason: '平板上再压一条底部栏，白吃掉一截读数高度');
      final rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.left, closeTo(0, 1));
      expect(rail.height, greaterThan(400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('点标签真的换页：一次只有一页在可视树里，标题栏跟着换', (tester) async {
      await pumpShell(tester);

      await tapTab(tester, '待办');
      expect(find.byType(TodoPage), findsOneWidget);
      expect(find.byType(ClockPage), findsNothing,
          reason: '没选中的页该退到 Offstage，不然两页的控件会一起被点到');
      expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('待办')),
          findsOneWidget);

      await tapTab(tester, '设置');
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.byType(TodoPage), findsNothing);

      await tapTab(tester, '时间');
      expect(find.byType(ClockPage), findsOneWidget);
      expect(find.byType(SettingsPage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点「进入待机」才锁横屏两档并进沉浸', (tester) async {
      recordSystemChrome();
      await pumpApp(tester);

      expect(find.byType(StandbyView), findsOneWidget);
      expect(find.byType(ClockPage), findsNothing,
          reason: '待机屏是全屏一层，底下那页要被摘掉，不然两套控件同时在场');
      expect(find.byType(ClockTimeDisplay), findsOneWidget);
      expect(orientationCalls.last, ['landscapeLeft', 'landscapeRight']);
      expect(uiModeCalls, contains('immersiveSticky'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('退出待机：系统栏与四向旋转都交还给外壳', (tester) async {
      await pumpApp(tester);
      recordSystemChrome();
      await exitStandby(tester);

      expect(find.byType(StandbyView), findsNothing);
      expect(find.byType(ClockPage), findsOneWidget);
      expect(orientationCalls.last, allOrientations,
          reason: '退出去还锁着横屏，待办与设置两页就没法竖着用了');
      expect(uiModeCalls.last, 'edgeToEdge');
    });

    testWidgets('设置里选「竖屏」：外壳不转、落盘，进待机才锁竖屏两档', (tester) async {
      recordSystemChrome();
      await pumpShell(tester);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.textContaining('待机屏排向'), 160,
          scrollable: settingsScrollable());
      await tester.ensureVisible(find.text('竖屏'));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));

      await tester.tap(find.text('竖屏'));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));

      expect(settings().orientation, AppOrientation.portrait);
      expect(StorageService.getSetting('screenOrientation', 'landscape'),
          'portrait',
          reason: '只在当次会话生效等于没存，下次打开又回横屏');
      expect(orientationCalls.last, allOrientations,
          reason: '排向只管待机屏：在外壳里就把手机锁成竖屏是越权');

      await tapTab(tester, '时间');
      await enterStandby(tester);
      expect(orientationCalls.last, ['portraitUp', 'portraitDown'],
          reason: '进了待机屏就该按选的那一档锁住');
    });

    testWidgets('库里存着竖屏时，一进待机就是竖屏两档（重启路径）', (tester) async {
      await StorageService.writeSettings({'screenOrientation': 'portrait'});
      recordSystemChrome();
      await pumpApp(tester);

      expect(settings().orientation, AppOrientation.portrait);
      expect(orientationCalls.last, ['portraitUp', 'portraitDown']);
    });

    testWidgets('平板走左侧导航栏那一支：三页与待机屏都不溢出', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpShell(tester);
      expect(find.byType(NavigationRail), findsOneWidget);

      for (final tab in ['待办', '设置', '时间']) {
        await tapTab(tester, tab);
        expect(tester.takeException(), isNull, reason: '$tab 页在平板尺寸下溢出');
      }
      await enterStandby(tester);
      expect(tester.takeException(), isNull);
      await exitStandby(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('键盘弹起来时导航栏不许溢出：平板与小平板两档都验', (tester) async {
      // 待办页的输入框会唤起键盘，Scaffold 把页体压矮；左侧导航栏是竖排三颗
      // 带文字的目的地，压到一定程度就装不下（横屏手机上实测溢出 50px）
      for (final size in [const Size(1180, 820), const Size(960, 600)]) {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        tester.view.viewInsets = const FakeViewPadding(bottom: 600);
        await pumpShell(tester);
        await tapTab(tester, '待办');
        await tester.enterText(find.byType(TextField), '键盘起来了');
        await pumpFrames(tester, 4, const Duration(milliseconds: 60));
        expect(tester.takeException(), isNull,
            reason: '${size.width}×${size.height} 弹键盘时溢出');
      }
      // 横屏手机才是这条高度门限的理由：Pixel 7 AVD 2400×1080@2.625 → 914×411 逻辑，
      // 键盘 570 物理像素 = 217 逻辑，页体只剩 138 高，竖排三颗带文字的目的地装不下
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.625;
      tester.view.viewInsets = const FakeViewPadding(bottom: 570);
      await pumpShell(tester);
      await tapTab(tester, '待办');
      await tester.enterText(find.byType(TextField), '键盘起来了');
      await pumpFrames(tester, 4, const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull, reason: '横屏手机弹键盘时溢出');
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    testWidgets('竖屏 390×844：外壳三页与待机屏都不溢出', (tester) async {
      await phoneSurface(tester);
      await pumpShell(tester);
      expect(find.byType(ClockTimeDisplay), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '竖屏手机是这一版的主场景');

      await tapTab(tester, '待办');
      expect(find.byType(TodoPage), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tapTab(tester, '设置');
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tapTab(tester, '时间');
      await enterStandby(tester);
      expect(tester.takeException(), isNull);
      await exitStandby(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('时间页与待机屏', () {
    testWidgets('两处都展示 HH:MM:SS 翻页数字', (tester) async {
      await pumpShell(tester);
      expect(find.byType(ClockTimeDisplay), findsOneWidget);
      expect(await readClock(tester), '10:00:00');

      await enterStandby(tester);
      expect(find.byType(ClockTimeDisplay), findsOneWidget);
      expect(await readClock(tester), '10:00:00');
      expect(tester.takeException(), isNull);
    });

    testWidgets('时间页给得出起表与待机两组入口', (tester) async {
      await pumpShell(tester);
      expect(find.text('开始一段计时'), findsOneWidget);
      for (final min in AppConstants.countdownPresets) {
        expect(find.text('$min 分'), findsOneWidget, reason: '少了 $min 分这一档');
      }
      expect(find.text('自定义'), findsOneWidget);
      expect(find.text('回到时钟'), findsOneWidget);
      expect(find.text('进入待机'), findsOneWidget);
    });

    testWidgets('卡片顺序：读数 → 起表 →（计时中）→ 进入待机', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpShell(tester);

      double top(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(tester.getTopLeft(find.byType(ClockTimeDisplay)).dy,
          lessThan(top('开始一段计时')));
      expect(top('开始一段计时'), lessThan(top('进入待机')),
          reason: '待机是二级目的地，不能把起表挤出首屏');

      await tester.tap(find.text('25 分'));
      await pumpFrames(tester, 6, const Duration(milliseconds: 120));
      expect(top('开始一段计时'), lessThan(top('进行中')));
      expect(top('进行中'), lessThan(top('进入待机')));
      expect(tester.takeException(), isNull);
      await stopTicker(tester);
    });

    testWidgets('进待机清掉遗留的撤销条：全屏那层不压别的页的提示', (tester) async {
      await pumpShell(tester);
      await openTodo(tester);
      await tester.enterText(find.byType(TextField), '删掉我');
      await tester.tap(find.byIcon(Icons.add));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));
      await tester.tap(find.byIcon(Icons.delete_outline));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));
      expect(find.byType(SnackBar), findsOneWidget, reason: '删除后该有撤销条');

      await tapTab(tester, '时间');
      await enterStandby(tester);
      expect(find.byType(SnackBar), findsNothing,
          reason: '撤销条跟着铺进了全屏待机，压在大数字下面');
      await exitStandby(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('待机屏无操作 6 秒后退出键不可点，点一下唤回后仍能退出', (tester) async {
      await pumpApp(tester);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

      await tester.pump(const Duration(seconds: 7));
      await pumpFrames(tester, 4, const Duration(milliseconds: 100));

      // 隐藏态下按钮被 IgnorePointer/Opacity 屏蔽：这次点击命不中按钮，
      // 只会经由最外层 Listener 把控件唤回（warnIfMissed 关掉，miss 是预期）
      await tester.tap(find.byIcon(Icons.fullscreen_exit), warnIfMissed: false);
      await pumpFrames(tester, 4, const Duration(milliseconds: 100));
      expect(find.byType(StandbyView), findsOneWidget,
          reason: '控件隐藏时那一下不该把待机屏退掉');

      await exitStandby(tester);
      expect(find.byType(ClockPage), findsOneWidget);
    });

    testWidgets('关掉「控件自动隐藏」：已淡出的控件立刻叫回，且不再有 6 秒时间盒',
        (tester) async {
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 7));
      await pumpFrames(tester, 4, const Duration(milliseconds: 100));

      await appSettings()
          .update(settings().copyWith(autoHideChrome: false));
      await pumpFrames(tester, 4, const Duration(milliseconds: 100));
      expect(
          tester
              .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
              .every((a) => a.opacity == 1),
          isTrue,
          reason: '关掉这一档要把已经淡出的控件当场叫回来');

      // 再等一个 6 秒：这一档关掉后不该重新藏起来
      await tester.pump(const Duration(seconds: 7));
      await pumpFrames(tester, 4, const Duration(milliseconds: 100));
      expect(
          tester
              .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
              .every((a) => a.opacity == 1),
          isTrue,
          reason: '关掉自动隐藏后不许再次藏起');

      await openSettings(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(StorageService.getSetting('autoHideChrome', true), isFalse);
      await tester.scrollUntilVisible(find.text('控件自动隐藏'), 120,
          scrollable: settingsScrollable());
      expect(find.text('控件自动隐藏'), findsOneWidget,
          reason: '这一档必须在设置页里找得到');
    });

    testWidgets('「控件自动隐藏」的关法落盘：重启后控件仍然常驻', (tester) async {
      await StorageService.writeSettings({'autoHideChrome': false});
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 7));
      await pumpFrames(tester, 4, const Duration(milliseconds: 100));
      expect(
          tester
              .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
              .every((a) => a.opacity == 1),
          isTrue);

      await openSettings(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
    });
  });

  group('待办页', () {
    testWidgets('待办是一个标签页，不再是盖住半屏的抽屉', (tester) async {
      await pumpShell(tester);
      expect(find.byType(Drawer), findsNothing);

      await openTodo(tester);
      expect(find.byType(Drawer), findsNothing, reason: '抽屉那一套该整个退场');
      expect(find.byType(TodoPage), findsOneWidget);
      final page = tester.getRect(find.byType(TodoPage));
      final screen = tester.getRect(find.byType(AppShell));
      expect(page.left, greaterThanOrEqualTo(screen.left));
      expect(page.right, lessThanOrEqualTo(screen.right));
      expect(page.top, greaterThanOrEqualTo(screen.top));
      expect(page.bottom, lessThanOrEqualTo(screen.bottom));
      expect(find.text('还没有待办'), findsOneWidget);
      expect(find.text('暂无待办，添加一条吧'), findsOneWidget);
      expect(find.text('添加待办'), findsOneWidget,
          reason: '空状态要给得出下一步，不能只留一句话');
    });

    testWidgets('新增待办出现在列表里，输入框被清空', (tester) async {
      await pumpShell(tester);
      await openTodo(tester);

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
      expect(find.text('还剩 1 件 · 共 1 件'), findsOneWidget);
    });

    testWidgets('勾选完成后出现清除入口，清除后列表与存储都空', (tester) async {
      await pumpShell(tester);
      await openTodo(tester);

      await tester.enterText(find.byType(TextField), '背单词');
      await tester.tap(find.byIcon(Icons.add));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));

      await tester.tap(find.byType(Checkbox));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));
      expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);
      expect(find.text('清除已完成（1）'), findsOneWidget);
      expect(find.text('还剩 0 件 · 共 1 件'), findsOneWidget);

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
      await pumpShell(tester);
      await openTodo(tester);
      await tester.enterText(find.byType(TextField), '删掉我');
      await tester.tap(find.byIcon(Icons.add));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));

      await tester.tap(find.byIcon(Icons.delete_outline));
      await pumpFrames(tester, 5, const Duration(milliseconds: 60));
      expect(find.text('暂无待办，添加一条吧'), findsOneWidget);
      expect(StorageService.getTodoList(), isEmpty);
    });

    testWidgets('切到别的标签再回来，输入到一半的字还在', (tester) async {
      await pumpShell(tester);
      await openTodo(tester);
      await tester.enterText(find.byType(TextField), '写一半');

      await tapTab(tester, '时间');
      await tapTab(tester, '待办');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '写一半',
          reason: 'IndexedStack 保状态，切个标签不该把人打的字吃掉');
    });

    testWidgets('横屏手机弹键盘：待办页不溢出，输入行在键盘上方，空状态滚得到',
        (tester) async {
      // 两档都是实测溢出过的几何：914×411（Pixel 7 AVD，键盘 217 逻辑）页体剩 138 高，
      // 640×360（键盘 200 逻辑）只剩 104 高。原来进度标题那一行 + 空状态那一列都是
      // 死高度，分别溢出 50px 与 4px；现在标题让位、空状态改成够高居中不够就滚。
      for (final geo in [
        (const Size(2400, 1080), 2.625, 570.0),
        (const Size(1280, 720), 2.0, 400.0),
      ]) {
        final (physical, dpr, keyboardPx) = geo;
        final logical = physical / dpr;
        final keyboard = keyboardPx / dpr;
        tester.view.physicalSize = physical;
        tester.view.devicePixelRatio = dpr;
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardPx);
        await pumpShell(tester);
        await tapTab(tester, '待办');
        await tester.enterText(find.byType(TextField), '键盘起来了');
        await pumpFrames(tester, 4, const Duration(milliseconds: 60));
        expect(tester.takeException(), isNull,
            reason: '${logical.width}×${logical.height} 弹键盘时溢出');

        final field = tester.getRect(find.byType(TextField));
        expect(field.height, greaterThan(0), reason: '输入框塌成 0 高就没法打字了');
        expect(field.bottom, lessThanOrEqualTo(logical.height - keyboard),
            reason: '输入框被键盘盖住了');
        expect(find.text('还没有待办'), findsNothing,
            reason: '高度不够时进度标题要让位，标题栏已经写着「待办」');

        final emptyScroll = find.descendant(
            of: find.byType(TodoPage),
            matching: find.byType(SingleChildScrollView));
        expect(emptyScroll, findsOneWidget, reason: '空状态要能滚，不能靠缩字');
        await tester.drag(emptyScroll, const Offset(0, -120));
        await pumpFrames(tester, 4, const Duration(milliseconds: 60));
        expect(tester.takeException(), isNull, reason: '滚空状态时溢出');

        tester.view.resetViewInsets();
        await pumpFrames(tester, 4, const Duration(milliseconds: 60));
        expect(find.text('还没有待办'), findsOneWidget,
            reason: '键盘收起来后进度标题要回来');
        expect(tester.takeException(), isNull);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
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
      expect(find.text('重来'), findsOneWidget,
          reason: '彩蛋只换掉中间那块，底下芯片条还在：归零态不给死的「继续」');

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

    testWidgets('归零后那颗芯片是「重来」，点它用上一轮的时长原地再起', (tester) async {
      await pumpApp(tester);
      appSettings()
          .update(settings().copyWith(onFinish: FinishBehavior.stayZero));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));

      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 2));
      await tick(tester, const Duration(seconds: 2));
      await pumpFrames(tester, 6, const Duration(milliseconds: 80));
      expect(await readClock(tester), '00:00:00');

      // resumeCountdown 见 remainTime<=0 直接 return，那颗「继续」是点不动的死芯片
      expect(find.text('继续'), findsNothing,
          reason: '归零态还挂着「继续」等于给用户一个按了没反应的按钮');
      expect(find.text('重来'), findsOneWidget);

      await tapChip(tester, '重来');
      final state = container.read(clockNotifierProvider);
      expect(state.total, const Duration(seconds: 2),
          reason: '重来的约定是复用上一轮选的时长，不是回到某个预设');
      expect(state.isRunning, isTrue);
      expect(await readClock(tester), '00:00:02');
      await stopTicker(tester);
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
      // 起表入口在时间页，不在待机屏：待机屏只留「正在跑的这一段」的出口
      await pumpShell(tester);
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

      await pumpShell(tester);
      await tapChip(tester, '自定义');
      await pumpFrames(tester, 8, const Duration(milliseconds: 60));
      expect(find.text('自定义倒计时'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 输入框 + 4 个快捷键 + 开始按钮都得完整落在屏内
      for (final target in [
        find.byType(TextField),
        find.text('${AppConstants.countdownPresets.last}'),
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

      await pumpShell(tester);
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

  /// 底部那根细进度条：默认开着，能用设置关掉，且和「底层进度组件」互不重复。
  group('底部细进度条开关', () {
    testWidgets('默认在场，关掉后消失并落盘', (tester) async {
      await pumpApp(tester);
      expect(settings().showProgressBar, isTrue,
          reason: '老版本一直有这根条，加开关后默认档必须还是开');

      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 20));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      appSettings().update(settings().copyWith(showProgressBar: false));
      await pumpFrames(tester, 3, const Duration(milliseconds: 50));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(StorageService.getSetting('showProgressBar', true), isFalse);
      await stopTicker(tester);
    });

    testWidgets('实时时钟下开或关都不画条：进度条只属于倒计时', (tester) async {
      await pumpApp(tester);
      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason: '进度条是「还剩多久」的语义，实时模式下没有剩余时间可画');

      for (final on in [false, true]) {
        appSettings().update(settings().copyWith(showProgressBar: on));
        await pumpFrames(tester, 3, const Duration(milliseconds: 50));
        expect(find.byType(LinearProgressIndicator), findsNothing,
            reason: '开关只该影响倒计时画面，别把条塞进实时时钟');
      }
      expect(find.byType(ClockTimeDisplay), findsOneWidget);
    });

    testWidgets('选了沙漏时不画两遍：细条让位给进度组件', (tester) async {
      appSettings().update(settings()
          .copyWith(progressDecor: ProgressDecor.hourglass));
      await pumpApp(tester);
      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 20));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(find.byType(ProgressDecorView), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason: '同一个「还剩多久」在数字下方画两遍');
      await stopTicker(tester);
    });

    testWidgets('日出日落只当背景，细条照旧；这时用户的关必须算数', (tester) async {
      appSettings()
          .update(settings().copyWith(progressDecor: ProgressDecor.sky));
      await pumpApp(tester);
      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 20));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(find.byType(ProgressDecorView), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget,
          reason: 'sky 是垫在整屏底下的环境层，不占数字下方，细条得留着当读数');

      appSettings().update(settings().copyWith(showProgressBar: false));
      await pumpFrames(tester, 3, const Duration(milliseconds: 50));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await stopTicker(tester);
    });

    testWidgets('关掉的档写进设置库，重启后读回还是不画条', (tester) async {
      await pumpApp(tester);
      appSettings().update(settings().copyWith(showProgressBar: false));

      container.dispose();
      container = ProviderContainer(
        overrides: [clockSourceProvider.overrideWithValue(() => fakeNow)],
      );
      await pumpApp(tester);
      expect(settings().showProgressBar, isFalse);

      container.read(clockNotifierProvider.notifier)
          .startCountdown(const Duration(seconds: 20));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await stopTicker(tester);
    });
  });

  group('设置', () {
    testWidgets('切换数字样式后时间页字重变化并落盘', (tester) async {
      await pumpShell(tester);
      await openSettings(tester);
      expect(find.byType(SettingsPage), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('粗黑力量体'),
        settingsScrollable(),
        const Offset(0, -120),
      );
      await tester.ensureVisible(find.text('粗黑力量体'));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      await tester.tap(find.text('粗黑力量体'));
      await pumpFrames(tester, 6, const Duration(milliseconds: 50));
      expect(StorageService.getSetting('clockVisualStyle', ''), 'boldPower');

      // 设置不再是一层子路由，退回时间页就是点回那颗标签
      await tapTab(tester, '时间');
      expect(find.byType(ClockPage), findsOneWidget);

      final digits = tester.widgetList<Text>(find.descendant(
          of: find.descendant(
              of: find.byType(ClockPage), matching: find.byType(FlipCardWidget)),
          matching: find.byType(Text)));
      expect(digits, isNotEmpty);
      for (final d in digits) {
        expect(d.style?.fontWeight, FontWeight.w900,
            reason: '每一格数字都要跟着换字重，${d.data} 却没有');
      }
    });

    testWidgets('横屏手机（914×411 逻辑）设置页不溢出，预览与选项都留得住高度',
        (tester) async {
      // Pixel7 横屏：2400×1080 物理 / density 2.625 → 逻辑 914×411。
      // 外壳的标题栏 + 底部导航条先吃掉 136，这一页只剩 275 高：宽度还够就分栏，
      // 选项能拿到整段 275；上下叠会被预览切掉一半，只剩 135 滚不出几行。
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const screenSize = Size(2400 / 2.625, 1080 / 2.625);

      await pumpShell(tester);
      await openSettings(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
      // 411 高的屏幕不给左侧导航栏：竖排三颗带文字的目的地装不下，
      // 键盘再咬掉一半时实测溢出 50px
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      final previewHeight = tester.getSize(find.byType(StylePreview)).height;
      final optionsHeight = tester.getSize(settingsList()).height;
      expect(previewHeight, greaterThanOrEqualTo(100),
          reason: '预览矮于此就看不清翻页了');
      expect(optionsHeight, greaterThan(previewHeight),
          reason: '选项区是主操作区，不该比预览还矮');
      expect(optionsHeight, lessThanOrEqualTo(screenSize.height),
          reason: '选项区不能比屏幕还高');

      // 滚到底逐屏确认：任何一张选项卡片都不许横向越界
      final options = settingsList();
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
      await pumpShell(tester);
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

    testWidgets('分区重排后两块都滚得到：外框在「外观」卡里靠前，结束行为在后面',
        (tester) async {
      await pumpShell(tester);
      await openSettings(tester);
      final options = settingsList();

      await tester.dragUntilVisible(
          find.text('粗外框'), options, const Offset(0, -120));
      await tester.ensureVisible(find.text('粗外框'));
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

      await tester.dragUntilVisible(
          find.text('自动重新开始'), options, const Offset(0, -120));
      await tester.ensureVisible(find.text('自动重新开始'));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      await tester.tap(find.text('自动重新开始'));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      expect(StorageService.getSetting('onFinish', ''), 'autoRestart');
    });

    testWidgets('七张分区卡从上到下都在：外观→数字样式→翻页动画→进度→结束→屏幕与声音→关于',
        (tester) async {
      await pumpShell(tester);
      await openSettings(tester);
      final options = find.descendant(
          of: find.byType(SettingsPage), matching: find.byType(Scrollable));

      // 只往下滚：哪张卡排到了前面，后面的那张就永远滚不到，所以这一趟同时验了顺序
      final cards = <Finder>[
        find.text('外观'),
        find.text('数字样式'),
        find.textContaining('翻页动画（${FlipAnimStyle.values.length - 1} 种'),
        find.text('进度显示'),
        find.text('倒计时结束'),
        find.text('屏幕与声音'),
        find.text('关于'),
      ];
      for (final card in cards) {
        await tester.scrollUntilVisible(card, 160, scrollable: options);
        await pumpFrames(tester, 2, const Duration(milliseconds: 50));
        expect(card, findsOneWidget, reason: '这张分区卡滚不到，顺序或标题变了');
      }
    });

    testWidgets('翻页动画按分组族铺开，一族一个小标题', (tester) async {
      await pumpShell(tester);
      await openSettings(tester);
      final options = find.descendant(
          of: find.byType(SettingsPage), matching: find.byType(Scrollable));

      for (final family in flipAnimFamilies.keys) {
        await tester.scrollUntilVisible(find.text(family), 120,
            scrollable: options);
        await pumpFrames(tester, 2, const Duration(milliseconds: 50));
        expect(find.text(family), findsOneWidget,
            reason: '「$family」这一族没铺成小标题，芯片会挤成一整面墙');
      }
    });

    testWidgets('设置页点「底部细进度条」开关：状态翻转并落盘', (tester) async {
      await pumpShell(tester);
      await openSettings(tester);
      final options = find.descendant(
          of: find.byType(SettingsPage), matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(find.text('底部细进度条'), 160,
          scrollable: options);
      await tester.ensureVisible(find.text('底部细进度条'));
      await pumpFrames(tester, 2, const Duration(milliseconds: 50));

      await tester.tap(find.text('底部细进度条'));
      await pumpFrames(tester, 4, const Duration(milliseconds: 50));
      expect(settings().showProgressBar, isFalse);
      expect(StorageService.getSetting('showProgressBar', true), isFalse,
          reason: '开关只在当次会话生效等于没存，重启又回到开');
      expect(tester
          .widget<Switch>(find.descendant(
              of: find.ancestor(
                  of: find.text('底部细进度条'),
                  matching: find.byType(SwitchListTile)),
              matching: find.byType(Switch)))
          .value, isFalse);
    });
  });
}
