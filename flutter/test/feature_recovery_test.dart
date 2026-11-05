import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:workcalendar/data/repository.dart';
import 'package:workcalendar/domain/models.dart';
import 'package:workcalendar/domain/classification.dart';
import 'package:workcalendar/services/agent_service.dart';
import 'package:workcalendar/services/ai_session.dart';
import 'package:workcalendar/services/sync_service.dart';

void main() {
  late Directory temp;
  late WcRepository repo;
  late AgentService api;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wc_recovery_');
    repo = await WcRepository.open(temp.path);
    api = AgentService(repo, changed: () {});
  });
  tearDown(() async {
    await api.stop();
    await temp.delete(recursive: true);
  });
  test('组合类别产生多个统一方向，未知类别不被伪造', () {
    final c = Competition.fromLegacyJson({
      'name': '测试',
      'deadline': '2099-01-01',
      'category': '文创设计/包装设计、IP形象',
    });
    expect(competitionDirections(c), containsAll(['文创与IP', '包装设计']));
    expect(c.category, '文创设计/包装设计、IP形象');
    c.category = '未识别专项';
    expect(competitionDirections(c), {'待归类'});
    c.extra['directions'] = ['空间与环境'];
    expect(competitionDirections(c), {'空间与环境'});
  });
  test('获奖按系列、级别、年份分类且保留未填日期', () {
    final a = Award.fromLegacyJson({
      'name': '奖项',
      'competition': '某系列',
      'level': '国家级',
      'award_date': '2025-02-01',
    });
    expect(awardGroup(a, AwardGrouping.competition), '某系列');
    expect(awardGroup(a, AwardGrouping.level), '国家级');
    expect(awardGroup(a, AwardGrouping.year), '2025年');
    a.awardDate = null;
    expect(awardGroup(a, AwardGrouping.year), '未填写年份');
  });
  Future<(int, Map<String, dynamic>)> req(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    bool auth = true,
    String? origin,
  }) async {
    final client = HttpClient();
    try {
      final r = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${api.port}$path'),
      );
      if (auth) r.headers.set('X-API-Token', api.token);
      if (origin != null) r.headers.set('Origin', origin);
      r.headers.contentType = ContentType.json;
      if (data != null) r.write(jsonEncode(data));
      final response = await r.close();
      return (
        response.statusCode,
        Map<String, dynamic>.from(
          jsonDecode(await utf8.decoder.bind(response).join()) as Map,
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  test('本机 API 鉴权、跨域拒绝、导入预览不写入、旧 text 入口可用', () async {
    await api.start();
    expect((await req('/api/competitions', auth: false)).$1, 401);
    expect(
      (await req('/api/competitions', origin: 'https://example.invalid')).$1,
      403,
    );
    final raw = {'name': '接口测试', 'deadline': '2099-12-31'};
    final preview = await req(
      '/api/import',
      method: 'POST',
      data: {'text': jsonEncode(raw), 'preview': true},
    );
    expect(preview.$2['competitions'], 1);
    expect(repo.allComps(), isEmpty);
    final imported = await req(
      '/api/import',
      method: 'POST',
      data: {'text': jsonEncode(raw)},
    );
    expect(imported.$2['report']['added'], 1);
    final id = repo.allComps().single.id;
    await req('/api/competitions/$id', method: 'PUT', data: {'notes': '已修改'});
    expect(repo.getComp(id)!.notes, '已修改');
    await req('/api/competitions/$id', method: 'DELETE');
    expect(repo.allComps(), isEmpty);
  });
  test('旧 awards records 导入接口及重复记录不重复创建', () async {
    await api.start();
    final payload = {
      'records': [
        {'name': 'API奖项', 'level': '国家级'},
      ],
    };
    expect(
      (await req(
        '/api/awards/import',
        method: 'POST',
        data: payload,
      )).$2['added'],
      1,
    );
    await req('/api/awards/import', method: 'POST', data: payload);
    expect(repo.allAwards(), hasLength(1));
  });
  test('同步必须批准，合成凭证按哈希传输，同名冲突保留原件', () async {
    final other = await Directory.systemTemp.createTemp('wc_peer_');
    final source = SyncService(api);
    final destRepo = await WcRepository.open(other.path);
    final dest = SyncService(AgentService(destRepo, changed: () {}));
    SyncClient? client;
    try {
      await File(repo.certs.path('proof.jpg')).writeAsBytes([1, 2, 3, 4]);
      await repo.upsertAward(
        Award.fromLegacyJson({
          'name': '合成奖项',
          'certificate_files': ['proof.jpg'],
        }),
      );
      await File(destRepo.certs.path('proof.jpg')).writeAsBytes([9, 9]);
      await source.start(loopbackOnly: true);
      source.begin();
      client = SyncClient(dest, Uri.parse('http://127.0.0.1:${source.port}'));
      await expectLater(
        client.jsonRequest('GET', '/manifest'),
        throwsStateError,
      );
      await client.requestPair(source.code);
      expect(await client.finishPair(), false);
      source.approve(client.requestId, true);
      expect(await client.finishPair(), true);
      final result = await client.transfer(
        push: false,
        update: false,
        status: (_) {},
      );
      expect(result['added'], 1);
      expect(await File(destRepo.certs.path('proof.jpg')).readAsBytes(), [
        9,
        9,
      ]);
      final copied = destRepo.allAwards().single.certificateFiles.single;
      expect(copied, isNot('proof.jpg'));
      expect(await File(destRepo.certs.path(copied)).readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
      await client.transfer(push: false, update: false, status: (_) {});
      expect(destRepo.allAwards(), hasLength(1));
      await source.stop();
    } finally {
      client?.cancel();
      await source.stop();
      await dest.stop();
      await other.delete(recursive: true);
    }
  });
  test('附件校验失败与路径穿越不得落入正式凭证', () async {
    final sync = SyncService(api);
    await expectLater(
      sync.receive(Stream.value([1]), '../bad', '${sha256.convert([1])}'),
      throwsFormatException,
    );
    await expectLater(
      sync.receive(Stream.value([2]), 'proof.jpg', '${sha256.convert([1])}'),
      throwsStateError,
    );
    expect(await File(repo.certs.path('proof.jpg')).exists(), false);
  });
  test('AI 模拟工具调用：拒绝写入不落盘，批准后使用真实仓库', () async {
    final mock = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var count = 0;
    mock.listen((r) async {
      await r.drain<void>();
      count++;
      final message = count.isOdd
          ? {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call1',
                  'type': 'function',
                  'function': {
                    'name': 'import',
                    'arguments': jsonEncode({
                      'data': jsonEncode({
                        'competitions': [
                          {'name': 'AI合成记录', 'deadline': '2099-01-01'},
                        ],
                      }),
                    }),
                  },
                },
              ],
            }
          : {'role': 'assistant', 'content': '已收到工具结果'};
      r.response.headers.contentType = ContentType.json;
      r.response.write(
        jsonEncode({
          'choices': [
            {'message': message},
          ],
        }),
      );
      await r.response.close();
    });
    try {
      final session = AiSession(api);
      final uri = Uri.parse('http://127.0.0.1:${mock.port}/chat/completions');
      await session.send(
        endpoint: uri,
        key: 'synthetic-key',
        model: 'mock',
        messages: [
          {'role': 'user', 'content': '导入'},
        ],
        approve: (_, _) async => false,
        status: (_) {},
      );
      expect(repo.allComps(), isEmpty);
      await session.send(
        endpoint: uri,
        key: 'synthetic-key',
        model: 'mock',
        messages: [
          {'role': 'user', 'content': '导入'},
        ],
        approve: (_, _) async => true,
        status: (_) {},
      );
      expect(repo.allComps(), hasLength(1));
    } finally {
      await mock.close(force: true);
    }
  });
}
