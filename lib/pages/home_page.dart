import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../state/app_state.dart';
import '../theme/catppuccin.dart';
import '../widgets/folder_panel.dart';
import '../widgets/tag_panel.dart';
import '../widgets/image_grid.dart';
import '../widgets/image_detail.dart';
import '../widgets/image_viewer.dart';
import '../widgets/filter_dialog.dart';
import '../widgets/tag_picker_dialog.dart';
import '../utils/log_util.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 左右面板的目标宽度
  static const double _leftPanelWidth = 280;
  static const double _rightPanelWidth = 320;

  /// 中央区域要保住的最小宽度。窗口不够时按比例压缩两侧面板去腾这块地方，
  /// 否则两侧固定宽度加起来会把中央挤成负数，顶部工具栏先报 overflow。
  static const double _minCenterWidth = 320;

  /// 面板被压到这么窄就别留了：半个面板既看不清内容，里面的行也放不下。
  static const double _minPanelWidth = 150;

  /// 两个分隔条的总宽
  static const double _resizeHandleWidth = 4;

  // 面板可见性
  bool _leftPanelOpen = true;
  bool _rightPanelOpen = true;

  // 左侧面板当前 tab: 0=文件夹, 1=标签
  int _leftTabIndex = 0;

  // 拖拽状态
  bool _dragging = false;

  /// 按窗口宽度算出两侧面板实际能占的宽度（只影响显示，不改用户的面板开关状态）。
  ///
  /// 窗口宽到装得下 280 + 320 + 中央 320 时就是原值；再窄就等比压缩，
  /// 压到不足 [_minPanelWidth] 直接不给这块地。
  ({double left, double right}) _panelWidths(double totalWidth) {
    var left = _leftPanelOpen ? _leftPanelWidth : 0.0;
    var right = _rightPanelOpen ? _rightPanelWidth : 0.0;
    final desired = left + right;
    final budget = totalWidth - _resizeHandleWidth * 2 - _minCenterWidth;
    if (desired == 0 || budget >= desired) return (left: left, right: right);

    final factor = budget <= 0 ? 0.0 : budget / desired;
    left *= factor;
    right *= factor;
    if (left < _minPanelWidth) left = 0;
    if (right < _minPanelWidth) right = 0;
    return (left: left, right: right);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return DropTarget(
      onDragDone: (detail) {
        setState(() => _dragging = false);
        _handleDrop(detail.files.map((f) => f.path).toList(), appState);
      },
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      child: Stack(
        children: [
          Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                final panels = _panelWidths(constraints.maxWidth);
                return Row(
                  children: [
                    // ═══ 左面板 ═══
                    if (_leftPanelOpen && panels.left > 0)
                      SizedBox(
                        width: panels.left,
                        child: _buildLeftPanel(),
                      ),

                    // 分隔条
                    _buildResizeHandle(() {
                      setState(() => _leftPanelOpen = !_leftPanelOpen);
                    }),

                    // ═══ 中央主区域 ═══
                    Expanded(child: _buildCenter()),

                    // 分隔条
                    _buildResizeHandle(() {
                      setState(() => _rightPanelOpen = !_rightPanelOpen);
                    }),

                    // ═══ 右面板 ═══
                    if (_rightPanelOpen && panels.right > 0)
                      SizedBox(
                        width: panels.right,
                        child: const ImageDetail(),
                      ),
                  ],
                );
              },
            ),
          ),
          // 拖拽提示覆盖层
          if (_dragging) _buildDropOverlay(),
          // 全屏图片查看器
          if (appState.showViewer) ImageViewer(state: appState),
        ],
      ),
    );
  }

  void _handleDrop(List<String> paths, AppState appState) {
    if (paths.isEmpty) return;
    logInfo('Home', 'Drop: ${paths.length} path(s)');
    appState.importPaths(paths);
  }

  Widget _buildDropOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Catppuccin.mauve.withValues(alpha: 0.15),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              decoration: BoxDecoration(
                color: Catppuccin.mantle.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Catppuccin.mauve,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 56,
                    color: Catppuccin.mauve,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '拖放文件夹或图片到此处',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Catppuccin.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '支持文件夹、单张或多张图片',
                    style: TextStyle(
                      fontSize: 13,
                      color: Catppuccin.subtext0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 左侧面板（文件夹 / 标签 切换） ──
  Widget _buildLeftPanel() {
    return Container(
      color: Catppuccin.mantle,
      child: Column(
        children: [
          // Tab 切换条
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: _leftTab('文件夹', 0),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _leftTab('标签', 1),
                ),
              ],
            ),
          ),
          const Divider(),
          // 面板内容
          Expanded(
            child: IndexedStack(
              index: _leftTabIndex,
              children: const [
                FolderPanel(),
                TagPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _leftTab(String label, int index) {
    final selected = _leftTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _leftTabIndex = index),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? Catppuccin.surface0 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Catppuccin.text : Catppuccin.overlay1,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ── 中央区域 ──
  Widget _buildCenter() {
    final appState = context.watch<AppState>();
    return Container(
      color: Catppuccin.base,
      child: Column(
        children: [
          const _TopToolbar(),
          const Divider(height: 1),
          // 面包屑导航（进入文件夹后显示）
          if (appState.currentFolder != null) const _BreadcrumbBar(),
          // 高级筛选活跃提示条
          if (appState.hasAdvancedFilter) const _AdvancedFilterBar(),
          // 多选操作条
          if (appState.selectedIds.isNotEmpty) const _SelectionBar(),
          const Expanded(child: ImageGrid()),
          const _BottomStatusBar(),
        ],
      ),
    );
  }

  // ── 拖拽折叠分隔条 ──
  Widget _buildResizeHandle(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 4,
          color: Catppuccin.crust,
          alignment: Alignment.center,
          child: Icon(
            Icons.more_vert,
            size: 12,
            color: Catppuccin.overlay0,
          ),
        ),
      ),
    );
  }
}

/// 顶部工具栏
class _TopToolbar extends StatefulWidget {
  const _TopToolbar();

  @override
  State<_TopToolbar> createState() => _TopToolbarState();
}

class _TopToolbarState extends State<_TopToolbar> {
  /// 搜索防抖时长。每敲一个键直接 refresh 会把列表刷成中间态，
  /// 而搜索词只有这一个输入框会改，攒一下再发足够快。
  static const _searchDebounce = Duration(milliseconds: 250);

  late final TextEditingController _ctrl;

  /// 输入过程中不能重建 controller，否则光标会被挪到末尾
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: context.read<AppState>().searchQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      if (!mounted) return;
      context.read<AppState>().setSearchQuery(_ctrl.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Catppuccin.mantle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 行内摆下「搜索框 + 排序 + 5 个动作」要 320 宽（6 个 48 的控件 + 间距 + 内边距）。
          // 不够宽还硬摆就会把这一行撑破——窗口 900 宽、左右面板都开着时中央只剩 292。
          final compact = constraints.maxWidth < 360;
          return Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    hintText: '搜索文件名...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (compact) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (v) => _onCompactSelected(appState, v),
                  itemBuilder: (_) => _compactItems(appState),
                ),
              ] else ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: '排序方式',
                  icon: const Icon(Icons.sort, size: 18),
                  onSelected: (v) => appState.setSortKey(v),
                  itemBuilder: (_) => [
                    _sortItem('添加时间', 'added_at', appState.sortKey),
                    _sortItem('文件名', 'filename', appState.sortKey),
                    _sortItem('别名', 'alias', appState.sortKey),
                    _sortItem('文件大小', 'file_size', appState.sortKey),
                    _sortItem('修改时间', 'file_mtime', appState.sortKey),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    appState.sortDescending
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    size: 18,
                  ),
                  tooltip: appState.sortDescending ? '降序（点击切换升序）' : '升序（点击切换降序）',
                  onPressed: () =>
                      appState.setSortDescending(!appState.sortDescending),
                ),
                IconButton(
                  icon: Icon(
                    appState.viewMode == 'grid'
                        ? Icons.view_list
                        : Icons.grid_view,
                    size: 18,
                  ),
                  tooltip: appState.viewMode == 'grid' ? '切换到列表' : '切换到网格',
                  onPressed: () => appState
                      .setViewMode(appState.viewMode == 'grid' ? 'list' : 'grid'),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list, size: 18),
                  color: appState.hasAdvancedFilter ? Catppuccin.mauve : null,
                  tooltip: '高级筛选',
                  onPressed: () => AdvancedFilterDialog.show(context),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: '刷新',
                  onPressed: () => appState.refresh(),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  tooltip: '设置',
                  onPressed: () => SettingsDialog.show(context),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// 窄窗口下的单一入口：排序、升降序、视图、筛选、刷新、设置全收进这个菜单。
  List<PopupMenuEntry<String>> _compactItems(AppState appState) {
    const sorts = <(String, String)>[
      ('added_at', '添加时间'),
      ('filename', '文件名'),
      ('alias', '别名'),
      ('file_size', '文件大小'),
      ('file_mtime', '修改时间'),
    ];
    return [
      for (final (key, label) in sorts)
        CheckedPopupMenuItem<String>(
          value: 'sort:$key',
          checked: appState.sortKey == key,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'toggle:descending',
        child: Text(appState.sortDescending ? '改为升序' : '改为降序',
            style: const TextStyle(fontSize: 12)),
      ),
      PopupMenuItem<String>(
        value: 'toggle:view',
        child: Text(appState.viewMode == 'grid' ? '切换到列表' : '切换到网格',
            style: const TextStyle(fontSize: 12)),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: 'filter',
        child: Text('高级筛选', style: TextStyle(fontSize: 12)),
      ),
      const PopupMenuItem<String>(
        value: 'refresh',
        child: Text('刷新', style: TextStyle(fontSize: 12)),
      ),
      const PopupMenuItem<String>(
        value: 'settings',
        child: Text('设置', style: TextStyle(fontSize: 12)),
      ),
    ];
  }

  void _onCompactSelected(AppState appState, String value) {
    if (value.startsWith('sort:')) {
      appState.setSortKey(value.substring('sort:'.length));
    } else if (value == 'toggle:descending') {
      appState.setSortDescending(!appState.sortDescending);
    } else if (value == 'toggle:view') {
      appState.setViewMode(appState.viewMode == 'grid' ? 'list' : 'grid');
    } else if (value == 'filter') {
      AdvancedFilterDialog.show(context);
    } else if (value == 'refresh') {
      appState.refresh();
    } else if (value == 'settings') {
      SettingsDialog.show(context);
    }
  }

  PopupMenuItem<String> _sortItem(String label, String key, String current) {
    return PopupMenuItem<String>(
      value: key,
      child: Row(
        children: [
          SizedBox(
              width: 72,
              child: Text(label, style: const TextStyle(fontSize: 12))),
          if (current == key)
            const Icon(Icons.check, size: 14, color: Catppuccin.mauve),
        ],
      ),
    );
  }
}

/// 高级筛选活跃提示条（显示当前表达式，可编辑/清除）
class _AdvancedFilterBar extends StatelessWidget {
  const _AdvancedFilterBar();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Catppuccin.surface0,
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 14, color: Catppuccin.mauve),
          const SizedBox(width: 6),
          const Text('高级筛选',
              style: TextStyle(fontSize: 11, color: Catppuccin.overlay1)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              appState.advancedFilter,
              style: const TextStyle(
                  fontSize: 11, color: Catppuccin.mauve, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () => AdvancedFilterDialog.show(context),
            icon: const Icon(Icons.edit, size: 13),
            tooltip: '编辑表达式',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          IconButton(
            onPressed: () => appState.clearAdvancedFilter(),
            icon: const Icon(Icons.close, size: 13),
            tooltip: '清除高级筛选',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}

/// 多选操作条（批量添加标签 / 清除选择）
class _SelectionBar extends StatelessWidget {
  const _SelectionBar();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Catppuccin.surface0,
      // 窄窗口下这一条放不下就横向滚动，别把 Row 撑破（原来这里还有个 Spacer，
      // 它在不定宽的行里没有意义，换成一个固定间距）。
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('已选 ${appState.selectedIds.length} 项',
                style: const TextStyle(fontSize: 11, color: Catppuccin.overlay1)),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () async {
                final tags = await showTagPickerDialog(context, title: '批量添加标签');
                if (tags != null && tags.isNotEmpty) {
                  await appState.addTagsToImages(appState.selectedIds, tags);
                }
              },
              icon: const Icon(Icons.sell_outlined, size: 14),
              label: const Text('添加标签', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: Catppuccin.mauve),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () async {
                final ids = await appState.getTagIdsOnImages(appState.selectedIds);
                if (!context.mounted) return;
                final tags = await showTagPickerDialog(context,
                    title: '批量移除标签', filterTagIds: ids);
                if (tags != null && tags.isNotEmpty) {
                  await appState.removeTagsFromImages(appState.selectedIds, tags);
                }
              },
              icon: const Icon(Icons.label_off_outlined, size: 14),
              label: const Text('移除标签', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: Catppuccin.red),
            ),
            const SizedBox(width: 16),
            TextButton.icon(
              onPressed: () => appState.clearSelection(),
              icon: const Icon(Icons.close, size: 14),
              label: const Text('清除选择', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: Catppuccin.overlay1),
            ),
          ],
        ),
      ),
    );
  }
}

/// 面包屑导航栏（文件夹浏览路径）
class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final crumb = appState.breadcrumb;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Catppuccin.mantle,
      // 路径深了面包屑会比窗口还宽，横向滚动兜住（原来是一条 Row 直接铺）。
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          IconButton(
            onPressed: crumb.length <= 1 ? null : () => appState.goUp(),
            icon: const Icon(Icons.arrow_upward, size: 15),
            tooltip: '上一级',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          TextButton(
            onPressed: () => appState.goRoot(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '全部图片',
              style: TextStyle(fontSize: 12, color: Catppuccin.blue),
            ),
          ),
          for (int i = 0; i < crumb.length; i++) ...[
            const Icon(Icons.chevron_right,
                size: 14, color: Catppuccin.overlay0),
            TextButton(
              onPressed: () => appState.enterFolder(crumb[i].id!),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                crumb[i].name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: i == crumb.length - 1
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: i == crumb.length - 1
                      ? Catppuccin.text
                      : Catppuccin.subtext0,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          ],
        ),
      ),
    );
  }
}

/// 底部状态栏
class _BottomStatusBar extends StatelessWidget {
  const _BottomStatusBar();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    String leftText;
    if (appState.importing) {
      leftText = '导入中 ${(appState.importProgress * 100).toStringAsFixed(0)}%';
    } else {
      final folders = appState.centerFolders.length;
      final images = appState.images.length;
      leftText = '$folders 个文件夹 · $images 张图片';
      if (appState.selectedIds.length > 1) {
        leftText = '已选 ${appState.selectedIds.length} 项 · $leftText';
      }
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Catppuccin.mantle,
      child: Row(
        children: [
          Flexible(
            child: Text(
              leftText,
              style: const TextStyle(color: Catppuccin.overlay1, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (appState.importing)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Catppuccin.mauve,
              ),
            )
          else
            const Text(
              '就绪',
              style: TextStyle(color: Catppuccin.overlay0, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
