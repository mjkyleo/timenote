import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/enum_def.dart';

/// 时钟状态
class ClockState {
  final ClockWorkMode workMode;
  final Duration remainTime;
  final bool isRunning;

  ClockState({
    required this.workMode,
    required this.remainTime,
    required this.isRunning,
  });

  ClockState copyWith({
    ClockWorkMode? workMode,
    Duration? remainTime,
    bool? isRunning,
  }) {
    return ClockState(
      workMode: workMode ?? this.workMode,
      remainTime: remainTime ?? this.remainTime,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}

final clockNotifierProvider = NotifierProvider<ClockNotifier, ClockState>(
  ClockNotifier.new,
);

class ClockNotifier extends Notifier<ClockState> {
  Timer? _timer;

  @override
  ClockState build() {
    return ClockState(
      workMode: ClockWorkMode.realtime,
      remainTime: Duration.zero,
      isRunning: false,
    );
  }

  void switchRealtime() {
    _stopTimer();
    state = state.copyWith(
      workMode: ClockWorkMode.realtime,
      remainTime: Duration.zero,
      isRunning: false,
    );
  }

  void startCountdown(Duration dur) {
    _stopTimer();
    state = state.copyWith(
      workMode: ClockWorkMode.countdown,
      remainTime: dur,
      isRunning: true,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final newRemain = state.remainTime - const Duration(seconds: 1);
      if (newRemain <= Duration.zero) {
        _stopTimer();
        state = state.copyWith(remainTime: Duration.zero, isRunning: false);
        return;
      }
      state = state.copyWith(remainTime: newRemain);
    });
  }

  void pauseCountdown() {
    _stopTimer();
    state = state.copyWith(isRunning: false);
  }

  void resumeCountdown() {
    if (state.remainTime <= Duration.zero) return;
    _stopTimer();
    state = state.copyWith(isRunning: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final newRemain = state.remainTime - const Duration(seconds: 1);
      if (newRemain <= Duration.zero) {
        _stopTimer();
        state = state.copyWith(remainTime: Duration.zero, isRunning: false);
        return;
      }
      state = state.copyWith(remainTime: newRemain);
    });
  }

  void stopCountdown() {
    _stopTimer();
    state = state.copyWith(remainTime: Duration.zero, isRunning: false);
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
