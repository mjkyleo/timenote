import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/enum_def.dart';

/// 可注入的时间源：生产用系统时钟，测试用假时钟
final clockSourceProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// 时钟状态
class ClockState {
  final ClockWorkMode workMode;

  /// 剩余时间（向上取整到秒，归零表示结束）
  final Duration remainTime;

  /// 本次倒计时总时长，用于进度展示
  final Duration total;
  final bool isRunning;

  const ClockState({
    required this.workMode,
    required this.remainTime,
    required this.total,
    required this.isRunning,
  });

  ClockState copyWith({
    ClockWorkMode? workMode,
    Duration? remainTime,
    Duration? total,
    bool? isRunning,
  }) {
    return ClockState(
      workMode: workMode ?? this.workMode,
      remainTime: remainTime ?? this.remainTime,
      total: total ?? this.total,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  /// 已消耗比例 0..1；非倒计时为 0
  double get progress {
    if (total.inMilliseconds <= 0) return 0;
    final consumed = total - remainTime;
    return (consumed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }
}

const ClockState _realtimeState = ClockState(
  workMode: ClockWorkMode.realtime,
  remainTime: Duration.zero,
  total: Duration.zero,
  isRunning: false,
);

final clockNotifierProvider = NotifierProvider<ClockNotifier, ClockState>(
  ClockNotifier.new,
);

class ClockNotifier extends Notifier<ClockState> {
  Timer? _ticker;
  DateTime? _deadline;

  @override
  ClockState build() {
    ref.onDispose(_stopTicker);
    return _realtimeState;
  }

  void switchRealtime() {
    _stopTicker();
    _deadline = null;
    state = _realtimeState;
  }

  void startCountdown(Duration dur) {
    if (dur <= Duration.zero) return;
    _deadline = _now().add(dur);
    state = ClockState(
      workMode: ClockWorkMode.countdown,
      remainTime: dur,
      total: dur,
      isRunning: true,
    );
    _startTicker();
  }

  void pauseCountdown() {
    if (!state.isRunning) return;
    _stopTicker();
    // 清空 deadline：暂停期间不消耗墙钟时间，remainTime 冻结在当前值
    _deadline = null;
    state = state.copyWith(isRunning: false);
  }

  void resumeCountdown() {
    if (state.isRunning || state.remainTime <= Duration.zero) return;
    _deadline = _now().add(state.remainTime);
    state = state.copyWith(isRunning: true);
    _startTicker();
  }

  /// 停止倒计时并回到实时时钟
  void stopCountdown() => switchRealtime();

  DateTime _now() => ref.read(clockSourceProvider)();

  /// 剩余时间，向上取整到整秒（避免刚启动就跳掉 1 秒）
  Duration _remainUntil(DateTime deadline) {
    final ms = deadline.difference(_now()).inMilliseconds;
    if (ms <= 0) return Duration.zero;
    return Duration(seconds: (ms + 999) ~/ 1000);
  }

  void _startTicker() {
    _stopTicker();
    _tick();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _tick() {
    final deadline = _deadline;
    if (deadline == null) return;
    final remain = _remainUntil(deadline);
    if (remain <= Duration.zero) {
      _stopTicker();
      _deadline = null;
      state = state.copyWith(remainTime: Duration.zero, isRunning: false);
      return;
    }
    // 只在整秒变化时发布状态，避免每秒之外的无谓重建
    if (remain.inSeconds == state.remainTime.inSeconds) return;
    state = state.copyWith(remainTime: remain);
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }
}
