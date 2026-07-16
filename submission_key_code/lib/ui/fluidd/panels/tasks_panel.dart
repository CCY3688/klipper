import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/printer_controller.dart';
import '../../../data/moonraker/moonraker_models.dart';
import '../widgets/fluidd_card.dart';

class TasksPanel extends StatefulWidget {
  const TasksPanel({super.key});

  @override
  State<TasksPanel> createState() => _TasksPanelState();
}

class _TasksPanelState extends State<TasksPanel> {
  @override
  void initState() {
    super.initState();
    // load once after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<PrinterController>();
      c.refreshGcodeFiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PrinterController>();

    return FluiddCard(
      title: '任务列表',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '刷新任务列表',
          icon: const Icon(Icons.refresh, color: Colors.grey, size: 20),
          onPressed: c.gcodeFilesLoading ? null : () => c.refreshGcodeFiles(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CurrentJobBar(
            state: c.printState,
            filename: c.filename,
            progress: c.progress,
          ),
          const SizedBox(height: 8),
          if (c.gcodeFilesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (c.gcodeFilesError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '加载失败: ${c.gcodeFilesError}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            )
          else if (c.gcodeFiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  '暂无任务（gcodes 目录为空）',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            )
          else
            SizedBox(
              height: 260,
              child: ListView.separated(
                itemCount: c.gcodeFiles.length,
                separatorBuilder: (context, index) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, i) {
                  final item = c.gcodeFiles[i];
                  return _TaskRow(item: item);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatefulWidget {
  final MoonrakerFileItem item;
  const _TaskRow({required this.item});

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _starting = false;
  bool _deleting = false;

  String _displayName(MoonrakerFileItem item) {
    // prefer path if provided (may include subdir)
    if (item.path.trim().isNotEmpty) return item.path;
    return item.filename;
  }

  Future<void> _confirmDelete(BuildContext context, PrinterController c, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C3034),
        title: const Text('删除任务', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text('确定要删除 $name 吗？', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      setState(() => _deleting = true);
      final success = await c.deleteGcodeFile(name);
      if (mounted && context.mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '已删除: $name' : '删除失败: ${c.lastError}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<PrinterController>();
    final messenger = ScaffoldMessenger.of(context);
    final item = widget.item;
    final name = _displayName(item);

    return ListTile(
      dense: true,
      title: Text(
        name,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'size: ${(item.size / 1024).toStringAsFixed(1)} KB',
        style: const TextStyle(color: Colors.white54, fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: _deleting 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
            onPressed: _deleting || _starting ? null : () => _confirmDelete(context, c, name),
            tooltip: '删除任务',
          ),
          const SizedBox(width: 8),
          const Text('立即开始', style: TextStyle(color: Colors.white54, fontSize: 11)),
          Switch(
            value: false,
            onChanged: _starting || _deleting
                ? null
                : (v) async {
                    if (!v) return;
                    setState(() => _starting = true);
                    final ok = await c.startPrintUploaded(name);
                    if (mounted) {
                      setState(() => _starting = false);
                      final msg = ok ? '已开始: $name' : '开始失败: ${c.lastError ?? 'unknown'}';
                      messenger.showSnackBar(
                        SnackBar(content: Text(msg)),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class _CurrentJobBar extends StatelessWidget {
  final String state;
  final String filename;
  final double progress;

  const _CurrentJobBar({
    required this.state,
    required this.filename,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final showFile = filename.isNotEmpty;
    final pct = (progress * 100).clamp(0, 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('当前任务: ', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(state, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            showFile ? filename : '--',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  backgroundColor: Colors.black26,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Text('$pct%', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
