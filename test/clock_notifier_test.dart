import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/providers/clock_providers.dart';

void main() {
  test('倒计时结束后 remainTime 归零且停止', () async {
    final notifier = ClockNotifier();
    notifier.startCountdown(const Duration(seconds: 1));
    await Future.delayed(const Duration(milliseconds: 1100));
    final state = notifier.state;
    expect(state.remainTime, Duration.zero);
    expect(state.isRunning, false);
    expect(state.workMode.toString(), contains('countdown'));
  });
}
