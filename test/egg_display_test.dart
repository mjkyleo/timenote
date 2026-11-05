import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/egg/egg_display.dart';
import 'package:timenote/settings/enum_def.dart';
import 'package:timenote/theme/ui_style.dart';

/// 彩蛋文案的显示压测。
///
/// 用户会导入自己的文案文件，而内置库那 520 条全是长度可控的中文。真正会出事的是
/// 「一整段没有换行点的长文案」「一长串带空格的英文」「中英夹在一起还有 URL」这三类：
/// 蛋屏是待机屏，没人会在倒计时结束后去滑动屏幕找后半句，所以这里的判据不是
/// 「不报错」，而是**这一条文案不用滚动就能整块看完**。
void main() {
  const cn = '逝者如斯夫，不舍昼夜。';
  const cnLong =
      '盛年不重来，一日难再晨。及时当勉励，岁月不待人。人生天地之间，若白驹之过隙，'
      '忽然而已。你热爱生活吗？那就不要浪费时间，因为时间是组成生命的材料。'
      '昨日只是一场梦，明日是可见的，但今天是实实在在的一天，所以要抓住今天。'
      '时间是最不偏私的，它给任何人都是二十四小时，同时又是最偏私的，'
      '它不肯把多的片刻分给任何人。';
  const enLong =
      'The secret of getting ahead is getting started; the secret of getting '
      'started is breaking your complex overwhelming task into small manageable '
      'tasks, and then starting on the first one, because time is the most '
      'valuable thing you can spend, for it can never be bought back.';
  const mixed =
      '专注结束啦！Review your day, then close Flutter issue #123 on GitHub '
      '和 待办清单，剩下的明天再讲。记得喝口水。';
  const urlToken =
      '详情见 https://docs.flutter.dev/release/breaking-changes/migrate-to-material-3-and-beyond';

  Future<Size> pumpEgg(WidgetTester tester, String copy, Size screen,
      {TextScaler scaler = TextScaler.noScaling}) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: UiLayer(
          tokens: UiTokens.classic(true),
          child: Scaffold(
            body: EggDisplay(text: copy, themeBase: ThemeBase.dark),
          ),
        ),
      ),
    ));
    await tester.pump();
    return tester.view.physicalSize;
  }

  /// 「不用滚就能看完」的判据：文本块本身的高度不许超过它所在滚动视口的高度，
  /// 宽度同理。
  void expectFitsWholeCopy(WidgetTester tester, String copy) {
    final viewport = tester.getSize(find.byType(SingleChildScrollView));
    final block = tester.getSize(find.text(copy));
    expect(block.width, lessThanOrEqualTo(viewport.width + 0.5),
        reason: '文案横向出了视口：长单词没被拆开');
    expect(block.height, lessThanOrEqualTo(viewport.height + 0.5),
        reason: '文案竖向出了视口：蛋屏是待机屏，没人在倒计时结束后滑动找后半句');
    expect(tester.takeException(), isNull, reason: '不允许有溢出异常');
  }

  group('蛋屏文案要整块可见', () {
    testWidgets('平板 800×600：内置库那批长度的中文不用滚', (tester) async {
      await pumpEgg(tester, cnLong, const Size(800, 600));
      expectFitsWholeCopy(tester, cnLong);
    });

    testWidgets('平板 1280×800：一整段英文（全是带空格的长句）不用滚',
        (tester) async {
      await pumpEgg(tester, enLong, const Size(1280, 800));
      expectFitsWholeCopy(tester, enLong);
    });

    testWidgets('手机横屏 914×411：中英混排夹 URL 和井号 issue 号不用滚',
        (tester) async {
      await pumpEgg(tester, mixed, const Size(914, 411));
      expectFitsWholeCopy(tester, mixed);
    });

    testWidgets('手机横屏 914×411：不可断行的超长 URL 不许捅破行宽',
        (tester) async {
      await pumpEgg(tester, urlToken, const Size(914, 411));
      expectFitsWholeCopy(tester, urlToken);
    });

    testWidgets('极短文案不该被无谓缩小：两行辅助文字都还在', (tester) async {
      await pumpEgg(tester, cn, const Size(800, 600));
      expect(find.text('专注结束'), findsOneWidget);
      expect(find.text('轻触任意处返回时钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('屏宽再大字号也有上限，不会涨成满屏一个字', (tester) async {
      await pumpEgg(tester, cn, const Size(2000, 1200));
      final size = tester.getSize(find.text(cn));
      expect(size.height, lessThan(200),
          reason: '2000 宽的屏上，四个字的短句不该按屏宽等比放大');
      expect(tester.takeException(), isNull);
    });

    testWidgets('横屏手机上辅助文字与文案一起活着，不许塌成 0 高', (tester) async {
      await pumpEgg(tester, cnLong, const Size(914, 411));
      for (final label in ['专注结束', '轻触任意处返回时钟']) {
        expect(tester.getSize(find.text(label)).height, greaterThan(0));
      }
    });

    testWidgets('用户在系统里调大字号后，长文案仍然整块可见', (tester) async {
      // Android「设置 → 显示 → 字体大小」拉到最大是 2.0x。Text 会自己乘这个系数，
      // 所以缩字号的测量必须按缩放后的真实高度算，否则这条路径在测试字体下
      // 看着放得下、到开了大字号的用户手机上就顶出可视区。
      await pumpEgg(tester, cnLong, const Size(800, 600),
          scaler: const TextScaler.linear(2.0));
      expectFitsWholeCopy(tester, cnLong);
    });

    testWidgets('短句就是基准字号，中文/英文都不被无故缩掉', (tester) async {
      // 短句（一行放得下）不该被量高宽那套算法误伤：宽度撑满的 1280 屏上
      // 基准是 (1280−96)/18 → 超上限，取 40。
      for (final copy in [cn, 'Stay hungry, stay young.']) {
        await pumpEgg(tester, copy, const Size(1280, 800));
        expect(tester.widget<Text>(find.text(copy)).style!.fontSize,
            closeTo(40, 0.51),
            reason: '$copy 只有 9 个词宽，放得下就该保持满档字号');
      }
    });

    testWidgets('系统字号开到 2x 也不影响短句的字号档位', (tester) async {
      await pumpEgg(tester, cn, const Size(1280, 800),
          scaler: const TextScaler.linear(2.0));
      expect(tester.widget<Text>(find.text(cn)).style!.fontSize,
          closeTo(40, 0.51));
      expectFitsWholeCopy(tester, cn);
    });

    testWidgets('同一块屏上，英文文案选出的字号不大于中文', (tester) async {
      // 这条是「中英文显示情况」的核心差异：中文每个字等宽、能在任意两字之间断行，
      // 英文只能在空格处断行，一个长单词就是一整块不可分的最小单位。所以同样长度
      // 的两种文案，英文占的行更宽、更容易顶出视口 → 只能选更小那一档。
      // 判据用「字号大小关系」而不是具体数值：具体数值依赖测试字体（flutter_test
      // 把字形画成 1em 方块，拉丁文比真机 Roboto 宽得多），关系则不会反过来。
      await pumpEgg(tester, cnLong, const Size(914, 411));
      final cnSize = tester.widget<Text>(find.text(cnLong)).style!.fontSize!;
      await pumpEgg(tester, enLong, const Size(914, 411));
      final enSize = tester.widget<Text>(find.text(enLong)).style!.fontSize!;
      expect(enSize, lessThanOrEqualTo(cnSize + 0.01),
          reason: '横屏 914×411 上英文比中文还宽松，说明断行判据没起作用');
      // 两档都还在可读下限之上，不是靠「缩成 14 了事」蒙过的
      expect(cnSize, greaterThan(EggDisplay.minFont));
      expect(enSize, greaterThan(EggDisplay.minFont));
    });

    testWidgets('横屏窄高 + 系统字号 2x：最坏组合下英文也只能整块看完',
        (tester) async {
      // 914×411 是「宽还够用、高最紧」的横屏手机，再叠 2x 字号就是蛋屏能遇到的
      // 最坏情形；英文在这里最容易先顶出去，所以单独钉一条。
      await pumpEgg(tester, enLong, const Size(914, 411),
          scaler: const TextScaler.linear(2.0));
      expectFitsWholeCopy(tester, enLong);
      // 整块可见不能是靠「缩成蚂蚁」换来的：渲染后的字号仍在可读下限之上
      final style = tester.widget<Text>(find.text(enLong)).style!;
      expect(style.fontSize! * 2.0, greaterThanOrEqualTo(EggDisplay.minFont));
    });

    testWidgets('长到缩不动了就交回滚动：横向不破、也不许崩', (tester) async {
      // 用户导入的文案长度不可控。竖向确实放不下时宁可让人滑（这屏是收尾彩蛋，
      // 滑一下比整块消失好），但横向溢出会把文字直接裁掉，那是真丢内容。
      final huge = cnLong * 8;
      await pumpEgg(tester, huge, const Size(914, 411));
      final viewport = tester.getSize(find.byType(SingleChildScrollView));
      final block = tester.getSize(find.text(huge));
      expect(block.width, lessThanOrEqualTo(viewport.width + 0.5));
      expect(tester.takeException(), isNull);
    });
  });
}
