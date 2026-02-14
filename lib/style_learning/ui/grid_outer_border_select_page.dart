import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/grid_segmenter.dart';
import '../services/image_editor_service.dart';

class GridOuterBorderSelectPage extends StatefulWidget {
  final Uint8List imageBytes;
  final GridOuterBorder? initialBorder;

  const GridOuterBorderSelectPage({
    super.key,
    required this.imageBytes,
    this.initialBorder,
  });

  @override
  State<GridOuterBorderSelectPage> createState() =>
      _GridOuterBorderSelectPageState();
}

class _GridOuterBorderSelectPageState extends State<GridOuterBorderSelectPage> {
  final ImageEditorService _editorService = ImageEditorService();

  Rect _selectRect = Rect.zero;
  Size _imageDisplaySize = Size.zero;
  Offset _imageDisplayOffset = Offset.zero;

  _RectDragMode _dragMode = _RectDragMode.none;
  Offset _panStart = Offset.zero;
  Rect _rectAtPanStart = Rect.zero;

  static const double _minRectSize = 40;
  static const double _handleTouchRadius = 26;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('框选模板外边框'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: Text(
              '确定',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => _buildSelectArea(constraints),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _resetSelection,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重置'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '请只框选最外层网格边框，系统会按模板固定行列自动切分',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectArea(BoxConstraints constraints) {
    final info = _editorService.getImageInfo(widget.imageBytes);
    final imageWidth = info.width.toDouble();
    final imageHeight = info.height.toDouble();

    final imageAspect = imageWidth / imageHeight;
    final containerAspect = constraints.maxWidth / constraints.maxHeight;

    double drawWidth;
    double drawHeight;
    if (containerAspect > imageAspect) {
      drawHeight = constraints.maxHeight;
      drawWidth = drawHeight * imageAspect;
    } else {
      drawWidth = constraints.maxWidth;
      drawHeight = drawWidth / imageAspect;
    }

    final left = (constraints.maxWidth - drawWidth) / 2;
    final top = (constraints.maxHeight - drawHeight) / 2;

    _imageDisplaySize = Size(drawWidth, drawHeight);
    _imageDisplayOffset = Offset(left, top);

    if (_selectRect == Rect.zero) {
      final initial = widget.initialBorder;
      if (initial != null) {
        _selectRect = Rect.fromLTWH(
          left + initial.left * drawWidth,
          top + initial.top * drawHeight,
          initial.width * drawWidth,
          initial.height * drawHeight,
        );
      } else {
        _selectRect = Rect.fromLTWH(
          left + 20,
          top + 20,
          drawWidth - 40,
          drawHeight - 40,
        );
      }
    }

    return GestureDetector(
      onPanStart: (details) {
        _dragMode = _resolveDragMode(details.localPosition);
        _panStart = details.localPosition;
        _rectAtPanStart = _selectRect;
      },
      onPanUpdate: (details) {
        setState(() {
          final dx = details.localPosition.dx - _panStart.dx;
          final dy = details.localPosition.dy - _panStart.dy;
          _selectRect = _computeDraggedRect(
            startRect: _rectAtPanStart,
            mode: _dragMode,
            dx: dx,
            dy: dy,
          );
          _selectRect = _constrainRect(_selectRect, left, top, drawWidth, drawHeight);
        });
      },
      onPanEnd: (_) {
        _dragMode = _RectDragMode.none;
      },
      child: Stack(
        children: [
          Center(
            child: Image.memory(
              widget.imageBytes,
              fit: BoxFit.contain,
            ),
          ),
          CustomPaint(
            size: Size.infinite,
            painter: _SelectionOverlayPainter(_selectRect),
          ),
          Positioned.fromRect(
            rect: _selectRect,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.lightBlueAccent, width: 2),
              ),
              child: Stack(
                children: [
                  _buildHandle(Alignment.topLeft),
                  _buildHandle(Alignment.topRight),
                  _buildHandle(Alignment.bottomLeft),
                  _buildHandle(Alignment.bottomRight),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(
          color: Colors.lightBlueAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  _RectDragMode _resolveDragMode(Offset pos) {
    final corners = <_RectDragMode, Offset>{
      _RectDragMode.resizeTopLeft: _selectRect.topLeft,
      _RectDragMode.resizeTopRight: _selectRect.topRight,
      _RectDragMode.resizeBottomLeft: _selectRect.bottomLeft,
      _RectDragMode.resizeBottomRight: _selectRect.bottomRight,
    };

    for (final entry in corners.entries) {
      if ((pos - entry.value).distance <= _handleTouchRadius) {
        return entry.key;
      }
    }

    if (_selectRect.contains(pos)) return _RectDragMode.move;
    return _RectDragMode.none;
  }

  Rect _computeDraggedRect({
    required Rect startRect,
    required _RectDragMode mode,
    required double dx,
    required double dy,
  }) {
    switch (mode) {
      case _RectDragMode.resizeTopLeft:
        return Rect.fromLTRB(
            startRect.left + dx, startRect.top + dy, startRect.right, startRect.bottom);
      case _RectDragMode.resizeTopRight:
        return Rect.fromLTRB(
            startRect.left, startRect.top + dy, startRect.right + dx, startRect.bottom);
      case _RectDragMode.resizeBottomLeft:
        return Rect.fromLTRB(
            startRect.left + dx, startRect.top, startRect.right, startRect.bottom + dy);
      case _RectDragMode.resizeBottomRight:
        return Rect.fromLTRB(
            startRect.left, startRect.top, startRect.right + dx, startRect.bottom + dy);
      case _RectDragMode.move:
        return startRect.shift(Offset(dx, dy));
      case _RectDragMode.none:
        return startRect;
    }
  }

  Rect _constrainRect(Rect rect, double left, double top, double drawWidth, double drawHeight) {
    final rightBound = left + drawWidth;
    final bottomBound = top + drawHeight;

    double l = rect.left;
    double t = rect.top;
    double r = rect.right;
    double b = rect.bottom;

    if (r - l < _minRectSize) {
      if (_dragMode == _RectDragMode.resizeTopLeft ||
          _dragMode == _RectDragMode.resizeBottomLeft) {
        l = r - _minRectSize;
      } else {
        r = l + _minRectSize;
      }
    }
    if (b - t < _minRectSize) {
      if (_dragMode == _RectDragMode.resizeTopLeft ||
          _dragMode == _RectDragMode.resizeTopRight) {
        t = b - _minRectSize;
      } else {
        b = t + _minRectSize;
      }
    }

    if (_dragMode == _RectDragMode.move) {
      final width = r - l;
      final height = b - t;
      l = l.clamp(left, rightBound - width);
      t = t.clamp(top, bottomBound - height);
      r = l + width;
      b = t + height;
    } else {
      l = l.clamp(left, rightBound - _minRectSize);
      t = t.clamp(top, bottomBound - _minRectSize);
      r = r.clamp(left + _minRectSize, rightBound);
      b = b.clamp(top + _minRectSize, bottomBound);
    }

    if (r - l < _minRectSize) {
      r = (l + _minRectSize).clamp(left + _minRectSize, rightBound);
    }
    if (b - t < _minRectSize) {
      b = (t + _minRectSize).clamp(top + _minRectSize, bottomBound);
    }

    return Rect.fromLTRB(l, t, r, b);
  }

  void _resetSelection() {
    setState(() {
      _selectRect = Rect.fromLTWH(
        _imageDisplayOffset.dx + 20,
        _imageDisplayOffset.dy + 20,
        _imageDisplaySize.width - 40,
        _imageDisplaySize.height - 40,
      );
    });
  }

  void _confirm() {
    final normLeft =
        ((_selectRect.left - _imageDisplayOffset.dx) / _imageDisplaySize.width)
            .clamp(0.0, 1.0);
    final normTop =
        ((_selectRect.top - _imageDisplayOffset.dy) / _imageDisplaySize.height)
            .clamp(0.0, 1.0);
    final normWidth = (_selectRect.width / _imageDisplaySize.width)
        .clamp(0.01, 1.0 - normLeft);
    final normHeight = (_selectRect.height / _imageDisplaySize.height)
        .clamp(0.01, 1.0 - normTop);

    Navigator.pop(
      context,
      GridOuterBorder(
        left: normLeft,
        top: normTop,
        width: normWidth,
        height: normHeight,
      ),
    );
  }
}

class _SelectionOverlayPainter extends CustomPainter {
  final Rect selectRect;

  _SelectionOverlayPainter(this.selectRect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, selectRect.top), paint);
    canvas.drawRect(
        Rect.fromLTRB(0, selectRect.bottom, size.width, size.height), paint);
    canvas.drawRect(
        Rect.fromLTRB(0, selectRect.top, selectRect.left, selectRect.bottom),
        paint);
    canvas.drawRect(
        Rect.fromLTRB(selectRect.right, selectRect.top, size.width, selectRect.bottom),
        paint);
  }

  @override
  bool shouldRepaint(covariant _SelectionOverlayPainter oldDelegate) {
    return oldDelegate.selectRect != selectRect;
  }
}

enum _RectDragMode {
  none,
  move,
  resizeTopLeft,
  resizeTopRight,
  resizeBottomLeft,
  resizeBottomRight,
}
