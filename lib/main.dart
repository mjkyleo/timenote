import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/storage_service.dart';
import 'core/providers/app_providers.dart';
import 'settings/enum_def.dart';
import 'flip_clock/clock_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 平板横屏优先
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await StorageService.init();
  runApp(const ProviderScope(child: TimeNoteApp()));
}

class TimeNoteApp extends ConsumerWidget {
  const TimeNoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeBase = ref.watch(
        appSettingsNotifierProvider.select((s) => s.themeBase));
    final isDark = themeBase == ThemeBase.dark;
    return MaterialApp(
      title: '时笺 TimeNote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueGrey, brightness: Brightness.dark),
      ),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: const ClockView(),
    );
  }
}
