import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants.dart';
import 'core/egg_service.dart';
import 'core/providers/app_providers.dart';
import 'core/storage_service.dart';
import 'settings/enum_def.dart';
import 'flip_clock/clock_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 平板横屏优先
  await SystemChrome.setPreferredOrientations(AppConstants.landscapeOrientations);
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

  static const Color _seed = Color(0xFF46586B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(
        appSettingsNotifierProvider.select((s) => s.themeBase == ThemeBase.dark));
    return MaterialApp(
      title: '时笺 TimeNote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: const ClockView(),
    );
  }
}
