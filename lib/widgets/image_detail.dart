import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/catppuccin.dart';

/// 右侧图片详情面板（显示选中图片的信息）
class ImageDetail extends StatelessWidget {
  const ImageDetail({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final image = appState.selectedImage;

    if (image == null) {
      return _buildEmpty();
    }

    final file = File(image.path);
    final exists = file.existsSync();
    final stat = exists ? file.statSync() : null;

    return Container(
      color: Catppuccin.mantle,
      child: Column(
        children: [
          // 顶部标题栏
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Catppuccin.surface0)),
            ),
            child: Row(
              children: [
                const Text(
                  '图片详情',
                  style: TextStyle(
                    color: Catppuccin.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!exists)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Catppuccin.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '文件已丢失',
                      style: TextStyle(color: Catppuccin.red, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),

          // 内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 概要
                  _section('基本信息', [
                    _row('文件名', image.filename),
                    _row('格式', (image.format ?? '').toUpperCase()),
                    if (image.fileSize != null)
                      _row('大小', _formatBytes(image.fileSize!)),
                    if (stat != null)
                      _row('修改时间',
                          '${stat.modified.year}-${stat.modified.month.toString().padLeft(2, '0')}-${stat.modified.day.toString().padLeft(2, '0')}'),
                    _row('添加时间',
                        DateTime.fromMillisecondsSinceEpoch(image.addedAt)
                            .toString()
                            .substring(0, 10)),
                  ]),
                  const SizedBox(height: 12),

                  // 路径
                  _section('路径', [
                    SelectableText(
                      image.path,
                      style: const TextStyle(
                        color: Catppuccin.subtext0,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // 尺寸（Phase 4 补全）
                  if (image.width != null || image.height != null)
                    _section('尺寸', [
                      _row('宽', '${image.width ?? '?'} px'),
                      _row('高', '${image.height ?? '?'} px'),
                    ]),
                  const SizedBox(height: 12),

                  // 标签（Phase 4 补全）
                  _section('标签', [
                    const Text(
                      '暂无标签（标签功能开发中）',
                      style: TextStyle(color: Catppuccin.overlay0, fontSize: 12),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      color: Catppuccin.mantle,
      child: Column(
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Catppuccin.surface0)),
            ),
            child: const Row(
              children: [
                Text(
                  '图片详情',
                  style: TextStyle(
                    color: Catppuccin.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline,
                      size: 40, color: Catppuccin.overlay0),
                  const SizedBox(height: 8),
                  const Text(
                    '点击图片查看详情',
                    style: TextStyle(color: Catppuccin.subtext0, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Catppuccin.lavender,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                color: Catppuccin.overlay1,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Catppuccin.text,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
