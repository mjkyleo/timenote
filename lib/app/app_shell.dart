import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/providers/app_providers.dart';
import '../core/system_ui.dart';
import '../flip_clock/clock_page.dart';
import '../settings/settings_page.dart';
import '../theme/ui_style.dart';
import '../todo/todo_page.dart';

/// App 外壳：底部三标签（时间 / 待办 / 设置），宽屏换成左侧 NavigationRail。
///
/// 这一层负责「像个 App」：进来就是一页一件事，入口常驻在底部；
/// 全屏沉浸的翻页大屏不再是根页，而是从「时间」页按一颗按钮进去的待机屏，
/// 所以排向与系统栏的锁法只在那一屏生效，这三页始终跟随系统旋转。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _pages = <Widget>[ClockPage(), TodoPage(), SettingsPage()];
  static const _titles = ['时间', '待办', '设置'];

  int _index = 0;

  @override
  void initState() {
    super.initState();
    AppSystemUi.enterApp();
    _applyWakelock(ref.read(appSettingsNotifierProvider).keepScreenOn);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  /// 常亮是整机属性：在待机屏之外也照设置生效，不然开关写「屏幕常亮」却只在待机管用
  void _applyWakelock(bool enabled) {
    if (enabled) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiScope.maybeOf(context) ??
        UiTokens.classic(Theme.of(context).brightness == Brightness.dark);

    ref.listen(appSettingsNotifierProvider.select((s) => s.keepScreenOn),
        (prev, next) {
      if (prev != null && prev != next) _applyWakelock(next);
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        // 高度门限比设置页高一截：竖排三颗带文字的导航目的地实测要 180 高
        // （键盘下只拿到 130.3，溢出 50），横屏手机整屏也才 411 高，
        // 所以这一档只给平板，手机横竖都用底部那条
        final wide = constraints.maxWidth >= 760 && constraints.maxHeight >= 600;
        final body = IndexedStack(index: _index, children: _pages);

        return Scaffold(
          backgroundColor: tokens.bg,
          appBar: AppBar(
            title: Text(uiLabelText(tokens, _titles[_index])),
            backgroundColor: tokens.surface ?? tokens.bg,
            foregroundColor: tokens.fg,
          ),
          // 窄屏：底部导航栏；宽屏：左侧导航栏，底部留白给手势区
          body: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _rail(tokens),
                    VerticalDivider(
                        width: 1, thickness: 1, color: tokens.muted),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide ? null : _bottomBar(tokens),
        );
      },
    );
  }

  Widget _bottomBar(UiTokens tokens) {
    return NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      backgroundColor: tokens.surface ?? tokens.bg,
      indicatorColor: (tokens.accentSelection ? tokens.accentInk : tokens.fg)
          .withValues(alpha: 0.18),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
            icon: Icon(Icons.schedule), label: '时间'),
        NavigationDestination(
            icon: Icon(Icons.checklist), label: '待办'),
        NavigationDestination(
            icon: Icon(Icons.settings), label: '设置'),
      ],
    );
  }

  Widget _rail(UiTokens tokens) {
    return NavigationRail(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      labelType: NavigationRailLabelType.all,
      backgroundColor: tokens.surface ?? tokens.bg,
      selectedIconTheme:
          IconThemeData(color: tokens.accentSelection ? tokens.accentInk : tokens.fg),
      unselectedIconTheme: IconThemeData(color: tokens.labelInk),
      selectedLabelTextStyle: TextStyle(color: tokens.fg, fontSize: 12),
      unselectedLabelTextStyle: TextStyle(color: tokens.labelInk, fontSize: 12),
      indicatorColor: (tokens.accentSelection ? tokens.accentInk : tokens.fg)
          .withValues(alpha: 0.18),
      destinations: const [
        NavigationRailDestination(
            icon: Icon(Icons.schedule), label: Text('时间')),
        NavigationRailDestination(
            icon: Icon(Icons.checklist), label: Text('待办')),
        NavigationRailDestination(
            icon: Icon(Icons.settings), label: Text('设置')),
      ],
    );
  }
}
