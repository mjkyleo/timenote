import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/flip_clock/clock_page.dart';
import 'package:timenote/flip_clock/standby_view.dart';

/// 外壳与待机屏的测试脚手架。
///
/// App 的第一屏是外壳（时间 / 待办 / 设置三标签），全屏大数字的待机屏要从时间页
/// 按「进入待机」才进得到。路由动画按帧推进：单次 `pump(500ms)` 只会停在过渡的
/// 起始值，所以这几个 helper 都循环小步 pump（同 app_widget_test 里 `pumpFrames`
/// 记的那条环境约束）。

/// 点底部导航栏（窄屏）或左侧导航栏（宽屏）上的某个标签。
/// 只按标签文字，不按图标：图标 `Icons.settings` 在别处也可能出现。
Future<void> tapTab(WidgetTester tester, String label) async {
  final bar = find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label));
  final rail = find.descendant(
      of: find.byType(NavigationRail), matching: find.text(label));
  final target = bar.evaluate().isNotEmpty ? bar : rail;
  expect(target, findsOneWidget, reason: '找不到标签「$label」');
  await tester.tap(target);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// 从时间页进入待机屏；已经在待机屏时直接返回。
///
/// 循环的收尾条件写的是「外壳还在树上」而不是「待机屏出现了」：路由一过渡就
/// 能在树里找到待机屏，可那 300ms 里底下那页还没被摘掉，此时全局 finder 会把
/// 两屏的同款控件一起数进来（实测两条 LinearProgressIndicator）。
Future<void> enterStandby(WidgetTester tester) async {
  if (find.byType(StandbyView).evaluate().isNotEmpty) return;
  await tester.ensureVisible(find.text('进入待机'));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.text('进入待机'));
  for (var i = 0;
      i < 16 && find.byType(ClockPage).evaluate().isNotEmpty;
      i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(StandbyView), findsOneWidget,
      reason: '按了「进入待机」却没进待机屏');
}

/// 从待机屏退回外壳（点左上角那颗「退出待机」）。同样要等过渡走完。
Future<void> exitStandby(WidgetTester tester) async {
  if (find.byType(StandbyView).evaluate().isEmpty) return;
  await wakeChrome(tester);
  await tester.tap(find.byIcon(Icons.fullscreen_exit));
  for (var i = 0;
      i < 16 && find.byType(StandbyView).evaluate().isNotEmpty;
      i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(StandbyView), findsNothing);
}

/// 控件层淡出后芯片连点击一起屏蔽（真实用户会先点一下屏幕把它唤回）。
/// 测试里倒计时往往是程序起表，没有那一次点击，所以点芯片前先唤回。
/// 彩蛋在场时不唤：那一屏「点任意处」的语义是结束彩蛋，不是唤回控件。
Future<void> wakeChrome(WidgetTester tester) async {
  if (find.byType(StandbyView).evaluate().isEmpty) return;
  final faded = tester.widgetList<AnimatedOpacity>(find.descendant(
      of: find.byType(StandbyView), matching: find.byType(AnimatedOpacity)));
  if (!faded.any((a) => a.opacity < 0.5)) return;

  // 点主区任意处唤回控件层（`StandbyView` 外层的 Listener）；不能用
  // ClockTimeDisplay 当锚点——倒计时/彩蛋在场时那块会换成别的组件。
  await tester.tap(find.byType(StandbyView), warnIfMissed: false);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
