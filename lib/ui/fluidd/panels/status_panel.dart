import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/printer_controller.dart';
import '../widgets/fluidd_card.dart';

class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key});

  Widget _buildRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// 根据 klippy 和打印状态返回显示状态和颜色
  (String, Color) _getDisplayState(PrinterController c) {
    // 首先检查 App 连接阶段
    if (c.phase == AppConnPhase.idle || 
        c.phase == AppConnPhase.disconnected ||
        c.phase == AppConnPhase.error) {
      return ('NOT CONNECTED', Colors.grey);
    }
    
    if (c.phase == AppConnPhase.connecting || c.phase == AppConnPhase.reconnecting) {
      return ('CONNECTING...', Colors.orangeAccent);
    }
    
    // 检查 Klippy 连接状态
    if (!c.klippyConnected) {
      return ('KLIPPY DISCONNECTED', Colors.redAccent);
    }
    
    // 根据 klippy 状态返回
    switch (c.klippyState) {
      case 'startup':
        return ('STARTING UP', Colors.orangeAccent);
      case 'shutdown':
        return ('SHUTDOWN', Colors.redAccent);
      case 'error':
        return ('ERROR', Colors.redAccent);
      case 'ready':
        // Klippy ready，显示打印状态
        final printState = c.printState;
        switch (printState) {
          case 'printing':
            return ('PRINTING', Colors.greenAccent);
          case 'paused':
            return ('PAUSED', Colors.yellowAccent);
          case 'error':
            return ('PRINT ERROR', Colors.redAccent);
          case 'complete':
            return ('COMPLETE', Colors.lightBlueAccent);
          case 'cancelled':
            return ('CANCELLED', Colors.orange);
          case 'standby':
            return ('STANDBY', Colors.white);
          default:
            return (printState.toUpperCase(), Colors.white);
        }
      default:
        return (c.klippyState.toUpperCase(), Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PrinterController>();
    
    final (displayState, statusColor) = _getDisplayState(c);

    return FluiddCard(
      title: 'Status',
      child: Column(
        children: [
          _buildRow('State', displayState, valueColor: statusColor),
          
          // 当 klippy 未就绪时显示错误/状态消息
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
          
          // 仅在 klippy 就绪时显示打印详情
          if (c.klippyReady) ...[
            const Divider(color: Colors.white24),
            _buildRow('File', c.filename.isEmpty ? '--' : c.filename),
            _buildRow('Progress', '${(c.progress * 100).toStringAsFixed(1)} %'),
            const SizedBox(height: 8),
            LinearProgressIndicator( value: c.progress, backgroundColor: Colors.black26, color: Colors.blue ),
            const SizedBox(height: 16),
            const Align(alignment: Alignment.centerLeft, child: Text("Toolhead Position", style: TextStyle(color: Colors.grey, fontSize: 12))),
            if (c.toolheadPosition != null && c.toolheadPosition!.length >= 3) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CoordBadge(axis: 'X', val: c.toolheadPosition![0]),
                  _CoordBadge(axis: 'Y', val: c.toolheadPosition![1]),
                  _CoordBadge(axis: 'Z', val: c.toolheadPosition![2]),
                ],
              )
            ] else 
              const Text("--", style: TextStyle(color: Colors.white54)),
          ],
        ],
      ),
    );
  }
}

class _CoordBadge extends StatelessWidget {
  final String axis;
  final double val;
  const _CoordBadge({required this.axis, required this.val});

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
           Text('$axis: ', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
           Text(val.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
