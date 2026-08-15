import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../db/folder_dao.dart';
import '../state/app_state.dart';
import '../theme/catppuccin.dart';

/// 左侧文件夹面板：导入 + 树形文件夹浏览（资源管理器式）
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
        // 树形文件夹列表
        Expanded(
          child: folders.isEmpty && !appState.importing
              ? _emptyGuide()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _allImagesEntry(appState),
                    _treeHeader(appState),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 8),
                        children: [
                          for (final f in folders)
                            _FolderTreeNode(
                              key: ValueKey('folder-${f.id}'),
                              folder: f,
                              depth: 0,
                              selectedId: appState.currentFolderId,
                              version: appState.folderVersion,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // ── 「全部图片」入口 ──
  Widget _allImagesEntry(AppState appState) {
    final selected = appState.currentFolderId == null;
    return InkWell(
      onTap: () => appState.goRoot(),
      child: Container(
        color: selected ? Catppuccin.surface0 : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 16,
              color: selected ? Catppuccin.mauve : Catppuccin.blue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '全部图片',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? Catppuccin.text : Catppuccin.subtext0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 树标题行（含新建根文件夹） ──
  Widget _treeHeader(AppState appState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 2),
      child: Row(
        children: [
          const Text(
            '文件夹',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Catppuccin.overlay1,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: () => _createRootFolder(appState),
              icon: const Icon(Icons.create_new_folder_outlined,
                  size: 15, color: Catppuccin.overlay0),
              tooltip: '新建根文件夹',
            ),
          ),
        ],
      ),
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
              onPressed:
                  appState.importing ? null : () => _addFromPath(appState),
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
                onPressed:
                    appState.importing ? null : () => _pickFolder(appState),
                icon: Icon(
                  appState.importing
                      ? Icons.hourglass_empty
                      : Icons.create_new_folder,
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
                onPressed:
                    appState.importing ? null : () => _pickFiles(appState),
                icon: Icon(
                  Icons.image_outlined,
                  size: 14,
                  color: appState.importing
                      ? Catppuccin.overlay1
                      : Catppuccin.teal,
                ),
                label: Text(
                  '浏览文件',
                  style: TextStyle(
                    fontSize: 12,
                    color: appState.importing
                        ? Catppuccin.overlay1
                        : Catppuccin.text,
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

  // ── 文件夹 CRUD 操作 ──

  Future<void> _createRootFolder(AppState appState) async {
    final name = await _promptFolderName('新建根文件夹');
    if (name == null || name.isEmpty) return;
    await appState.createFolder(name);
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

  Future<String?> _promptFolderName(String title, {String? initial}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

/// 递归树节点：懒加载子文件夹 + 展开/收起 + 右键菜单
class _FolderTreeNode extends StatefulWidget {
  final VirtualFolder folder;
  final int depth;
  final int? selectedId;
  final int version;

  const _FolderTreeNode({
    super.key,
    required this.folder,
    required this.depth,
    required this.selectedId,
    required this.version,
  });

  @override
  State<_FolderTreeNode> createState() => _FolderTreeNodeState();
}

class _FolderTreeNodeState extends State<_FolderTreeNode> {
  List<VirtualFolder>? _children;
  bool _expanded = false;
  bool _loadingChildren = false;

  @override
  void didUpdateWidget(_FolderTreeNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 结构变化（新建/重命名/删除/移动）后重新加载子节点
    if (oldWidget.version != widget.version) {
      _children = null;
      if (_expanded) {
        _loadChildren();
      }
    }
  }

  Future<void> _toggle() async {
    final willExpand = !_expanded;
    setState(() => _expanded = willExpand);
    if (willExpand && _children == null) {
      await _loadChildren();
    }
  }

  Future<void> _loadChildren() async {
    if (_loadingChildren) return;
    setState(() => _loadingChildren = true);
    final appState = context.read<AppState>();
    final children = await appState.loadChildFolders(widget.folder.id!);
    if (mounted) {
      setState(() {
        _children = children;
        _loadingChildren = false;
        if (children.isNotEmpty) _expanded = true;
      });
    }
  }

  Future<void> _createChildFolder(AppState appState) async {
    final name = await _promptName('新建子文件夹');
    if (name == null || name.isEmpty) return;
    await appState.createFolder(name, parentId: widget.folder.id);
    if (mounted) {
      _children = null;
      _expanded = true;
      _loadChildren();
    }
  }

  Future<void> _rename(AppState appState) async {
    final name =
        await _promptName('重命名文件夹', initial: widget.folder.name);
    if (name == null || name.isEmpty) return;
    await appState.renameFolder(widget.folder.id!, name);
  }

  Future<void> _delete(AppState appState) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除文件夹「${widget.folder.name}」？'),
        content: const Text('仅删除虚拟文件夹记录，不会删除磁盘上的图片。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Catppuccin.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await appState.deleteFolder(widget.folder.id!);
    }
  }

  Future<String?> _promptName(String title, {String? initial}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selected = widget.selectedId == widget.folder.id;
    final hasChildren =
        _children == null ? null : (_children!.isNotEmpty);

    return Column(
      children: [
        InkWell(
          onTap: () => appState.enterFolder(widget.folder.id!),
          child: Container(
            color: selected ? Catppuccin.surface0 : null,
            padding: EdgeInsets.only(
              left: 6 + widget.depth * 14.0,
              right: 4,
              top: 2,
              bottom: 2,
            ),
            child: Row(
              children: [
                // 展开箭头（懒加载后若无子文件夹则隐藏）
                SizedBox(
                  width: 20,
                  height: 20,
                  child: hasChildren == false
                      ? null
                      : InkWell(
                          onTap: _toggle,
                          borderRadius: BorderRadius.circular(4),
                          child: Icon(
                            _expanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 16,
                            color: Catppuccin.overlay0,
                          ),
                        ),
                ),
                Icon(
                  _expanded
                      ? Icons.folder_open
                      : Icons.folder,
                  size: 15,
                  color: Catppuccin.yellow,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.folder.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected ? Catppuccin.text : Catppuccin.subtext0,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 更多菜单
                SizedBox(
                  width: 24,
                  height: 20,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 15,
                    icon: const Icon(Icons.more_vert,
                        size: 15, color: Catppuccin.overlay0),
                    tooltip: '文件夹操作',
                    onSelected: (v) => _onMenu(v, appState),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'new',
                        child: Text('新建子文件夹', style: TextStyle(fontSize: 12)),
                      ),
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('重命名', style: TextStyle(fontSize: 12)),
                      ),
                      if (widget.folder.parentId != null)
                        const PopupMenuItem(
                          value: 'move_root',
                          child: Text('移动到根级', style: TextStyle(fontSize: 12)),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('删除',
                            style: TextStyle(
                                fontSize: 12, color: Catppuccin.red)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 展开后的子节点
        if (_expanded && _children != null)
          for (final child in _children!)
            _FolderTreeNode(
              key: ValueKey('folder-${child.id}'),
              folder: child,
              depth: widget.depth + 1,
              selectedId: widget.selectedId,
              version: widget.version,
            ),
      ],
    );
  }

  void _onMenu(String value, AppState appState) {
    switch (value) {
      case 'new':
        _createChildFolder(appState);
        break;
      case 'rename':
        _rename(appState);
        break;
      case 'move_root':
        appState.moveFolder(widget.folder.id!, null);
        break;
      case 'delete':
        _delete(appState);
        break;
    }
  }
}
