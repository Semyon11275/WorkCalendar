import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/agent_service.dart';
import '../services/ai_session.dart';
import '../state/providers.dart';
import 'widgets.dart';

final agentServiceProvider = Provider<AgentService>((ref) {
  final service = AgentService(
    ref.watch(repositoryProvider),
    changed: () => ref.invalidate(libraryProvider),
  );
  ref.onDispose(service.stop);
  return service;
});

class ManagementPage extends ConsumerStatefulWidget {
  const ManagementPage({super.key});
  @override
  ConsumerState<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends ConsumerState<ManagementPage> {
  final _url = TextEditingController(
    text: 'https://api.deepseek.com/chat/completions',
  );
  final _model = TextEditingController(text: 'deepseek-chat');
  final _key = TextEditingController();
  final _input = TextEditingController();
  final List<Map<String, dynamic>> _history = [];
  late AiSession _ai;
  bool _busy = false;
  String _status = '';
  @override
  void initState() {
    super.initState();
    _ai = AiSession(ref.read(agentServiceProvider));
    final config = readAppSettings(ref.read(repositoryProvider));
    _url.text = '${config['ai_endpoint'] ?? _url.text}';
    _model.text = '${config['ai_model'] ?? _model.text}';
  }

  @override
  void dispose() {
    _ai.cancel();
    for (final c in [_url, _model, _key, _input]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_input.text.trim().isEmpty ||
        _key.text.trim().isEmpty ||
        _model.text.trim().isEmpty) {
      showSnack(context, '请填写 API 密钥、模型和消息');
      return;
    }
    final text = _input.text.trim();
    _input.clear();
    setState(() {
      _busy = true;
      _history.add({'role': 'user', 'content': text});
    });
    try {
      await writeAppSetting(
        ref.read(repositoryProvider),
        'ai_endpoint',
        _url.text.trim(),
      );
      await writeAppSetting(
        ref.read(repositoryProvider),
        'ai_model',
        _model.text.trim(),
      );
      final answer = await _ai.send(
        endpoint: Uri.parse(_url.text.trim()),
        key: _key.text.trim(),
        model: _model.text.trim(),
        messages: List.of(_history),
        status: (s) {
          if (mounted) setState(() => _status = s);
        },
        approve: (name, args) async {
          if (!mounted) return false;
          return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('确认 AI 操作：$name'),
                  content: SizedBox(
                    width: 600,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(args),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('拒绝'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('确认执行'),
                    ),
                  ],
                ),
              ) ??
              false;
        },
      );
      if (mounted) {
        setState(() => _history.add({'role': 'assistant', 'content': answer}));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _history.add({'role': 'assistant', 'content': '请求未完成：$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(agentServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AI 助手与管理接口')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '外部 Agent API',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    api.server == null
                        ? '已关闭；开启后仅本机可访问'
                        : '运行中：http://127.0.0.1:${api.port}',
                  ),
                  const Text(
                    '支持记录查询、增改删、JSON/Markdown 一键批量导入和导入预览。外部调用的写入会直接生效，请只把令牌交给可信 Agent。',
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: () async {
                          try {
                            if (api.server == null) {
                              await api.start();
                            } else {
                              await api.stop();
                            }
                            if (mounted) setState(() {});
                          } catch (e) {
                            if (context.mounted) {
                              showSnack(context, '启动失败：$e', error: true);
                            }
                          }
                        },
                        child: Text(api.server == null ? '开启本机 API' : '关闭 API'),
                      ),
                      if (api.server != null)
                        OutlinedButton(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: jsonEncode({
                                  'url': 'http://127.0.0.1:${api.port}',
                                  'header': 'X-API-Token',
                                  'token': api.token,
                                }),
                              ),
                            );
                            if (context.mounted) {
                              showSnack(context, '连接配置已复制（含访问令牌）');
                            }
                          },
                          child: const Text('复制 Agent 连接配置'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('内置 AI 助手', style: Theme.of(context).textTheme.titleLarge),
          const Text(
            '兼容旧版的 OpenAI 格式服务；查询结果会发送给你指定的 AI 服务。每次写入在本机单独确认。密钥仅在本页内存中保留，不写入归档。',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: '完整 chat/completions 地址',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _model,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '模型名'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _key,
            enabled: !_busy,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API 密钥（本次会话）'),
          ),
          const SizedBox(height: 16),
          for (final message in _history)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  '${message['role'] == 'user' ? '你' : '助手'}：${message['content']}',
                ),
              ),
            ),
          if (_busy) ...[const LinearProgressIndicator(), Text(_status)],
          TextField(
            controller: _input,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '例如：找出本周截止的比赛；导入下面的获奖 JSON……',
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: _busy ? null : _send,
                child: const Text('发送'),
              ),
              if (_busy)
                TextButton(
                  onPressed: () => _ai.cancel(),
                  child: const Text('取消请求'),
                ),
              TextButton(
                onPressed: _busy ? null : () => setState(_history.clear),
                child: const Text('清空对话'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
