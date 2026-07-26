import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/tag_dao.dart';
import '../state/app_state.dart';
import '../theme/catppuccin.dart';

/// 左侧标签面板 —— 命名空间分组 + 搜索 + CRUD
class TagPanel extends StatefulWidget {
  const TagPanel({super.key});

  @override
  State<TagPanel> createState() => _TagPanelState();
}

class _TagPanelState extends State<TagPanel> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allTags = appState.allTags;
    final filter = appState.tagFilter;
    final activeIds = appState.activeTagIds;

    // 搜索过滤
    var filtered = _search.isEmpty
        ? allTags
        : allTags
            .where((t) =>
                t.name.toLowerCase().contains(_search.toLowerCase()) ||
                t.namespace.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    // 按命名空间分组
    final namespaces = <String, List<Tag>>{};
    for (final tag in filtered) {
      final ns = tag.namespace.isEmpty ? '(无命名空间)' : tag.namespace;
      namespaces.putIfAbsent(ns, () => []);
      namespaces[ns]!.add(tag);
    }

    // 排序
    final sortedNs = namespaces.keys.toList()
      ..sort((a, b) {
        if (a == '(无命名空间)') return 1;
        if (b == '(无命名空间)') return -1;
        return a.compareTo(b);
      });

    return Container(
      color: Catppuccin.crust,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          _panelHeader(appState),
          const Divider(height: 1),
          // 搜索栏
          _searchBar(),
          const Divider(height: 1),
          // 活跃筛选指示条
          if (activeIds.isNotEmpty) _activeFilterBar(appState),
          // 标签列表
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: sortedNs.length,
              itemBuilder: (ctx, i) => _namespaceGroup(
                sortedNs[i],
                namespaces[sortedNs[i]]!,
                appState,
                filter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelHeader(AppState appState) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Catppuccin.mantle,
      child: Row(
        children: [
          const Text(
            '标签',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Catppuccin.subtext0,
            ),
          ),
          const Spacer(),
          // 新建按钮
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: '新建标签',
            onPressed: () => _showCreateDialog(appState),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          // 清除筛选
          if (appState.tagFilter.active)
            IconButton(
              icon: const Icon(Icons.clear, size: 14),
              tooltip: '清除筛选',
              onPressed: () => appState.clearTagFilters(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      color: Catppuccin.mantle,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v),
        style: const TextStyle(fontSize: 12, color: Catppuccin.text),
        decoration: InputDecoration(
          hintText: '搜索标签...',
          hintStyle: const TextStyle(fontSize: 12, color: Catppuccin.overlay1),
          prefixIcon:
              const Icon(Icons.search, size: 14, color: Catppuccin.overlay1),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon:
                      const Icon(Icons.clear, size: 14, color: Catppuccin.overlay1),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                  },
                  padding: EdgeInsets.zero,
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          filled: true,
          fillColor: Catppuccin.surface0,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _activeFilterBar(AppState appState) {
    final filter = appState.tagFilter;
    final tagMap = {for (final t in appState.allTags) t.id!: t};

    final chips = <Widget>[];
    for (final id in filter.andTagIds) {
      final tag = tagMap[id];
      if (tag == null) continue;
      chips.add(_filterChip('AND ${tag.name}', Catppuccin.green, () {
        appState.toggleAndFilter(id);
      }));
    }
    for (final id in filter.orTagIds) {
      final tag = tagMap[id];
      if (tag == null) continue;
      chips.add(_filterChip('OR ${tag.name}', Catppuccin.yellow, () {
        appState.toggleOrFilter(id);
      }));
    }
    for (final id in filter.notTagIds) {
      final tag = tagMap[id];
      if (tag == null) continue;
      chips.add(_filterChip('NOT ${tag.name}', Catppuccin.red, () {
        appState.toggleNotFilter(id);
      }));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Catppuccin.surface0,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Wrap(spacing: 4, runSpacing: 2, children: chips),
    );
  }

  Widget _filterChip(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, color: color),
        ),
      ),
    );
  }

  // ── 命名空间分组 ──
  Widget _namespaceGroup(
      String ns, List<Tag> tags, AppState appState, TagFilter filter) {
    tags.sort((a, b) => a.name.compareTo(b.name));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 命名空间头
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            ns,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Catppuccin.overlay2,
              letterSpacing: 0.5,
            ),
          ),
        ),
        // 标签项
        ...tags.map((tag) => _tagItem(tag, appState, filter)),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _tagItem(Tag tag, AppState appState, TagFilter filter) {
    final andActive = filter.andTagIds.contains(tag.id);
    final orActive = filter.orTagIds.contains(tag.id);
    final notActive = filter.notTagIds.contains(tag.id);
    final anyActive = andActive || orActive || notActive;

    final dotColor = _parseColor(tag.color);
    final bgColor = anyActive
        ? Catppuccin.surface1
        : Colors.transparent;

    return Material(
      color: bgColor,
      child: InkWell(
        onTap: () {
          // 默认用 AND 模式
          appState.toggleAndFilter(tag.id!);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              // 色点
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: anyActive
                      ? Border.all(color: dotColor.withValues(alpha: 0.8), width: 2)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              // 名称
              Expanded(
                child: Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: anyActive ? Catppuccin.text : Catppuccin.subtext1,
                    fontWeight: anyActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 筛选菜单
              _filterPopup(tag, appState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterPopup(Tag tag, AppState appState) {
    final filter = appState.tagFilter;
    final andActive = filter.andTagIds.contains(tag.id);
    final orActive = filter.orTagIds.contains(tag.id);
    final notActive = filter.notTagIds.contains(tag.id);

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 12,
      icon: Icon(
        Icons.more_horiz,
        size: 12,
        color: (andActive || orActive || notActive)
            ? Catppuccin.text
            : Catppuccin.overlay0,
      ),
      tooltip: '筛选选项',
      onSelected: (action) {
        switch (action) {
          case 'and':
            appState.toggleAndFilter(tag.id!);
            break;
          case 'or':
            appState.toggleOrFilter(tag.id!);
            break;
          case 'not':
            appState.toggleNotFilter(tag.id!);
            break;
          case 'clear':
            appState.toggleAndFilter(tag.id!);
            appState.toggleOrFilter(tag.id!);
            appState.toggleNotFilter(tag.id!);
            break;
          case 'delete':
            _showDeleteDialog(tag, appState);
            break;
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'and',
          child: _popupItem('AND 交集', '必须拥有此标签', Icons.search, andActive),
        ),
        PopupMenuItem(
          value: 'or',
          child: _popupItem('OR 并集', '可以拥有此标签', Icons.filter_list, orActive),
        ),
        PopupMenuItem(
          value: 'not',
          child: _popupItem('NOT 排除', '不能拥有此标签', Icons.block, notActive),
        ),
        if (andActive || orActive || notActive)
          const PopupMenuDivider(),
        if (andActive || orActive || notActive)
          const PopupMenuItem(value: 'clear', child: Text('清除此标签筛选', style: TextStyle(fontSize: 12))),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: const Text('删除标签', style: TextStyle(fontSize: 12, color: Catppuccin.red)),
        ),
      ],
    );
  }

  Widget _popupItem(String title, String sub, IconData icon, bool active) {
    return Row(
      children: [
        Icon(icon, size: 14, color: active ? Catppuccin.mauve : Catppuccin.overlay1),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 12)),
            Text(sub,
                style: const TextStyle(fontSize: 10, color: Catppuccin.overlay1)),
          ],
        ),
        if (active)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.check, size: 12, color: Catppuccin.mauve),
          ),
      ],
    );
  }

  // ── 创建对话框 ──
  void _showCreateDialog(AppState appState) {
    final nameCtrl = TextEditingController();
    final nsCtrl = TextEditingController();
    String color = '#cba6f7';
    final presetColors = [
      '#cba6f7', '#f38ba8', '#fab387', '#f9e2af',
      '#a6e3a1', '#94e2d5', '#89dceb', '#b4befe',
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            backgroundColor: Catppuccin.mantle,
            title: const Text('新建标签', style: TextStyle(color: Catppuccin.text)),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '标签名',
                      hintText: '例如：风景',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nsCtrl,
                    decoration: const InputDecoration(
                      labelText: '命名空间 (可选)',
                      hintText: '例如：地点',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: presetColors.map((c) {
                      final selected = color == c;
                      return GestureDetector(
                        onTap: () => setLocal(() => color = c),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _parseColor(c),
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(color: Catppuccin.text, width: 2)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消', style: TextStyle(color: Catppuccin.overlay1)),
              ),
              TextButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isNotEmpty) {
                    appState.createTag(name,
                        namespace: nsCtrl.text.trim(), color: color);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('创建', style: TextStyle(color: Catppuccin.mauve)),
              ),
            ],
          );
        });
      },
    );
  }

  void _showDeleteDialog(Tag tag, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Catppuccin.mantle,
        title: const Text('删除标签', style: TextStyle(color: Catppuccin.text)),
        content: Text(
          '确定删除「${tag.name}」？关联的图片标签也会被移除。',
          style: const TextStyle(color: Catppuccin.subtext1),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Catppuccin.overlay1)),
          ),
          TextButton(
            onPressed: () {
              appState.deleteTag(tag.id!);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Catppuccin.red)),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      final h = hex.replaceFirst('#', '');
      final intVal = int.parse(h, radix: 16);
      return Color(intVal | 0xFF000000);
    } catch (_) {
      return Catppuccin.mauve;
    }
  }
}
