import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/providers/app_providers.dart';
import '../core/providers/clock_providers.dart';
import '../settings/enum_def.dart';
import '../theme/ui_style.dart';
import 'clock_controller.dart';
import 'controls.dart';
import 'standby_view.dart';

/// 「时间」标签页：现在几点 / 怎么起一段计时 / 正在跑的那段 / 要不要挂成待机屏。
///
/// 之前这些全挤在同一屏：大数字铺满、按钮贴在屏幕底下、右上角再挂两颗入口，
/// 手机竖着拿时读数和按钮互相抢地方。这里改成正常的一页一件事——
/// 读数收成一张卡，控件摊成能滚的分区，全屏大数字交给「进入待机」那一屏。
class ClockPage extends ConsumerWidget {
  const ClockPage({super.key});

  static const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSetting = ref.watch(appSettingsNotifierProvider);
    final clockState = ref.watch(clockNotifierProvider);
    final notifier = ref.read(clockNotifierProvider.notifier);
    final clockSource = ref.read(clockSourceProvider);
    final tokens = UiScope.maybeOf(context) ??
        UiTokens.classic(Theme.of(context).brightness == Brightness.dark);
    final isCountdown = clockState.workMode == ClockWorkMode.countdown;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _readoutCard(context, appSetting, clockState, tokens, clockSource,
            isCountdown),
        const SizedBox(height: 12),
        _startCard(context, tokens, clockState, notifier, isCountdown,
            (minutes) => notifier.startCountdown(Duration(minutes: minutes))),
        if (isCountdown) ...[
          const SizedBox(height: 12),
          _runningCard(context, tokens, clockState, notifier),
        ],
        // 待机是二级目的地，压在主动作下面：起表不能被它挤出首屏
        const SizedBox(height: 12),
        _standbyCard(context, tokens),
      ],
    );
  }

  /// 读数卡：实时走字与倒计时剩余共用一张卡，只是内容与副标题不同
  Widget _readoutCard(
    BuildContext context,
    AppSettingsState appSetting,
    ClockState clockState,
    UiTokens tokens,
    DateTime Function() clockSource,
    bool isCountdown,
  ) {
    // 高度跟着屏宽走并夹在两段之间：390 宽竖屏约 130，平板封顶 190，
    // 再高就把下面的分区挤出首屏
    final height = (MediaQuery.sizeOf(context).width * 0.34).clamp(104.0, 190.0);
    final themeBase =
        resolveThemeBase(appSetting.themeBase, Theme.of(context).brightness);
    final display = isCountdown
        ? CountdownDisplay(
            remain: clockState.remainTime,
            animStyle: appSetting.flipAnimStyle,
            visualStyle: appSetting.clockVisualStyle,
            speed: appSetting.animSpeed,
            themeBase: themeBase,
            plateFrame: appSetting.plateFrame,
          )
        : ClockTimeDisplay(
            now: clockSource,
            animStyle: appSetting.flipAnimStyle,
            visualStyle: appSetting.clockVisualStyle,
            speed: appSetting.animSpeed,
            themeBase: themeBase,
            plateFrame: appSetting.plateFrame,
          );
    final now = clockSource();
    final caption = isCountdown
        ? clockState.isRunning
            ? '倒计时进行中 · 本段 ${_durationLabel(clockState.total)}'
            : clockState.remainTime == Duration.zero
                ? '倒计时已结束'
                : '倒计时已暂停'
        : '${now.month} 月 ${now.day} 日 · 星期${_weekdays[(now.weekday - 1) % 7]}';

    return _card(
      context,
      tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: height, child: display),
          const SizedBox(height: 6),
          Text(caption,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: tokens.labelInk)),
        ],
      ),
    );
  }

  /// 待机入口：一键回到原来那套全屏大数字 + 控件自动隐藏
  Widget _standbyCard(BuildContext context, UiTokens tokens) {
    return _card(
      context,
      tokens,
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '待机屏\n全屏大数字、控件自动隐藏，挂桌角当床头钟。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () {
              // 撤销条挂在根 ScaffoldMessenger 上，会跟着铺进全屏待机那层；
              // 待机屏只该有大数字，进屏前把别的页遗留的提示清掉
              ScaffoldMessenger.of(context).clearSnackBars();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const StandbyView()),
              );
            },
            icon: const Icon(Icons.fullscreen),
            label: const Text('进入待机'),
          ),
        ],
      ),
    );
  }

  /// 起计时：预设档 + 自定义 + 回到实时
  Widget _startCard(
    BuildContext context,
    UiTokens tokens,
    ClockState clockState,
    ClockNotifier notifier,
    bool isCountdown,
    ValueChanged<int> start,
  ) {
    return _card(
      context,
      tokens,
      title: '开始一段计时',
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final min in AppConstants.countdownPresets)
            clockChip(
              tokens: tokens,
              label: '$min 分',
              selected: isCountdown &&
                  clockState.total == Duration(minutes: min) &&
                  clockState.isRunning,
              onTap: () => start(min),
            ),
          clockChip(
            tokens: tokens,
            label: '自定义',
            selected: false,
            icon: Icons.add_alarm,
            onTap: () async {
              // 与待机屏共用同一个弹窗：两处入口的约定必须一样
              final minutes = await askCustomCountdown(context);
              if (minutes != null && minutes >= AppConstants.minCountdownMinutes) {
                start(minutes);
              }
            },
          ),
          clockChip(
            tokens: tokens,
            label: '回到时钟',
            selected: !isCountdown,
            onTap: notifier.switchRealtime,
          ),
        ],
      ),
    );
  }

  /// 进行中：读数之外还要给得出「停掉它」，进度与控制都放这张卡
  Widget _runningCard(
    BuildContext context,
    UiTokens tokens,
    ClockState clockState,
    ClockNotifier notifier,
  ) {
    final zeroed =
        !clockState.isRunning && clockState.remainTime == Duration.zero;
    final track = tokens.fg.withValues(alpha: 0.14);
    final ink = tokens.accentSelection ? tokens.accentInk : tokens.fg;
    return _card(
      context,
      tokens,
      title: '进行中',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius:
                BorderRadius.circular(tokens.chipRadius.clamp(0, 8).toDouble()),
            child: LinearProgressIndicator(
              value: clockState.progress,
              minHeight: 6,
              backgroundColor: track,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              clockChip(
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
              clockChip(
                tokens: tokens,
                label: '停止',
                selected: false,
                icon: Icons.stop,
                onTap: notifier.stopCountdown,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _durationLabel(Duration d) => d.inMinutes >= 60
    ? '${d.inHours} 小时 ${d.inMinutes % 60} 分'
    : '${d.inMinutes} 分';

/// 与设置页同款的一张卡：一层 surface + 细描边
Widget _card(BuildContext context, UiTokens tokens,
        {String? title, required Widget child}) =>
    Material(
      color: tokens.surface ?? tokens.fg.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: tokens.muted.withValues(alpha: 0.32),
            width: tokens.chipStrokeWidth),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(uiLabelText(tokens, title),
                  style: uiLabelStyle(context, tokens)),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      ),
    );
