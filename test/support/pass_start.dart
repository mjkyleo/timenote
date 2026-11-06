import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/flip_clock/clock_view.dart';
import 'package:timenote/start/start_view.dart';

/// App 的第一屏是开始页，跑主屏回归的测试都要先按下「开始」才进得到时钟。
///
/// 路由动画按帧推进；旧路由要等过渡（300ms）结束后的那一帧才真的从树上摘掉，
/// 实测到 500ms，所以循环到开始页消失为止（同 app_widget_test 里 `pumpFrames`
/// 记的那条环境约束：单次 `pump(500ms)` 只会停在过渡的起始值）。
/// 开始页已经不在树上（用例会重复 `pumpWidget` 换 container）时直接返回。
Future<void> passStartScreen(WidgetTester tester) async {
  if (find.byType(StartView).evaluate().isEmpty) return;
  // 矮屏（914×411 逻辑再被键盘吃掉一截）上「开始」会滚出视口，先要回来再点
  await tester.ensureVisible(find.text('开始'));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.text('开始'));
  for (var i = 0; i < 12 && find.byType(StartView).evaluate().isNotEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 控件层淡出后芯片连点击一起屏蔽（真实用户会先点一下屏幕把它唤回）。
/// 测试里倒计时往往是程序起表，没有那一次点击，所以点芯片前先唤回。
/// 彩蛋在场时不唤：那一屏「点任意处」的语义是结束彩蛋，不是唤回控件。
Future<void> wakeChrome(WidgetTester tester) async {
  if (find.byType(ClockView).evaluate().isEmpty) return;
  final faded = tester.widgetList<AnimatedOpacity>(find.descendant(
      of: find.byType(ClockView), matching: find.byType(AnimatedOpacity)));
  if (!faded.any((a) => a.opacity < 0.5)) return;

  // 点主区任意处唤回控件层（`ClockView` 外层的 Listener）；不能用
  // ClockTimeDisplay 当锚点——倒计时/彩蛋在场时那块会换成别的组件。
  await tester.tap(find.byType(ClockView), warnIfMissed: false);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
