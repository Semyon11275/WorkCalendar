/// 凭证查看器：图片用 InteractiveViewer 缩放；PDF/HTML 等交系统外部打开。
/// 原则：预览不触碰原件字节，不注入任何应用脚本桥。
library;

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../state/providers.dart';
import 'widgets.dart';

const _imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'};

class CertificateViewerPage extends ConsumerStatefulWidget {
  const CertificateViewerPage({
    super.key,
    required this.awardId,
    required this.initialIndex,
  });
  final String awardId;
  final int initialIndex;

  static Route<void> route({
    required String awardId,
    required int initialIndex,
  }) => MaterialPageRoute(
    builder: (_) =>
        CertificateViewerPage(awardId: awardId, initialIndex: initialIndex),
  );

  @override
  ConsumerState<CertificateViewerPage> createState() =>
      _CertificateViewerPageState();
}

class _CertificateViewerPageState extends ConsumerState<CertificateViewerPage> {
  late int _index = widget.initialIndex;
  final TransformationController _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _copying = false;
  Future<void> _copyImage(String path) async {
    setState(() => _copying = true);
    try {
      final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
      final frame = await codec.getNextFrame();
      codec.dispose();
      try {
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        if (data == null) throw StateError('无法解码图片');
        await const MethodChannel('workcalendar/image_clipboard').invokeMethod<void>('copyRgba', {
          'width': frame.image.width, 'height': frame.image.height,
          'bytes': data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        });
      } finally { frame.image.dispose(); }
      if (mounted) showSnack(context, '图片已复制，可直接粘贴');
    } catch (e) {
      if (mounted) showSnack(context, '复制失败：$e', error: true);
    } finally { if (mounted) setState(() => _copying = false); }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// 双击在「放大到点击位置」与「还原」间切换（对齐旧版全屏查看器）。
  void _handleDoubleTap() {
    if (_transform.value != Matrix4.identity()) {
      _transform.value = Matrix4.identity();
      return;
    }
    final position = _doubleTapDetails?.localPosition;
    const scale = 2.5;
    if (position != null) {
      _transform.value = Matrix4.translationValues(
        -position.dx * (scale - 1),
        -position.dy * (scale - 1),
        0,
      ).scaledByDouble(scale, scale, scale, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final repo = ref.watch(repositoryProvider);
    final award = lib.awards.where((a) => a.id == widget.awardId).firstOrNull;
    final scheme = Theme.of(context).colorScheme;

    if (award == null || award.certificateFiles.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(icon: Icons.error_outline, title: '记录不存在或没有凭证'),
      );
    }
    final names = award.certificateFiles;
    if (_index >= names.length) _index = 0;
    final name = names[_index];
    final path = repo.certs.path(name);
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.')).toLowerCase()
        : '';
    final isImage = _imageExts.contains(ext);
    final exists = File(path).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (Platform.isWindows && exists && isImage)
            IconButton(tooltip: '复制图片', icon: const Icon(Icons.copy),
              onPressed: _copying ? null : () => _copyImage(path)),
          IconButton(
            tooltip: '外部打开',
            icon: const Icon(Icons.open_in_new),
            onPressed: () async {
              final r = await OpenFilex.open(path);
              if (r.type != ResultType.done && context.mounted) {
                showSnack(context, '打开失败：${r.message}', error: true);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: !exists
                ? EmptyView(
                    icon: Icons.file_present_outlined,
                    title: '凭证文件缺失',
                    hint: '记录中只留有文件名「$name」，原件不在数据目录。可重新添加或从备份恢复。',
                  )
                : isImage
                ? GestureDetector(
                    onDoubleTapDown: (d) => _doubleTapDetails = d,
                    onDoubleTap: _handleDoubleTap,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      maxScale: 8,
                      child: Center(
                        child: Image.file(
                          File(File('$path.preview.jpg').existsSync() ? '$path.preview.jpg' : path),
                          cacheWidth: 1600,
                          errorBuilder: (_, _, _) => EmptyView(
                            icon: Icons.broken_image_outlined,
                            title: '图片无法解码',
                            hint: '文件可能损坏，可尝试外部打开',
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 56,
                          color: scheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          ext == '.pdf'
                              ? 'PDF 凭证请用系统查看器打开'
                              : '该格式不支持内嵌预览，请用系统查看器打开',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final r = await OpenFilex.open(path);
                            if (r.type != ResultType.done && context.mounted) {
                              showSnack(
                                context,
                                '打开失败：${r.message}',
                                error: true,
                              );
                            }
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('用系统查看器打开'),
                        ),
                      ],
                    ),
                  ),
          ),
          if (names.length > 1)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '上一个',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _index > 0
                          ? () => setState(() {
                              _transform.value = Matrix4.identity();
                              _index--;
                            })
                          : null,
                    ),
                    Text('${_index + 1} / ${names.length}'),
                    IconButton(
                      tooltip: '下一个',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _index < names.length - 1
                          ? () => setState(() {
                              _transform.value = Matrix4.identity();
                              _index++;
                            })
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
