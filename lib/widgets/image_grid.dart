import 'package:flutter/material.dart';
import '../theme/catppuccin.dart';

/// 中央缩略图网格（占位 — 后续 Phase 接入图片数据 + GridView.builder）
class ImageGrid extends StatelessWidget {
  const ImageGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 64, color: Catppuccin.overlay0),
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
            '拖拽文件夹到此处或点击左侧面板添加文件夹',
            style: TextStyle(
              color: Catppuccin.overlay0,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              // TODO: 实现文件夹选择
            },
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
}
