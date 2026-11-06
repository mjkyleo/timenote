import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/constants.dart';
import '../core/egg_service.dart';
import '../core/providers/app_providers.dart';
import '../core/providers/clock_providers.dart';
import '../core/system_ui.dart';
import '../progress_decor/progress_decor.dart';
import '../settings/enum_def.dart';
import '../theme/ui_style.dart';
import '../egg/egg_display.dart';
import 'clock_controller.dart';
import 'controls.dart';

/// 无操作后隐藏控件的时长；待机场景下让画面回到纯数字
const Duration _chromeHideDelay = Duration(seconds: 6);

/// 待机屏：从「时间」页按「进入待机」进来的全屏大屏。
///
/// 这一屏才是原来那个「平板离线翻页时钟」：锁排向、隐藏状态栏与导航条、控件
/// 6 秒自动淡出、归零走结束行为（停留 / 重开 / 彩蛋）。设置与待办不在这里挂
/// 入口 —— 它们各自是一个标签，退出去就在。
class StandbyView extends ConsumerStatefulWidget {
  const StandbyView({super.key});

  @override
  ConsumerState<StandbyView> createState() => _StandbyViewState();
}

class _StandbyViewState extends ConsumerState<StandbyView> {
  bool _showEgg = false;
  String _eggText = '';
  bool _chromeVisible = true;
  Timer? _eggTimer;
  Timer? _chromeTimer;
  AudioPlayer? _alarm;
  late final DateTime Function() _clockSource = ref.read(clockSourceProvider);
  late final ProviderSubscription<ClockState> _clockSub;

  @override
  void initState() {
    super.initState();
    // 排向在这一屏开屏时定一次：改排向的入口在「设置」标签，而待机屏盖在它上面，
    // 所以这里不需要再监听设置变化，退出去改完再进来就是新方向
    AppSystemUi.enterStandby(ref.read(appSettingsNotifierProvider).orientation);
    // 倒计时归零 → 按「结束行为」那一档分发（停留 / 重开 / 彩蛋），外加提示音
    _clockSub = ref.listenManual(clockNotifierProvider, (prev, next) {
      final justFinished = prev != null &&
          prev.remainTime > Duration.zero &&
          next.remainTime == Duration.zero &&
          next.workMode == ClockWorkMode.countdown;
      if (justFinished) _onCountdownFinished(next.total);
    });
    _scheduleChromeHide();
  }

  @override
  void dispose() {
    _eggTimer?.cancel();
    _chromeTimer?.cancel();
    _clockSub.close();
    // 退回外壳三页：系统栏要回来、旋转要交还给系统，否则导航栏一直被吞着
    AppSystemUi.enterApp();
    super.dispose();
  }

  void _pokeChrome() {
    _scheduleChromeHide();
    if (!_chromeVisible) setState(() => _chromeVisible = true);
  }

  /// 定时藏控件是待机屏的签名，但「暂停/停止」是倒计时唯一的出口，
  /// 给它设时间盒对需要更多时间的人不友好（accessibility.md › Cognitive），
  /// 所以这一条必须可以整体关掉；关掉时立刻把已经淡出的控件叫回来。
  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    if (!ref.read(appSettingsNotifierProvider).autoHideChrome) {
      if (mounted && !_chromeVisible) setState(() => _chromeVisible = true);
      return;
    }
    _chromeTimer = Timer(_chromeHideDelay, () {
      if (mounted && _chromeVisible) setState(() => _chromeVisible = false);
    });
  }

  /// 控件层：淡出后连点击一起屏蔽，点屏幕任意处唤回
  Widget _chrome(Widget child) => AnimatedOpacity(
        opacity: _chromeVisible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: IgnorePointer(ignoring: !_chromeVisible, child: child),
      );

  Future<void> _onCountdownFinished(Duration lastTotal) async {
    final setting = ref.read(appSettingsNotifierProvider);
    // 彩蛋先上屏：提示音走平台通道与文件 IO，不能把视觉反馈挡在后面
    if (setting.onFinish == FinishBehavior.showEgg && mounted) {
      setState(() {
        _eggText = EggService.getRandomQuote();
        _showEgg = true;
      });
      _eggTimer?.cancel();
      _eggTimer = Timer(
        const Duration(seconds: AppConstants.eggStaySeconds),
        _hideEgg,
      );
    } else if (setting.onFinish == FinishBehavior.autoRestart && mounted) {
      // 「上一次选的时长」就是这一轮的 total：连坐时不必再伸手点一遍
      ref.read(clockNotifierProvider.notifier).startCountdown(lastTotal);
    }
    // stayZero：什么都不做，屏幕留着 00:00:00
    // 触感与提示音是两条独立通道：静音或听不见的人靠这一次震动知道表走完了
    HapticFeedback.heavyImpact();
    if (!setting.soundEnable) return;
    try {
      await (_alarm ??= AudioPlayer()).play(AssetSource('audio/alert.wav'));
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

  @override
  Widget build(BuildContext context) {
    final appSetting = ref.watch(appSettingsNotifierProvider);
    final clockState = ref.watch(clockNotifierProvider);
    final notifier = ref.read(clockNotifierProvider.notifier);
    final tokens = UiScope.maybeOf(context) ??
        UiTokens.classic(Theme.of(context).brightness == Brightness.dark);
    final themeBase =
        resolveThemeBase(appSetting.themeBase, Theme.of(context).brightness);
    final fg = tokens.fg;

    // 设置页改完「控件自动隐藏」得当场生效，不必等下次触摸
    ref.listen(appSettingsNotifierProvider.select((s) => s.autoHideChrome),
        (prev, next) => _scheduleChromeHide());

    return Listener(
      onPointerDown: (_) => _pokeChrome(),
      child: Scaffold(
        backgroundColor: tokens.bg,
        body: UiLayer(
          tokens: tokens,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 日出日落是环境层，永远垫在最底下，不抢读数
              if (appSetting.progressDecor == ProgressDecor.sky &&
                  clockState.workMode == ClockWorkMode.countdown)
                Positioned.fill(
                  child: ProgressDecorView(
                    decor: ProgressDecor.sky,
                    progress: clockState.progress,
                    fg: fg,
                    accent: tokens.accentSelection ? tokens.accentInk : tokens.fg,
                    bg: tokens.bg,
                  ),
                ),
              Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _showEgg ? _hideEgg : null,
                      child: _mainArea(appSetting, clockState, themeBase),
                    ),
                  ),
                  // 进度条是「还在计时」的唯一凭据，沉浸式状态下也留着；
                  // 按钮是操作入口，藏起来才是沉浸
                  if (clockState.workMode == ClockWorkMode.countdown)
                    _progressArea(appSetting, clockState, tokens),
                  _chrome(_controls(clockState, notifier, tokens)),
                ],
              ),
              Positioned(
                top: 12,
                left: 16,
                child: SafeArea(
                  child: _chrome(
                    IconButton(
                      // 待机屏唯一的出口：图标说「退出全屏」，不是汉堡菜单
                      icon: const Icon(Icons.fullscreen_exit, size: 28),
                      color: fg,
                      tooltip: '退出待机',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mainArea(
    AppSettingsState appSetting,
    ClockState clockState,
    ThemeBase themeBase,
  ) {
    if (_showEgg) {
      return EggDisplay(text: _eggText, themeBase: themeBase);
    }
    final clock = clockState.workMode == ClockWorkMode.realtime
        ? ClockTimeDisplay(
            now: _clockSource,
            animStyle: appSetting.flipAnimStyle,
            visualStyle: appSetting.clockVisualStyle,
            speed: appSetting.animSpeed,
            themeBase: themeBase,
            plateFrame: appSetting.plateFrame,
          )
        : CountdownDisplay(
            remain: clockState.remainTime,
            animStyle: appSetting.flipAnimStyle,
            visualStyle: appSetting.clockVisualStyle,
            speed: appSetting.animSpeed,
            themeBase: themeBase,
            plateFrame: appSetting.plateFrame,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: clock,
    );
  }

  /// 进度层：选了 aux 组件就顶掉那根细条（同一个信息不画两遍）
  ///
  /// [ProgressDecor.sky] 例外——它是背景层，细条留着当读数。
  Widget _progressArea(
    AppSettingsState appSetting,
    ClockState clockState,
    UiTokens tokens,
  ) {
    final decor = appSetting.progressDecor;
    if (decor == ProgressDecor.none || decor == ProgressDecor.sky) {
      // 关了以后倒计时画面只剩数字本身：连「还在走」的凭据都不留
      return appSetting.showProgressBar
          ? _progressBar(clockState, tokens)
          : const SizedBox.shrink();
    }
    final band = (MediaQuery.sizeOf(context).height * 0.18).clamp(46.0, 104.0);
    return SizedBox(
      height: band,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ProgressDecorView(
          decor: decor,
          progress: clockState.progress,
          fg: tokens.fg,
          accent: tokens.accentSelection ? tokens.accentInk : tokens.fg,
          bg: tokens.bg,
        ),
      ),
    );
  }

  Widget _progressBar(ClockState clockState, UiTokens tokens) {
    final track = tokens.fg.withValues(alpha: 0.14);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: ClipRRect(
        // 复古印刷/编辑部这类直角风格把进度条也收成直角
        borderRadius:
            BorderRadius.circular(tokens.chipRadius.clamp(0, 8).toDouble()),
        child: LinearProgressIndicator(
          value: clockState.progress,
          minHeight: 5,
          backgroundColor: track,
          color: tokens.accentSelection ? tokens.accentInk : tokens.fg,
        ),
      ),
    );
  }

  /// 控制层：待机屏只留「正在跑的这一段」的出口，起什么表是「时间」页的事
  Widget _controls(ClockState clockState, ClockNotifier notifier,
      UiTokens tokens) {
    if (clockState.workMode != ClockWorkMode.countdown) {
      return const SizedBox.shrink();
    }
    final zeroed =
        !clockState.isRunning && clockState.remainTime == Duration.zero;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            clockChip(
              tokens: tokens,
              // 归零那一档「继续」是死的（resumeCountdown 见 remainTime<=0 直接 return），
              // 所以停留档下这颗芯片换成「重来」，用这一轮的 total 原地再起一次。
              label: zeroed
                  ? '重来'
                  : clockState.isRunning
                      ? '暂停'
                      : '继续',
              selected: false,
              icon: zeroed
                  ? Icons.refresh
                  : clockState.isRunning
                      ? Icons.pause
                      : Icons.play_arrow,
              onTap: clockState.isRunning
                  ? notifier.pauseCountdown
                  : zeroed
                      ? () => notifier.startCountdown(clockState.total)
                      : notifier.resumeCountdown,
            ),
            clockChip(
              tokens: tokens,
              label: '停止',
              selected: false,
              icon: Icons.stop,
              onTap: notifier.stopCountdown,
            ),
          ],
        ),
      ),
    );
  }
}
