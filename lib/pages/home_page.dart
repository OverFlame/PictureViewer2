import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/catppuccin.dart';
import '../widgets/folder_panel.dart';
import '../widgets/tag_panel.dart';
import '../widgets/image_grid.dart';
import '../widgets/image_detail.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 面板可见性
  bool _leftPanelOpen = true;
  bool _rightPanelOpen = true;

  // 左侧面板当前 tab: 0=文件夹, 1=标签
  int _leftTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // ═══ 左面板 ═══
          if (_leftPanelOpen)
            SizedBox(
              width: 280,
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
          if (_rightPanelOpen)
            SizedBox(
              width: 320,
              child: const ImageDetail(),
            ),
        ],
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
    return Container(
      color: Catppuccin.base,
      child: Column(
        children: const [
          _TopToolbar(),
          Divider(height: 1),
          Expanded(child: ImageGrid()),
          _BottomStatusBar(),
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
class _TopToolbar extends StatelessWidget {
  const _TopToolbar();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final ctrl = TextEditingController(text: appState.searchQuery);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Catppuccin.mantle,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              onChanged: (v) => appState.setSearchQuery(v),
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
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.filter_list, size: 18),
            tooltip: '高级筛选',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: '刷新',
            onPressed: () => appState.refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 18),
            tooltip: '设置',
            onPressed: () {},
          ),
        ],
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
      leftText = '${appState.totalCount} 张图片'
          '${appState.images.length < appState.totalCount ? " (已加载 ${appState.images.length})" : ""}';
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Catppuccin.mantle,
      child: Row(
        children: [
          Text(
            leftText,
            style: const TextStyle(color: Catppuccin.overlay1, fontSize: 11),
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
