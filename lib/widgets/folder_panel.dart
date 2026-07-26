import 'package:flutter/material.dart';
import '../theme/catppuccin.dart';

/// 左侧文件夹面板（占位 — 后续 Phase 接入数据库）
class FolderPanel extends StatelessWidget {
  const FolderPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 欢迎引导
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            children: [
              Icon(Icons.folder_open, size: 48, color: Catppuccin.overlay0),
              const SizedBox(height: 12),
              const Text(
                '添加文件夹开始使用',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Catppuccin.subtext0,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '点击下方按钮或拖拽文件夹到窗口',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Catppuccin.overlay0,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  // TODO: 实现文件夹选择
                },
                icon: const Icon(Icons.create_new_folder, size: 18),
                label: const Text('添加文件夹'),
                style: FilledButton.styleFrom(
                  backgroundColor: Catppuccin.mauve,
                  foregroundColor: Catppuccin.base,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        // 文件夹列表区域（占位）
      ],
    );
  }
}
