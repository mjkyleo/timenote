import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app_shell.dart';
import 'core/egg_service.dart';
import 'core/providers/app_providers.dart';
import 'core/storage_service.dart';
import 'settings/enum_def.dart';
import 'theme/ui_style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 方向和系统栏都不在这里定：外壳三页跟随系统，只有进「待机屏」那一层才锁
  // （见 app/app_shell.dart 与 flip_clock/standby_view.dart）
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
      // 第一屏就是 App 外壳：底部三标签，时间页里才有一键进入的待机屏
      home: const AppShell(),
    );
  }
}
