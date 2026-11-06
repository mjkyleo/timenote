import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/providers/app_providers.dart';
import '../core/update_check.dart';
import '../flip_clock/flip_card_widget.dart';
import '../theme/ui_style.dart';
import 'enum_def.dart';
import 'style_picker.dart';

/// 设置标签页（外壳的第三页）：七张分区卡（外观 / 数字样式 / 翻页动画 / 进度显示 /
/// 倒计时结束 / 屏幕与声音 / 关于），卡内再按小标签分组
///
/// 左侧（窄屏时上方）是实时预览：改任何一项都能立刻看到翻页效果，
/// 不必退回时间页去验证。标题栏由外壳给，这一页只负责页体。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appSettingsNotifierProvider);
    final notifier = ref.read(appSettingsNotifierProvider.notifier);
    // 这一页渲染出来是黑是白，看 Material 解析后的亮度：
    // 用户选「跟随系统」时 appState.themeBase 只是意图，不是结果
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tokens = UiScope.maybeOf(context) ?? UiTokens.classic(isDark);
    final labelColor = tokens.fg;

    final options =
        _options(context, appState, labelColor, tokens, notifier.update);
    final preview = Padding(
      padding: const EdgeInsets.all(16),
      child: StylePreview(state: appState),
    );

    return UiLayer(
      tokens: tokens,
      solid: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 这一页现在是外壳里的一个标签，标题栏 + 底部导航条先吃掉 136：
          // 横屏手机（914×411）只剩 275 高，但宽度还够两栏，分栏比上下叠
          // 更能给选项留出高度；宽度不够（竖屏手机）才退回上下布局
          final wide = constraints.maxWidth >= 760 && constraints.maxHeight >= 260;
          if (!wide) {
            // 预览按页体高度比例给，不再固定吃掉 210 让选项只剩一条缝
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
              Expanded(
                  flex: constraints.maxWidth >= 1000 ? 2 : 1, child: preview),
              Expanded(
                  flex: constraints.maxWidth >= 1000 ? 3 : 2, child: options),
            ],
          );
        },
      ),
    );
  }

  /// 选项区：七张分区卡，卡内再按「小标签 + 芯片墙」分组。
  ///
  /// 之前是九段标题直接摊在一条列表里，25 枚动画芯片糊成一面墙，找一个动画要逐行读；
  /// 现在动画按实验室原样分八小类，外框/结束/进度各自归到「外观 / 数字样式 / 翻页动画 /
  /// 进度显示 / 倒计时结束 / 屏幕与声音」里，一屏一类。
  Widget _options(
    BuildContext context,
    AppSettingsState appState,
    Color labelColor,
    UiTokens tokens,
    Future<void> Function(AppSettingsState) update,
  ) {
    Widget item(String label, bool selected, VoidCallback onTap,
            {TextStyle? labelStyle, UiTokens? swatch}) =>
        buildStyleItem(context, label, selected, onTap,
            labelStyle: labelStyle, swatch: swatch);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _card(context, tokens, '外观', [
          _group(tokens, '底色', [
            for (final base in ThemeBase.values)
              item(themeBaseName(base), appState.themeBase == base,
                  () => update(appState.copyWith(themeBase: base))),
          ]),
          _group(tokens, '界面风格（${UiStyle.values.length} 套整屏令牌）', [
            for (final u in UiStyle.values)
              item(uiStyleName(u), appState.uiStyle == u,
                  () => update(appState.copyWith(uiStyle: u)),
                  swatch: uiTokensFor(
                      u, Theme.of(context).brightness == Brightness.dark)),
          ]),
          _group(tokens, '数字外框（底板描边）', [
            for (final f in PlateFrame.values)
              item(plateFrameName(f), appState.plateFrame == f,
                  () => update(appState.copyWith(plateFrame: f))),
          ]),
          _hint(tokens, '外框只管描边这一层，底板的填充与光影仍跟着界面风格走。'),
        ]),
        _card(context, tokens, '数字样式', [
          _group(tokens, '计时画面（${ClockVisualStyle.values.length} 种）', [
            for (final v in ClockVisualStyle.values)
              item(visualStyleName(v), appState.clockVisualStyle == v,
                  () => update(appState.copyWith(clockVisualStyle: v)),
                  labelStyle: labelStyleFor(v, labelColor)),
          ]),
          _group(tokens, '动画速度', [
            for (final v in AnimSpeed.values)
              item(speedName(v), appState.animSpeed == v,
                  () => update(appState.copyWith(animSpeed: v))),
          ]),
        ]),
        _card(context, tokens,
            '翻页动画（${FlipAnimStyle.values.length - 1} 种 + 混合轮换）', [
          for (final entry in flipAnimFamilies.entries)
            _group(tokens, entry.key, [
              for (final v in entry.value)
                item(flipAnimName(v), appState.flipAnimStyle == v,
                    () => update(appState.copyWith(flipAnimStyle: v))),
            ]),
        ]),
        _card(context, tokens, '进度显示', [
          _switch(
              tokens,
              '底部细进度条',
              '倒计时时数字下方那一根；关掉画面只剩数字',
              appState.showProgressBar,
              (val) => update(appState.copyWith(showProgressBar: val))),
          _group(
              tokens, '底层进度组件（数字下方/背景，${ProgressDecor.values.length - 1} 种）', [
            for (final d in ProgressDecor.values)
              item(progressDecorName(d), appState.progressDecor == d,
                  () => update(appState.copyWith(progressDecor: d))),
          ]),
          _hint(
              tokens,
              '选其中一种会顶掉那根细进度条（同一个信息不画两遍）；'
              '「日出日落」是背景层，细条照旧留着当读数。'),
        ]),
        _card(context, tokens, '倒计时结束', [
          _group(tokens, '归零之后', [
            for (final b in FinishBehavior.values)
              item(finishBehaviorName(b), appState.onFinish == b,
                  () => update(appState.copyWith(onFinish: b))),
          ]),
          _hint(
              tokens,
              '自动重开用的是上一次选的那个时长；彩蛋展示 ${AppConstants.eggStaySeconds} 秒后切回实时时钟，'
              '文案完全随机。'),
        ]),
        _card(context, tokens, '屏幕与声音', [
          _group(tokens, '待机屏排向', [
            for (final o in AppOrientation.values)
              item(appOrientationName(o), appState.orientation == o,
                  () => update(appState.copyWith(orientation: o))),
          ]),
          _hint(tokens, '只管「进入待机」那一屏：待机时锁到这个方向，'
              '时间 / 待办 / 设置三页始终跟着手机当前拿法旋转。'),
          _switch(tokens, '屏幕常亮', '立即生效，防止平板息屏', appState.keepScreenOn,
              (val) => update(appState.copyWith(keepScreenOn: val))),
          _switch(tokens, '提示音', '倒计时结束时播放，与结束行为互不影响', appState.soundEnable,
              (val) => update(appState.copyWith(soundEnable: val))),
          // 暂停/停止是倒计时唯一的出口，定时藏掉它对慢的人不友好，所以给关掉的权利
          _switch(
              tokens,
              '控件自动隐藏',
              '无操作 6 秒后只剩数字，点屏幕任意处唤回；关掉则常驻',
              appState.autoHideChrome,
              (val) => update(appState.copyWith(autoHideChrome: val))),
        ]),
        _card(context, tokens, '关于', [
          Text(
            '时笺 TimeNote · 平板离线翻页时钟\n'
            '专注计时 + 待办 + 彩蛋文案\n'
            '不登录、不广告；除了你主动点下面「检查更新」那一次请求，App 不发任何网络包 · MIT\n'
            '当前构建：${buildSha.isEmpty ? '本地构建（没注构建号，比对不了）' : shortOf(buildSha)}',
            style: const TextStyle(fontSize: 13, height: 1.7),
          ),
          const UpdateCheckSection(),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  /// 一张分区卡：标题 + 卡内若干组。底色用风格给的 surface，没给就用一层淡前景。
  ///
  /// 用 [Material] 而不是 `Container`+`BoxDecoration`：卡里有 `SwitchListTile`，
  /// 它在最近的 Material 祖先上画背景与水波纹，卡在中间垫一层带色的 DecoratedBox
  /// 会把开关的点击反馈整个吃掉（Flutter 自己会断言报出来）。
  Widget _card(BuildContext context, UiTokens tokens, String title,
          List<Widget> body) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
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
                Row(
                  children: [
                    // 一小段强调色竖条当类目锚点，比纯文字标题更好扫
                    Container(
                      width: 3,
                      height: 14,
                      color: tokens.accentSelection
                          ? tokens.accentInk
                          : tokens.fg,
                    ),
                    const SizedBox(width: 8),
                    Text(uiLabelText(tokens, title),
                        style: uiLabelStyle(context, tokens)),
                  ],
                ),
                for (final w in body) w,
              ],
            ),
          ),
        ),
      );

  /// 卡内的一组：小标签在上，芯片墙在下
  Widget _group(UiTokens tokens, String label, List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                // 11px 正好压在 iPadOS 最小字号下限上，再叠 muted 的低对比就读不出了；
                // 抬到 12 并走 labelInk（令牌层已按 WCAG 兜到 4.5:1）
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w500,
                    color: tokens.labelInk)),
            // 芯片自带 4 像素外边距，这里补齐到横竖都是 10 的统一间隙
            Wrap(
                spacing: 2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: chips),
          ],
        ),
      );

  /// 开关行：与芯片同色系，标题/副标题都走令牌前景，暗风格下不会糊成灰底黑字
  Widget _switch(UiTokens tokens, String title, String subtitle, bool value,
          void Function(bool) onChanged) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: TextStyle(color: tokens.fg)),
          subtitle: Text(subtitle,
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: tokens.labelInk)),
          value: value,
          onChanged: (val) => onChanged(val),
        ),
      );

  /// 芯片组下面那行小字：三档结束行为这类「选完当场看不出差别」的组，
  /// 光靠芯片名说不清约定
  Widget _hint(UiTokens tokens, String text) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Text(text,
            style: TextStyle(fontSize: 12, height: 1.4, color: tokens.labelInk)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                themeBase:
                    resolveThemeBase(s.themeBase, Theme.of(context).brightness),
                plateFrame: s.plateFrame,
              ),
            ),
          ),
          Text(
            '${visualStyleName(s.clockVisualStyle)} · ${flipAnimName(s.flipAnimStyle)}',
            style: TextStyle(fontSize: 12, color: tokens.labelInk),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// 「检查更新」这一段：点了才发那一次请求，平时零请求。
///
/// 只报「云端是不是有更新的构建」，不下载、不安装——debug keystore 签名的包
/// 也只能靠用户自己下载重装，所以顺手给一条可复制的地址。
class UpdateCheckSection extends ConsumerStatefulWidget {
  const UpdateCheckSection({super.key});

  @override
  ConsumerState<UpdateCheckSection> createState() => _UpdateCheckSectionState();
}

class _UpdateCheckSectionState extends ConsumerState<UpdateCheckSection> {
  UpdateCheckResult? _result;
  bool _running = false;
  bool _copied = false;

  Future<void> _check() async {
    setState(() {
      _running = true;
      _copied = false;
    });
    final result = await checkForUpdate(ref.read(latestShaFetcherProvider));
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(
        const ClipboardData(text: devBuildReleaseUrl));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  String _message(UpdateCheckResult? r) {
    if (_running) return '正在问云端最新构建…';
    if (r == null) return '还没检查过：比对的是构建 commit，不会自动下载或安装。';
    switch (r.status) {
      case UpdateCheckStatus.upToDate:
        return '已是最新（构建 ${shortOf(buildSha)}）。';
      case UpdateCheckStatus.available:
        return '云端有更新的构建 ${r.remoteShort}，你这份是 ${shortOf(buildSha)}：'
            '复制地址下 APK 装上就是新版。';
      case UpdateCheckStatus.localBuild:
        return '本地构建没注构建号，比不了；云端最新是 ${r.remoteShort}。';
      case UpdateCheckStatus.failed:
        return '检查失败：没网络，或者云端还没发布过 dev-build 安装包。';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiScope.maybeOf(context) ?? UiTokens.classic(false);
    final accent =
        tokens.accentSelection ? tokens.accentInk : tokens.fg;
    final style = OutlinedButton.styleFrom(
      foregroundColor: accent,
      side: BorderSide(color: accent.withValues(alpha: 0.6)),
    );
    final canCopy = _result != null &&
        _result!.status != UpdateCheckStatus.failed &&
        _result!.status != UpdateCheckStatus.upToDate;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                style: style,
                onPressed: _running ? null : _check,
                child: Text(_running ? '检查中…' : '检查更新'),
              ),
              if (canCopy)
                OutlinedButton(
                  style: style,
                  onPressed: _copyLink,
                  child: Text(_copied ? '已复制' : '复制下载地址'),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message(_result),
                style: TextStyle(
                    fontSize: 12, height: 1.6, color: tokens.labelInk)),
          ),
        ],
      ),
    );
  }
}
