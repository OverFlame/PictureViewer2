import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/image_dao.dart';
import '../state/app_state.dart';
import '../theme/catppuccin.dart';

/// 中央缩略图网格 — GridView.builder 虚拟滚动，接入 AppState
class ImageGrid extends StatefulWidget {
  const ImageGrid({super.key});

  @override
  State<ImageGrid> createState() => _ImageGridState();
}

class _ImageGridState extends State<ImageGrid> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 400) {
      context.read<AppState>().loadMore();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // 空状态
    if (!appState.loading && appState.images.isEmpty) {
      return _buildEmptyState(context);
    }

    // 加载中（首次）
    if (appState.loading && appState.images.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: Catppuccin.mauve,
          strokeWidth: 2,
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (_) => false,
      child: GridView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1,
        ),
        itemCount: appState.images.length,
        itemBuilder: (ctx, i) => _ThumbnailCard(
          image: appState.images[i],
          selected: appState.selectedImage?.id == appState.images[i].id,
          onTap: () => appState.selectImage(appState.images[i].id),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final appState = context.read<AppState>();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, size: 64, color: Catppuccin.overlay0),
          const SizedBox(height: 16),
          const Text(
            '还没有加载图片',
            style: TextStyle(
              color: Catppuccin.subtext0,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击下方按钮选择文件夹开始导入',
            style: TextStyle(color: Catppuccin.overlay0, fontSize: 12),
          ),
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
    // 使用简陋但可用的文件夹选择方式
    // 桌面端可直接用 TextField + 手动输入路径
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Catppuccin.mantle,
        title: const Text('输入文件夹路径', style: TextStyle(color: Catppuccin.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如: D:\\Pictures',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(color: Catppuccin.text, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && Directory(result).existsSync()) {
      if (context.mounted) {
        appState.importDirectory(result);
      }
    } else if (result != null && result.isNotEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件夹不存在，请检查路径')),
        );
      }
    }
  }
}

/// 单个缩略图卡片
class _ThumbnailCard extends StatelessWidget {
  final ImageItem image;
  final bool selected;
  final VoidCallback onTap;

  const _ThumbnailCard({
    required this.image,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final thumbFile = File(appState.thumbPath(image.path));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Catppuccin.surface0,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? Catppuccin.mauve : Colors.transparent,
            width: selected ? 2 : 0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 缩略图（如果已缓存）或占位图标
            if (thumbFile.existsSync())
              Image.file(thumbFile, fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
                  _placeholder())
            else
              _placeholder(),

            // 底部文件名标签
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.black54,
                child: Text(
                  image.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
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
