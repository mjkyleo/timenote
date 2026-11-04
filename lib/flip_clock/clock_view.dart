import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/providers/app_providers.dart';
import '../core/providers/clock_providers.dart';
import '../core/egg_service.dart';
import '../core/constants.dart';
import '../todo/todo_drawer.dart';
import '../settings/settings_page.dart';
import '../egg/egg_display.dart';
import 'clock_controller.dart';
import '../settings/enum_def.dart';

/// 主屏：时钟 / 倒计时 / 彩蛋 + 右上角汉堡与设置入口
class ClockView extends ConsumerStatefulWidget {
  const ClockView({super.key});

  @override
  ConsumerState<ClockView> createState() => _ClockViewState();
}

class _ClockViewState extends ConsumerState<ClockView> {
  DateTime _now = DateTime.now();
  Timer? _timer;
  bool _showEgg = false;
  String _eggText = '';
  final AudioPlayer _audioPlayer = AudioPlayer();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late ProviderSubscription<ClockState> _clockSub;

  @override
  void initState() {
    super.initState();
    // 平板横屏优先
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    EggService.loadQuotes();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
    // 一次性订阅倒计时归零 → 触发彩蛋（避免在 build 内重复注册）
    _clockSub = ref.listenManual(clockNotifierProvider, (prev, next) {
      if (prev != null &&
          prev.remainTime > Duration.zero &&
          next.remainTime == Duration.zero &&
          next.workMode == ClockWorkMode.countdown) {
        _triggerEgg();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final setting = ref.read(appSettingsNotifierProvider);
      if (setting.keepScreenOn) {
        WakelockPlus.enable();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clockSub.close();
    WakelockPlus.disable();
    _audioPlayer.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _triggerEgg() async {
    final setting = ref.read(appSettingsNotifierProvider);
    if (!setting.eggEnable) return;
    if (setting.soundEnable) {
      try {
        await _audioPlayer.play(AssetSource('audio/alert.wav'));
      } catch (_) {
        // 音频缺失/损坏时静默降级，不崩溃
      }
    }
    if (!mounted) return;
    setState(() {
      _eggText = EggService.getRandomQuote();
      _showEgg = true;
    });
    Future.delayed(const Duration(seconds: AppConstants.eggStaySeconds), () {
      if (mounted) {
        setState(() {
          _showEgg = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appSetting = ref.watch(appSettingsNotifierProvider);
    final clockState = ref.watch(clockNotifierProvider);
    final clockNotifier = ref.read(clockNotifierProvider.notifier);
    final bgColor =
        appSetting.themeBase == ThemeBase.dark ? Colors.black : Colors.white;
    final textColor =
        appSetting.themeBase == ThemeBase.dark ? Colors.white : Colors.black;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bgColor,
      endDrawer: const TodoDrawer(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 时钟 / 彩蛋主区域
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_showEgg) {
                setState(() {
                  _showEgg = false;
                });
              }
            },
            child: Center(
              child: _showEgg
                  ? EggDisplay(text: _eggText, themeBase: appSetting.themeBase)
                  : clockState.workMode == ClockWorkMode.realtime
                      ? ClockTimeDisplay(
                          time: _now,
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
                        ),
            ),
          ),
          // 右上角：设置 + 汉堡（待办抽屉）
          Positioned(
            top: 24,
            right: 24,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.settings, size: 28),
                    color: textColor,
                    tooltip: '设置',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsPage()),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.menu, size: 28),
                    color: textColor,
                    tooltip: '待办',
                    onPressed: () {
                      _scaffoldKey.currentState?.openEndDrawer();
                    },
                  ),
                ],
              ),
            ),
          ),
          // 底部操作区
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ...AppConstants.countdownPresets.map((min) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: ElevatedButton(
                        onPressed: () {
                          clockNotifier.startCountdown(Duration(minutes: min));
                        },
                        child: Text('$min min'),
                      ),
                    );
                  }),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => clockNotifier.switchRealtime(),
                    child: const Text('时钟'),
                  ),
                  if (clockState.workMode == ClockWorkMode.countdown) ...[n                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: clockState.isRunning
                          ? () => clockNotifier.pauseCountdown()
                          : () => clockNotifier.resumeCountdown(),
                      child: Text(clockState.isRunning ? '暂停' : '继续'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => clockNotifier.stopCountdown(),
                      child: const Text('停止'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
