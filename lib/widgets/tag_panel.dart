import 'package:flutter/material.dart';
import '../theme/catppuccin.dart';

/// 左侧标签筛选面板（占位 — 后续 Phase 接入数据库）
class TagPanel extends StatefulWidget {
  const TagPanel({super.key});

  @override
  State<TagPanel> createState() => _TagPanelState();
}

class _TagPanelState extends State<TagPanel> {
  final _searchCtrl = TextEditingController();
  String _filterExp = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 搜索 + 筛选表达式输入
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: '标签筛选 (e.g. character:hatsune rating:safe)',
              prefixIcon: Icon(Icons.search, size: 18),
              suffixIcon: Icon(Icons.help_outline, size: 18),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (v) => setState(() => _filterExp = v),
          ),
        ),
        const Divider(height: 1),
        // 标签列表（占位）
        Expanded(
          child: _filterExp.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.label_outline,
                          size: 36, color: Catppuccin.overlay0),
                      const SizedBox(height: 8),
                      const Text(
                        '导入图片后标签将显示在此处',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Catppuccin.subtext0,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              : const Center(
                  child: Text(
                    '筛选: 待实现',
                    style: TextStyle(color: Catppuccin.subtext0, fontSize: 12),
                  ),
                ),
        ),
      ],
    );
  }
}
