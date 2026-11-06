import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/providers/app_providers.dart';
import '../flip_clock/clock_view.dart';
import '../settings/enum_def.dart';
import '../settings/settings_page.dart' show StylePreview;
import '../settings/style_picker.dart';
import '../theme/ui_style.dart';

/// 开始页：App 打开后的第一屏，只做一件事——定方向，然后进时钟。
///
/// 之前 `main()` 一上来就把全应用锁成横屏：平板待机没问题，手机竖着拿就得先
/// 把机器转过来才能看清画面。现在方向变成这一页上两颗能直接按的芯片，
/// 默认仍是横屏（原来那套观感），点了当场转过去，所见即所得。
class StartView extends ConsumerWidget {
  const StartView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appSettingsNotifierProvider);
    final tokens = UiScope.maybeOf(context) ?? UiTokens.classic(false);
    final notifier = ref.read(appSettingsNotifierProvider.notifier);

    // 方向与导航都不等通道回执：setPreferredOrientations 是发出去就完事的
    // 单向调用（`await` 它在测试的 fake-async 里会挂住，真机也没必要让按钮等它）
    void choose(AppOrientation o) {
      notifier.update(appState.copyWith(orientation: o));
      SystemChrome.setPreferredOrientations(AppConstants.orientationsOf(o));
    }

    void start() {
      SystemChrome.setPreferredOrientations(
          AppConstants.orientationsOf(appState.orientation));
      // pushReplacement：时钟页就是新的根，返回键该退出 App，不该退回开始页
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => const ClockView(),
      ));
    }

    return Scaffold(
      backgroundColor: tokens.bg,
      body: UiLayer(
        tokens: tokens,
        solid: true,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 与设置页同一条门限：只看宽度会把横屏手机当平板
              final wide =
                  constraints.maxWidth >= 760 && constraints.maxHeight >= 400;
              final controls = _controls(
                  context, appState, tokens, choose, start,
                  wide: wide);
              final preview = Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: StylePreview(state: appState),
              );
              if (!wide) {
                final previewHeight =
                    (constraints.maxHeight * 0.4).clamp(140.0, 260.0);
                return Column(
                  children: [
                    SizedBox(height: previewHeight, child: preview),
                    Expanded(child: controls),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: preview),
                  Expanded(
                      flex: constraints.maxWidth >= 1000 ? 2 : 3,
                      child: controls),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    AppSettingsState appState,
    UiTokens tokens,
    ValueChanged<AppOrientation> choose,
    VoidCallback start, {
    required bool wide,
  }) {
    final theme = Theme.of(context);
    final items = [
      for (final o in AppOrientation.values)
        buildStyleItem(
          context,
          appOrientationName(o),
          appState.orientation == o,
          () => choose(o),
        ),
    ];

    // 一律可滚：横屏手机（914×411 逻辑）键盘一顶就只剩不到 200 高，
    // 摊成不可滚的 Column 会把「开始」挤出屏幕（accessibility.md › 各尺寸都要够得着）
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: ConstrainedBox(
          // 内容比视口矮时靠 minHeight 撑满、由 mainAxisAlignment 居中；
          // 比视口高就退成从顶部开始滚
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                wide ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Text(
                uiLabelText(tokens, '时笺 TimeNote'),
                style: uiLabelStyle(context, tokens, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                '离线翻页时钟 · 不登录、不广告\n先选一个拿手机的方式，再开始。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.labelInk,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              Text('屏幕排向',
                  style: TextStyle(
                      fontSize: 12, letterSpacing: 1, color: tokens.labelInk)),
              const SizedBox(height: 4),
              Wrap(spacing: 2, runSpacing: 2, children: items),
              const SizedBox(height: 24),
              Align(
                alignment: wide ? Alignment.centerLeft : Alignment.center,
                child: FilledButton.icon(
                  onPressed: start,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('开始'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(180, 52),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '进入后状态栏与导航条自动隐藏；方向可以在设置页「屏幕与声音」里随时改。',
                style: TextStyle(
                    fontSize: 12, height: 1.6, color: tokens.labelInk),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
