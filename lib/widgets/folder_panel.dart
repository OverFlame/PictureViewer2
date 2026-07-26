import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../db/folder_dao.dart';
import '../state/app_state.dart';
import '../theme/catppuccin.dart';

/// 左侧文件夹面板：导入 + 文件夹列表
class FolderPanel extends StatefulWidget {
  const FolderPanel({super.key});

  @override
  State<FolderPanel> createState() => _FolderPanelState();
}

class _FolderPanelState extends State<FolderPanel> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final folders = appState.folders;

    return Column(
      children: [
        // 导入按钮
        Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: appState.importing ? null : () => _pickFolder(appState),
              icon: Icon(
                appState.importing ? Icons.hourglass_empty : Icons.create_new_folder,
                size: 16,
              ),
              label: Text(appState.importing ? '导入中...' : '添加文件夹'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Catppuccin.mauve,
                side: BorderSide(color: Catppuccin.surface1),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),
        // 导入进度条
        if (appState.importing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: LinearProgressIndicator(
              value: appState.importProgress,
              backgroundColor: Catppuccin.surface0,
              color: Catppuccin.mauve,
              minHeight: 2,
            ),
          ),
        const Divider(height: 1),
        // 文件夹列表
        Expanded(
          child: folders.isEmpty && !appState.importing
              ? _emptyGuide()
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: folders.map((f) => _folderItem(f, appState)).toList(),
                ),
        ),
      ],
    );
  }

  Widget _emptyGuide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 48, color: Catppuccin.overlay0),
            const SizedBox(height: 12),
            const Text(
              '点击「添加文件夹」导入图片',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Catppuccin.subtext0,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _folderItem(VirtualFolder folder, AppState appState) {
    return InkWell(
      onTap: () {
        // 选中文件夹时触发筛选（图片网格会按路径前缀过滤）
        // 这部分逻辑在 image_grid 的文件夹选择中处理
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.folder, size: 16, color: Catppuccin.yellow),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                folder.name,
                style: const TextStyle(fontSize: 12, color: Catppuccin.text),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${folder.id}',
              style: const TextStyle(fontSize: 10, color: Catppuccin.overlay0),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFolder(AppState appState) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: '选择包含图片的文件夹',
    );
    if (result != null && mounted) {
      await appState.importDirectory(result);
    }
  }
}
