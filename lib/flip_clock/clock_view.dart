import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/constants.dart';
import '../core/egg_service.dart';
import '../core/providers/app_providers.dart';
import '../core/providers/clock_providers.dart';
import '../settings/enum_def.dart';
import '../settings/settings_page.dart';
import '../todo/todo_drawer.dart';
import '../egg/egg_display.dart';
import 'clock_controller.dart';

/// 无操作后隐藏控件的时长；待机时钟场景下让画面回到纯数字
const Duration _chromeHideDelay = Duration(seconds: 6);

/// 主屏：时钟 / 倒计时 / 彩蛋 + 右上角设置与待办入口
class ClockView extends ConsumerStatefulWidget {
  const ClockView({super.key});

  @override
  ConsumerState<ClockView> createState() => _ClockViewState();
}

class _ClockViewState extends ConsumerState<ClockView> {
  bool _showEgg = false;
  String _eggText = '';
  bool _chromeVisible = true;
  Timer? _eggTimer;
  Timer? _chromeTimer;
  AudioPlayer? _alarm;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ProviderSubscription<ClockState> _clockSub;
  late final ProviderSubscription<bool> _wakelockSub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(AppConstants.landscapeOrientations);
    _applyWakelock(ref.read(appSettingsNotifierProvider).keepScreenOn);
    // 倒计时归零 → 提示音 + 彩蛋（避免在 build 内重复注册）
    _clockSub = ref.listenManual(clockNotifierProvider, (prev, next) {
      final justFinished = prev != null &&
          prev.remainTime > Duration.zero &&
          next.remainTime == Duration.zero &&
          next.workMode == ClockWorkMode.countdown;
      if (justFinished) _onCountdownFinished();
    });
    // 常亮开关需要即时生效，而不是等下次启动
    _wakelockSub = ref.listenManual(
      appSettingsNotifierProvider.select((s) => s.keepScreenOn),
      (prev, next) {
        if (prev != null && prev != next) _applyWakelock(next);
      },
    );
    _scheduleChromeHide();
  }

  @override
  void dispose() {
    _eggTimer?.cancel();
    _chromeTimer?.cancel();
    _clockSub.close();
    _wakelockSub.close();
    WakelockPlus.disable();
    _alarm?.dispose();
    super.dispose();
  }

  void _applyWakelock(bool enabled) {
    if (enabled) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _pokeChrome() {
    _scheduleChromeHide();
    if (!_chromeVisible) setState(() => _chromeVisible = true);
  }

  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(_chromeHideDelay, () {
      if (mounted && _chromeVisible) setState(() => _chromeVisible = false);
    });
  }

  Future<void> _onCountdownFinished() async {
    final setting = ref.read(appSettingsNotifierProvider);
    // 彩蛋先上屏：提示音走平台通道与文件 IO，不能把视觉反馈挡在后面
    if (setting.eggEnable && mounted) {
      setState(() {
        _eggText = EggService.getRandomQuote();
        _showEgg = true;
      });
      _eggTimer?.cancel();
      _eggTimer = Timer(
        const Duration(seconds: AppConstants.eggStaySeconds),
        _hideEgg,
      );
    }
    if (!setting.soundEnable) return;
    try {
      await (_alarm ??= AudioPlayer())
          .play(AssetSource('audio/alert.wav'));
    } catch (_) {
      // 音频缺失/解码失败时静默降级
    }
  }

  void _hideEgg() {
    _eggTimer?.cancel();
    if (!mounted || !_showEgg) return;
    setState(() => _showEgg = false);
    // 彩蛋收尾即本次计时结束：回到实时时钟，不留 00:00:00 死屏
    ref.read(clockNotifierProvider.notifier).switchRealtime();
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  Future<void> _askCustomCountdown() async {
    _pokeChrome();
    // controller 由弹窗自己持有并释放：在这里 dispose 会在退场动画期间
    // 被 TextField 重新监听，触发 "used after being disposed"
    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => const _CustomCountdownDialog(),
    );
    if (minutes == null || minutes < AppConstants.minCountdownMinutes) return;
    ref.read(clockNotifierProvider.notifier).startCountdown(
          Duration(minutes: minutes),
        );
  }

  @override
  Widget build(BuildContext context) {
    final appSetting = ref.watch(appSettingsNotifierProvider);
    final clockState = ref.watch(clockNotifierProvider);
    final notifier = ref.read(clockNotifierProvider.notifier);
    final isDark = appSetting.themeBase == ThemeBase.dark;
    final fg = isDark ? Colors.white : Colors.black;

    return Listener(
      onPointerDown: (_) => _pokeChrome(),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: isDark ? Colors.black : Colors.white,
        endDrawer: const TodoDrawer(),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showEgg ? _hideEgg : null,
                    child: _mainArea(appSetting, clockState),
                  ),
                ),
                if (clockState.workMode == ClockWorkMode.countdown)
                  _progressBar(clockState, fg),
                _controls(appSetting, clockState, notifier, fg),
              ],
            ),
            Positioned(
              top: 16,
              right: 20,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_chromeVisible,
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings, size: 28),
                          color: fg,
                          tooltip: '设置',
                          onPressed: _openSettings,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.menu, size: 28),
                          color: fg,
                          tooltip: '待办清单',
                          onPressed: () =>
                              _scaffoldKey.currentState?.openEndDrawer(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mainArea(
    AppSettingsState appSetting,
    ClockState clockState,
  ) {
    if (_showEgg) {
      return EggDisplay(text: _eggText, themeBase: appSetting.themeBase);
    }
    final clock = clockState.workMode == ClockWorkMode.realtime
        ? ClockTimeDisplay(
            animStyle: appSetting.flipAnimStyle,
            visualStyle: appSetting.clockVisualStyle,
            speed: appSetting.animSpeed,
            themeBase: appSetting.themeBase,
          )
        : CountdownDisplay(
            remain: clockState.remainTime,
            animStyle: appSetting.flipAnimStyle,
            visualStyle: appSetting.clockVisualStyle,
            speed: appSetting.animSpeed,
            themeBase: appSetting.themeBase,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: clock,
    );
  }

  Widget _progressBar(ClockState clockState, Color fg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: clockState.progress,
          minHeight: 5,
          backgroundColor: fg.withValues(alpha: 0.14),
          color: fg,
        ),
      ),
    );
  }

  Widget _controls(
    AppSettingsState appSetting,
    ClockState clockState,
    ClockNotifier notifier,
    Color fg,
  ) {
    final isCountdown = clockState.workMode == ClockWorkMode.countdown;
    final chips = <Widget>[
      for (final min in AppConstants.countdownPresets)
        _chip(
          label: '$min 分',
          selected: isCountdown &&
              clockState.total == Duration(minutes: min) &&
              clockState.isRunning,
          fg: fg,
          onTap: () => notifier.startCountdown(Duration(minutes: min)),
        ),
      _chip(
        label: '自定义',
        selected: false,
        fg: fg,
        icon: Icons.add_alarm,
        onTap: _askCustomCountdown,
      ),
      _chip(
        label: '时钟',
        selected: !isCountdown,
        fg: fg,
        onTap: notifier.switchRealtime,
      ),
      if (isCountdown)
        _chip(
          label: clockState.isRunning ? '暂停' : '继续',
          selected: false,
          fg: fg,
          icon: clockState.isRunning ? Icons.pause : Icons.play_arrow,
          onTap: clockState.isRunning
              ? notifier.pauseCountdown
              : notifier.resumeCountdown,
        ),
      if (isCountdown)
        _chip(
          label: '停止',
          selected: false,
          fg: fg,
          icon: Icons.stop,
          onTap: notifier.stopCountdown,
        ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: chips,
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required Color fg,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final border = selected ? fg : fg.withValues(alpha: 0.32);
    return ActionChip(
      label: Text(label),
      labelStyle: TextStyle(color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
      avatar: icon == null
          ? null
          : Icon(icon, size: 18, color: fg),
      backgroundColor: selected ? fg.withValues(alpha: 0.16) : Colors.transparent,
      side: BorderSide(color: border),
      shape: const StadiumBorder(),
      onPressed: onTap,
    );
  }
}

/// 自定义倒计时分钟数（1-600）
class _CustomCountdownDialog extends StatefulWidget {
  const _CustomCountdownDialog();

  @override
  State<_CustomCountdownDialog> createState() => _CustomCountdownDialogState();
}

class _CustomCountdownDialogState extends State<_CustomCountdownDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_controller.text.trim());
    if (minutes == null ||
        minutes < AppConstants.minCountdownMinutes ||
        minutes > AppConstants.maxCountdownMinutes) {
      setState(() => _error =
          '请输入 ${AppConstants.minCountdownMinutes}-${AppConstants.maxCountdownMinutes} 之间的分钟数');
      return;
    }
    Navigator.of(context).pop(minutes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义倒计时'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 3,
            decoration: InputDecoration(
              labelText: '分钟',
              counterText: '',
              errorText: _error,
              helperText:
                  '${AppConstants.minCountdownMinutes}-${AppConstants.maxCountdownMinutes} 分钟',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final min in const [15, 30, 45, 60])
                ActionChip(
                  label: Text('$min'),
                  onPressed: () {
                    _controller.text = '$min';
                    Navigator.of(context).pop(min);
                  },
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('开始'),
        ),
      ],
    );
  }
}
