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
      appBar: AppBar(title: const Text('Moonraker 状态')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('连接阶段: ${c.phase.name}'),
            if (c.lastError != null)
              Text(
                '错误: ${c.lastError}',
                style: const TextStyle(color: Colors.red),
              ),
            Text('进程状态通知次数: ${c.procStatNotifyCount}'),
            Text('Moonraker 版本: ${c.moonrakerVersion}'),
            const Divider(),

            // Klippy 状态（新增）
            Text('Klippy 是否连接: ${c.klippyConnected}'),
            Text('Klippy 状态: ${c.klippyState}'),
            Text('Klippy 是否就绪: ${c.klippyReady}'),
            Text(
              'Klippy 状态消息: ${c.klippyStateMessage}',
              style: TextStyle(
                color: c.klippyReady ? Colors.green : Colors.orange,
              ),
            ),
            const Divider(),

            Text('Klippy（server/info）: ${c.klippyStateFromServerInfo}'),
            Text('打印机（printer/info）: ${c.printerState}'),
            const Divider(),

            Text('打印状态: ${c.printState}'),
            Text('文件名: ${c.filename}'),
            Text('SD 是否活动: ${c.sdIsActive}'),
            Text('进度: ${(c.progress * 100).toStringAsFixed(1)}%'),
            Text('工具头位置: ${c.toolheadPosition}'),
            Text('G-code 位置: ${c.gcodePosition}'),

            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => c.sendTestGcode(),
                  child: const Text('发送 M115'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    final text = c.logger.exportText();
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
                  },
                  child: const Text('导出日志'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    c.disconnect();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('断开连接'),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Text('日志:'),
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
