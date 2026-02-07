//类比“面板”：只显示状态、触发动作，不直接操纵底层协议。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/app_logger.dart';
import '../state/printer_controller.dart';

class StatusPage extends StatelessWidget {
  const StatusPage({super.key});

  Color _logColor(BuildContext context, LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case LogLevel.info:
        return Theme.of(context).colorScheme.onSurface;
      case LogLevel.warn:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PrinterController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Moonraker Status')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phase: ${c.phase.name}'),
            if (c.lastError != null)
              Text('Error: ${c.lastError}',
                  style: const TextStyle(color: Colors.red)),
            Text('proc_stat_notify_count: ${c.procStatNotifyCount}'),
            Text('Moonraker: ${c.moonrakerVersion}'),
            Text('Klippy(server/info): ${c.klippyStateFromServerInfo}'),
            Text('Printer(printer/info): ${c.printerState}'),
            const Divider(),

            Text('print_state: ${c.printState}'),
            Text('filename: ${c.filename}'),
            Text('sd_active: ${c.sdIsActive}'),
            Text('progress: ${(c.progress * 100).toStringAsFixed(1)}%'),
            Text('toolhead.position: ${c.toolheadPosition}'),
            Text('gcode_move.gcode_position: ${c.gcodePosition}'),

            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => c.sendTestGcode(),
                  child: const Text('Send M115'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    final text = c.logger.exportText();
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logs copied to clipboard')),
                    );
                  },
                  child: const Text('Export Logs'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    c.disconnect();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Disconnect'),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Text('Logs:'),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.black12,
                child: ListView(
                  children: c.logger.entries.reversed
                      .map(
                        (e) => Text(
                          e.toLine(),
                          style: TextStyle(color: _logColor(context, e.level)),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}