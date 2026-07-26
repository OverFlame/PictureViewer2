import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../db/image_dao.dart';
import '../state/app_state.dart';
import '../theme/catppuccin.dart';
import '../utils/log_util.dart';

/// 导出 / 分享操作按钮组
class ExportActions extends StatelessWidget {
  final ImageItem? image;
  final VoidCallback? onDone;

  const ExportActions({super.key, this.image, this.onDone});

  @override
  Widget build(BuildContext context) {
    if (image == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actionButton(
          icon: Icons.file_copy,
          tooltip: '另存为...',
          onTap: () => _saveAs(context),
        ),
        const SizedBox(width: 2),
        _actionButton(
          icon: Icons.folder_open,
          tooltip: '打开文件位置',
          onTap: () => _openLocation(context),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Catppuccin.surface0,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: Catppuccin.overlay1),
        ),
      ),
    );
  }

  // ── 另存为 ──
  Future<void> _saveAs(BuildContext context) async {
    final img = image;
    if (img == null) return;

    final appState = context.read<AppState>();
    String? destDir = await FilePicker.getDirectoryPath(
      dialogTitle: '选择保存目录',
    );

    if (destDir == null || !context.mounted) return;

    final destPath = await appState.copySelectedImageTo(destDir);
    if (destPath != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存到 ${p.relative(destPath)}'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '打开',
            textColor: Catppuccin.lavender,
            onPressed: () => _openFileLocation(destPath),
          ),
        ),
      );
      onDone?.call();
    }
  }

  // ── 打开文件位置 ──
  void _openLocation(BuildContext context) {
    final img = image;
    if (img == null) return;
    _openFileLocation(img.path);
  }

  void _openFileLocation(String path) {
    try {
      Process.run('explorer', ['/select,', path]);
    } catch (e) {
      logError('Export', 'Failed to open file location', e.toString());
    }
  }
}
