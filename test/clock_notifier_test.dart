import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/providers/clock_providers.dart';
import 'package:timenote/settings/enum_def.dart';

/// 用注入的假时钟 + FakeAsync 驱动 ClockNotifier：
/// 走时完全由时间源决定，不依赖真实睡眠，也不受机器负载影响。
void main() {
  late DateTime now;

  ProviderContainer buildContainer() {
    now = DateTime(2026, 11, 4, 9, 0, 0);
    final c = ProviderContainer(
      overrides: [clockSourceProvider.overrideWithValue(() => now)],
    );
    addTearDown(c.dispose);
    return c;
  }

  ClockNotifier notifierOf(ProviderContainer c) =>
      c.read(clockNotifierProvider.notifier);

  ClockState stateOf(ProviderContainer c) => c.read(clockNotifierProvider);

  group('ClockNotifier 倒计时走时', () {
    test('启动后展示完整时长，并按墙钟递减', () {
      fakeAsync((async) {
        final c = buildContainer();
        notifierOf(c).startCountdown(const Duration(seconds: 10));
        expect(stateOf(c).remainTime, const Duration(seconds: 10));
        expect(stateOf(c).workMode, ClockWorkMode.countdown);
        expect(stateOf(c).isRunning, isTrue);

        now = now.add(const Duration(seconds: 3));
        async.elapse(const Duration(milliseconds: 400));
        expect(stateOf(c).remainTime, const Duration(seconds: 7));
      });
    });

    test('剩余秒数向上取整，刚启动不会先跳掉一秒', () {
      fakeAsync((async) {
        final c = buildContainer();
        notifierOf(c).startCountdown(const Duration(seconds: 10));
        now = now.add(const Duration(milliseconds: 500));
        async.elapse(const Duration(milliseconds: 1000));
        expect(stateOf(c).remainTime, const Duration(seconds: 10));

        now = now.add(const Duration(milliseconds: 600));
        async.elapse(const Duration(milliseconds: 400));
        expect(stateOf(c).remainTime, const Duration(seconds: 9));
      });
    });

    test('同一整秒内的多次轮询不重复发布状态', () {
      fakeAsync((async) {
        final c = buildContainer();
        final emitted = <Duration>[];
        c.listen(
          clockNotifierProvider,
          (_, next) => emitted.add(next.remainTime),
        );
        notifierOf(c).startCountdown(const Duration(seconds: 30));
        final before = emitted.length;

        // 时间源没前进，250ms 轮询打了 8 次也应该是同一秒
        async.elapse(const Duration(seconds: 2));
        expect(emitted.length, before);

        now = now.add(const Duration(seconds: 1));
        async.elapse(const Duration(milliseconds: 400));
        expect(emitted.length, before + 1);
      });
    });

    test('归零后进入结束态并停表', () {
      fakeAsync((async) {
        final c = buildContainer();
        notifierOf(c).startCountdown(const Duration(seconds: 5));
        now = now.add(const Duration(seconds: 5));
        async.elapse(const Duration(milliseconds: 400));

        expect(stateOf(c).remainTime, Duration.zero);
        expect(stateOf(c).isRunning, isFalse);
        expect(stateOf(c).workMode, ClockWorkMode.countdown);

        async.elapse(const Duration(seconds: 30));
        expect(async.pendingTimers, isEmpty);
        expect(stateOf(c).remainTime, Duration.zero);
      });
    });

    test('暂停期间不消耗时间，继续后接着剩余时间走', () {
      fakeAsync((async) {
        final c = buildContainer();
        notifierOf(c).startCountdown(const Duration(seconds: 20));
        now = now.add(const Duration(seconds: 5));
        async.elapse(const Duration(milliseconds: 400));
        expect(stateOf(c).remainTime, const Duration(seconds: 15));

        notifierOf(c).pauseCountdown();
        now = now.add(const Duration(minutes: 3));
        async.elapse(const Duration(seconds: 3));
        expect(stateOf(c).remainTime, const Duration(seconds: 15));
        expect(stateOf(c).isRunning, isFalse);

        notifierOf(c).resumeCountdown();
        expect(stateOf(c).isRunning, isTrue);
        now = now.add(const Duration(seconds: 2));
        async.elapse(const Duration(milliseconds: 400));
        expect(stateOf(c).remainTime, const Duration(seconds: 13));
      });
    });

    test('归零后继续无效', () {
      fakeAsync((async) {
        final c = buildContainer();
        notifierOf(c).startCountdown(const Duration(seconds: 2));
        now = now.add(const Duration(seconds: 2));
        async.elapse(const Duration(milliseconds: 400));
        notifierOf(c).resumeCountdown();
        expect(stateOf(c).isRunning, isFalse);
      });
    });

    test('停止后回到实时时钟', () {
      fakeAsync((async) {
        final c = buildContainer();
        notifierOf(c).startCountdown(const Duration(minutes: 2));
        notifierOf(c).stopCountdown();
        expect(stateOf(c).workMode, ClockWorkMode.realtime);
        expect(stateOf(c).remainTime, Duration.zero);
        expect(stateOf(c).isRunning, isFalse);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('非正数的时长被忽略', () {
      fakeAsync((async) {
        final c = buildContainer();
        notifierOf(c).startCountdown(Duration.zero);
        expect(stateOf(c).workMode, ClockWorkMode.realtime);
      });
    });

    test('重复启动只保留一个定时器', () {
      fakeAsync((async) {
        final c = buildContainer();
        final n = notifierOf(c);
        n.startCountdown(const Duration(seconds: 30));
        n.startCountdown(const Duration(seconds: 10));
        async.elapse(const Duration(seconds: 2));
        expect(async.pendingTimers, hasLength(1));
        expect(stateOf(c).total, const Duration(seconds: 10));
      });
    });

    test('进度按比例增长且封顶为 1', () {
      fakeAsync((async) {
        final c = buildContainer();
        notifierOf(c).startCountdown(const Duration(seconds: 20));
        expect(stateOf(c).progress, 0);
        now = now.add(const Duration(seconds: 10));
        async.elapse(const Duration(milliseconds: 400));
        expect(stateOf(c).progress, closeTo(0.5, 0.06));
        now = now.add(const Duration(minutes: 5));
        async.elapse(const Duration(milliseconds: 400));
        expect(stateOf(c).progress, 1);
      });
    });
  });

  group('ClockNotifier 生命周期', () {
    test('实时模式下不产生定时器', () {
      fakeAsync((async) {
        final c = buildContainer();
        async.elapse(const Duration(seconds: 5));
        expect(stateOf(c).workMode, ClockWorkMode.realtime);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('provider 销毁后定时器被取消', () {
      // 该用例自己负责 dispose，因此不走 addTearDown
      now = DateTime(2026, 11, 4, 9, 0, 0);
      fakeAsync((async) {
        final c = ProviderContainer(
          overrides: [clockSourceProvider.overrideWithValue(() => now)],
        );
        c.read(clockNotifierProvider.notifier)
            .startCountdown(const Duration(minutes: 5));
        expect(async.pendingTimers, hasLength(1));
        c.dispose();
        async.elapse(const Duration(seconds: 30));
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
