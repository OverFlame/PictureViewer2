import 'package:flutter/material.dart';
import '../theme/catppuccin.dart';

/// 关于页对话框
class AppAboutDialog extends StatelessWidget {
  const AppAboutDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const AppAboutDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Catppuccin.mantle,
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Catppuccin.lavender.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.image_outlined,
                size: 36,
                color: Catppuccin.lavender,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'PictureViewer',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Catppuccin.text,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'v1.0.0',
              style: TextStyle(
                fontSize: 12,
                color: Catppuccin.overlay1,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '一款基于 Flutter 的现代化桌面图片浏览器，\n'
              '支持标签管理、EXIF 查看、批量导入等功能。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Catppuccin.subtext0,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(color: Catppuccin.surface0),
            const SizedBox(height: 12),
            _infoRow('框架', 'Flutter Desktop (Windows)'),
            _infoRow('主题', 'Catppuccin Mocha / Latte'),
            _infoRow('数据库', 'SQLite (sqflite)'),
            _infoRow('开发语言', 'Dart'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭',
              style: TextStyle(color: Catppuccin.overlay1)),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Catppuccin.overlay1,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                color: Catppuccin.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
