import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../db/image_dao.dart';
import '../services/exif_service.dart';
import '../state/app_state.dart';
import '../theme/catppuccin.dart';
import '../utils/log_util.dart';

/// =============================================================
/// Full-screen image viewer with zoom, pan, keyboard shortcuts,
/// animated page transitions, preloading, and EXIF metadata.
/// =============================================================
class ImageViewer extends StatefulWidget {
  final AppState state;

  const ImageViewer({super.key, required this.state});

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  final TransformationController _transformCtrl = TransformationController();
  final FocusNode _focusNode = FocusNode();

  bool _showUI = true;
  bool _showExif = false;
  double _zoomLevel = 1.0;
  bool _isFitToWindow = true;
  bool _isImageLoading = true;
  int _prevViewerIndex = -1;
  int _displayedImageId = -1;

  final Map<int, ExifData?> _exifCache = {};
  ExifData? _currentExif;

  AppState get _st => widget.state;

  @override
  void initState() {
    super.initState();
    logInfo('Viewer', 'ImageViewer opened');
    _prevViewerIndex = _st.viewerIndex;
    _onPageChanged();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _transformCtrl.dispose();
    logInfo('Viewer', 'ImageViewer closed');
    super.dispose();
  }

  // ============================================================
  // Page change
  // ============================================================

  void _checkPageChanged() {
    final idx = _st.viewerIndex;
    if (idx == _prevViewerIndex) return;
    _prevViewerIndex = idx;
    logDebug('Viewer', 'Page changed: idx=$idx (${idx + 1}/${_st.viewerImages.length})');
    _onPageChanged();
  }

  void _onPageChanged() {
    final img = _st.viewerImage;
    if (img == null) return;
    final id = img.id;
    if (id == null) return;

    _transformCtrl.value = Matrix4.identity();
    _zoomLevel = 1.0;
    _isFitToWindow = true;
    _isImageLoading = true;
    _displayedImageId = id;

    _loadExifForCurrent();
    _preloadAdjacent();
  }

  // ============================================================
  // Zoom logic
  // ============================================================

  Matrix4 _getMatrix() => _transformCtrl.value;

  /// Get the current visual scale from the matrix.
  double _getCurrentScale() {
    final m = _getMatrix();
    return m.getMaxScaleOnAxis();
  }

  /// Apply a scale factor centered on a given viewport point (or center).
  /// `factor` > 1 = zoom in, < 1 = zoom out.  Clamped to [0.05, 50].
  void _applyScale(double factor, {Offset? focal}) {
    final matrix = _getMatrix().clone();
    final current = matrix.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.05, 50.0);
    if ((target - current).abs() < 1e-6) return;

    final size = context.size ?? const Size(1, 1);
    final focalPt = focal ?? Offset(size.width / 2, size.height / 2);

    // Convert focal point from viewport to scene coordinates
    final inv = Matrix4.inverted(matrix);
    final sceneFocal = MatrixUtils.transformPoint(inv, focalPt);

    matrix.translate(sceneFocal.dx, sceneFocal.dy);
    matrix.scale(target / current);
    matrix.translate(-sceneFocal.dx, -sceneFocal.dy);

    _transformCtrl.value = matrix;
    setState(() {
      _zoomLevel = target;
      _isFitToWindow = target <= 1.01;
    });
  }

  void _zoomIn() => _applyScale(1.4);
  void _zoomOut() => _applyScale(1.0 / 1.4);
  void _fitToWindow() {
    _transformCtrl.value = Matrix4.identity();
    setState(() {
      _zoomLevel = 1.0;
      _isFitToWindow = true;
    });
  }

  // ============================================================
  // Mouse wheel (Ctrl+Scroll to zoom)
  // ============================================================

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      if (HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.controlLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.controlRight)) {
        final dy = event.scrollDelta.dy;
        final factor = dy > 0 ? 1.0 / 1.15 : 1.15;
        _applyScale(factor, focal: event.localPosition);
      }
    }
  }

  // ============================================================
  // Navigation
  // ============================================================

  void _previous() {
    logDebug('Viewer', 'Navigate: prev');
    _st.navigateViewer(-1);
  }

  void _next() {
    logDebug('Viewer', 'Navigate: next');
    _st.navigateViewer(1);
  }

  // ============================================================
  // EXIF
  // ============================================================

  Future<void> _loadExifForCurrent() async {
    final img = _st.viewerImage;
    if (img == null) return;
    final id = img.id;
    if (id == null) return;

    if (_exifCache.containsKey(id)) {
      _currentExif = _exifCache[id];
      logDebug('Viewer', 'EXIF cache hit for id=$id');
      if (mounted) setState(() {});
      return;
    }

    try {
      final data = await ExifService.read(img.path);
      _exifCache[id] = data;
      _currentExif = data;
      logDebug('Viewer', 'EXIF loaded for id=$id: hasData=${data.hasData}');
    } catch (e) {
      _exifCache[id] = null;
      _currentExif = null;
      logWarn('Viewer', 'EXIF read failed: $e');
    }
    if (mounted) setState(() {});
  }

  // ============================================================
  // Preload adjacent images into Flutter image cache
  // ============================================================

  void _preloadAdjacent() {
    final imgs = _st.viewerImages;
    final idx = _st.viewerIndex;

    if (idx > 0) {
      final prev = imgs[idx - 1];
      final prov = FileImage(File(prev.path));
      final stream = prov.resolve(ImageConfiguration.empty);
      stream.addListener(ImageStreamListener(
        (_, __) {},
        onError: (_, __) {},
      ));
    }

    if (idx < imgs.length - 1) {
      final next = imgs[idx + 1];
      final prov = FileImage(File(next.path));
      final stream = prov.resolve(ImageConfiguration.empty);
      stream.addListener(ImageStreamListener(
        (_, __) {},
        onError: (_, __) {},
      ));
    }

    logDebug('Viewer', 'Preload: prev=${idx > 0} next=${idx < imgs.length - 1}');
  }

  // ============================================================
  // Keyboard
  // ============================================================

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _previous();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _next();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _st.closeViewer();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.numpadAdd:
        _zoomIn();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        _zoomOut();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit0:
      case LogicalKeyboardKey.numpad0:
        _fitToWindow();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        setState(() => _showUI = !_showUI);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyI:
        setState(() => _showExif = !_showExif);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    _checkPageChanged();

    final img = _st.viewerImage;
    if (img == null) {
      logWarn('Viewer', 'Build called with null viewerImage');
      return const SizedBox.shrink();
    }

    final isFirst = _st.viewerIndex <= 0;
    final isLast = _st.viewerIndex >= _st.viewerImages.length - 1;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: Scaffold(
          backgroundColor: Catppuccin.crust.withOpacity(0.97),
          body: Stack(
            fit: StackFit.expand,
            children: [
              _buildImageArea(),
              if (_isImageLoading) _buildLoadingOverlay(),
              if (_showUI) _buildTopBar(img),
              if (_showUI) _buildBottomBar(isFirst, isLast),
              if (_showExif) _buildExifPanel(),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Sub-widgets
  // ============================================================

  Widget _buildImageArea() {
    return GestureDetector(
      onTap: () {
        if (!_showExif) setState(() => _showUI = !_showUI);
      },
      child: InteractiveViewer(
        transformationController: _transformCtrl,
        minScale: 0.05,
        maxScale: 50.0,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        panEnabled: true,
        scaleEnabled: true,
        onInteractionUpdate: (details) {
          setState(() {
            _zoomLevel = _getCurrentScale();
            _isFitToWindow = _zoomLevel <= 1.01;
          });
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _displayedImageId == -1
              ? const SizedBox.shrink()
              : _buildImageWidget(key: ValueKey(_displayedImageId)),
        ),
      ),
    );
  }

  Widget _buildImageWidget({Key? key}) {
    final img = _st.viewerImage;
    if (img == null) return const SizedBox.shrink();

    final file = File(img.path);
    if (!file.existsSync()) {
      return _buildErrorWidget('文件不存在: ${img.filename}');
    }

    return Image.file(
      file,
      key: key,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isImageLoading) setState(() => _isImageLoading = false);
          });
        } else if (frame != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isImageLoading) setState(() => _isImageLoading = false);
          });
        }
        return child;
      },
      errorBuilder: (context, error, stack) => _buildErrorWidget(error.toString()),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 64, color: Catppuccin.overlay0),
          const SizedBox(height: 16),
          Text('无法加载图片', style: TextStyle(color: Catppuccin.overlay0, fontSize: 16)),
          const SizedBox(height: 8),
          Text(message,
              style: TextStyle(color: Catppuccin.overlay1, fontSize: 12),
              textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _isImageLoading ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Catppuccin.base.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40, height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Catppuccin.lavender),
                  ),
                ),
                const SizedBox(height: 12),
                Text('加载中...', style: TextStyle(color: Catppuccin.subtext0, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(ImageItem img) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.55), Colors.black.withOpacity(0.0)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(img.filename,
                    style: TextStyle(color: Catppuccin.text, fontSize: 15, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _pageIndicator(),
              const SizedBox(width: 12),
              _zoomBadge(),
              const SizedBox(width: 8),
              _toolbarBtn(Icons.zoom_out, '缩小 (-)', _zoomOut),
              _pctBtn(),
              _toolbarBtn(Icons.zoom_in, '放大 (+)', _zoomIn),
              _toolbarBtn(Icons.fit_screen_outlined, '适应窗口 (0)', _fitToWindow),
              _toolbarBtn(_showExif ? Icons.info : Icons.info_outline, 'EXIF 信息 (I)',
                  () => setState(() => _showExif = !_showExif), active: _showExif),
              const SizedBox(width: 8),
              _toolbarBtn(Icons.close, '关闭 (Esc)', () => _st.closeViewer(), isClose: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageIndicator() {
    final total = _st.viewerImages.length;
    final cur = _st.viewerIndex + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: Catppuccin.surface0.withOpacity(0.6),
          borderRadius: BorderRadius.circular(10)),
      child: Text('$cur / $total',
          style: TextStyle(color: Catppuccin.subtext0, fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }

  Widget _zoomBadge() {
    final pct = (_zoomLevel * 100).round();
    final isFit = _isFitToWindow;
    return GestureDetector(
      onTap: _fitToWindow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Catppuccin.surface0.withOpacity(0.6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          isFit ? '适应' : '$pct%',
          style: TextStyle(
            color: isFit ? Catppuccin.green : Catppuccin.subtext0,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _pctBtn() {
    final pct = (_zoomLevel * 100).round();
    return GestureDetector(
      onTap: _fitToWindow,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$pct%',
          style: TextStyle(
            color: Catppuccin.subtext0,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _toolbarBtn(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    bool active = false,
    bool isClose = false,
  }) {
    final Color fg;
    if (isClose) {
      fg = Catppuccin.red;
    } else if (active) {
      fg = Catppuccin.lavender;
    } else {
      fg = Catppuccin.subtext0;
    }

    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool isFirst, bool isLast) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.55), Colors.black.withOpacity(0.0)],
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _navBtn(Icons.chevron_left, '上一张 (←)', _previous, disabled: isFirst),
              const SizedBox(width: 4),
              _navBtn(Icons.chevron_right, '下一张 (→)', _next, disabled: isLast),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navBtn(IconData icon, String tooltip, VoidCallback onTap,
      {bool disabled = false}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 28,
              color: disabled ? Catppuccin.overlay0 : Catppuccin.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExifPanel() {
    final exif = _currentExif;
    if (exif == null || !exif.hasData) {
      return Positioned(
        right: 16, top: 64,
        child: _exifCard([_exifRow(exif == null ? '加载中...' : '无 EXIF 数据', '')]),
      );
    }

    final rows = <Widget>[];
    if ((exif.make?.isNotEmpty == true) || (exif.model?.isNotEmpty == true)) {
      final camera = [exif.make, exif.model].where((s) => s != null && s.isNotEmpty).join(' ');
      rows.add(_exifRow('相机', camera));
    }
    if (exif.lensModel?.isNotEmpty == true) {
      rows.add(_exifRow('镜头', exif.lensModel!));
    }
    rows.add(_exifRow('尺寸', exif.dimensionDisplay));
    if (exif.isoSpeed != null) rows.add(_exifRow('ISO', exif.isoDisplay));
    if (exif.fNumber != null) rows.add(_exifRow('光圈', exif.fNumberDisplay));
    if (exif.exposureTime != null) rows.add(_exifRow('快门', exif.exposureDisplay));
    if (exif.focalLength != null) rows.add(_exifRow('焦距', exif.focalDisplay));
    if (exif.dateTime?.isNotEmpty == true) rows.add(_exifRow('时间', exif.dateTime!));
    if (exif.gpsLatitude != null && exif.gpsLongitude != null) {
      rows.add(_exifRow('GPS', '${exif.gpsLatitude!.toStringAsFixed(4)}, ${exif.gpsLongitude!.toStringAsFixed(4)}'));
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      right: 16,
      top: 64,
      child: _exifCard(rows),
    );
  }

  Widget _exifCard(List<Widget> children) {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Catppuccin.mantle.withOpacity(0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Catppuccin.surface0.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: Catppuccin.lavender),
              const SizedBox(width: 6),
              Text('EXIF',
                  style: TextStyle(
                    color: Catppuccin.lavender,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _exifRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: TextStyle(
                color: Catppuccin.overlay1,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Catppuccin.text,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

}
