import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/constants.dart';
import 'package:timenote/flip_clock/flip_card_widget.dart';
import 'package:timenote/flip_clock/flip_renderer.dart';
import 'package:timenote/settings/enum_def.dart';

/// 渲染层回归测试：
/// 1) 翻页动画在静止态必须回到完全可见（历史 bug：经典翻牌停在 180° 镜像态）
/// 2) 10 种数字样式必须两两可辨（历史 bug：只有字体名不同，字体未打包时画面完全一样）
/// 3) 数字必须自适应缩放，不能溢出屏幕
void main() {
  const samples = <FlipAnimStyle, FlipRenderer>{
    FlipAnimStyle.flipCard: FlipCardRenderer(),
    FlipAnimStyle.pageCurl: PageCurlRenderer(),
    FlipAnimStyle.slideFlip: SlideFlipRenderer(),
    FlipAnimStyle.segmentFlip: SegmentFlipRenderer(),
    FlipAnimStyle.fadeFlip: FadeFlipRenderer(),
  };

  Widget bare(Widget child) => Directionality(
        textDirection: TextDirection.ltr,
        child: child,
      );

  group('翻页动画静止态', () {
    for (final entry in samples.entries) {
      testWidgets('${entry.key} 结束时数字完全平铺', (tester) async {
        const settled = AlwaysStoppedAnimation<double>(1);
        final wrapped = entry.value.transition(
          const Text('12:34', textDirection: TextDirection.ltr),
          settled,
        );
        await tester.pumpWidget(bare(wrapped));

        var checked = 0;
        for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
          // 列主序：[0] 为 x 基向量的 x 分量（<0 即左右镜像），
          // [5] 为 y 基向量的 y 分量（≈0 即数字侧立成一条边，等于看不见）
          checked++;
          expect(
            t.transform[0],
            greaterThan(0.9),
            reason: '静止时不应左右镜像（rotateY 停在 π 会让 [0] == -1）',
          );
          expect(
            t.transform[5],
            greaterThan(0.9),
            reason: '静止时不应侧立/上下镜像（数字会变成一条边）',
          );
        }
        for (final s
            in tester.widgetList<ScaleTransition>(find.byType(ScaleTransition))) {
          checked++;
          expect(s.scale.value, closeTo(1, 0.001));
        }
        for (final s
            in tester.widgetList<SlideTransition>(find.byType(SlideTransition))) {
          checked++;
          expect(s.position.value, Offset.zero);
        }
        for (final f
            in tester.widgetList<FadeTransition>(find.byType(FadeTransition))) {
          checked++;
          expect(f.opacity.value, closeTo(1, 0.001));
        }
        expect(checked, greaterThan(0), reason: '过渡包装至少应包含一个动画组件');
      });
    }

    testWidgets('切换数字后仍会回到静止态，且不抛异常', (tester) async {
      Widget clock(String text) => FlipCardWidget(
            content: text,
            animDur: const Duration(milliseconds: 120),
            animStyle: FlipAnimStyle.flipCard,
            visualStyle: ClockVisualStyle.retroMechanical,
            themeBase: ThemeBase.dark,
          );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox(width: 600, height: 300, child: clock('12:34'))),
      ));
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox(width: 600, height: 300, child: clock('12:35'))),
      ));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // AnimatedSwitcher 会保留退场子节点直到下一次 build（此时它已转到侧立、不可见），
      // 所以只断言仍在展示的那个数字回到完全平铺
      final transforms = tester
          .widgetList<Transform>(find.ancestor(
            of: find.text('12:35'),
            matching: find.byType(Transform),
          ))
          .toList();
      expect(transforms, isNotEmpty);
      for (final t in transforms) {
        expect(t.transform[0], greaterThan(0.9),
            reason: '换数字后不应停在镜像态');
        expect(t.transform[5], greaterThan(0.9),
            reason: '换数字后不应停在侧立态');
      }
    });
  });

  group('10 种数字样式', () {
    test('每种样式都有显式外观配置', () {
      for (final s in ClockVisualStyle.values) {
        expect(clockLooks.containsKey(s), isTrue, reason: '$s 缺少外观配置');
        expect(AppConstants.styleFontMap.containsKey(s), isTrue,
            reason: '$s 缺少字体映射');
      }
    });

    test('两两之间至少有一个可见维度不同', () {
      final seen = <String, ClockVisualStyle>{};
      for (final s in ClockVisualStyle.values) {
        final look = appearanceFor(s);
        final style = clockTextStyle(
          look: look,
          foreground: Colors.black,
          fontFamily: null,
        );
        final signature = [
              look.weight,
              look.fontStyle,
              look.letterSpacing,
              look.sizeScale,
              look.strokeWidth,
              look.plateOpacity,
              look.radius,
              look.padding,
              look.seam,
              look.tabular,
              style.foreground?.style,
              style.fontFeatures?.length,
            ].join('|');
        final duplicated = seen[signature];
        expect(duplicated, isNull,
            reason: '$s 与 $duplicated 的外观参数完全相同，用户无法分辨');
        seen[signature] = s;
      }
      expect(seen.length, ClockVisualStyle.values.length);
    });

    test('镂空描边样式只描边不填充', () {
      final style = clockTextStyle(
        look: appearanceFor(ClockVisualStyle.hollowStroke),
        foreground: Colors.white,
        fontFamily: null,
      );
      expect(style.color, isNull);
      expect(style.foreground?.style, PaintingStyle.stroke);
    });
  });

  group('自适应缩放', () {
    testWidgets('极窄容器里数字不越界', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 90,
            child: FlipCardWidget(
              content: '1234:56:78',
              animDur: Duration(milliseconds: 100),
              animStyle: FlipAnimStyle.slideFlip,
              visualStyle: ClockVisualStyle.boldPower,
              themeBase: ThemeBase.light,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.text('1234:56:78'));
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(220));
      expect(box.top, greaterThanOrEqualTo(0));
      expect(box.bottom, lessThanOrEqualTo(90));
    });

    testWidgets('每种动画 + 每种风格组合都能渲染', (tester) async {
      for (final anim in FlipAnimStyle.values) {
        for (final visual in ClockVisualStyle.values) {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 500,
                height: 260,
                child: FlipCardWidget(
                  key: ValueKey('$anim-$visual'),
                  content: '09:41',
                  animDur: const Duration(milliseconds: 50),
                  animStyle: anim,
                  visualStyle: visual,
                  themeBase: visual.index.isEven ? ThemeBase.dark : ThemeBase.light,
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(find.text('09:41'), findsOneWidget,
              reason: '$anim × $visual 组合应渲染出数字');
          expect(tester.takeException(), isNull,
              reason: '$anim × $visual 组合不应抛异常');
        }
      }
    });
  });
}
