import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../state/printer_controller.dart';
import '../../../state/settings_controller.dart';
import '../widgets/fluidd_card.dart';

class StatusPanel extends StatefulWidget {
  const StatusPanel({super.key});

  @override
  State<StatusPanel> createState() => _StatusPanelState();
}

class _StatusPanelState extends State<StatusPanel> {
  /// Which axis is currently being edited by keyboard: 'X', 'Y', 'Z', or null
  String? _editingAxis;
  final _editController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _editController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 根据 klippy 和打印状态返回显示状态和颜色
  (String, Color) _getDisplayState(PrinterController c) {
    if (c.phase == AppConnPhase.idle ||
        c.phase == AppConnPhase.disconnected ||
        c.phase == AppConnPhase.error) {
      return ('未连接', Colors.grey);
    }

    if (c.phase == AppConnPhase.connecting ||
        c.phase == AppConnPhase.reconnecting) {
      return ('连接中...', Colors.orangeAccent);
    }

    if (!c.klippyConnected) {
      return ('Klippy 已断开', Colors.redAccent);
    }

    switch (c.klippyState) {
      case 'startup':
        return ('启动中', Colors.orangeAccent);
      case 'shutdown':
        return ('已关闭', Colors.redAccent);
      case 'error':
        return ('错误', Colors.redAccent);
      case 'ready':
        final printState = c.printState;
        switch (printState) {
          case 'printing':
            return ('打印中', Colors.greenAccent);
          case 'paused':
            return ('已暂停', Colors.yellowAccent);
          case 'error':
            return ('打印错误', Colors.redAccent);
          case 'complete':
            return ('已完成', Colors.lightBlueAccent);
          case 'cancelled':
            return ('已取消', Colors.orange);
          case 'standby':
            return ('待机', Colors.white);
          default:
            return (printState.toUpperCase(), Colors.white);
        }
      default:
        return (c.klippyState.toUpperCase(), Colors.grey);
    }
  }

  /// 发送绝对位置移动 G-code（点击提交时调用）
  Future<void> _moveToAxis(
    PrinterController c,
    SettingsController s,
    String axis,
    double pos,
  ) async {
    final speed = axis == 'Z' ? s.zSpeed.toInt() : s.xySpeed.toInt();
    // 切换到绝对坐标 → 移动到目标位置 → 切回相对坐标
    final gcode = 'G90\nG1 $axis$pos F$speed\nG91';
    final error = await c.sendGcode(gcode);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
    );
  }

  /// 弹出提示：请先进行归零操作
  void _showNotHomedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('提示', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          '请先进行归零操作',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _startEditing(String axis, double currentVal, bool isHomed) {
    if (!isHomed) {
      _showNotHomedDialog();
      return;
    }
    setState(() {
      _editingAxis = axis;
      _editController.text = currentVal.toStringAsFixed(2);
    });
    // 延迟聚焦，确保 TextField 已构建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _submitEdit(PrinterController c, SettingsController s) {
    final text = _editController.text.trim();
    final parsed = double.tryParse(text);
    if (parsed != null && _editingAxis != null) {
      _moveToAxis(c, s, _editingAxis!, parsed);
    }
    setState(() {
      _editingAxis = null;
      _editController.clear();
    });
    _focusNode.unfocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingAxis = null;
      _editController.clear();
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PrinterController>();
    final s = context.watch<SettingsController>();

    final (displayState, statusColor) = _getDisplayState(c);

    return FluiddCard(
      title: '状态',
      child: Column(
        children: [
          _buildRow('状态', displayState, valueColor: statusColor),

          if (!c.klippyReady && c.phase == AppConnPhase.connected) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text(
                c.klippyStateMessage,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ],

          if (c.klippyReady) ...[
            const Divider(color: Colors.white24),
            _buildRow('文件', c.filename.isEmpty ? '--' : c.filename),
            _buildRow('进度', '${(c.progress * 100).toStringAsFixed(1)} %'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: c.progress,
              backgroundColor: Colors.black26,
              color: Colors.blue,
            ),
            const SizedBox(height: 16),
            // ── Live position (motion_report) ──
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "实时位置",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            if (c.livePosition != null && c.livePosition!.length >= 3) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _LiveCoordBadge(axis: 'X', val: c.livePosition![0]),
                  _LiveCoordBadge(axis: 'Y', val: c.livePosition![1]),
                  _LiveCoordBadge(axis: 'Z', val: c.livePosition![2]),
                ],
              ),
            ] else
              const Text(
                "[--, --, --]",
                style: TextStyle(color: Colors.white54),
              ),
            const SizedBox(height: 12),
            // ── Commanded position (toolhead.position) — editable ──
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    "工具头位置（点击编辑）",
                    style: TextStyle(
                      color: c.isHomed ? Colors.grey : Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
                  if (!c.isHomed) ...[
                    const SizedBox(width: 6),
                    const Text(
                      "⚠ 未归零",
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (c.toolheadPosition != null &&
                c.toolheadPosition!.length >= 3) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _EditableCoordBadge(
                    axis: 'X',
                    val: c.toolheadPosition![0],
                    isEditing: _editingAxis == 'X',
                    controller: _editingAxis == 'X' ? _editController : null,
                    focusNode: _editingAxis == 'X' ? _focusNode : null,
                    homed: c.isHomed,
                    onTap: () =>
                        _startEditing('X', c.toolheadPosition![0], c.isHomed),
                    onSubmit: () => _submitEdit(c, s),
                    onCancel: _cancelEdit,
                  ),
                  _EditableCoordBadge(
                    axis: 'Y',
                    val: c.toolheadPosition![1],
                    isEditing: _editingAxis == 'Y',
                    controller: _editingAxis == 'Y' ? _editController : null,
                    focusNode: _editingAxis == 'Y' ? _focusNode : null,
                    homed: c.isHomed,
                    onTap: () =>
                        _startEditing('Y', c.toolheadPosition![1], c.isHomed),
                    onSubmit: () => _submitEdit(c, s),
                    onCancel: _cancelEdit,
                  ),
                  _EditableCoordBadge(
                    axis: 'Z',
                    val: c.toolheadPosition![2],
                    isEditing: _editingAxis == 'Z',
                    controller: _editingAxis == 'Z' ? _editController : null,
                    focusNode: _editingAxis == 'Z' ? _focusNode : null,
                    homed: c.isHomed,
                    onTap: () =>
                        _startEditing('Z', c.toolheadPosition![2], c.isHomed),
                    onSubmit: () => _submitEdit(c, s),
                    onCancel: _cancelEdit,
                  ),
                ],
              ),
            ] else if (c.livePosition == null || c.livePosition!.length < 3)
              const Text("--", style: TextStyle(color: Colors.white54)),
          ],
        ],
      ),
    );
  }
}

/// Editable commanded-position badge.
/// In display mode: shows a tappable badge.
/// When homed: blue axis label + white value.
/// When not homed: orange axis label + orange tint border (warning).
/// In edit mode: shows a compact TextField for keyboard input.
class _EditableCoordBadge extends StatelessWidget {
  final String axis;
  final double val;
  final bool isEditing;
  final bool homed;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  const _EditableCoordBadge({
    required this.axis,
    required this.val,
    required this.isEditing,
    required this.homed,
    this.controller,
    this.focusNode,
    required this.onTap,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    // Colors based on homing state
    final axisColor = homed ? Colors.blue : Colors.orangeAccent;
    final borderColor = homed
        ? Colors.white10
        : Colors.orangeAccent.withValues(alpha: 0.4);
    final valueColor = homed
        ? Colors.white
        : Colors.orangeAccent.withValues(alpha: 0.8);

    if (isEditing && controller != null && focusNode != null) {
      return Container(
        width: 110,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2C3034),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blueAccent),
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9\-.]')),
          ],
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            hintText: val.toStringAsFixed(2),
            hintStyle: const TextStyle(
              color: Colors.white24,
              fontFamily: 'monospace',
            ),
            prefixText: '$axis: ',
            prefixStyle: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          onSubmitted: (_) => onSubmit(),
          onTapOutside: (_) => onCancel(),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$axis: ',
              style: TextStyle(
                color: axisColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Expanded(
              child: Text(
                val.toStringAsFixed(2),
                style: TextStyle(
                  color: valueColor,
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live position badge — shows actual stepper position in brackets, matching Fluidd style
class _LiveCoordBadge extends StatelessWidget {
  final String axis;
  final double val;
  const _LiveCoordBadge({required this.axis, required this.val});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Text(
            '$axis: ',
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            '[',
            style: TextStyle(color: Colors.white54, fontFamily: 'monospace'),
          ),
          Text(
            val.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontFamily: 'monospace',
            ),
          ),
          const Text(
            ']',
            style: TextStyle(color: Colors.white54, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
