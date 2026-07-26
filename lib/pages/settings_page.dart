import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../services/thumbnail_cache.dart';
import '../theme/catppuccin.dart';
import '../utils/log_util.dart';
import 'about_page.dart';

/// 设置对话框
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return AlertDialog(
      backgroundColor: Catppuccin.mantle,
      title: const Row(
        children: [
          Icon(Icons.settings_outlined, size: 20, color: Catppuccin.lavender),
          SizedBox(width: 8),
          Text('设置', style: TextStyle(color: Catppuccin.text, fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sectionTitle('外观'),
              const SizedBox(height: 8),
              _themeSelector(appState),
              const SizedBox(height: 16),
              _sectionTitle('网格'),
              const SizedBox(height: 8),
              _gridColumnsSelector(appState),
              const SizedBox(height: 16),
              _sectionTitle('缩略图缓存'),
              const SizedBox(height: 8),
              _cacheSizeSelector(appState, context),
              const SizedBox(height: 20),
              const Divider(color: Catppuccin.surface0),
              const SizedBox(height: 12),
              _aboutTile(context),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭',
              style: TextStyle(color: Catppuccin.overlay1)),
        ),
      ],
    );
  }

  // ── 主题选择器 ──
  Widget _themeSelector(AppState appState) {
    return Container(
      decoration: BoxDecoration(
        color: Catppuccin.surface0,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          _themeOption(
            label: '跟随系统',
            icon: Icons.brightness_auto,
            selected: appState.themeMode == ThemeMode.system,
            onTap: () => appState.setThemeMode(ThemeMode.system),
          ),
          _themeOption(
            label: '浅色',
            icon: Icons.light_mode,
            selected: appState.themeMode == ThemeMode.light,
            onTap: () => appState.setThemeMode(ThemeMode.light),
          ),
          _themeOption(
            label: '深色',
            icon: Icons.dark_mode,
            selected: appState.themeMode == ThemeMode.dark,
            onTap: () => appState.setThemeMode(ThemeMode.dark),
          ),
        ],
      ),
    );
  }

  Widget _themeOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? Catppuccin.lavender.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Catppuccin.lavender : Catppuccin.overlay1,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? Catppuccin.lavender : Catppuccin.overlay1,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 网格列数 ──
  Widget _gridColumnsSelector(AppState appState) {
    return Container(
      decoration: BoxDecoration(
        color: Catppuccin.surface0,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Text('缩略图列数',
              style: TextStyle(fontSize: 12, color: Catppuccin.subtext1)),
          const Spacer(),
          _iconButton(
            icon: Icons.remove,
            onTap: appState.gridColumns > 2
                ? () => appState.setGridColumns(appState.gridColumns - 1)
                : null,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 28,
            child: Text(
              '${appState.gridColumns}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Catppuccin.text,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _iconButton(
            icon: Icons.add,
            onTap: appState.gridColumns < 10
                ? () => appState.setGridColumns(appState.gridColumns + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _iconButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: onTap != null ? Catppuccin.surface1 : Catppuccin.surface0,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? Catppuccin.text : Catppuccin.overlay0,
        ),
      ),
    );
  }

  // ── 缓存大小 ──
  Widget _cacheSizeSelector(AppState appState, BuildContext parentContext) {
    return Container(
      decoration: BoxDecoration(
        color: Catppuccin.surface0,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('磁盘缓存上限',
                  style: TextStyle(fontSize: 12, color: Catppuccin.subtext1)),
              const Spacer(),
              Text(
                _formatSizeMB(appState.cacheSizeMB),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Catppuccin.lavender,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Catppuccin.lavender,
              inactiveTrackColor: Catppuccin.surface1,
              thumbColor: Catppuccin.lavender,
              overlayColor: Catppuccin.lavender.withValues(alpha: 0.15),
              trackHeight: 4,
            ),
            child: Slider(
              value: appState.cacheSizeMB.toDouble(),
              min: 256,
              max: 8192,
              divisions: 31,
              onChanged: (v) => appState.setCacheSizeMB(v.round()),
            ),
          ),
          Row(
            children: [
              const Text('256 MB',
                  style: TextStyle(fontSize: 10, color: Catppuccin.overlay0)),
              const Spacer(),
              const Text('8 GB',
                  style: TextStyle(fontSize: 10, color: Catppuccin.overlay0)),
            ],
          ),
          const SizedBox(height: 8),
          _clearCacheButton(parentContext),
        ],
      ),
    );
  }

  String _formatSizeMB(int mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '$mb MB';
  }

  Widget _clearCacheButton(BuildContext parentContext) {
    return GestureDetector(
      onTap: () => _confirmClearCache(parentContext),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Catppuccin.surface1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cleaning_services_outlined,
                size: 14, color: Catppuccin.overlay1),
            SizedBox(width: 6),
            Text('清除缩略图缓存',
                style: TextStyle(fontSize: 11, color: Catppuccin.overlay1)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearCache(BuildContext parentContext) async {
    final confirmed = await showDialog<bool>(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: Catppuccin.mantle,
        title: const Text('清除缓存',
            style: TextStyle(color: Catppuccin.text, fontSize: 16)),
        content: const Text('将删除所有缩略图缓存，下次浏览时需重新生成。',
            style: TextStyle(color: Catppuccin.subtext0, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消',
                style: TextStyle(color: Catppuccin.overlay1)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定', style: TextStyle(color: Catppuccin.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && parentContext.mounted) {
      _clearCacheDirs();
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(
          content: Text('缓存已清除'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearCacheDirs() {
    final cacheDir = Directory(ThumbnailService.instance.cacheDir);
    if (cacheDir.existsSync()) {
      for (final entity in cacheDir.listSync(recursive: true)) {
        if (entity is File) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
      logInfo('Settings', 'Cache cleared');
    }
  }

  // ── 关于 ──
  Widget _aboutTile(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        AppAboutDialog.show(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Catppuccin.surface0,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Catppuccin.lavender),
            SizedBox(width: 10),
            Text('关于 PictureViewer',
                style: TextStyle(color: Catppuccin.text, fontSize: 13)),
            Spacer(),
            Icon(Icons.chevron_right, size: 18, color: Catppuccin.overlay1),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Catppuccin.overlay2,
        letterSpacing: 0.5,
      ),
    );
  }
}
