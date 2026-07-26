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
  final _pathController = TextEditingController();
  final _pathFocus = FocusNode();

  @override
  void dispose() {
    _pathController.dispose();
    _pathFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final folders = appState.folders;

    return Column(
      children: [
        // 路径输入框
        _buildPathInput(appState),
        // 导入按钮行
        _buildImportButtons(appState),
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

  Widget _buildPathInput(AppState appState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _pathController,
                focusNode: _pathFocus,
                enabled: !appState.importing,
                onSubmitted: (_) => _addFromPath(appState),
                decoration: InputDecoration(
                  hintText: '输入文件夹或文件路径，回车添加',
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: Catppuccin.overlay1,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Catppuccin.surface1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Catppuccin.surface1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Catppuccin.mauve),
                  ),
                  filled: true,
                  fillColor: Catppuccin.surface0,
                ),
                style: TextStyle(fontSize: 12, color: Catppuccin.text),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 32,
            child: IconButton(
              onPressed: appState.importing ? null : () => _addFromPath(appState),
              icon: const Icon(Icons.add, size: 18),
              tooltip: '从路径添加',
              style: IconButton.styleFrom(
                foregroundColor: Catppuccin.mauve,
                backgroundColor: Catppuccin.surface0,
                side: BorderSide(color: Catppuccin.surface1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportButtons(AppState appState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: appState.importing ? null : () => _pickFolder(appState),
                icon: Icon(
                  appState.importing ? Icons.hourglass_empty : Icons.create_new_folder,
                  size: 14,
                ),
                label: Text(
                  appState.importing ? '导入中...' : '添加文件夹',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Catppuccin.mauve,
                  side: BorderSide(color: Catppuccin.surface1),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: appState.importing ? null : () => _pickFiles(appState),
                icon: Icon(
                  Icons.image_outlined,
                  size: 14,
                  color: appState.importing ? Catppuccin.overlay1 : Catppuccin.teal,
                ),
                label: Text(
                  '浏览文件',
                  style: TextStyle(
                    fontSize: 12,
                    color: appState.importing ? Catppuccin.overlay1 : Catppuccin.text,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Catppuccin.teal,
                  side: BorderSide(color: Catppuccin.surface1),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ),
            ),
          ),
        ],
      ),
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
              '拖拽文件夹/图片到主区域 |\n点击按钮浏览 | 输入路径添加',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Catppuccin.subtext0,
                fontSize: 12,
                height: 1.5,
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

  void _addFromPath(AppState appState) {
    final text = _pathController.text.trim();
    if (text.isEmpty) return;
    _pathController.clear();
    _pathFocus.unfocus();
    appState.importPaths([text]);
  }

  Future<void> _pickFolder(AppState appState) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: '选择包含图片的文件夹',
    );
    if (result != null && mounted) {
      await appState.importDirectory(result);
    }
  }

  Future<void> _pickFiles(AppState appState) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'tiff', 'tif', 'ico',
      ],
      allowMultiple: true,
      dialogTitle: '选择图片文件',
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      final paths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();
      if (paths.isNotEmpty) {
        await appState.importPaths(paths);
      }
    }
  }
}
