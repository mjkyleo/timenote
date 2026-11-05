import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 构建号：CI 出包时用 `--dart-define=BUILD_SHA=<完整 SHA>` 注进来。
/// 本地 `flutter run` 不带这个参数，拿到的是空串，界面会明说「比对不了」，
/// 而不是假装「已是最新」。
const String buildSha = String.fromEnvironment('BUILD_SHA');

const String _repo = 'mjkyleo/timenote';

/// 每次发布都会覆盖的那份纯文本完整 SHA。
///
/// 走 Releases 附件而不是 `api.github.com`：那条有 IP 限流（未认证 60 次/小时，
/// 移动网络同出口的人共享），这条是普通文件下载，取回来就是一个 SHA 字符串。
const String latestBuildUrl =
    'https://github.com/$_repo/releases/download/dev-build/dev-build-sha.txt';

/// 安装包所在页。不引 `url_launcher`（鸿蒙侧没有官方实现），所以只给复制。
const String devBuildReleaseUrl = 'https://github.com/$_repo/releases/tag/dev-build';

enum UpdateCheckStatus { upToDate, available, localBuild, failed }

class UpdateCheckResult {
  final UpdateCheckStatus status;

  /// 云端最新构建的完整 SHA，拿不到时为空
  final String remoteSha;
  const UpdateCheckResult(this.status, {this.remoteSha = ''});

  String get remoteShort => shortOf(remoteSha);
}

/// 七位短号，和 CI 在 Release 说明里写的口径一致
String shortOf(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;

/// 抓取云端最新构建号；测试把这条缝换掉，一次真实请求都不会发出去
typedef LatestShaFetcher = Future<String> Function();

final latestShaFetcherProvider =
    Provider<LatestShaFetcher>((ref) => fetchLatestBuildSha);

Future<String> fetchLatestBuildSha({
  String url = latestBuildUrl,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
    // 这条路上其实不带也能 200（实测附件直链无 UA = 200，缺 UA 会 403 的是
    // api.github.com），带上是免得哪天改读 API 时踩那个坑
    request.headers.set(HttpHeaders.userAgentHeader, 'TimeNote');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return (await response.transform(utf8.decoder).join().timeout(timeout)).trim();
  } finally {
    // 不强制关掉的话失败的连接会一直挂在事件循环里
    client.close(force: true);
  }
}

/// 只有这一处真的碰网络，其余分支全靠注入进来的 [fetch]。
///
/// [localSha] 也留成参数：`buildSha` 是编译期 `String.fromEnvironment`，测试里
/// 永远是空串，不传进来就只能测到「本地构建」这一条分支。
Future<UpdateCheckResult> checkForUpdate(
  LatestShaFetcher fetch, {
  String? localSha,
}) async {
  final local = localSha ?? buildSha;
  final String remote;
  try {
    remote = (await fetch()).trim();
  } catch (_) {
    return const UpdateCheckResult(UpdateCheckStatus.failed);
  }
  if (remote.isEmpty) return const UpdateCheckResult(UpdateCheckStatus.failed);
  if (local.isEmpty) {
    return UpdateCheckResult(UpdateCheckStatus.localBuild, remoteSha: remote);
  }
  final same = shortOf(remote).toLowerCase() == shortOf(local).toLowerCase();
  return UpdateCheckResult(
      same ? UpdateCheckStatus.upToDate : UpdateCheckStatus.available,
      remoteSha: remote);
}
