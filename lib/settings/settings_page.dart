import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/app_providers.dart';
import 'enum_def.dart';
import 'style_picker.dart';

/// 设置页：底色 / 10 种数字样式 / 5 种翻页动画 / 速度 / 开关
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  void initState() {
    super.initState();
    // 保持平板横屏约束
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appSettingsNotifierProvider);
    final appNotifier = ref.read(appSettingsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle('底色模式'),
          Row(
            children: [
              buildStyleItem(
                context,
                '亮色（白）',
                appState.themeBase == ThemeBase.light,
                () => appNotifier.update(
                    appState.copyWith(themeBase: ThemeBase.light)),
              ),
              buildStyleItem(
                context,
                '暗色（黑）',
                appState.themeBase == ThemeBase.dark,
                () => appNotifier.update(
                    appState.copyWith(themeBase: ThemeBase.dark)),
              ),
            ],
          ),
          _sectionTitle('计时画面风格（10 种数字样式）'),
          Wrap(
            children: ClockVisualStyle.values.map((v) {
              return buildStyleItem(
                context,
                visualStyleName(v),
                appState.clockVisualStyle == v,
                () => appNotifier.update(
                    appState.copyWith(clockVisualStyle: v)),
              );
            }).toList(),
          ),
          _sectionTitle('翻页动画样式（5 种）'),
          Wrap(
            children: FlipAnimStyle.values.map((v) {
              return buildStyleItem(
                context,
                flipAnimName(v),
                appState.flipAnimStyle == v,
                () =>
                    appNotifier.update(appState.copyWith(flipAnimStyle: v)),
              );
            }).toList(),
          ),
          _sectionTitle('翻页动画速度'),
          Wrap(
            children: AnimSpeed.values.map((v) {
              return buildStyleItem(
                context,
                speedName(v),
                appState.animSpeed == v,
                () => appNotifier.update(appState.copyWith(animSpeed: v)),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('屏幕常亮'),
            subtitle: const Text('默认开启，防止平板息屏'),
            value: appState.keepScreenOn,
            onChanged: (val) =>
                appNotifier.update(appState.copyWith(keepScreenOn: val)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('倒计时结束彩蛋'),
            subtitle: const Text('归零后展示随机文案，5 秒后自动切回'),
            value: appState.eggEnable,
            onChanged: (val) =>
                appNotifier.update(appState.copyWith(eggEnable: val)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('提示音'),
            subtitle: const Text('倒计时结束时播放提示音'),
            value: appState.soundEnable,
            onChanged: (val) =>
                appNotifier.update(appState.copyWith(soundEnable: val)),
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
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
}
