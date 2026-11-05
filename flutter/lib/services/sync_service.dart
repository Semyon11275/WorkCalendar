import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'agent_service.dart';

/// Explicitly enabled, approved-device-only LAN transfer. No remote CRUD/AI access.
class SyncService {
  SyncService(this.agent);
  final AgentService agent;
  HttpServer? server;
  String code = '';
  DateTime expiry = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, Map<String, dynamic>> pending = {};
  final Set<String> tokens = {};
  final Map<String, List<DateTime>> attempts = {};
  int get port => server?.port ?? 0;
  Future<void> start({bool loopbackOnly = false}) async {
    if (server != null) return;
    server = await HttpServer.bind(
      loopbackOnly ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4,
      0,
    );
    server!.listen((r) {
      unawaited(_handle(r));
    });
  }

  Future<void> stop() async {
    final old = server;
    server = null;
    tokens.clear();
    pending.clear();
    code = '';
    await old?.close(force: true);
  }

  void begin() {
    if (server == null) throw StateError('请先开启同步接收');
    code = agent
        .secret()
        .replaceAll(RegExp('[^a-zA-Z0-9]'), '')
        .substring(0, 8);
    expiry = DateTime.now().add(const Duration(minutes: 3));
    pending.clear();
  }

  void approve(String id, bool allow) {
    final p = pending[id];
    if (p == null || DateTime.now().isAfter(p['expires'] as DateTime)) return;
    p['approved'] = allow;
    if (allow) {
      p['token'] = agent.secret();
      tokens.add(p['token'] as String);
    }
  }

  static bool safeName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !name.contains('/') &&
      !name.contains('\\') &&
      !name.contains(':') &&
      !name.contains('\u0000');
  Future<Map<String, dynamic>> manifest() async {
    final data = agent.snapshot();
    final result = <Map<String, dynamic>>[];
    final names = (data['awards'] as List)
        .expand((a) => (a['certificate_files'] as List).cast<String>())
        .toSet();
    for (final name in names) {
      if (!safeName(name)) throw StateError('非法附件引用');
      final file = File(agent.repo.certs.path(name));
      if (!await file.exists()) throw StateError('缺少附件：$name');
      result.add({
        'name': name,
        'size': await file.length(),
        'sha256': '${await sha256.bind(file.openRead()).first}',
      });
    }
    if (jsonEncode(data) != jsonEncode(agent.snapshot())) {
      throw StateError('生成清单期间数据变化，请重试');
    }
    return {...data, 'certificates': result};
  }

  /// Stream bytes to a private staging file, verify, then install without overwrite.
  Future<String> receive(
    Stream<List<int>> stream,
    String name,
    String hash,
  ) async {
    if (!safeName(name) || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('非法附件清单');
    }
    final temp = File('${agent.repo.dataDir}/sync-staging/${agent.secret()}');
    await temp.parent.create(recursive: true);
    try {
      final sink = temp.openWrite();
      var size = 0;
      try {
        await for (final chunk in stream.timeout(const Duration(seconds: 90))) {
          size += chunk.length;
          if (size > 8 * 1024 * 1024 * 1024) throw StateError('单附件超过 8 GiB');
          sink.add(chunk);
          if (size % (4 * 1024 * 1024) < chunk.length) await sink.flush();
        }
      } finally {
        await sink.close();
      }
      if ('${await sha256.bind(temp.openRead()).first}' != hash) {
        throw StateError('附件 SHA256 不一致');
      }
      var saved = name;
      var dest = File(agent.repo.certs.path(saved));
      if (await dest.exists()) {
        if ('${await sha256.bind(dest.openRead()).first}' == hash) return saved;
        final ext = name.contains('.')
            ? name.substring(name.lastIndexOf('.'))
            : '';
        saved = '$hash${ext.length < 16 ? ext : ""}';
        dest = File(agent.repo.certs.path(saved));
        if (await dest.exists()) {
          if ('${await sha256.bind(dest.openRead()).first}' == hash) {
            return saved;
          }
          throw StateError('已有附件内容冲突');
        }
      }
      await temp.rename(dest.path);
      return saved;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<Map<String, dynamic>> commit(
    Map<String, dynamic> data, {
    bool update = false,
  }) async {
    for (final a in data['awards'] as List? ?? []) {
      for (final name in a['certificate_files'] as List? ?? []) {
        if (name is! String ||
            !safeName(name) ||
            !await File(agent.repo.certs.path(name)).exists()) {
          throw StateError('记录引用的附件尚未到齐');
        }
      }
    }
    return agent.importData({
      'competitions': data['competitions'] ?? [],
      'awards': data['awards'] ?? [],
    }, update: update);
  }

  Future<void> _handle(HttpRequest r) async {
    try {
      final path = r.uri.path;
      final ip = r.connectionInfo?.remoteAddress.address ?? '';
      if (r.headers.value('Origin') != null) {
        agent.reply(r, {'error': '拒绝网页请求'}, 403);
        return;
      }
      if (path == '/pair/request' && r.method == 'POST') {
        final now = DateTime.now();
        attempts.removeWhere(
          (_, v) => v.every((t) => now.difference(t).inMinutes >= 1),
        );
        final hits = attempts.putIfAbsent(ip, () => [])
          ..removeWhere((t) => now.difference(t).inMinutes >= 1);
        if (hits.length >= 5) {
          agent.reply(r, {'error': '请求过多'}, 429);
          return;
        }
        hits.add(now);
        final b = await agent.body(r);
        if (code.isEmpty || now.isAfter(expiry) || b['code'] != code) {
          agent.reply(r, {'error': '配对码无效'}, 401);
          return;
        }
        final id = agent.secret();
        code = '';
        pending[id] = {
          'ip': ip,
          'approved': null,
          'expires': now.add(const Duration(minutes: 3)),
        };
        agent.reply(r, {'request_id': id}, 202);
        return;
      }
      if (path == '/pair/result' && r.method == 'POST') {
        final b = await agent.body(r);
        final p = pending[b['request_id']];
        if (p == null ||
            p['ip'] != ip ||
            DateTime.now().isAfter(p['expires'] as DateTime)) {
          agent.reply(r, {'error': '配对失效'}, 403);
          return;
        }
        if (p['approved'] == null) {
          agent.reply(r, {'pending': true}, 202);
          return;
        }
        if (p['approved'] != true) {
          agent.reply(r, {'error': '接收端拒绝'}, 403);
          return;
        }
        agent.reply(r, {'token': p['token']});
        return;
      }
      if (!tokens.contains(r.headers.value('X-Sync-Token'))) {
        agent.reply(r, {'error': '尚未配对'}, 401);
        return;
      }
      if (path == '/manifest' && r.method == 'GET') {
        agent.reply(r, await manifest());
        return;
      }
      if (path == '/file') {
        final name = r.uri.queryParameters['name'] ?? '';
        if (!safeName(name)) throw const FormatException('非法文件名');
        if (r.method == 'GET') {
          if (!agent.repo.allAwards().any(
            (a) => a.certificateFiles.contains(name),
          )) {
            throw StateError('附件未被库引用');
          }
          final file = File(agent.repo.certs.path(name));
          if (!await file.exists()) {
            agent.reply(r, {'error': '附件不存在'}, 404);
            return;
          }
          r.response.headers.contentType = ContentType.binary;
          r.response.contentLength = await file.length();
          await r.response.addStream(file.openRead());
          return;
        }
        if (r.method == 'POST') {
          final saved = await receive(
            r,
            name,
            r.uri.queryParameters['sha256'] ?? '',
          );
          agent.reply(r, {'name': saved});
          return;
        }
      }
      if (path == '/records' && r.method == 'POST') {
        final b = await agent.body(r);
        agent.reply(r, await commit(b, update: b['update_existing'] == true));
        return;
      }
      agent.reply(r, {'error': '不支持的同步接口'}, 404);
    } catch (e) {
      agent.reply(r, {'error': '$e'}, 400);
    } finally {
      await r.response.close();
    }
  }
}

class SyncClient {
  SyncClient(this.local, this.base) {
    final ip = InternetAddress.tryParse(base.host);
    final bytes = ip?.rawAddress;
    final private =
        ip?.isLoopback == true ||
        (bytes != null &&
            bytes.length == 4 &&
            (bytes[0] == 10 ||
                (bytes[0] == 192 && bytes[1] == 168) ||
                (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31)));
    if (base.scheme != 'http' || !private || base.userInfo.isNotEmpty) {
      throw ArgumentError('仅支持明确填写的局域网 IP 地址');
    }
  }
  final SyncService local;
  final Uri base;
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  String token = '';
  String requestId = '';
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    client.close(force: true);
  }

  Future<Map<String, dynamic>> jsonRequest(
    String method,
    String path, [
    Object? data,
  ]) async {
    final r = await client
        .openUrl(method, base.resolve(path))
        .timeout(const Duration(seconds: 30));
    r.followRedirects = false;
    r.headers.set('X-Sync-Token', token);
    r.headers.contentType = ContentType.json;
    if (data != null) r.write(jsonEncode(data));
    final response = await r.close().timeout(const Duration(minutes: 5));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(minutes: 2))) {
      if (bytes.length + chunk.length > 16 * 1024 * 1024) {
        throw StateError('记录清单过大');
      }
      bytes.addAll(chunk);
    }
    final body = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(bytes)) as Map,
    );
    if (response.statusCode >= 300) {
      throw StateError('${body['error'] ?? response.statusCode}');
    }
    return body;
  }

  Future<void> requestPair(String code) async {
    requestId =
        '${(await jsonRequest('POST', '/pair/request', {'code': code}))['request_id']}';
  }

  Future<bool> finishPair() async {
    final b = await jsonRequest('POST', '/pair/result', {
      'request_id': requestId,
    });
    if (b['pending'] == true) return false;
    token = '${b['token']}';
    return true;
  }

  Future<Map<String, dynamic>> transfer({
    required bool push,
    required bool update,
    required void Function(String) status,
  }) async {
    final data = push
        ? await local.manifest()
        : await jsonRequest('GET', '/manifest');
    final mapping = <String, String>{};
    final certs = data['certificates'] as List;
    for (var i = 0; i < certs.length; i++) {
      if (cancelled) throw StateError('已取消');
      final item = certs[i] as Map;
      final name = '${item['name']}';
      final hash = '${item['sha256']}';
      status('传输凭证 ${i + 1}/${certs.length}：$name');
      final uri = base
          .resolve('/file')
          .replace(queryParameters: {'name': name, 'sha256': hash});
      if (push) {
        final r = await client.postUrl(uri);
        r.followRedirects = false;
        r.headers.set('X-Sync-Token', token);
        final f = File(local.agent.repo.certs.path(name));
        r.contentLength = await f.length();
        await r.addStream(f.openRead());
        final response = await r.close();
        final b = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
        if (response.statusCode != 200) throw StateError('${b['error']}');
        mapping[name] = '${b['name']}';
      } else {
        final existing = File(local.agent.repo.certs.path(name));
        if (await existing.exists() &&
            '${await sha256.bind(existing.openRead()).first}' == hash) {
          mapping[name] = name;
          continue;
        }
        final r = await client.getUrl(uri);
        r.followRedirects = false;
        r.headers.set('X-Sync-Token', token);
        final response = await r.close();
        if (response.statusCode != 200) {
          await response.drain<void>();
          throw StateError('附件下载失败');
        }
        mapping[name] = await local.receive(response, name, hash);
      }
    }
    if (cancelled) throw StateError('已取消');
    final awards = (data['awards'] as List)
        .map(
          (a) => {
            ...Map<String, dynamic>.from(a as Map),
            'certificate_files': (a['certificate_files'] as List)
                .map((n) => mapping[n] ?? n)
                .toList(),
          },
        )
        .toList();
    final payload = {
      'competitions': data['competitions'],
      'awards': awards,
      'update_existing': update,
    };
    status('附件校验完成，合并记录');
    return push
        ? jsonRequest('POST', '/records', payload)
        : local.commit(payload, update: update);
  }
}
