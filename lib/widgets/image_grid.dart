import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/folder_dao.dart';
import '../db/image_dao.dart';
import '../services/thumbnail_cache.dart';
import '../state/app_state.dart';
import '../theme/catppuccin.dart';
import '../utils/log_util.dart';

/// 中间栏：资源管理器式浏览（子文件夹 + 直接图片），支持网格/列表视图与多选。
class ImageGrid extends StatefulWidget {
  const ImageGrid({super.key});

  @override
  State<ImageGrid> createState() => _ImageGridState();
}

class _ImageGridState extends State<ImageGrid> {
  void _openViewer(AppState appState, int index) {
    final images = appState.images;
    if (images.isEmpty) return;
    logInfo('Grid', 'Opening viewer at index $index (${images.length} images)');
    appState.openViewer(images, index);
  }

  /// 根据修饰键决定选择行为：Shift=区间、Ctrl=切换、否则单选
  void _handleImageTap(AppState appState, int id) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    if (shift) {
      appState.rangeSelect(id);
    } else if (ctrl) {
      appState.toggleSelect(id);
    } else {
      appState.selectImage(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final folders = appState.centerFolders;
    final images = appState.images;

    if (!appState.loading && folders.isEmpty && images.isEmpty) {
      return _buildEmptyState(context);
    }
    if (appState.loading && folders.isEmpty && images.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Catppuccin.mauve, strokeWidth: 2),
      );
    }

    if (appState.viewMode == 'list') {
      return _buildList(appState, folders, images);
    }
    return _buildGrid(appState, folders, images);
  }

  // ── 网格 ──
  Widget _buildGrid(AppState appState, List<VirtualFolder> folders,
      List<ImageItem> images) {
    final total = folders.length + images.length;
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: appState.gridColumns,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: total,
      itemBuilder: (ctx, i) {
        if (i < folders.length) {
          return _FolderTile(folder: folders[i], compact: true);
        }
        final img = images[i - folders.length];
        return _ThumbnailCard(
          image: img,
          selected: appState.isSelected(img.id ?? -1),
          onTap: () => _handleImageTap(appState, img.id!),
          onDoubleTap: () => _openViewer(appState, i - folders.length),
          compact: true,
        );
      },
    );
  }

  // ── 列表 ──
  Widget _buildList(AppState appState, List<VirtualFolder> folders,
      List<ImageItem> images) {
    final total = folders.length + images.length;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: total,
      itemBuilder: (ctx, i) {
        if (i < folders.length) {
          return _FolderTile(folder: folders[i], compact: false);
        }
        final img = images[i - folders.length];
        return _ThumbnailCard(
          image: img,
          selected: appState.isSelected(img.id ?? -1),
          onTap: () => _handleImageTap(appState, img.id!),
          onDoubleTap: () => _openViewer(appState, i - folders.length),
          compact: false,
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final appState = context.read<AppState>();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open, size: 64, color: Catppuccin.overlay0),
          const SizedBox(height: 16),
          const Text('这里还没有内容',
              style: TextStyle(color: Catppuccin.subtext0, fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          const Text('添加文件夹或拖拽图片开始导入',
              style: TextStyle(color: Catppuccin.overlay0, fontSize: 12)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _pickFolder(context, appState),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('添加文件夹'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Catppuccin.mauve,
              side: const BorderSide(color: Catppuccin.surface1),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder(BuildContext context, AppState appState) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: '选择包含图片的文件夹',
    );
    if (result != null && result.isNotEmpty && context.mounted) {
      await appState.importDirectory(result);
    }
  }
}

/// 文件夹瓦片（网格/列表）
class _FolderTile extends StatelessWidget {
  final VirtualFolder folder;
  final bool compact;

  const _FolderTile({required this.folder, required this.compact});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    if (compact) {
      return GestureDetector(
        onTap: () => appState.enterFolder(folder.id!),
        child: Container(
          decoration: BoxDecoration(
            color: Catppuccin.surface0,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder, size: 44, color: Catppuccin.yellow),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Catppuccin.text),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListTile(
      dense: true,
      leading: const Icon(Icons.folder, size: 22, color: Catppuccin.yellow),
      title: Text(folder.name,
          style: const TextStyle(fontSize: 13, color: Catppuccin.text)),
      onTap: () => appState.enterFolder(folder.id!),
    );
  }
}

/// 图片卡片（网格/列表），懒加载缩略图，支持多选高亮
class _ThumbnailCard extends StatefulWidget {
  final ImageItem image;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final bool compact;

  const _ThumbnailCard({
    required this.image,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.compact,
  });

  @override
  State<_ThumbnailCard> createState() => _ThumbnailCardState();
}

class _ThumbnailCardState extends State<_ThumbnailCard> {
  bool _thumbReady = false;

  @override
  void initState() {
    super.initState();
    _checkAndGenerate();
  }

  @override
  void didUpdateWidget(_ThumbnailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.path != widget.image.path) {
      _thumbReady = false;
      _checkAndGenerate();
    }
  }

  Future<void> _checkAndGenerate() async {
    final path = widget.image.path;
    final thumbFile = File(ThumbnailService.instance.thumbPath(path, size: 300));
    if (thumbFile.existsSync()) {
      if (mounted) setState(() => _thumbReady = true);
      return;
    }
    try {
      await ThumbnailService.instance.ensureThumbnail(path, size: 300);
      if (mounted) setState(() => _thumbReady = true);
    } catch (e) {
      logDebug('Grid', 'Thumbnail generate failed: $path ($e)');
    }
  }

  String get _displayName => widget.image.alias ?? widget.image.filename;

  @override
  Widget build(BuildContext context) {
    final thumbFile = File(ThumbnailService.instance.thumbPath(widget.image.path, size: 300));

    if (!widget.compact) {
      // 列表行
      return InkWell(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          color: widget.selected ? Catppuccin.surface0 : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: _thumbReady && thumbFile.existsSync()
                    ? Image.file(thumbFile, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder())
                    : _placeholder(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Catppuccin.text)),
                    if (widget.image.alias != null)
                      Text(widget.image.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: Catppuccin.overlay0)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 网格卡片
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      child: Container(
        decoration: BoxDecoration(
          color: Catppuccin.surface0,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.selected ? Catppuccin.mauve : Colors.transparent,
            width: widget.selected ? 2 : 0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_thumbReady && thumbFile.existsSync())
              Image.file(thumbFile, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder())
            else
              _placeholder(),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.black54,
                child: Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return const Center(
      child: Icon(Icons.image_outlined, color: Catppuccin.overlay0, size: 32),
    );
  }
}
