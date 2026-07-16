import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/app_logger.dart';
import '../../../state/printer_controller.dart';
import '../widgets/fluidd_card.dart';

class ConsolePanel extends StatefulWidget {
  const ConsolePanel({super.key});

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  void _sendCommand(PrinterController c) {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    c.sendGcode(text);
    _inputCtrl.clear();
    // Auto scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0, // Reverse list, 0 is bottom
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _logColor(BuildContext context, LogLevel level) {
    // Fluidd console colors
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.white;
      case LogLevel.warn:
        return Colors.orange;
      case LogLevel.error:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PrinterController>();
    final entries = c.consoleEntries;

    return FluiddCard(
      title: '控制台',
      scrollable: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
          onPressed: c.clearConsole,
          tooltip: '清空控制台',
        ),
        IconButton(
          icon: const Icon(Icons.content_copy, size: 20, color: Colors.grey),
          onPressed: () async {
            final text = c.exportConsoleText();
            await Clipboard.setData(ClipboardData(text: text));
          },
          tooltip: '复制日志',
        ),
      ],
      child: Column(
        children: [
          // Log Area
          Container(
            height: 300,
            color: const Color(0xFF1E1E1E), // Darker console bg
            child: ListView.builder(
              controller: _scrollCtrl,
              reverse:
                  true, // Newest at bottom visually if we stack from bottom?
              // Actually standard logs usually have newest at bottom.
              // Using reverse: true means index 0 is at bottom.
              padding: const EdgeInsets.all(8),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                // entries is chronological.
                // If reverse=true, index 0 is the last item in the list (newest).
                final entry = entries[entries.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '[${entry.ts.hour.toString().padLeft(2, '0')}:${entry.ts.minute.toString().padLeft(2, '0')}:${entry.ts.second.toString().padLeft(2, '0')}] ',
                          style: const TextStyle(
                            color: Colors.blueGrey,
                            fontSize: 12,
                          ),
                        ),
                        if (entry.tag.isNotEmpty)
                          TextSpan(
                            text: '${entry.tag} ',
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        TextSpan(
                          text: entry.msg,
                          style: TextStyle(
                            color: _logColor(context, entry.level),
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Input Area
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  style: const TextStyle(
                    color: Colors.white,
                  ), // Force white text for dark theme
                  decoration: const InputDecoration(
                    hintText: '发送 G-code...',
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _sendCommand(c),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _sendCommand(c),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
