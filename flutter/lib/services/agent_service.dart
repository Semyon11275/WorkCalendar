import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'sync_service.dart';
import '../data/repository.dart';
import '../data/exchange.dart';
import '../domain/models.dart';

/// Loopback-only API. Remote hosts cannot manage the library.
class AgentService {
  AgentService(this.repo, {required this.changed});
  final WcRepository repo;
  final void Function() changed;
  HttpServer? server;
  String token = '';
  int get port => server?.port ?? 0;
  String secret() =>
      base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)));
  Future<void> start() async {
    if (server != null) return;
    final file = File('${repo.dataDir}/api_token.txt');
    token = await file.exists() ? (await file.readAsString()).trim() : '';
    if (token.length < 32) {
      token = secret();
      await file.writeAsString(token, flush: true);
    }
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((req) {
      unawaited(_handle(req));
    });
    await File('${repo.dataDir}/agent_connection.json').writeAsString(
      jsonEncode({
        'url': 'http://127.0.0.1:${server!.port}',
        'token_file': file.path,
        'schema': 'workcalendar-agent-v1',
      }),
      flush: true,
    );
  }

  Future<void> stop() async {
    final old = server;
    server = null;
    await old?.close(force: true);
  }

  Map<String, dynamic> snapshot() => {
    'competitions': repo.allComps().map((c) => c.toLegacyJson()).toList(),
    'awards': repo.allAwards().map((a) => a.toLegacyJson()).toList(),
  };
  Future<Map<String, dynamic>> importData(
    Object data, {
    bool update = false,
  }) async {
    final bundle = parseTextSource(
      data is String ? data : jsonEncode(data),
      'Agent',
    );
    final report = await repo.applyImport(
      compRecords: bundle.comps,
      awardRecords: bundle.awards,
      certificates: bundle.certificates,
      updateExisting: update,
    );
    changed();
    return {
      'ok': report.errors.isEmpty,
      'added': report.added,
      'updated': report.updated,
      'skipped': report.skipped,
      'errors': report.errors,
      'warnings': report.warnings,
    };
  }

  Future<Map<String, dynamic>> operate(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'query':
        final q = '${args['keyword'] ?? ''}'.toLowerCase();
        final all = snapshot();
        return {
          for (final e in all.entries)
            e.key: (e.value as List)
                .where(
                  (r) => q.isEmpty || jsonEncode(r).toLowerCase().contains(q),
                )
                .toList(),
        };
      case 'import':
        return importData(
          args['data'] ?? args,
          update: args['update_existing'] == true,
        );
      case 'update_competition':
        final id = '${args['id']}';
        final old = repo.getComp(id);
        if (old == null) throw StateError('比赛不存在');
        await repo.upsertComp(
          Competition.fromLegacyJson({
            ...old.toLegacyJson(),
            ...Map<String, dynamic>.from(args['fields'] as Map),
            'id': id,
            'created_at': old.createdAt,
          }),
        );
      case 'update_award':
        final id = '${args['id']}';
        final old = repo.getAward(id);
        if (old == null) throw StateError('获奖不存在');
        await repo.upsertAward(
          Award.fromLegacyJson({
            ...old.toLegacyJson(),
            ...Map<String, dynamic>.from(args['fields'] as Map),
            'id': id,
            'created_at': old.createdAt,
          }),
        );
      case 'delete_competition':
        await repo.deleteComp('${args['id']}');
      case 'delete_award':
        await repo.deleteAward('${args['id']}');
      default:
        throw ArgumentError('未知操作：$action');
    }
    changed();
    return {'ok': true};
  }

  Future<Map<String, dynamic>> body(HttpRequest req) async {
    final chunks = <int>[];
    await for (final chunk in req.timeout(const Duration(seconds: 30))) {
      if (chunks.length + chunk.length > 16 * 1024 * 1024) {
        throw StateError('JSON 超过 16 MiB，请分批导入');
      }
      chunks.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(chunks));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('请求体必须为 JSON 对象');
    }
    return decoded;
  }

  void reply(HttpRequest r, Object data, [int status = 200]) {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    r.response.headers.set('Cache-Control', 'no-store');
    r.response.write(jsonEncode(data));
  }

  Future<void> _handle(HttpRequest r) async {
    try {
      final path = r.uri.path;
      final method = r.method;
      if (r.headers.value('Origin') != null) {
        reply(r, {'error': '不接受网页跨域调用'}, 403);
        return;
      }
      if (path == '/api/health' && method == 'GET') {
        reply(r, {'ok': true, 'service': 'workcalendar-agent-v1'});
        return;
      }
      if (r.headers.value('X-API-Token') != token) {
        reply(r, {'error': '需要有效令牌'}, 401);
        return;
      }
      if (path == '/api/certificates' && method == 'POST') {
        final name = r.uri.queryParameters['name'] ?? '';
        final hash = r.uri.queryParameters['sha256'] ?? '';
        final saved = await SyncService(this).receive(r, name, hash);
        reply(r, {'ok': true, 'name': saved});
        return;
      }
      if (path == '/api/schema' && method == 'GET') {
        reply(r, {
          'version': 1,
          'verification_requirements': '核验要求：赛事归属、奖项名称和作者以证书正文及官方公告为依据，不得根据文件名归类；只知年份或月份时不得补造月日，日期留空并在备注记录原文和精度；来源链接、赛项与阶段需注明；日期离群需复核而非自动改写；报名开始不得晚于同一阶段结束；评审、公示、颁奖可晚于投稿截止；作者角色与一作标记须一致；无凭证须注明原因。禁止直接改写数据库 JSON，请使用导入接口并检查返回报告。',
          'routes': [
            'GET /api/competitions',
            'GET /api/awards',
            'POST /api/import',
            'POST /api/awards/import',
            'PUT/DELETE /api/competitions/:id',
            'PUT/DELETE /api/awards/:id',
          ],
          'import': {
            'data': 'JSON 对象/数组或 Markdown 文本',
            'update_existing': false,
          },
        });
        return;
      }
      if (path == '/api/import' || path == '/api/awards/import') {
        if (method != 'POST') {
          reply(r, {'error': '请使用 POST'}, 405);
          return;
        }
        final b = await body(r);
        Object data = b['text'] ?? b['data'] ?? b;
        if (path == '/api/awards/import' && b.containsKey('records')) {
          data = {'awards': b['records']};
        }
        if (b['preview'] == true) {
          final bundle = parseTextSource(
            data is String ? data : jsonEncode(data),
            'API',
          );
          reply(r, {
            'competitions': bundle.comps.length,
            'awards': bundle.awards.length,
            'warnings': bundle.warnings,
          });
          return;
        }
        final report = await importData(
          data,
          update:
              b['update_existing'] == true ||
              r.uri.queryParameters['update'] == 'true',
        );
        reply(r, {
          ...report,
          'report': report,
          'total':
              (report['added'] as int) +
              (report['updated'] as int) +
              (report['skipped'] as int),
        });
        return;
      }
      for (final kind in ['competitions', 'awards']) {
        if (path != '/api/$kind' && !path.startsWith('/api/$kind/')) continue;
        final list = snapshot()[kind] as List;
        final id = path == '/api/$kind'
            ? null
            : path.substring('/api/$kind/'.length);
        if (method == 'GET') {
          final q = (r.uri.queryParameters['keyword'] ?? '').toLowerCase();
          if (id != null) {
            final item = list.where((x) => x['id'] == id).firstOrNull;
            reply(
              r,
              item == null
                  ? {'error': '不存在'}
                  : {kind == 'awards' ? 'award' : 'competition': item},
              item == null ? 404 : 200,
            );
          } else {
            final filtered = list
                .where(
                  (x) => q.isEmpty || jsonEncode(x).toLowerCase().contains(q),
                )
                .toList();
            reply(r, {kind: filtered, 'count': filtered.length});
          }
          return;
        }
        if (method == 'POST' && id == null) {
          reply(
            r,
            await importData({
              kind: [await body(r)],
            }),
          );
          return;
        }
        final singular = kind == 'awards' ? 'award' : 'competition';
        if (id != null && method == 'PUT') {
          reply(
            r,
            await operate('update_$singular', {
              'id': id,
              'fields': await body(r),
            }),
          );
          return;
        }
        if (id != null && method == 'DELETE') {
          reply(r, await operate('delete_$singular', {'id': id}));
          return;
        }
      }
      reply(r, {'error': '接口不存在'}, 404);
    } catch (e) {
      reply(r, {'ok': false, 'error': '$e'}, 400);
    } finally {
      await r.response.close();
    }
  }
}
