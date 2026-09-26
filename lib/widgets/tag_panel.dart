import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/tag_dao.dart';
import '../state/app_state.dart';
import '../theme/catppuccin.dart';
import '../utils/color_util.dart';
import '../utils/log_util.dart';
import 'color_picker_dialog.dart';

/// 标签面板扁平列表的一行：命名空间头或标签项
class _TagRow {
  const _TagRow.header(this.namespace) : tag = null;
  const _TagRow.tag(this.tag) : namespace = null;

  final String? namespace;
  final Tag? tag;
}

/// 左侧标签面板 —— 命名空间分组 + 搜索 + CRUD
class TagPanel extends StatefulWidget {
  const TagPanel({super.key});

  @override
  State<TagPanel> createState() => _TagPanelState();
}

class _TagPanelState extends State<TagPanel> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  Timer? _searchDebounce;

  /// 输入防抖：每敲一个字就全量重建标签列表，2000 个标签会卡手。
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _search = value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() => _search = '');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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
    final query = _search.toLowerCase();
    var filtered = _search.isEmpty
        ? allTags
        : allTags
            .where((t) =>
                t.name.toLowerCase().contains(query) ||
                t.namespace.toLowerCase().contains(query))
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

    // 拍平成「命名空间头 + 标签项」的单层列表：按命名空间整段建 Column
    // 时，一个装了上千标签的命名空间会被一次性全部建出来。
    final rows = <_TagRow>[];
    for (final ns in sortedNs) {
      rows.add(_TagRow.header(ns));
      final tags = namespaces[ns]!..sort((a, b) => a.name.compareTo(b.name));
      for (final tag in tags) {
        rows.add(_TagRow.tag(tag));
      }
    }

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
              itemCount: rows.length,
              itemBuilder: (ctx, i) {
                final row = rows[i];
                final tag = row.tag;
                return tag == null
                    ? _namespaceHeader(row.namespace!)
                    : _tagItem(tag, appState, filter);
              },
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
        onChanged: _onSearchChanged,
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
                  onPressed: _clearSearch,
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

  // ── 命名空间头 ──
  Widget _namespaceHeader(String ns) {
    return Container(
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
            // 一次移除该标签在 AND / OR / NOT 里的全部痕迹。
            // 不能连调三个 toggle：第二个会把刚移除的标签加回来，
            // 终态固定变成「排除该标签」。
            appState.clearTagFilterFor(tag.id!);
            break;
          case 'edit':
            _showEditDialog(tag, appState);
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
        const PopupMenuItem(
          value: 'edit',
          child: Text('编辑标签', style: TextStyle(fontSize: 12)),
        ),
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
    showDialog(
      context: context,
      builder: (_) => const _TagCreateDialog(),
    );
  }

  void _showEditDialog(Tag tag, AppState appState) {
    showDialog(
      context: context,
      builder: (_) => _TagEditDialog(tag: tag),
    );
  }

  void _showDeleteDialog(Tag tag, AppState appState) {
    showDialog(
      context: context,
      builder: (_) => _TagDeleteDialog(tag: tag),
    );
  }

  Color _parseColor(String hex) =>
      parseHexColor(hex, fallback: Catppuccin.mauve);
}

/// 新建标签对话框。
///
/// 原来这段是内联的 StatefulBuilder：controller 建在 build 里没人释放，
/// 「创建」按钮把 createTag 的 Future 丢掉就关窗，写库失败也照样显示成功，
/// 名字为空时按钮干脆没反应。
class _TagCreateDialog extends StatefulWidget {
  const _TagCreateDialog();

  @override
  State<_TagCreateDialog> createState() => _TagCreateDialogState();
}

class _TagCreateDialogState extends State<_TagCreateDialog> {
  static const _presetColors = [
    '#cba6f7', '#f38ba8', '#fab387', '#f9e2af',
    '#a6e3a1', '#94e2d5', '#89dceb', '#b4befe',
  ];

  final _nameCtrl = TextEditingController();
  final _nsCtrl = TextEditingController();
  String _color = '#cba6f7';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nsCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final appState = context.read<AppState>();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '标签名不能为空');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await appState.createTag(name,
          namespace: _nsCtrl.text.trim(), color: _color);
      if (!mounted) return;
      Navigator.pop(context);
      if (!created.created) {
        messenger.showSnackBar(
            const SnackBar(content: Text('已存在同名标签，直接使用了它')));
      }
    } catch (e) {
      logError('TagPanel', '创建标签失败', e);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '创建失败：$e';
      });
    }
  }

  Future<void> _pickColor() async {
    final hex = await ColorPickerDialog.show(context, initialHex: _color);
    if (hex != null && mounted) {
      setState(() => _color = hex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Catppuccin.mantle,
      title: const Text('新建标签', style: TextStyle(color: Catppuccin.text)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '标签名',
                hintText: '例如：风景',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nsCtrl,
              decoration: const InputDecoration(
                labelText: '命名空间 (可选)',
                hintText: '例如：地点',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _presetColors.map((c) {
                final selected = _color == c;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color:
                          parseHexColor(c, fallback: Catppuccin.mauve),
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Catppuccin.text, width: 2)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickColor,
                icon: const Icon(Icons.colorize, size: 16),
                label: const Text('自定义颜色', style: TextStyle(fontSize: 12)),
                style:
                    TextButton.styleFrom(foregroundColor: Catppuccin.mauve),
              ),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 12, color: Catppuccin.red)),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: Catppuccin.overlay1)),
        ),
        TextButton(
          onPressed: _saving ? null : _create,
          child: const Text('创建', style: TextStyle(color: Catppuccin.mauve)),
        ),
      ],
    );
  }
}

/// 删除标签确认框。
///
/// 原来是内联的 AlertDialog：onPressed 里把 deleteTag 的 Future 丢掉就立刻
/// pop，删除失败（外键冲突、库被占用）用户看到的仍然是「删掉了」。
class _TagDeleteDialog extends StatefulWidget {
  final Tag tag;
  const _TagDeleteDialog({required this.tag});

  @override
  State<_TagDeleteDialog> createState() => _TagDeleteDialogState();
}

class _TagDeleteDialogState extends State<_TagDeleteDialog> {
  String? _error;
  bool _deleting = false;

  Future<void> _delete() async {
    final appState = context.read<AppState>();
    final id = widget.tag.id;
    if (id == null) {
      setState(() => _error = '这个标签没有 id，删不掉');
      return;
    }

    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await appState.deleteTag(id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      logError('TagPanel', '删除标签失败', e);
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = '删除失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Catppuccin.mantle,
      title: const Text('删除标签', style: TextStyle(color: Catppuccin.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '确定删除「${widget.tag.name}」？关联的图片标签也会被移除。',
            style: const TextStyle(color: Catppuccin.subtext1),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style:
                      const TextStyle(fontSize: 12, color: Catppuccin.red)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: Catppuccin.overlay1)),
        ),
        TextButton(
          onPressed: _deleting ? null : _delete,
          child: const Text('删除', style: TextStyle(color: Catppuccin.red)),
        ),
      ],
    );
  }
}

/// 标签编辑对话框（改名 / 改命名空间 / 改颜色）
class _TagEditDialog extends StatefulWidget {
  final Tag tag;
  const _TagEditDialog({required this.tag});

  @override
  State<_TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<_TagEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nsCtrl;
  late String _color;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.tag.name);
    _nsCtrl = TextEditingController(
        text: widget.tag.namespace == 'general' ? '' : widget.tag.namespace);
    _color = widget.tag.color;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final appState = context.read<AppState>();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '标签名不能为空');
      return;
    }
    final result = await appState.updateTag(Tag(
      id: widget.tag.id,
      namespace: _nsCtrl.text.trim(),
      name: name,
      color: _color,
    ));
    if (!mounted) return;
    if (result != null) {
      setState(() => _error = result);
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _pickColor() async {
    final hex = await ColorPickerDialog.show(context, initialHex: _color);
    if (hex != null && mounted) {
      setState(() => _color = hex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(_color);
    return AlertDialog(
      backgroundColor: Catppuccin.mantle,
      title: const Text('编辑标签', style: TextStyle(color: Catppuccin.text)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '标签名'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nsCtrl,
              decoration: const InputDecoration(
                labelText: '命名空间 (可选)',
                hintText: '留空为 general',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('颜色',
                    style:
                        TextStyle(fontSize: 12, color: Catppuccin.subtext1)),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _pickColor,
                  child: Container(
                    width: 36,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Catppuccin.surface1),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _color,
                    style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Catppuccin.overlay1),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(fontSize: 12, color: Catppuccin.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: Catppuccin.overlay1)),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
