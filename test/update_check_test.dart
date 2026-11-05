import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timenote/core/update_check.dart';
import 'package:timenote/settings/settings_page.dart';

/// 手动「检查更新」：比对逻辑 + 真发一次请求的那条路 + 设置页接线。
///
/// 全文件不碰 github.com：注入 fetcher 测分支，`fetchLatestBuildSha` 测本地
/// 起的 loopback HTTP 服务。
void main() {
  const local = 'e00bf9b1234567890e00bf9b1234567890abcdef';
  const newer = '2c6d5f412345678902c6d5f41234567890abcd';

  group('比对逻辑', () {
    test('完整 SHA 一致（含大小写差）判已最新', () async {
      final same = await checkForUpdate(() async => local, localSha: local);
      expect(same.status, UpdateCheckStatus.upToDate);

      final cased =
          await checkForUpdate(() async => local.toUpperCase(), localSha: local);
      expect(cased.status, UpdateCheckStatus.upToDate,
          reason: 'git 都是小写，但比对不该因为云端多写个大写就报有新版');
    });

    test('只比前七位，和 CI 在 Release 说明里的口径一致', () async {
      final tailDiffers = await checkForUpdate(
          () async => '${local.substring(0, 7)}'
              '9999999999999999999999999999',
          localSha: local);
      expect(tailDiffers.status, UpdateCheckStatus.upToDate,
          reason: '短号相同就是同一次构建；比完整 40 位会被 CI 的口径差坑到');
    });

    test('云端换了提交就报有新版，并把远端短号带出来', () async {
      final r = await checkForUpdate(() async => newer, localSha: local);
      expect(r.status, UpdateCheckStatus.available);
      expect(r.remoteShort, '2c6d5f4');
    });

    test('本地构建（没有构建号）说「比不了」，不假装已是最新', () async {
      final r = await checkForUpdate(() async => newer, localSha: '');
      expect(r.status, UpdateCheckStatus.localBuild,
          reason: '空串和远端任何值都不同，判成 available 等于每次点都说你有新版；'
              '判成 upToDate 更是撒谎');
      expect(r.remoteShort, '2c6d5f4');
    });

    test('远端空串与抛异常都归到 failed', () async {
      expect((await checkForUpdate(() async => '   ', localSha: local)).status,
          UpdateCheckStatus.failed);
      final boom = await checkForUpdate(() async => throw const HttpException('HTTP 404'),
          localSha: local);
      expect(boom.status, UpdateCheckStatus.failed);
      expect(boom.remoteSha, isEmpty);
    });
  });

  group('真实抓取（loopback 服务，不出本机）', () {
    // flutter_test 会把 HttpClient 整个换成「任何请求都回 400」的假实现（跑完这个
    // 文件时那句 Warning 就是它发的），所以这条组里必须先把全局覆盖摘掉，
    // 用完再装回去；请求仍然只打到本机的 loopback 端口，不碰外网。
    HttpOverrides? original;
    setUp(() {
      original = HttpOverrides.current;
      HttpOverrides.global = null;
    });
    tearDown(() => HttpOverrides.global = original);

    test('200 的正文按 trim 后原样返回', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(server.forEach((req) async {
        req.response
          ..headers.contentType = ContentType('text', 'plain')
          ..write('  $newer\n');
        await req.response.close();
      }));
      addTearDown(() => server.close(force: true));

      final sha = await fetchLatestBuildSha(
          url: 'http://127.0.0.1:${server.port}/dev-build-sha.txt');
      expect(sha, newer, reason: '云端附件带换行与空格，不 trim 就永远比不中');
    });

    test('非 200 抛出来，交给上层归成检查失败', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(server.forEach((req) async {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }));
      addTearDown(() => server.close(force: true));

      await expectLater(
          fetchLatestBuildSha(url: 'http://127.0.0.1:${server.port}/nope'),
          throwsA(isA<Exception>()));
    });
  });

  group('设置页接线', () {
    Future<void> pumpSection(WidgetTester tester, LatestShaFetcher fetch) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [latestShaFetcherProvider.overrideWithValue(fetch)],
        child: const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(child: UpdateCheckSection())),
        ),
      ));
      await tester.pump();
    }

    testWidgets('没点之前一次请求都不发，也没有复制按钮', (tester) async {
      var called = 0;
      await pumpSection(tester, () async {
        called++;
        return newer;
      });
      expect(called, 0, reason: '「手动」的意思就是不进设置页就不发请求');
      expect(find.textContaining('还没检查过'), findsOneWidget);
      expect(find.text('复制下载地址'), findsNothing);
    });

    testWidgets('点「检查更新」走注入的那条缝，报出远端短号并给出复制',
        (tester) async {
      await pumpSection(tester, () async => newer);
      await tester.tap(find.text('检查更新'));
      await tester.pump();

      expect(find.textContaining('2c6d5f4'), findsOneWidget);
      expect(find.text('复制下载地址'), findsOneWidget);
    });

    testWidgets('复制的是 dev-build 发布页，不是那条 .txt', (tester) async {
      // 这个 SDK 的 flutter_test 不接管剪贴板：不装 mock 的话 `await
      // Clipboard.setData` 永远不返回，按钮上的「已复制」根本刷不出来
      // （第一次跑就卡在这，整条 testWidgets 超时无输出）。
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') calls.add(call);
        return null;
      });
      addTearDown(
          () => tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpSection(tester, () async => newer);
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      await tester.tap(find.text('复制下载地址'));
      await tester.pump();

      expect(find.text('已复制'), findsOneWidget);
      expect(calls, hasLength(1));
      expect((calls.single.arguments! as Map)['text'], devBuildReleaseUrl,
          reason: '复制给用户的是能点开下载的那页，不是纯 SHA 附件');
    });

    testWidgets('请求失败就明说失败，不摆一个没用的复制按钮', (tester) async {
      await pumpSection(tester, () async => throw const HttpException('boom'));
      await tester.tap(find.text('检查更新'));
      await tester.pump();

      expect(find.textContaining('检查失败'), findsOneWidget);
      expect(find.text('复制下载地址'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
