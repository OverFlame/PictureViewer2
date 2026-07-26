import 'package:flutter/material.dart';
import '../theme/catppuccin.dart';

/// 右侧图片详情面板（占位 — 后续 Phase 接入数据）
class ImageDetail extends StatelessWidget {
  const ImageDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Catppuccin.mantle,
      child: Column(
        children: [
          // 顶部标题栏
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Catppuccin.surface0),
              ),
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
                Spacer(),
              ],
            ),
          ),
          // 空白占位
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline,
                      size: 40, color: Catppuccin.overlay0),
                  const SizedBox(height: 8),
                  const Text(
                    '点击图片查看详情',
                    style: TextStyle(
                      color: Catppuccin.subtext0,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '标签、尺寸、路径等信息',
                    style: TextStyle(
                      color: Catppuccin.overlay0,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
