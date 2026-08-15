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
  Future<void> _openLocation(BuildContext context) async {
    final img = image;
    if (img == null) return;
    await _openFileLocation(img.path);
  }

  /// 在系统文件管理器中定位并显示文件。
  ///
  /// 各平台实现：
  /// - Windows: `explorer /select,<path>` 在资源管理器中选中该文件
  /// - macOS:   `open -R <path>` 在 Finder 中显示该文件
  /// - Linux:   `xdg-open <目录>`（xdg-open 无法选中单个文件，退而打开其所在目录）
  Future<void> _openFileLocation(String path) async {
    try {
      ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('explorer', ['/select,$path']);
      } else if (Platform.isMacOS) {
        result = await Process.run('open', ['-R', path]);
      } else {
        result = await Process.run('xdg-open', [p.dirname(path)]);
      }
      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        logWarn('Export',
            'Open file location exited ${result.exitCode}: ${result.stderr}');
      }
    } catch (e) {
      logError('Export', 'Failed to open file location', e.toString());
    }
  }
}
