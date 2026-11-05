import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/providers/app_providers.dart';
import 'package:timenote/core/providers/clock_providers.dart';
import 'package:timenote/core/storage_service.dart';
import 'package:timenote/main.dart';
import 'package:timenote/progress_decor/progress_decor.dart';
import 'package:timenote/settings/enum_def.dart';
import 'package:timenote/settings/style_picker.dart';

import 'support/fake_storage.dart';
import 'support/fake_wakelock.dart';

const Color _accent = Color(0xFF00FF00);
const Color _fg = Color(0xFFFFFFFF);
const Size _band = Size(240, 100);

/// 一次光栅化的结果：只认画布上真实落下的像素
class _Raster {
  final Uint8List rgba;
  final int width;
  final int height;

  const _Raster({
    required this.rgba,
    required this.width,
    required this.height,
  });

  /// 完全不透明的纯 accent 像素数：抗锯齿边缘会混色，所以只数「实打实是这个色」的点，
  /// 用它来判「这一档进度到底画没画亮色」
  int get solidAccent {
    var n = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if (_isAccent(i, alpha: 255)) n++;
    }
    return n;
  }

  /// 第一条 accent 色像素所在行号，没有则返回高度
  ///
  /// 量水面不能量「有像素的第一行」——容器边框永远画在最上面一行。
  int get topAccentRow {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (_isAccent((y * width + x) * 4, alpha: null)) return y;
      }
    }
    return height;
  }

  /// 落笔的像素总数（含半透明），用来证明这一件真的画出了可见内容
  int get painted {
    var n = 0;
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] > 0) n++;
    }
    return n;
  }

  /// [rawRgba] 是预乘缓冲，[_accent] 又是纯绿：它的 r/b 恒为 0、g 恒等于 a，
  /// 所以认「r、b 归零且绿通道有值」比拿未预乘的 0/255/0 逐字节比对更稳
  bool _isAccent(int i, {required int? alpha}) =>
      rgba[i] == 0 &&
      rgba[i + 2] == 0 &&
      rgba[i + 1] > 0 &&
      (alpha == null ? rgba[i + 3] > 0 : rgba[i + 3] == alpha);
}

/// 把 painter 真的画到离屏位图上
///
/// 绘制指令的包围盒只能证明「调用过 draw」，裁剪掉的部分照样算在包围盒里；
/// 像素才证明「画面上的这一块真的多了东西」。
Future<_Raster> _raster(ProgressDecorPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), size);
  final picture = recorder.endRecording();
  final w = size.width.toInt();
  final h = size.height.toInt();
  final image = picture.toImageSync(w, h);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) throw StateError('测试环境取不到像素，这条断言等于没测');
  return _Raster(
      rgba: data.buffer.asUint8List(), width: w, height: h);
}

ProgressDecorPainter _painter(ProgressDecor d, double progress,
        {double tick = 0}) =>
    ProgressDecorPainter(
        decor: d, progress: progress, tick: tick, fg: _fg, accent: _accent);

void main() {
  group('进度层的数学与约定', () {
    test('remainOf 是唯一的「已消耗 → 剩余」映射', () {
      expect(remainOf(0), 1);
      expect(remainOf(1), 0);
      expect(remainOf(0.25), closeTo(0.75, 1e-9));
      // 越界要夹住：ClockState.progress 自己夹了，这层不能因为脏值画出负宽度
      expect(remainOf(-0.5), 1);
      expect(remainOf(1.5), 0);
      for (var i = 0; i < 10; i++) {
        expect(remainOf(i / 10), greaterThanOrEqualTo(remainOf((i + 1) / 10)),
            reason: '剩余量必须随进度单调递减');
      }
    });

    test('只有沙漏/水波/蜡烛挂连续动画', () {
      // 这三件有沙粒/水波/火苗，其余按进度画一次就够，挂 60fps Ticker 纯属费电
      expect(animatedProgressDecors, {
        ProgressDecor.hourglass,
        ProgressDecor.water,
        ProgressDecor.candle,
      });
      expect(animatedProgressDecors, isNot(contains(ProgressDecor.none)));
      expect(animatedProgressDecors, isNot(contains(ProgressDecor.sky)),
          reason: '日出日落是环境层，逐帧重绘整个背景吃不消');
    });

    test('每种进度组件都有中文名且两两不同', () {
      final names = ProgressDecor.values.map(progressDecorName).toList();
      expect(names.toSet(), hasLength(names.length));
      expect(names.first, '不使用', reason: '默认档必须在设置页里说清「不用」');
    });

    test('shouldRepaint 认全六个入参，改底色也要重画', () {
      final base = _painter(ProgressDecor.ring, 0.5);
      expect(base.shouldRepaint(_painter(ProgressDecor.ring, 0.5)), isFalse);
      expect(
          base.shouldRepaint(_painter(ProgressDecor.water, 0.5)), isTrue,
          reason: '换组件不重画会留下上一件的残影');
      expect(base.shouldRepaint(_painter(ProgressDecor.ring, 0.6)), isTrue);
      expect(
          base.shouldRepaint(_painter(ProgressDecor.ring, 0.5, tick: 0.3)),
          isTrue);
      expect(
          base.shouldRepaint(const ProgressDecorPainter(
                  decor: ProgressDecor.ring,
                  progress: 0.5,
                  tick: 0,
                  fg: Colors.black,
                  accent: _accent)),
          isTrue);
      expect(
          base.shouldRepaint(const ProgressDecorPainter(
                  decor: ProgressDecor.ring,
                  progress: 0.5,
                  tick: 0,
                  fg: _fg,
                  accent: _accent,
                  bg: Colors.brown)),
          isTrue,
          reason: 'sky 的压色层跟着 tokens.bg 走，底色变了必须重画');
    });
  });

  group('进度层真的画到画布上', () {
    // toByteData 走真实事件循环，必须包在 runAsync 里，否则会卡在 fake-async
    Future<Map<ProgressDecor, _Raster>> rasterAll(
        WidgetTester tester, double progress) async {
      late Map<ProgressDecor, _Raster> out;
      await tester.runAsync(() async {
        out = {
          for (final d in ProgressDecor.values)
            d: await _raster(_painter(d, progress), _band)
        };
      });
      return out;
    }

    testWidgets('除 none 外每种组件都画出可见内容，none 一个像素都不画',
        (tester) async {
      final atHalf = await rasterAll(tester, 0.5);
      expect(atHalf[ProgressDecor.none]!.painted, 0,
          reason: '选了「不使用」就一个像素都不该出现');
      for (final d
          in ProgressDecor.values.where((e) => e != ProgressDecor.none)) {
        expect(atHalf[d]!.painted, greaterThan(50),
            reason: '$d 下发了绘制指令，落到底图上却几乎看不见');
      }
    });

    testWidgets('日出日落铺满整块背景并压一层底色', (tester) async {
      final out = (await rasterAll(tester, 0.5))[ProgressDecor.sky]!;
      expect(out.painted, out.width * out.height,
          reason: '环境层要盖满整块区域，露出底色就是漏画');
      final stride = out.width * 4;
      // 左上/右上/左下三个角都必须不透明：压不住底色的环境层会让数字发灰
      for (final off in [0, stride - 4, (out.height - 1) * stride]) {
        expect(out.rgba[off + 3], 255, reason: 'sky 必须在整块区域内不透明');
      }
    });

    testWidgets('水位与蜡烛随进度收缩：accent 部分一路往下退', (tester) async {
      final start = await rasterAll(tester, 0);
      final end = await rasterAll(tester, 1);
      expect(start[ProgressDecor.water]!.topAccentRow,
          lessThan(end[ProgressDecor.water]!.topAccentRow),
          reason: '水面高度就是剩余时长，进度走满水必须见底');
      expect(start[ProgressDecor.candle]!.topAccentRow,
          lessThan(end[ProgressDecor.candle]!.topAccentRow),
          reason: '蜡烛越烧越矮，火苗烧尽后光晕不该还挂在半空');
    });

    testWidgets('灯带和圆环按剩余比例亮着，走完就全灭', (tester) async {
      final start = await rasterAll(tester, 0);
      final mid = await rasterAll(tester, 0.5);
      final end = await rasterAll(tester, 1);
      // 灯珠是一颗颗整颗灭的，纯 accent 像素数就是「还剩几颗」
      expect(start[ProgressDecor.led]!.solidAccent,
          greaterThan(mid[ProgressDecor.led]!.solidAccent),
          reason: '22 颗灯珠要按剩余依次熄灭');
      expect(mid[ProgressDecor.led]!.solidAccent,
          greaterThan(end[ProgressDecor.led]!.solidAccent));
      expect(end[ProgressDecor.led]!.solidAccent, 0);
      expect(start[ProgressDecor.ring]!.solidAccent, greaterThan(0));
      expect(end[ProgressDecor.ring]!.solidAccent, 0,
          reason: '环形填充到 0 剩余就不该再画一段亮弧');
    });
  });

  group('进度层接到主屏', () {
    late ProviderContainer container;
    late DateTime fakeNow;

    ProviderContainer newContainer() => ProviderContainer(
          overrides: [
            clockSourceProvider.overrideWithValue(() => fakeNow),
          ],
        );

    setUp(() async {
      installFakeWakelock();
      await useMemoryStorage();
      await StorageService.writeSettings({'soundEnable': false});
      fakeNow = DateTime(2026, 11, 4, 10, 0, 0);
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
    }

    Future<void> setDecor(WidgetTester tester, ProgressDecor d) async {
      await container
          .read(appSettingsNotifierProvider.notifier)
          .update(container
              .read(appSettingsNotifierProvider)
              .copyWith(progressDecor: d));
      await pumpApp(tester);
    }

    Future<void> startCountdown(WidgetTester tester,
        [Duration dur = const Duration(seconds: 40)]) async {
      container.read(clockNotifierProvider.notifier).startCountdown(dur);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> advance(WidgetTester tester, Duration d) async {
      fakeNow = fakeNow.add(d);
      await tester.pump(d);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// 倒计时用的是 Timer.periodic，留着会让 flutter_test 报「测试结束还有定时器」；
    /// 每个起跑倒计时的用例收尾都要停一下
    void endCountdown() =>
        container.read(clockNotifierProvider.notifier).stopCountdown();

    ProgressDecorPainter bandPainter(WidgetTester tester) =>
        tester.widget<CustomPaint>(find.descendant(
          of: find.byType(ProgressDecorView),
          matching: find.byType(CustomPaint),
        )).painter! as ProgressDecorPainter;

    test('出厂默认不挂进度组件，老用户升版本也不会突然多出背景层', () {
      // setUp 只写过 soundEnable，progressDecor 这个 key 不在箱里，走的正是默认分支
      expect(container.read(appSettingsNotifierProvider).progressDecor,
          ProgressDecor.none);
    });

    testWidgets('待机时钟不挂进度层：它只回答「还剩多少」', (tester) async {
      await setDecor(tester, ProgressDecor.hourglass);
      expect(find.byType(ProgressDecorView), findsNothing,
          reason: '实时模式没有剩余时长，进度层没有意义');
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('默认仍是原来那根细进度条', (tester) async {
      await pumpApp(tester);
      await startCountdown(tester);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(ProgressDecorView), findsNothing);
      endCountdown();
    });

    testWidgets('选了组件就顶掉细条，同一个信息不画两遍', (tester) async {
      await setDecor(tester, ProgressDecor.ring);
      await startCountdown(tester);
      expect(find.byType(ProgressDecorView), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason: '进度带和细条读数重复，只能留一个');
      endCountdown();
    });

    testWidgets('日出日落是背景层，读数细条留着', (tester) async {
      await setDecor(tester, ProgressDecor.sky);
      await startCountdown(tester);
      expect(find.byType(ProgressDecorView), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // 背景层必须垫在内容层底下，压在数字上面就把主屏糊掉了
      // find.ancestor 从目标往上走，.first 才是最近的那层 Stack（主屏自己的 Stack）
      final body = tester
          .widget<Stack>(find.ancestor(
              of: find.byType(ProgressDecorView), matching: find.byType(Stack))
              .first)
          .children;
      expect(body.first, isA<Positioned>(),
          reason: 'sky 应当排在主屏 Stack 的第一位（最底一层）');
      expect((body.first as Positioned).child, isA<ProgressDecorView>());
      endCountdown();
    });

    testWidgets('进度层的读数跟着倒计时走', (tester) async {
      await setDecor(tester, ProgressDecor.water);
      await startCountdown(tester, const Duration(seconds: 40));
      expect(bandPainter(tester).progress, 0);
      await advance(tester, const Duration(seconds: 10));
      expect(bandPainter(tester).progress, closeTo(0.25, 0.03),
          reason: 'progress 与 ClockState.progress 同一个定义：已消耗比例');
      await advance(tester, const Duration(seconds: 26));
      expect(bandPainter(tester).progress, closeTo(0.9, 0.03));
      endCountdown();
    });

    testWidgets('静态组件不挂循环 Ticker，沙漏的沙粒逐帧在动', (tester) async {
      await setDecor(tester, ProgressDecor.ring);
      await startCountdown(tester);
      // ring 不在 animatedProgressDecors 里：能 settle 就说明没有 60fps 循环
      await tester.pumpAndSettle();
      final settled = bandPainter(tester).tick;
      await advance(tester, const Duration(seconds: 3));
      expect(bandPainter(tester).tick, settled,
          reason: '按进度画一次的组件不该有循环相位');
      endCountdown();

      await setDecor(tester, ProgressDecor.hourglass);
      await startCountdown(tester);
      final before = bandPainter(tester).tick;
      await tester.pump(const Duration(milliseconds: 400));
      expect(bandPainter(tester).tick, isNot(before),
          reason: '沙漏靠连续相位驱动重绘，否则沙粒停在同一帧');
      endCountdown();
    });

    testWidgets('进度层的颜色取自当前界面令牌，不是写死的白绿', (tester) async {
      await setDecor(tester, ProgressDecor.ring);
      await startCountdown(tester);
      final classicDark = bandPainter(tester);
      endCountdown();
      await container
          .read(appSettingsNotifierProvider.notifier)
          .update(container
              .read(appSettingsNotifierProvider)
              .copyWith(themeBase: ThemeBase.light));
      await pumpApp(tester);
      await startCountdown(tester);
      expect(bandPainter(tester).fg, isNot(classicDark.fg),
          reason: '切黑白底色后进度层要跟着换前景色，否则暗底白字亮底也白字');
      endCountdown();
    });

    testWidgets('设置页可选：翻到进度组件区点「沙漏」', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byIcon(Icons.settings));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      // 选项在列表末尾，直接 find 还没被 ListView 建出来，要边滚边找
      await tester.scrollUntilVisible(find.text('沙漏'), 120);
      expect(find.textContaining('底层进度组件'), findsOneWidget);

      await tester.tap(find.text('沙漏'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(container.read(appSettingsNotifierProvider).progressDecor,
          ProgressDecor.hourglass);
      expect(StorageService.getSetting('progressDecor', ''), 'hourglass');
    });

    testWidgets('选中的进度组件写进设置库，重启后读回', (tester) async {
      await setDecor(tester, ProgressDecor.annualRings);
      await startCountdown(tester);
      expect(StorageService.getSetting('progressDecor', ''), 'annualRings');

      container.dispose();
      container = newContainer();
      await pumpApp(tester);
      expect(container.read(appSettingsNotifierProvider).progressDecor,
          ProgressDecor.annualRings);
      await startCountdown(tester);
      expect(find.byType(ProgressDecorView), findsOneWidget);
      endCountdown();
    });
  });
}
