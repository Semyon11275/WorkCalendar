import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sync_service.dart';
import 'management_page.dart';
import 'widgets.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(ref.watch(agentServiceProvider));
  ref.onDispose(service.stop);
  return service;
});

class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});
  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  SyncClient? _client;
  String _status = '';
  bool _busy = false;
  bool _update = false;
  List<String> _ips = [];
  @override
  void dispose() {
    _client?.cancel();
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => _status = '未完成：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transfer(bool push) async {
    final ok = await confirmDialog(
      context,
      push ? '推送到配对设备' : '从配对设备拉取',
      '将传输全部比赛、获奖和原始凭证。${_update ? '同 ID 记录将合并更新。' : '保留接收端已有记录，只新增缺失记录。'}不会同步删除。',
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final result = await _client!.transfer(
        push: push,
        update: _update,
        status: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (mounted) setState(() => _status = '完成：${jsonEncode(result)}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(syncServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设备配对与数据同步')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('仅在可信局域网使用。接收端批准后才可传输数据；本版提供手动合并推送/拉取，不自动传播删除。'),
          const SizedBox(height: 16),
          Text('这台设备作为接收端', style: Theme.of(context).textTheme.titleLarge),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        if (server.server == null) {
                          await server.start();
                          final interfaces = await NetworkInterface.list(
                            type: InternetAddressType.IPv4,
                          );
                          _ips = interfaces
                              .expand((i) => i.addresses)
                              .map((a) => 'http://${a.address}:${server.port}')
                              .toList();
                        } else {
                          await server.stop();
                          _ips = [];
                        }
                      }),
                child: Text(server.server == null ? '开启局域网接收' : '关闭接收并撤销配对'),
              ),
              OutlinedButton(
                onPressed: server.server == null || _busy
                    ? null
                    : () => setState(server.begin),
                child: const Text('生成配对码'),
              ),
              TextButton(
                onPressed: () => setState(() {}),
                child: const Text('刷新待批准请求'),
              ),
            ],
          ),
          if (server.server != null) ...[
            SelectableText(_ips.join('\n')),
            if (server.code.isNotEmpty)
              SelectableText('配对码：${server.code}（3 分钟有效）'),
            for (final entry in server.pending.entries)
              ListTile(
                title: Text('设备 ${entry.value['ip']}'),
                subtitle: Text(
                  entry.value['approved'] == null
                      ? '等待你的批准'
                      : entry.value['approved'] == true
                      ? '已批准'
                      : '已拒绝',
                ),
                trailing: entry.value['approved'] == null
                    ? Wrap(
                        children: [
                          TextButton(
                            onPressed: () => setState(
                              () => server.approve(entry.key, false),
                            ),
                            child: const Text('拒绝'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                setState(() => server.approve(entry.key, true)),
                            child: const Text('允许'),
                          ),
                        ],
                      )
                    : null,
              ),
          ],
          const Divider(height: 40),
          Text('连接另一台设备', style: Theme.of(context).textTheme.titleLarge),
          TextField(
            controller: _address,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: '接收端地址，例如 http://192.168.1.20:12345',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '接收端显示的配对码'),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        _client?.cancel();
                        _client = SyncClient(
                          server,
                          Uri.parse(_address.text.trim()),
                        );
                        await _client!.requestPair(_code.text.trim());
                        _status = '请求已发送，请在接收端刷新并批准';
                      }),
                child: const Text('请求配对'),
              ),
              OutlinedButton(
                onPressed: _busy || _client == null
                    ? null
                    : () => _run(() async {
                        _status = await _client!.finishPair()
                            ? '配对成功，可合并传输'
                            : '接收端尚未批准';
                      }),
                child: const Text('已批准，完成配对'),
              ),
            ],
          ),
          SwitchListTile(
            value: _update,
            onChanged: _busy ? null : (v) => setState(() => _update = v),
            title: const Text('合并更新接收端已有记录'),
            subtitle: const Text('默认关闭；关闭时仅新增，附件同名冲突另存，不覆盖原件。'),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _busy || (_client?.token.isEmpty ?? true)
                    ? null
                    : () => _transfer(false),
                child: const Text('合并拉取'),
              ),
              FilledButton(
                onPressed: _busy || (_client?.token.isEmpty ?? true)
                    ? null
                    : () => _transfer(true),
                child: const Text('合并推送'),
              ),
              if (_busy)
                TextButton(
                  onPressed: () {
                    _client?.cancel();
                  },
                  child: const Text('取消传输'),
                ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          SelectableText(_status),
        ],
      ),
    );
  }
}
