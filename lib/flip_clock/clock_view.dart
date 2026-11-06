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
import '../progress_decor/progress_decor.dart';
import '../settings/enum_def.dart';
import '../settings/settings_page.dart';
import '../theme/ui_style.dart';
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
  late final DateTime Function() _clockSource = ref.read(clockSourceProvider);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ProviderSubscription<ClockState> _clockSub;
  late final ProviderSubscription<bool> _wakelockSub;
  late final ProviderSubscription<AppOrientation> _orientationSub;

  @override
  void initState() {
    super.initState();
    _applyOrientation(ref.read(appSettingsNotifierProvider).orientation);
    // 待机翻页时钟：状态栏与导航条会毁掉整屏观感（模拟器实测可见 3:05 / LTE / 电量）。
    // immersiveSticky = 边缘滑动临时唤回后自动再隐藏；鸿蒙侧 flutter_ohos 的
    // PlatformPlugin.setSystemChromeEnabledSystemUIMode 显式实现了这个模式，不是空调用。
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 开始页与设置页都能改排向，改完得立刻生效，不能等下次启动
    _orientationSub = ref.listenManual(
      appSettingsNotifierProvider.select((s) => s.orientation),
      (prev, next) {
        if (prev != null && prev != next) _applyOrientation(next);
      },
    );
    _applyWakelock(ref.read(appSettingsNotifierProvider).keepScreenOn);
    // 倒计时归零 → 按「结束行为」那一档分发（停留 / 重开 / 彩蛋），外加提示音
    _clockSub = ref.listenManual(clockNotifierProvider, (prev, next) {
      final justFinished = prev != null &&
          prev.remainTime > Duration.zero &&
          next.remainTime == Duration.zero &&
          next.workMode == ClockWorkMode.countdown;
      if (justFinished) _onCountdownFinished(next.total);
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
    _orientationSub.close();
    WakelockPlus.disable();
    _alarm?.dispose();
    super.dispose();
  }

  /// 按用户在这一轮选的排向锁方向（横屏两档 / 竖屏两档）
  ///
  /// 只在这一次决定里锁：开始页不锁，进时钟才锁，退出 App 交给系统。
  void _applyOrientation(AppOrientation o) {
    SystemChrome.setPreferredOrientations(AppConstants.orientationsOf(o));
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
  ///
  /// 起表之后用户只要数字，倒计时按钮和右上角入口都算噪声；
  /// 待机屏和倒计时共用这一套自动隐藏，行为只有一处定义。
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
    // （accessibility.md › Hearing「Use haptics in addition to audio cues」）
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
    final tokens = UiScope.maybeOf(context) ??
        UiTokens.classic(Theme.of(context).brightness == Brightness.dark);
    // 「跟随系统」时把档位落到这一刻的黑/白，再交给渲染层
    final themeBase =
        resolveThemeBase(appSetting.themeBase, Theme.of(context).brightness);
    final fg = tokens.fg;

    // 设置页改完「控件自动隐藏」得当场生效，不必等下次触摸
    ref.listen(appSettingsNotifierProvider.select((s) => s.autoHideChrome),
        (prev, next) => _scheduleChromeHide());

    return Listener(
      onPointerDown: (_) => _pokeChrome(),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: tokens.bg,
        endDrawer: const TodoDrawer(),
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
                  _chrome(_controls(appSetting, clockState, notifier, tokens)),
                ],
              ),
              Positioned(
                top: 16,
                right: 20,
                child: _chrome(
                  SafeArea(
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
                          // Icons.menu 表意「导航抽屉」，这里开的是待办清单，
                          // 用清单自己的图标（icons.md › 图标与含义一致）
                          icon: const Icon(Icons.checklist, size: 28),
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

  Widget _controls(
    AppSettingsState appSetting,
    ClockState clockState,
    ClockNotifier notifier,
    UiTokens tokens,
  ) {
    final isCountdown = clockState.workMode == ClockWorkMode.countdown;
    final zeroed = isCountdown &&
        !clockState.isRunning &&
        clockState.remainTime == Duration.zero;
    final chips = <Widget>[
      for (final min in AppConstants.countdownPresets)
        _chip(
          tokens: tokens,
          label: '$min 分',
          selected: isCountdown &&
              clockState.total == Duration(minutes: min) &&
              clockState.isRunning,
          onTap: () => notifier.startCountdown(Duration(minutes: min)),
        ),
      _chip(
        tokens: tokens,
        label: '自定义',
        selected: false,
        icon: Icons.add_alarm,
        onTap: _askCustomCountdown,
      ),
      _chip(
        tokens: tokens,
        label: '时钟',
        selected: !isCountdown,
        onTap: notifier.switchRealtime,
      ),
      if (isCountdown)
        _chip(
          // 归零那一档「继续」是死的（resumeCountdown 见 remainTime<=0 直接 return），
          // 所以停留档下这颗芯片换成「重来」，用这一轮的 total 原地再起一次。
          tokens: tokens,
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
      if (isCountdown)
        _chip(
          tokens: tokens,
          label: '停止',
          selected: false,
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
    required UiTokens tokens,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final fg = tokens.fg;
    final ink = tokens.accentSelection ? tokens.accentInk : fg;
    final border = selected ? ink : fg.withValues(alpha: 0.32);
    final shape = tokens.chipRadius >= 900
        ? const StadiumBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.chipRadius));
    return ActionChip(
      // 芯片默认只有 32 高（SDK chip.dart 的 _kChipHeight），低于
      // buttons.md 要求的 44x44 命中区；用内衬把它撑到 44+，
      // 视觉上的胶囊形状不变。
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      label: Text(uiLabelText(tokens, label)),
      labelStyle: TextStyle(
          color: fg,
          letterSpacing: tokens.labelTracking * 0.3,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
      avatar: icon == null ? null : Icon(icon, size: 18, color: fg),
      backgroundColor:
          selected ? ink.withValues(alpha: 0.16) : Colors.transparent,
      side: BorderSide(color: border, width: tokens.chipStrokeWidth),
      shape: shape,
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
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
      // 横屏手机上软键盘会把弹窗可用高度压到 150 逻辑像素左右：AlertDialog 的外边距
      // 是 viewInsets + insetPadding 之和，非 scrollable 的 content 会被 Flexible 压成
      // 3 像素高，输入框整块消失（Pixel7 横屏实测）。三处一起改才留得住输入区。
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      title: const Text('自定义倒计时'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            // 不自动抢焦点：一抢焦点就弹键盘，弹窗立刻被压瘪；改成用户点输入框才弹，
            // 且 15/30/45/60 快捷键不需要键盘就能用。
            autofocus: false,
            keyboardType: TextInputType.number,
            maxLength: 3,
            decoration: InputDecoration(
              labelText: '分钟',
              hintText:
                  '${AppConstants.minCountdownMinutes}-${AppConstants.maxCountdownMinutes}',
              counterText: '',
              errorText: _error,
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
                  onPressed: () => Navigator.of(context).pop(min),
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
