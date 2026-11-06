import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants.dart';
import 'core/egg_service.dart';
import 'core/providers/app_providers.dart';
import 'core/storage_service.dart';
import 'settings/enum_def.dart';
import 'theme/ui_style.dart';
import 'flip_clock/clock_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 平板横屏优先
  await SystemChrome.setPreferredOrientations(AppConstants.landscapeOrientations);
  // 待机翻页时钟：状态栏与导航条会毁掉整屏观感（模拟器实测可见 3:05 / LTE / 电量）。
  // immersiveSticky = 边缘滑动临时唤回后自动再隐藏；鸿蒙侧 flutter_ohos 的
  // PlatformPlugin.setSystemChromeEnabledSystemUIMode 显式实现了这个模式，不是空调用。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  try {
    await StorageService.init();
  } catch (error) {
    // 存储不可用时仍然可用：当作不持久化的待机时钟，避免白屏
    debugPrint('TimeNote: 本地存储初始化失败，降级运行（$error）');
  }
  await EggService.loadQuotes();
  runApp(const ProviderScope(child: TimeNoteApp()));
}

class TimeNoteApp extends ConsumerWidget {
  const TimeNoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(
        appSettingsNotifierProvider.select((s) => s.themeBase));
    final uiStyle =
        ref.watch(appSettingsNotifierProvider.select((s) => s.uiStyle));

    // classic 沿用引入本层之前的种子色，保证 Material 组件观感一字不变
    ThemeData theme(Brightness brightness) {
      final isDark = brightness == Brightness.dark;
      final tokens = uiTokensFor(uiStyle, isDark);
      final seed =
          uiStyle == UiStyle.classic ? const Color(0xFF46586B) : tokens.accent;
      return ThemeData(
        useMaterial3: true,
        brightness: brightness,
        // 底色交给令牌；Material 组件（开关、输入框、按钮）跟随同一套强调色
        scaffoldBackgroundColor: tokens.bg,
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      );
    }

    return MaterialApp(
      title: '时笺 TimeNote',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: switch (choice) {
        ThemeBase.system => ThemeMode.system,
        ThemeBase.light => ThemeMode.light,
        ThemeBase.dark => ThemeMode.dark,
      },
      // builder 包住 Navigator，于是主屏 / 设置页 / 抽屉 / 弹窗共用同一份令牌；
      // 亮度取 Material 已经解析好的那一档，跟随系统时自动跟着翻转
      builder: (context, child) {
        final tokens = uiTokensFor(
            uiStyle, Theme.of(context).brightness == Brightness.dark);
        return UiScope(
          style: uiStyle,
          tokens: tokens,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const ClockView(),
    );
  }
}
