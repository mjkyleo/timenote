import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage_service.dart';
import '../../settings/enum_def.dart';

/// 应用设置状态
class AppSettingsState {
  final ThemeBase themeBase;
  final UiStyle uiStyle;
  final FlipAnimStyle flipAnimStyle;
  final ClockVisualStyle clockVisualStyle;
  final AnimSpeed animSpeed;
  final ProgressDecor progressDecor;
  final FinishBehavior onFinish;
  final PlateFrame plateFrame;
  final bool showProgressBar;
  final bool keepScreenOn;
  final bool soundEnable;

  /// 控件层是否 6 秒后自动隐藏（待机屏的沉浸式签名）；关掉就常驻
  final bool autoHideChrome;

  /// 待机屏的排向，设置里随时改（默认横屏，沿用原来的观感）；外壳三页不受它影响
  final AppOrientation orientation;

  AppSettingsState({
    required this.themeBase,
    required this.uiStyle,
    required this.flipAnimStyle,
    required this.clockVisualStyle,
    required this.animSpeed,
    required this.progressDecor,
    required this.onFinish,
    required this.plateFrame,
    required this.showProgressBar,
    required this.keepScreenOn,
    required this.soundEnable,
    this.autoHideChrome = true,
    this.orientation = AppOrientation.landscape,
  });

  AppSettingsState copyWith({
    ThemeBase? themeBase,
    UiStyle? uiStyle,
    FlipAnimStyle? flipAnimStyle,
    ClockVisualStyle? clockVisualStyle,
    AnimSpeed? animSpeed,
    ProgressDecor? progressDecor,
    FinishBehavior? onFinish,
    PlateFrame? plateFrame,
    bool? showProgressBar,
    bool? keepScreenOn,
    bool? soundEnable,
    bool? autoHideChrome,
    AppOrientation? orientation,
  }) {
    return AppSettingsState(
      themeBase: themeBase ?? this.themeBase,
      uiStyle: uiStyle ?? this.uiStyle,
      flipAnimStyle: flipAnimStyle ?? this.flipAnimStyle,
      clockVisualStyle: clockVisualStyle ?? this.clockVisualStyle,
      animSpeed: animSpeed ?? this.animSpeed,
      progressDecor: progressDecor ?? this.progressDecor,
      onFinish: onFinish ?? this.onFinish,
      plateFrame: plateFrame ?? this.plateFrame,
      showProgressBar: showProgressBar ?? this.showProgressBar,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      soundEnable: soundEnable ?? this.soundEnable,
      autoHideChrome: autoHideChrome ?? this.autoHideChrome,
      orientation: orientation ?? this.orientation,
    );
  }
}

final appSettingsNotifierProvider =
    NotifierProvider<AppSettingsNotifier, AppSettingsState>(
  AppSettingsNotifier.new,
);

class AppSettingsNotifier extends Notifier<AppSettingsState> {
  @override
  AppSettingsState build() {
    final themeRaw =
        StorageService.getSetting('themeBase', ThemeBase.system.name);
    final uiRaw = StorageService.getSetting('uiStyle', UiStyle.classic.name);
    final flipRaw = StorageService.getSetting(
        'flipAnimStyle', FlipAnimStyle.tickerRoll.name);
    final visualRaw = StorageService.getSetting(
        'clockVisualStyle', ClockVisualStyle.appleMinimal.name);
    final speedRaw =
        StorageService.getSetting('animSpeed', AnimSpeed.normal.name);
    final decorRaw =
        StorageService.getSetting('progressDecor', ProgressDecor.none.name);
    final finishRaw =
        StorageService.getSetting('onFinish', FinishBehavior.showEgg.name);
    final frameRaw =
        StorageService.getSetting('plateFrame', PlateFrame.follow.name);
    final barRaw = StorageService.getSetting('showProgressBar', true);
    final keepOn = StorageService.getSetting('keepScreenOn', true);
    final soundOn = StorageService.getSetting('soundEnable', true);
    final autoHide = StorageService.getSetting('autoHideChrome', true);
    final orientationRaw = StorageService.getSetting(
        'screenOrientation', AppOrientation.landscape.name);

    return AppSettingsState(
      themeBase: ThemeBase.values.firstWhere(
        (e) => e.name == themeRaw,
        orElse: () => ThemeBase.system,
      ),
      uiStyle: UiStyle.values.firstWhere(
        (e) => e.name == uiRaw,
        orElse: () => UiStyle.classic,
      ),
      flipAnimStyle: FlipAnimStyle.values.firstWhere(
        (e) => e.name == flipRaw,
        orElse: () => FlipAnimStyle.tickerRoll,
      ),
      clockVisualStyle: ClockVisualStyle.values.firstWhere(
        (e) => e.name == visualRaw,
        orElse: () => ClockVisualStyle.appleMinimal,
      ),
      animSpeed: AnimSpeed.values.firstWhere(
        (e) => e.name == speedRaw,
        orElse: () => AnimSpeed.normal,
      ),
      progressDecor: ProgressDecor.values.firstWhere(
        (e) => e.name == decorRaw,
        orElse: () => ProgressDecor.none,
      ),
      onFinish: FinishBehavior.values.firstWhere(
        (e) => e.name == finishRaw,
        orElse: () => FinishBehavior.showEgg,
      ),
      plateFrame: PlateFrame.values.firstWhere(
        (e) => e.name == frameRaw,
        orElse: () => PlateFrame.follow,
      ),
      showProgressBar: barRaw,
      keepScreenOn: keepOn,
      soundEnable: soundOn,
      autoHideChrome: autoHide,
      orientation: AppOrientation.values.firstWhere(
        (e) => e.name == orientationRaw,
        orElse: () => AppOrientation.landscape,
      ),
    );
  }

  Future<void> update(AppSettingsState newState) async {
    state = newState;
    await StorageService.writeSettings({
      'themeBase': newState.themeBase.name,
      'uiStyle': newState.uiStyle.name,
      'flipAnimStyle': newState.flipAnimStyle.name,
      'clockVisualStyle': newState.clockVisualStyle.name,
      'animSpeed': newState.animSpeed.name,
      'progressDecor': newState.progressDecor.name,
      'onFinish': newState.onFinish.name,
      'plateFrame': newState.plateFrame.name,
      'showProgressBar': newState.showProgressBar,
      'keepScreenOn': newState.keepScreenOn,
      'soundEnable': newState.soundEnable,
      'autoHideChrome': newState.autoHideChrome,
      'screenOrientation': newState.orientation.name,
    });
  }
}
