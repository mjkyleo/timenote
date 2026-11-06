import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/providers/app_providers.dart';
import 'package:timenote/core/providers/clock_providers.dart';
import 'package:timenote/core/storage_service.dart';
import 'package:timenote/flip_clock/flip_card_widget.dart';
import 'package:timenote/main.dart';
import 'package:timenote/settings/enum_def.dart';
import 'package:timenote/settings/style_picker.dart';
import 'package:timenote/theme/ui_style.dart';

import 'support/app_harness.dart';
import 'support/fake_storage.dart';
import 'support/fake_wakelock.dart';

void main() {
  group('令牌表完整性', () {
    test('每个界面风格都有亮/暗两版', () {
      for (final s in UiStyle.values) {
        final spec = uiStyleSpecs[s];
        expect(spec, isNotNull, reason: '$s 缺少令牌定义');
        expect(spec!.$1.bg, isNot(spec.$2.bg), reason: '$s 亮暗两版底色相同');
        expect(spec.$1.fg, isNot(spec.$2.fg), reason: '$s 亮暗两版前景相同');
        // 亮版必须真的更亮：这条能抓住注册表里 (亮, 暗) 写反的风格
        expect(spec.$1.bg.computeLuminance(),
            greaterThan(spec.$2.bg.computeLuminance()),
            reason: '$s 的亮版底色比暗版还暗，八成是两版写反了');
      }
    });

    test('每套令牌的前景都能从底色里跳出来', () {
      for (final entry in uiStyleSpecs.entries) {
        for (final tokens in [entry.value.$1, entry.value.$2]) {
          // 相对亮度差，不是 WCAG 对比率：只用来挡「fg 和 bg 撞色」
          final contrast =
              (tokens.fg.computeLuminance() - tokens.bg.computeLuminance())
                  .abs();
          expect(contrast, greaterThan(0.45),
              reason: '${entry.key} 的 fg/bg 对比过低（$contrast）');
        }
      }
    });

    test('文字用色全矩阵守住 WCAG 4.5:1（labelInk / accentInk）', () {
      // 皮肤给的 muted / accent 是装饰色，实测有 7 套亮色的 muted 不到 4.5:1
      // （复古印刷 2.63、视觉小说 3.20…），9 套的 accent 连满 alpha 都不够。
      // 标签与文字按钮一律走派生色，这里把底线钉住。
      for (final entry in uiStyleSpecs.entries) {
        for (final tokens in [entry.value.$1, entry.value.$2]) {
          final tag =
              '${entry.key}/${tokens == entry.value.$1 ? '亮' : '暗'}';
          // 面板色是半透明的，得先压到底色上才是屏幕上真正的那一层背景
          final backs = {
            tokens.bg,
            if (tokens.surface != null)
              compositeOver(tokens.surface!, tokens.bg),
          };
          for (final back in backs) {
            expect(contrastRatio(tokens.fg, back), greaterThanOrEqualTo(4.5),
                reason: '$tag fg 读不见');
            expect(contrastRatio(tokens.labelInk, back),
                greaterThanOrEqualTo(4.5),
                reason: '$tag labelInk 未达 4.5:1');
            expect(contrastRatio(tokens.accentInk, back),
                greaterThanOrEqualTo(4.5),
                reason: '$tag accentInk 未达 4.5:1');
          }
        }
      }
    });

    test('classic 不加任何底板装饰，其余风格至少加一种', () {
      for (final isDark in [false, true]) {
        expect(uiTokensFor(UiStyle.classic, isDark).hasPlateDecor, isFalse,
            reason: 'classic 必须与引入令牌层之前的渲染路径一致');
      }
      for (final s in UiStyle.values.where((e) => e != UiStyle.classic)) {
        expect(uiTokensFor(s, false).hasPlateDecor || uiTokensFor(s, true).hasPlateDecor,
            isTrue,
            reason: '$s 声称换了环境却没有任何底板装饰');
      }
    });

    test('除 classic 外每套都写明取色出处', () {
      for (final s in UiStyle.values.where((e) => e != UiStyle.classic)) {
        final p = uiTokensFor(s, false).provenance;
        expect(p, isNotEmpty, reason: '$s 没标 token 来源');
        expect(p.contains('page:') || p.contains('derived:'), isTrue,
            reason: '$s 的出处需要区分页面原值与推导值');
      }
    });

    testWidgets('未注入 UiScope 时按 Theme.brightness 回落到 classic',
        (tester) async {
      late UiTokens captured;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            captured = UiScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ));
      // 独立挂载、没有 UiScope 的控件不该拿到暗色令牌
      expect(captured.bg, uiTokensFor(UiStyle.classic, false).bg);
    });
  });

  group('风格真的画到界面上', () {
    late ProviderContainer container;

    ProviderContainer newContainer() => ProviderContainer(
          overrides: [
            // 冻结时间源：秒数不自己跳，翻页动画才不会同时挂着两份数字底板
            clockSourceProvider.overrideWithValue(
              () => DateTime(2026, 11, 4, 10, 0, 0),
            ),
          ],
        );

    setUp(() async {
      installFakeWakelock();
      await useMemoryStorage();
      await StorageService.writeSettings({'soundEnable': false});
      container = newContainer();
    });

    tearDown(() async {
      container.dispose();
      await releaseMemoryStorage();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TimeNoteApp(),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // 第一屏就是外壳的时间页，翻页读数已经在画面里，不用再过开始页
    }

    test('出厂默认底色是跟随系统', () {
      // 黑白底从「结果」变成「意图」：默认档交给平台亮度，手动档仍然覆盖它
      expect(container.read(appSettingsNotifierProvider).themeBase,
          ThemeBase.system,
          reason: 'R：默认改成固定黑或白要动这条');
    });

    test('出厂默认动画是滚筒走字', () {
      // setUp 只写过 soundEnable：效果类 key 全都不在箱里，走的正是默认值分支
      expect(container.read(appSettingsNotifierProvider).flipAnimStyle,
          FlipAnimStyle.tickerRoll,
          reason: 'R1 把默认动画定成了滚筒，改默认值要在这里钉住');
    });

    Future<void> pick(WidgetTester tester, UiStyle style, ThemeBase base) async {
      await container.read(appSettingsNotifierProvider.notifier).update(
          container
              .read(appSettingsNotifierProvider)
              .copyWith(uiStyle: style, themeBase: base));
      await pumpApp(tester);
    }
    testWidgets('选风格后主屏底色真的换成该风格的 bg', (tester) async {
      await pick(tester, UiStyle.classic, ThemeBase.dark);
      final scaffoldBefore = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffoldBefore.backgroundColor,
          uiTokensFor(UiStyle.classic, true).bg);

      await pick(tester, UiStyle.neumorphism, ThemeBase.dark);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFF23272E),
          reason: '切到软胶拟物后主屏底色应换成暗版 bg，而不是仍跟着黑白底走');
    });

    testWidgets('底色选「跟随系统」时，主屏按平台亮度落到黑或白', (tester) async {
      await pick(tester, UiStyle.classic, ThemeBase.system);

      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(tester.binding.platformDispatcher
          .clearPlatformBrightnessTestValue);
      await pumpApp(tester);
      expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          uiTokensFor(UiStyle.classic, true).bg,
          reason: '系统暗色时该落到暗版 bg');

      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      await pumpApp(tester);
      expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          uiTokensFor(UiStyle.classic, false).bg,
          reason: '切回系统亮色要立刻跟着变，不必重启');
    });

    testWidgets('带阴影的风格真的把阴影画到了数字底板上', (tester) async {
      await pick(tester, UiStyle.neumorphism, ThemeBase.light);
      final plate = tester
          .widget<Container>(find.byKey(const Key('flip-plate')))
          .decoration! as BoxDecoration;
      expect(plate.boxShadow, hasLength(2), reason: '软胶是一暗一亮双影');
      expect(plate.color, const Color(0xFFE0E5EC));

      await pick(tester, UiStyle.classic, ThemeBase.dark);
      expect(find.byKey(const Key('flip-plate')), findsNothing,
          reason: 'classic + 无底板数字样式不应出现装饰节点');
    });

    testWidgets('外框档位穿过设置一直打到主屏，不只是设置页预览动', (tester) async {
      Future<void> setFrame(PlateFrame frame) =>
          container.read(appSettingsNotifierProvider.notifier).update(
              container
                  .read(appSettingsNotifierProvider)
                  .copyWith(uiStyle: UiStyle.classic, plateFrame: frame));

      await setFrame(PlateFrame.follow);
      await pumpApp(tester);
      expect(find.byKey(const Key('flip-plate')), findsNothing,
          reason: 'classic 本就不该有底板装饰节点');

      await setFrame(PlateFrame.thin);
      await pumpApp(tester);
      final plate = tester
          .widget<Container>(find.byKey(const Key('flip-plate')))
          .decoration! as BoxDecoration;
      expect(plate.border?.top.width, 1.5,
          reason: '主屏没跟着档位走，说明设置值没穿过 ClockTimeDisplay');
      expect(StorageService.getSetting('plateFrame', ''), 'thin');

      await setFrame(PlateFrame.none);
      await pumpApp(tester);
      expect(find.byKey(const Key('flip-plate')), findsNothing);
    });

    testWidgets('11 套风格 × 黑白底色全矩阵冒烟：三页与待机屏都不报错',
        (tester) async {
      // IndexedStack 里没选中的两页走 Offstage：照样构建与布局，所以一次 pump
      // 就能验到三页的**构建期**异常。但 RenderFlex 溢出是 paint 阶段才报的，
      // Offstage 不 paint —— 溢出由各页自己的用例钉（切过去才炸），别指望这一条。
      await pumpApp(tester);
      for (final style in UiStyle.values) {
        for (final base in ThemeBase.values) {
          await pick(tester, style, base);
          expect(tester.takeException(), isNull,
              reason: '$style / $base 外壳三页渲染异常');

          await enterStandby(tester);
          expect(tester.takeException(), isNull,
              reason: '$style / $base 待机屏渲染异常');
          await exitStandby(tester);
          expect(tester.takeException(), isNull,
              reason: '$style / $base 退出待机后渲染异常');
        }
      }
    });

    testWidgets('选中的风格写进设置库，重启后读回', (tester) async {
      await pick(tester, UiStyle.retroVintage, ThemeBase.light);
      expect(StorageService.getSetting('uiStyle', ''), 'retroVintage');
      container.dispose();

      container = newContainer();
      await pumpApp(tester);
      expect(container.read(appSettingsNotifierProvider).uiStyle,
          UiStyle.retroVintage);
      expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          const Color(0xFFF5E6D3));
    });
  });

  group('数字外框档位', () {
    /// 一套「什么都没给」的令牌和几套「自带描边」的令牌，用来验档位说了算
    final noStroke = uiTokensFor(UiStyle.classic, true);
    final hairline = uiTokensFor(UiStyle.editorial, true);
    final heavy = uiTokensFor(UiStyle.retroVintage, true);

    test('follow 照抄令牌，none 一律去掉，thin/thick 一律补上', () {
      expect(resolvePlateFrame(PlateFrame.follow, hairline),
          (hairline.plateStroke, hairline.plateStrokeWidth));

      // 令牌里没描边的风格：档位要自己兜一个颜色，不能画成透明
      final (thinColor, thinWidth) = resolvePlateFrame(PlateFrame.thin, noStroke);
      expect(thinColor, isNotNull);
      expect(thinColor, noStroke.fg.withValues(alpha: 0.42));
      expect(thinWidth, 1.5);
      expect(resolvePlateFrame(PlateFrame.thick, noStroke).$2, 3);

      // 档位覆盖风格：复古印刷自带 3px 粗线，选细就得变细
      expect(heavy.plateStrokeWidth, 3, reason: '前提：复古印刷原样是 3px');
      expect(resolvePlateFrame(PlateFrame.thin, heavy).$2, 1.5);

      for (final tokens in [noStroke, hairline, heavy]) {
        expect(resolvePlateFrame(PlateFrame.none, tokens).$1, isNull,
            reason: '选了去掉外框还留线，这一档就等于没生效');
        expect(resolvePlateFrame(PlateFrame.thick, tokens).$1, isNotNull,
            reason: '选了粗外框却不画，风格没自带线时用户什么都看不到');
      }
    });

    testWidgets('档位真的改变主屏底板的描边节点', (tester) async {
      Widget board(PlateFrame frame) => MaterialApp(
            home: Scaffold(
              body: UiScope(
                style: UiStyle.classic,
                tokens: noStroke,
                child: Center(
                  child: FlipCardWidget(
                    content: '10:00',
                    animDur: const Duration(milliseconds: 450),
                    animStyle: FlipAnimStyle.crossfade,
                    visualStyle: ClockVisualStyle.appleMinimal,
                    themeBase: ThemeBase.dark,
                    plateFrame: frame,
                  ),
                ),
              ),
            ),
          );

      // classic + 苹果极简本是不加任何底板装饰的组合（上面已钉过）
      await tester.pumpWidget(board(PlateFrame.follow));
      await tester.pump();
      expect(find.byKey(const Key('flip-plate')), findsNothing);

      await tester.pumpWidget(board(PlateFrame.thick));
      await tester.pump();
      final plate = tester
          .widget<Container>(find.byKey(const Key('flip-plate')))
          .decoration! as BoxDecoration;
      expect(plate.border?.top.width, 3);
      expect(plate.color, isNull,
          reason: '外框档只管描边；底板填充与光影仍归界面风格，classic 没给就不该冒出来');

      await tester.pumpWidget(board(PlateFrame.none));
      await tester.pump();
      expect(find.byKey(const Key('flip-plate')), findsNothing,
          reason: '去掉外框后这对组合应回到无装饰路径');
      expect(tester.takeException(), isNull);
    });

    test('四档都有中文名且两两不同', () {
      final names = PlateFrame.values.map(plateFrameName).toList();
      expect(names.toSet(), hasLength(PlateFrame.values.length));
      expect(names.first, '跟随界面风格');
    });

    test('三档结束行为都有中文名且两两不同', () {
      final names = FinishBehavior.values.map(finishBehaviorName).toList();
      expect(names.toSet(), hasLength(FinishBehavior.values.length));
      expect(names, contains('停留 00:00:00'));
    });
  });

  test('quotes 之外的资源声明没有被这次改动破坏', () {
    // pubspec 声明的资产必须真实存在，否则 CI 的 asset bundle 会失败
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('assets/audio/alert.wav'), isTrue);
    expect(File('assets/audio/alert.wav').existsSync(), isTrue);
  });
}
