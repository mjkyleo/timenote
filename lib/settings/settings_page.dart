import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/providers/app_providers.dart';
import '../flip_clock/flip_card_widget.dart';
import '../theme/ui_style.dart';
import 'enum_def.dart';
import 'style_picker.dart';

/// 设置页：底色 / 11 套界面风格 / 10 种数字样式 / 8 种翻页动画 / 速度 / 开关
///
/// 左侧（窄屏时上方）是实时预览：改任何一项都能立刻看到翻页效果，
/// 不必退回主屏去验证。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appSettingsNotifierProvider);
    final notifier = ref.read(appSettingsNotifierProvider.notifier);
    final isDark = appState.themeBase == ThemeBase.dark;
    final tokens =
        UiScope.maybeOf(context) ?? UiTokens.classic(isDark);
    final labelColor = tokens.fg;

    final options = _options(context, appState, labelColor, tokens, notifier.update);
    final preview = Padding(
      padding: const EdgeInsets.all(16),
      child: StylePreview(state: appState),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(uiLabelText(tokens, '设置')),
        backgroundColor: tokens.surface ?? tokens.bg,
        foregroundColor: tokens.fg,
      ),
      backgroundColor: tokens.bg,
      body: UiLayer(
        tokens: tokens,
        solid: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 只看宽度会把横屏手机当平板：812×319 下左栏 2:3 分走后预览占掉
            // 整屏高度、选项只剩 447 宽，所以高度不够就退回上下布局
            final wide = constraints.maxWidth >= 760 &&
                constraints.maxHeight >= 400;
            if (!wide) {
              // 预览按屏高比例给，横屏手机上不再固定吃掉 210 让选项只剩一条缝
              final previewHeight =
                  (constraints.maxHeight * 0.42).clamp(140.0, 240.0);
              return Column(
                children: [
                  SizedBox(height: previewHeight, child: preview),
                  Expanded(child: options),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 预览是配角：屏宽的一半在手机上会把选项挤成一条窄柱
                Expanded(flex: constraints.maxWidth >= 1000 ? 2 : 1, child: preview),
                Expanded(flex: constraints.maxWidth >= 1000 ? 3 : 2, child: options),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _options(
    BuildContext context,
    AppSettingsState appState,
    Color labelColor,
    UiTokens tokens,
    Future<void> Function(AppSettingsState) update,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        _sectionTitle(context, tokens, '底色模式'),
        _chips([
          for (final base in ThemeBase.values)
            buildStyleItem(
              context,
              base == ThemeBase.light ? '亮色（白）' : '暗色（黑）',
              appState.themeBase == base,
              () => update(appState.copyWith(themeBase: base)),
            ),
        ]),
        _sectionTitle(context, tokens, '界面风格（11 套整屏令牌）'),
        _chips([
          for (final u in UiStyle.values)
            buildStyleItem(
              context,
              uiStyleName(u),
              appState.uiStyle == u,
              () => update(appState.copyWith(uiStyle: u)),
              swatch: uiTokensFor(u, appState.themeBase == ThemeBase.dark),
            ),
        ]),
        _sectionTitle(context, tokens, '计时画面风格（10 种数字样式）'),
        _chips([
          for (final v in ClockVisualStyle.values)
            buildStyleItem(
              context,
              visualStyleName(v),
              appState.clockVisualStyle == v,
              () => update(appState.copyWith(clockVisualStyle: v)),
              labelStyle: labelStyleFor(v, labelColor),
            ),
        ]),
        _sectionTitle(context, tokens, '翻页动画样式（${FlipAnimStyle.values.length} 种）'),
        _chips([
          for (final v in FlipAnimStyle.values)
            buildStyleItem(
              context,
              flipAnimName(v),
              appState.flipAnimStyle == v,
              () => update(appState.copyWith(flipAnimStyle: v)),
            ),
        ]),
        _sectionTitle(context, tokens, '翻页动画速度'),
        _chips([
          for (final v in AnimSpeed.values)
            buildStyleItem(
              context,
              speedName(v),
              appState.animSpeed == v,
              () => update(appState.copyWith(animSpeed: v)),
            ),
        ]),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('屏幕常亮'),
          subtitle: const Text('立即生效，防止平板息屏'),
          value: appState.keepScreenOn,
          onChanged: (val) =>
              update(appState.copyWith(keepScreenOn: val)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('倒计时结束彩蛋'),
          subtitle: const Text(
              '归零后展示随机文案，${AppConstants.eggStaySeconds} 秒后自动切回'),
          value: appState.eggEnable,
          onChanged: (val) => update(appState.copyWith(eggEnable: val)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('提示音'),
          subtitle: const Text('倒计时结束时播放，与彩蛋开关互不影响'),
          value: appState.soundEnable,
          onChanged: (val) => update(appState.copyWith(soundEnable: val)),
        ),
        const SizedBox(height: 24),
        const Text('关于时笺 TimeNote',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          '平板离线翻页时钟 · 专注计时 + 待办 + 彩蛋\n'
          '纯离线运行，无登录，无广告\n'
          '开源协议：MIT',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, UiTokens tokens, String t) =>
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(uiLabelText(tokens, t), style: uiLabelStyle(context, tokens)),
      );

  /// 一组选项芯片：芯片自带 4 像素外边距，这里补齐到横竖都是 10 的统一间隙，
  /// 否则 11 套界面风格会散成高低不齐的 4-5 行
  Widget _chips(List<Widget> items) => Wrap(
        spacing: 2,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: items,
      );
}

/// 实时预览：交替两个时间以演示当前翻页动画
class StylePreview extends StatefulWidget {
  final AppSettingsState state;

  const StylePreview({super.key, required this.state});

  @override
  State<StylePreview> createState() => _StylePreviewState();
}

class _StylePreviewState extends State<StylePreview> {
  static const List<String> _samples = ['09:41', '10:10', '25:00'];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _samples.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final isDark = s.themeBase == ThemeBase.dark;
    final tokens = UiScope.maybeOf(context) ?? UiTokens.classic(isDark);
    return Container(
      decoration: BoxDecoration(
        color: tokens.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.muted.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FlipCardWidget(
                content: _samples[_index],
                animDur: AppConstants.animDurationOf(s.animSpeed),
                animStyle: s.flipAnimStyle,
                visualStyle: s.clockVisualStyle,
                themeBase: s.themeBase,
              ),
            ),
          ),
          Text(
            '${visualStyleName(s.clockVisualStyle)} · ${flipAnimName(s.flipAnimStyle)}',
            style: TextStyle(fontSize: 12, color: tokens.muted),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
