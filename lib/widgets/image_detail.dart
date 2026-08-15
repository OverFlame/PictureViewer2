import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/image_dao.dart';
import '../db/tag_dao.dart';
import '../state/app_state.dart';
import '../services/exif_service.dart';
import '../services/thumbnail_cache.dart';
import '../theme/catppuccin.dart';
import '../utils/log_util.dart';
import 'export_actions.dart';

/// 右侧详情面板：选中图片信息 + 标签编辑
class ImageDetail extends StatefulWidget {
  const ImageDetail({super.key});

  @override
  State<ImageDetail> createState() => _ImageDetailState();
}

class _ImageDetailState extends State<ImageDetail> {
  ExifData? _exifData;
  bool _exifLoading = false;
  int? _lastImageId;

  @override
  Widget build(BuildContext context) {
    // 监听 selectedImage 变化
    final appState = context.watch<AppState>();
    final image = appState.selectedImage;

    // 选中图片变化时，重新加载 EXIF
    if (image != null && image.id != _lastImageId) {
      _lastImageId = image.id;
      _loadExif(image.path);
    } else if (image == null && _lastImageId != null) {
      _lastImageId = null;
      _exifData = null;
      _exifLoading = false;
    }

    if (image == null) {
      return Container(
        color: Catppuccin.crust,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: 48, color: Catppuccin.surface1),
              SizedBox(height: 12),
              Text(
                '选择一张图片以查看详情',
                style: TextStyle(color: Catppuccin.overlay1, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Catppuccin.crust,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          _panelHeader(),
          const Divider(height: 1),
          // 内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 大图预览（保持纵横比，点击打开全屏查看器）
                  _ImagePreview(image: image),
                  const SizedBox(height: 12),
                  _fileInfoSection(image),
                  const SizedBox(height: 16),
                  _divider(),
                  const SizedBox(height: 12),
                  _exifSection(),
                  const SizedBox(height: 12),
                  _divider(),
                  const SizedBox(height: 12),
                  _tagSection(context, appState, image),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── EXIF 信息 ──
  void _loadExif(String path) {
    setState(() => _exifLoading = true);
    _exifData = null;
    ExifService.read(path).then((data) {
      if (mounted) {
        setState(() {
          _exifData = data;
          _exifLoading = false;
        });
        logDebug('Detail', 'EXIF loaded for id=$_lastImageId: hasData=${data.hasData}');
      }
    });
  }

  Widget _exifSection() {
    if (_exifLoading) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(
          child: SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: Catppuccin.overlay1),
          ),
        ),
      );
    }

    final e = _exifData;
    if (e == null || !e.hasData) {
      return const Text('无 EXIF 数据',
          style: TextStyle(
              fontSize: 11,
              color: Catppuccin.overlay0));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('EXIF 信息',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Catppuccin.overlay2,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        if (e.make != null || e.model != null)
          _exifRow('相机',
              [e.make, e.model].whereType<String>().join(' ')),
        if (e.dateTime != null) _exifRow('拍摄时间', e.dateTime!),
        _exifRow('曝光',
            '${e.exposureDisplay}  ${e.fNumberDisplay}  ${e.isoDisplay}'),
        _exifRow('焦距', e.focalDisplay),
        if (e.flash != null)
          _exifRow('闪光灯', e.flash! ? '已开启' : '未开启'),
        _exifRow('尺寸', e.dimensionDisplay),
        if (e.lensModel != null) _exifRow('镜头', e.lensModel!),
        if (e.software != null) _exifRow('软件', e.software!),
        if (e.colorSpace != null) _exifRow('色彩空间', e.colorSpace!),
        if (e.orientation != null) _exifRow('方向', e.orientation!),
        if (e.gpsLatitude != null || e.gpsLongitude != null)
          _exifRow('GPS', e.gpsDisplay),
      ],
    );
  }

  Widget _exifRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Catppuccin.overlay1)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 11, color: Catppuccin.subtext1)),
          ),
        ],
      ),
    );
  }

  Widget _panelHeader() {
    final appState = context.read<AppState>();
    final image = appState.selectedImage;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Catppuccin.mantle,
      child: Row(
        children: [
          const Text(
            '详情',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Catppuccin.subtext0,
            ),
          ),
          const Spacer(),
          ExportActions(image: image),
        ],
      ),
    );
  }

  // ── 文件信息 ──
  Widget _fileInfoSection(ImageItem image) {
    final file = File(image.path);
    final exists = file.existsSync();
    final stat = exists ? file.statSync() : null;
    final mtime = stat != null
        ? DateTime.fromMillisecondsSinceEpoch(stat.modified.millisecondsSinceEpoch)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('文件信息',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Catppuccin.overlay2,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        _row('文件名', image.filename),
        _row('格式', (image.format ?? '?').toUpperCase()),
        _row('尺寸',
            '${image.width ?? '?'} x ${image.height ?? '?'}'),
        _row('文件大小', _formatSize(image.fileSize)),
        _row('路径', image.path, mono: true),
        if (mtime != null)
          _row('修改时间',
              '${mtime.year}-${mtime.month.toString().padLeft(2, '0')}-${mtime.day.toString().padLeft(2, '0')} '
                  '${mtime.hour.toString().padLeft(2, '0')}:${mtime.minute.toString().padLeft(2, '0')}'),
        if (!exists)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Catppuccin.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 12, color: Catppuccin.red),
                SizedBox(width: 4),
                Text('文件已丢失',
                    style: TextStyle(fontSize: 11, color: Catppuccin.red)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Catppuccin.overlay1)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: Catppuccin.text,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '?';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── 标签区域 ──
  Widget _tagSection(BuildContext context, AppState appState, ImageItem image) {
    final imageId = image.id;
    if (imageId == null) return const SizedBox.shrink();

    return _TagEditor(imageId: imageId);
  }

  Widget _divider() {
    return const Divider(height: 1, color: Catppuccin.surface0);
  }
}

/// 详情栏顶部大图预览：懒加载 800px 缩略图，保持纵横比，点击打开全屏查看器
class _ImagePreview extends StatefulWidget {
  final ImageItem image;
  const _ImagePreview({required this.image});

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  String? _previewPath;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.path != widget.image.path) {
      _previewPath = null;
      _loading = true;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final path = await ThumbnailService.instance
          .ensureThumbnail(widget.image.path, size: 800);
      if (mounted) {
        setState(() {
          _previewPath = path;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      logDebug('Detail', 'Preview load failed: ${widget.image.path} ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final appState = context.read<AppState>();
        appState.openViewer([widget.image], 0);
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Catppuccin.surface0,
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Catppuccin.overlay1,
            ),
          ),
        ),
      );
    }
    if (_failed || _previewPath == null) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  size: 32, color: Catppuccin.overlay0),
              SizedBox(height: 6),
              Text('预览不可用',
                  style: TextStyle(fontSize: 11, color: Catppuccin.overlay1)),
            ],
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: Image.file(
        File(_previewPath!),
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox(
          height: 120,
          child: Center(
            child: Icon(Icons.broken_image_outlined,
                size: 32, color: Catppuccin.overlay0),
          ),
        ),
      ),
    );
  }
}

/// 标签编辑器：显示已绑定标签 + 添加新标签
class _TagEditor extends StatefulWidget {
  final int imageId;
  const _TagEditor({required this.imageId});

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  List<Tag>? _imageTags;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void didUpdateWidget(_TagEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId) {
      _imageTags = null;
      _loading = true;
      _loadTags();
    }
  }

  Future<void> _loadTags() async {
    setState(() => _loading = true);
    final appState = context.read<AppState>();
    final tags = await appState.getImageTags(widget.imageId);
    if (mounted) {
      setState(() {
        _imageTags = tags;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 1.5, color: Catppuccin.overlay1,
          ),
        ),
      );
    }

    final bound = _imageTags ?? [];
    final boundIds = bound.map((t) => t.id).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('标签',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Catppuccin.overlay2,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        // 已绑定标签 chips
        if (bound.isNotEmpty)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: bound.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _tagColor(tag.color).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: _tagColor(tag.color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tag.name,
                      style: TextStyle(
                          fontSize: 11, color: _tagColor(tag.color)),
                    ),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: () {
                        appState.toggleTagOnSelected(tag);
                        setState(() {
                          bound.removeWhere((t) => t.id == tag.id);
                        });
                      },
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: _tagColor(tag.color).withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          )
        else
          const Text('未设置标签',
              style: TextStyle(fontSize: 11, color: Catppuccin.overlay0)),
        const SizedBox(height: 10),
        // 添加标签按钮
        InkWell(
          onTap: () => _showAddDialog(appState, boundIds),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: Catppuccin.surface1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 12, color: Catppuccin.overlay1),
                SizedBox(width: 4),
                Text('添加标签',
                    style: TextStyle(fontSize: 11, color: Catppuccin.overlay1)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAddDialog(AppState appState, Set<int?> boundIds) {
    final unbound = appState.allTags
        .where((t) => !boundIds.contains(t.id))
        .toList()
      ..sort((a, b) {
        final na = a.namespace.isEmpty ? 'zzz' : a.namespace;
        final nb = b.namespace.isEmpty ? 'zzz' : b.namespace;
        final cmp = na.compareTo(nb);
        return cmp != 0 ? cmp : a.name.compareTo(b.name);
      });

    showDialog(
      context: context,
      builder: (ctx) {
        final searchCtrl = TextEditingController();
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            backgroundColor: Catppuccin.mantle,
            title: const Text('添加标签', style: TextStyle(color: Catppuccin.text)),
            content: SizedBox(
              width: 280,
              height: 350,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      hintText: '搜索或输入新标签名...',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: unbound
                          .where((t) =>
                              searchCtrl.text.isEmpty ||
                              t.name
                                  .toLowerCase()
                                  .contains(searchCtrl.text.toLowerCase()))
                          .map((tag) => ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _tagColor(tag.color),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                title: Text(tag.name,
                                    style: const TextStyle(fontSize: 12)),
                                subtitle: tag.namespace.isNotEmpty
                                    ? Text(tag.namespace,
                                        style: const TextStyle(fontSize: 10))
                                    : null,
                                onTap: () {
                                  appState.toggleTagOnSelected(tag);
                                  Navigator.pop(ctx);
                                  _loadTags();
                                },
                              ))
                          .toList(),
                    ),
                  ),
                  // 如果搜索匹配为空，提供快速创建
                  if (searchCtrl.text.isNotEmpty &&
                      unbound
                          .where((t) => t.name
                              .toLowerCase()
                              .contains(searchCtrl.text.toLowerCase()))
                          .isEmpty)
                    ListTile(
                      dense: true,
                      leading:
                          const Icon(Icons.add, size: 16, color: Catppuccin.mauve),
                      title: Text(
                        '创建 "${searchCtrl.text}"',
                        style: const TextStyle(
                            fontSize: 12, color: Catppuccin.mauve),
                      ),
                      onTap: () async {
                        final tag = await appState.createTag(
                            searchCtrl.text.trim());
                        appState.toggleTagOnSelected(tag);
                        if (mounted) Navigator.pop(ctx);
                        _loadTags();
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭',
                    style: TextStyle(color: Catppuccin.overlay1)),
              ),
            ],
          );
        });
      },
    );
  }

  Color _tagColor(String hex) {
    try {
      final h = hex.replaceFirst('#', '');
      return Color(int.parse(h, radix: 16) | 0xFF000000);
    } catch (_) {
      return Catppuccin.mauve;
    }
  }
}
