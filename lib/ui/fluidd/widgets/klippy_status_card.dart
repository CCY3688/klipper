import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/printer_controller.dart';

/// 当 Klippy 未就绪时显示的状态卡片（参考 Fluidd 的 KlippyStatusCard）
/// 显示错误信息、重启按钮等
class KlippyStatusCard extends StatelessWidget {
  const KlippyStatusCard({super.key});

  String _getKlippyStateTitle(PrinterController c) {
    if (c.phase != AppConnPhase.connected) {
      return 'Not Connected';
    }
    
    switch (c.klippyState) {
      case 'startup':
        return 'Starting Up';
      case 'shutdown':
        return 'Shutdown';
      case 'error':
        return 'Error';
      case 'disconnected':
        return 'Disconnected';
      default:
        return c.klippyState;
    }
  }

  Color _getStateColor(PrinterController c) {
    if (c.phase != AppConnPhase.connected) {
      return Colors.grey;
    }
    
    switch (c.klippyState) {
      case 'startup':
        return Colors.orange;
      case 'shutdown':
      case 'error':
      case 'disconnected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStateIcon(PrinterController c) {
    if (c.phase != AppConnPhase.connected) {
      return Icons.cloud_off;
    }
    
    switch (c.klippyState) {
      case 'startup':
        return Icons.hourglass_empty;
      case 'shutdown':
        return Icons.power_settings_new;
      case 'error':
        return Icons.error_outline;
      case 'disconnected':
        return Icons.link_off;
      default:
        return Icons.warning_amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PrinterController>();
    final stateColor = _getStateColor(c);
    final stateTitle = _getKlippyStateTitle(c);
    final stateIcon = _getStateIcon(c);

    return Card(
      color: const Color(0xFF2C3034),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Icon(stateIcon, color: stateColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Klippy: $stateTitle',
                  style: TextStyle(
                    color: stateColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 状态消息
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: stateColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: stateColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    c.klippyStateMessage,
                    style: TextStyle(color: stateColor, fontSize: 14),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 操作按钮
                Row(
                  children: [
                    // 重启 Firmware 按钮
                    if (c.klippyState == 'error' || c.klippyState == 'shutdown')
                      ElevatedButton.icon(
                        onPressed: () {
                          c.sendGcode('FIRMWARE_RESTART');
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Firmware Restart'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    
                    const SizedBox(width: 8),
                    
                    // 重新连接按钮（当 klippy 断开时）
                    if (c.klippyState == 'disconnected' && c.phase == AppConnPhase.connected)
                      ElevatedButton.icon(
                        onPressed: () {
                          // 发送重连请求（可能需要通过 Moonraker 重启 Klipper 服务）
                          c.sendGcode('RESTART');
                        },
                        icon: const Icon(Icons.power_settings_new, size: 18),
                        label: const Text('Restart Klipper'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade800,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
