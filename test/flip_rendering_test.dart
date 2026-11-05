import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/constants.dart';
import 'package:timenote/flip_clock/flip_card_widget.dart';
import 'package:timenote/flip_clock/flip_renderer.dart';
import 'package:timenote/settings/enum_def.dart';
import 'package:timenote/settings/style_picker.dart';

/// 渲染层回归测试：
/// 1) 翻页动画在静止态必须只剩新数字（历史 bug：经典翻牌停在 180° 镜像态）
/// 2) 半途必须真的在动，且上叶绕中缝而不是绕中心（生硬的根因）
/// 3) 只有真的变了的格子才翻页
/// 4) 10 种数字样式必须两两可辨（历史 bug：只有字体名不同，字体未打包时画面完全一样）
/// 5) 数字必须自适应缩放，不能溢出屏幕
/// 6) 逐格错开起跑的动画必须真的错开，且总时长不许失控
void main() {
  const samples = <FlipAnimStyle, FlipRenderer>{
    FlipAnimStyle.flipCard: FlipCardRenderer(),
    FlipAnimStyle.pageCurl: PageCurlRenderer(),
    FlipAnimStyle.slideFlip: SlideFlipRenderer(),
    FlipAnimStyle.segmentFlip: SegmentFlipRenderer(),
    FlipAnimStyle.fadeFlip: FadeFlipRenderer(),
    FlipAnimStyle.tickerRoll: TickerRollRenderer(),
    FlipAnimStyle.dropSettle: DropSettleRenderer(),
    // 动效实验室第一批：翻折
    FlipAnimStyle.diagFold: DiagFoldRenderer(),
    FlipAnimStyle.bounceFlip: BounceFlipRenderer(),
    FlipAnimStyle.cardFlip: CardFlipRenderer(),
    // 动效实验室第一批：位移
    FlipAnimStyle.slideAcross: SlideAcrossRenderer(),
    FlipAnimStyle.cascade: CascadeRenderer(),
    // 动效实验室第一批：遮罩
    FlipAnimStyle.blind: BlindRenderer(),
    FlipAnimStyle.iris: IrisRenderer(),
    FlipAnimStyle.polygon: PolygonRenderer(),
    // 动效实验室第一批：形变
    FlipAnimStyle.crossfade: CrossfadeRenderer(),
    FlipAnimStyle.blurFocus: BlurFocusRenderer(),
    FlipAnimStyle.jelly: JellyRenderer(),
    // 动效实验室第二批：碎片
    FlipAnimStyle.pixelShuffle: PixelShuffleRenderer(),
    FlipAnimStyle.particleScatter: ParticleScatterRenderer(),
    FlipAnimStyle.shardBurst: ShardBurstRenderer(),
    // 动效实验室第二批：光学
    FlipAnimStyle.fluidDissolve: FluidDissolveRenderer(),
    FlipAnimStyle.liquidGlass: LiquidGlassRenderer(),
    FlipAnimStyle.crtScan: CrtScanlineRenderer(),
  };

  Widget bare(Widget child) => Directionality(
        textDirection: TextDirection.ltr,
        child: child,
      );

  const Widget newer = Text('12:35', textDirection: TextDirection.ltr);
  const Widget older = Text('12:34', textDirection: TextDirection.ltr);

  group('翻页动画静止态', () {
    for (final entry in samples.entries) {
      testWidgets('${entry.key} 结束时只剩新数字', (tester) async {
        await tester.pumpWidget(bare(entry.value.transition(
              newChild: newer,
              oldChild: older,
              t: 1,
        )));

        expect(find.text('12:34'), findsNothing,
            reason: '旧牌不许留在树里，否则下一次翻页会串位');
        expect(find.text('12:35'), findsOneWidget);
        // 静止态必须是完全平铺：既不能镜像也不能侧立成一条边
        for (final t
            in tester.widgetList<Transform>(find.byType(Transform))) {
          expect(t.transform[0], greaterThan(0.9),
              reason: '静止时不应左右镜像（rotateY 停在 π 会让 [0] == -1）');
          expect(t.transform[5], greaterThan(0.9),
              reason: '静止时不应上下镜像/侧立（数字会变成一条边）');
        }
        for (final f
            in tester.widgetList<Opacity>(find.byType(Opacity))) {
          expect(f.opacity, 1, reason: '静止时新数字不许是半透明的');
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('${entry.key} 半途每个进度都在动且不抛异常', (tester) async {
        for (final t in const [0.0, 0.2, 0.4, 0.55, 0.7, 0.85, 0.99]) {
          await tester.pumpWidget(bare(entry.value.transition(
                newChild: newer,
                oldChild: older,
                t: t,
          )));
          expect(tester.takeException(), isNull,
              reason: '${entry.key} 在 t=$t 渲染异常');
          final animated = find.byType(Transform).evaluate().isNotEmpty ||
              find.byType(FractionalTranslation).evaluate().isNotEmpty ||
              find.byType(Opacity).evaluate().isNotEmpty;
          expect(animated, isTrue,
              reason: '${entry.key} 在 t=$t 没有任何动画包装，等于没动画');
        }
      });

      testWidgets('${entry.key} 入场（没有旧牌）也能走完', (tester) async {
        for (final t in const [0.0, 0.5, 0.99]) {
          await tester.pumpWidget(bare(entry.value.transition(
                newChild: newer,
                t: t,
          )));
          expect(tester.takeException(), isNull,
              reason: '${entry.key} 入场在 t=$t 渲染异常');
        }
      });
    }

    testWidgets('经典翻牌绕中缝铰链，而不是整块绕中心 tipping', (tester) async {
      // 上叶的铰链必须贴在中缝（自己的下缘），下叶铰链贴在自己的上缘；
      // 绕中心转就变成「整块板子 tipping」，是原来手感生硬的直接原因
      Widget at(double t) => bare(const FlipCardRenderer().transition(
            newChild: newer,
            oldChild: older,
            t: t,
      ));
      await tester.pumpWidget(at(0.5));

      final hinges = tester
          .widgetList<Transform>(find.byType(Transform))
          .map((t) => t.alignment)
          .toList();
      expect(hinges, contains(Alignment.bottomCenter),
          reason: '上叶要绕下缘（=牌子中缝）翻，实测铰链：$hinges');
      expect(hinges, contains(Alignment.topCenter),
          reason: '下叶要绕上缘（=牌子中缝）落下，实测铰链：$hinges');

      // 翻到一半时上叶确实转到接近侧立（[5] == cos 角度），说明确实在翻而不是平移
      final upperAngle = tester
          .widgetList<Transform>(find.byType(Transform))
          .firstWhere((t) => t.alignment == Alignment.bottomCenter)
          .transform;
      expect(upperAngle[5], lessThan(0.5),
          reason: 't=0.5 时上叶应该已经倒下大半，实测缩放因子 ${upperAngle[5]}');
    });

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
      // 翻页收尾后旧数字要被彻底摘掉，只剩新的那一片
      expect(find.text('4'), findsNothing, reason: '翻页结束后不许留着旧数字');
      final transforms = tester
          .widgetList<Transform>(find.ancestor(
            of: find.text('5'),
            matching: find.byType(Transform),
          ))
          .toList();
      for (final t in transforms) {
        expect(t.transform[0], greaterThan(0.9), reason: '换数字后不应停在镜像态');
        expect(t.transform[5], greaterThan(0.9), reason: '换数字后不应停在侧立态');
      }
    });

    testWidgets('只有变了的格子翻页，没变的格子保持静止', (tester) async {
      Widget clock(String text) => FlipCardWidget(
            content: text,
            animDur: const Duration(milliseconds: 200),
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
      await tester.pump(const Duration(milliseconds: 80));

      // 整串只有最后一位变了：其余格子不该被卷进翻页
      for (final still in const ['1', '2', '3']) {
        expect(
          find.ancestor(
            of: find.text(still),
            matching: find.byType(Transform),
          ),
          findsNothing,
          reason: '$still 这一格没变，不该被施加任何翻转变换',
        );
      }
      expect(
        find.ancestor(of: find.text('5'), matching: find.byType(Transform)),
        findsWidgets,
        reason: '变了的格子必须真的在翻',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('混合轮换', () {
    testWidgets('连续翻页确实换效果，而不是永远同一种', (tester) async {
      Widget clock(String text) => FlipCardWidget(
            content: text,
            animDur: const Duration(milliseconds: 200),
            animStyle: FlipAnimStyle.autoMix,
            visualStyle: ClockVisualStyle.boldPower,
            themeBase: ThemeBase.dark,
          );

      Future<Set<String>> shapeAtHalfWay(String from, String to) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox(width: 400, height: 200, child: clock(from))),
        ));
        await tester.pumpAndSettle();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox(width: 400, height: 200, child: clock(to))),
        ));
        await tester.pump(const Duration(milliseconds: 60));
        // 只数牌子里的变换：MaterialApp 自带 4 个位移包装，会把中间态差异冲淡
        Finder inClock(Type t) => find.descendant(
              of: find.byType(FlipCardWidget),
              matching: find.byType(t),
            );
        final shapes = <String>{
          for (final tr in tester
              .widgetList<Transform>(inClock(Transform)))
            '${tr.alignment}:${tr.transform[5].toStringAsFixed(1)}',
          for (final f in tester
              .widgetList<FractionalTranslation>(inClock(FractionalTranslation)))
            'slide:${f.translation.dx.toStringAsFixed(1)},${f.translation.dy.toStringAsFixed(1)}',
        };
        return shapes;
      }

      final shapes = <Set<String>>{};
      const steps = [
        ('1', '2'),
        ('2', '3'),
        ('3', '4'),
        ('4', '5'),
        ('5', '6'),
      ];
      for (final step in steps) {
        shapes.add(await shapeAtHalfWay(step.$1, step.$2));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(shapes.length, greaterThan(2),
          reason: '连续 5 次翻页只看到 ${shapes.length} 种中间态，混合轮换没生效');
    });
  });

  group('动效批次登记', () {
    test('每种动画都登记了渲染器与中文名，能进池的都在池里', () {
      for (final s in FlipAnimStyle.values) {
        expect(getRenderer(s), isNot(isNull), reason: '$s 没有渲染器');
        expect(flipAnimName(s), isNotEmpty, reason: '$s 没有中文名');
        if (s == FlipAnimStyle.autoMix) continue;
        expect(samples.containsKey(s), isTrue,
            reason: '$s 没进渲染层回归样本，新加的动画会漏测');
        if (!poolExcludedStyles.contains(s)) {
          expect(flipMixCycle, contains(s),
              reason: '$s 既不是仅收尾也不是贵切片，就该被混合轮换用到');
        }
      }
    });

    test('中文名两两不同，用户在设置页里分得清', () {
      final names = {for (final s in FlipAnimStyle.values) flipAnimName(s)};
      expect(names.length, FlipAnimStyle.values.length);
    });

    test('仅收尾与高频慎用的动画不许进每秒轮换的池子', () {
      expect(flipMixCycle, isNot(contains(FlipAnimStyle.autoMix)));
      expect(
        flipMixCycle.toSet(),
        FlipAnimStyle.values
            .toSet()
            .difference({FlipAnimStyle.autoMix})
            .difference(poolExcludedStyles),
        reason: '池子必须正好等于「每秒可用」那一档，多一种少一种都是漏登记',
      );
      for (final s in {...finaleOnlyStyles, ...cautionStyles}) {
        expect(poolExcludedStyles, contains(s),
            reason: '$s 实验室标了仅收尾/高频慎用，却还留在轮换池里');
      }
    });

    test('25 档动画正好被分组卡盖住：新加动画没分组就会漏上设置页', () {
      final grouped = [for (final f in flipAnimFamilies.values) ...f];
      expect(grouped.toSet().length, grouped.length,
          reason: '同一档挂进两个分组，设置页会出现两颗都能选的重复芯片');
      expect(
        grouped.toSet(),
        FlipAnimStyle.values.toSet(),
        reason: '分组表少一档就有动画点不到，多一档说明新加的动画没登记',
      );
      expect(flipAnimFamilies.values.any((f) => f.isEmpty), isFalse,
          reason: '空分组会在设置页画出一个只有小标题、没有芯片的窗口');
    });

    testWidgets('碎片类的散开方向逐帧稳定，只会往原位收不会抖成噪点', (tester) async {
      // 散开向量靠 sin-hash 取种子（与 t 无关），所以同一块碎片每一帧都在同一条飞行线上
      Future<List<Offset>> piecesAt(FlipRenderer r, double t) async {
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: r.transition(
            newChild: const Text('8', textDirection: TextDirection.ltr),
            t: t,
          ),
        ));
        final list = tester
            .widgetList<FractionalTranslation>(find.byType(FractionalTranslation))
            .map((f) => f.translation)
            .toList();
        expect(list, isNotEmpty, reason: '$r 在 t=$t 没有碎片在飞');
        return list;
      }

      for (final r in const [
        PixelShuffleRenderer(),
        ParticleScatterRenderer(),
        ShardBurstRenderer(),
      ]) {
        final early = await piecesAt(r, 0.15);
        final middle = await piecesAt(r, 0.5);
        expect(middle.length, early.length,
            reason: '$r 半途碎片数量变了，说明有碎片提前消失或凭空冒出来');
        for (var i = 0; i < early.length; i++) {
          expect(early[i].distance, greaterThan(0),
              reason: '$r 第 $i 块碎片一开始就没散开');
          expect(early[i].dx * middle[i].dx + early[i].dy * middle[i].dy,
              greaterThanOrEqualTo(0),
              reason: '$r 第 $i 块碎片中途改了方向：${early[i]} → ${middle[i]}');
          expect(middle[i].distance, lessThanOrEqualTo(early[i].distance),
              reason: '$r 第 $i 块碎片越飞越远：${early[i]} → ${middle[i]}');
        }
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('逐格错开（级联）', () {
    Widget clock(String text, Duration dur) => FlipCardWidget(
          content: text,
          animDur: dur,
          animStyle: FlipAnimStyle.cascade,
          visualStyle: ClockVisualStyle.boldPower,
          themeBase: ThemeBase.dark,
        );

    double dyAt(WidgetTester tester, int cell) {
      final t = tester.widgetList<FractionalTranslation>(find.descendant(
        of: find.byKey(ValueKey('cell$cell')),
        matching: find.byType(FractionalTranslation),
      )).last;
      return t.translation.dy;
    }

    testWidgets('同一时刻越靠后的格子落得越少，且收尾能归位', (tester) async {
      const base = Duration(milliseconds: 200);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(width: 600, height: 300, child: clock('11:11', base))),
      ));
      await tester.pumpAndSettle();
      // 五个字符格同时变化，才有先后可比
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(width: 600, height: 300, child: clock('22:22', base))),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      final first = dyAt(tester, 0);
      final last = dyAt(tester, 4);
      expect(first, greaterThan(last),
          reason: '级联必须是从左往右依次落，实测首格 $first 末格 $last');
      expect(last, lessThan(0), reason: '末格此时应该还在格子上方没落到位');

      // 错开量按时长比例摊，末格最多晚 40% 落位，不许贴着下一次变化才到
      await tester.pumpAndSettle();
      // 只量自己这块牌子：空的 MaterialApp + Scaffold 里本来就挂着 4 个位移包装
      expect(
        find.descendant(
          of: find.byType(FlipCardWidget),
          matching: find.byType(FractionalTranslation),
        ),
        findsNothing,
        reason: '收尾后不许留下位移包装',
      );
      expect(tester.takeException(), isNull);
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
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('1234:56:78'), findsOneWidget,
          reason: '数字被拆成一格一格，整串读法必须仍然完整，不能逐字念');
      handle.dispose();

      // 整块翻页板（10 格）是唯一被 FittedBox 缩放的单元，量它才不会漏掉缩放
      final board = find.descendant(
          of: find.byType(FlipCardWidget), matching: find.byType(Row));
      final box = tester.getRect(board);
      expect(box.width, greaterThan(0));
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(220));
      expect(box.top, greaterThanOrEqualTo(0));
      expect(box.bottom, lessThanOrEqualTo(90));
    });

    testWidgets('每种动画 + 每种风格组合都能渲染', (tester) async {
      final handle = tester.ensureSemantics();
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
          expect(find.bySemanticsLabel('09:41'), findsOneWidget,
              reason: '$anim × $visual 组合应渲染出数字');
          expect(tester.takeException(), isNull,
              reason: '$anim × $visual 组合不应抛异常');
        }
      }
      handle.dispose();
    });
  });
}
