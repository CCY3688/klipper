import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/moonraker/moonraker_models.dart';
import '../../state/printer_controller.dart';
import 'widgets/fluidd_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 配置页 —— 对标 fluidd Configure.vue
//   左栏：config 根目录（printer.cfg / moonraker.conf 等）
//   右栏：logs / docs / config_examples
// ─────────────────────────────────────────────────────────────────────────────
class ConfigurePage extends StatelessWidget {
  const ConfigurePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
            child: _FileBrowserCard(root: 'config', title: '配置文件'),
          )),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
            child: _MultiRootBrowserCard(
              roots: const ['logs', 'docs', 'config_examples'],
              title: '其他文件',
            ),
          )),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _FileBrowserCard(root: 'config', title: '配置文件'),
          _MultiRootBrowserCard(
            roots: const ['logs', 'docs', 'config_examples'],
            title: '其他文件',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 单 root 文件浏览卡（用于 config）
// ─────────────────────────────────────────────────────────────────────────────
class _FileBrowserCard extends StatefulWidget {
  final String root;
  final String title;
  const _FileBrowserCard({required this.root, required this.title});

  @override
  State<_FileBrowserCard> createState() => _FileBrowserCardState();
}

class _FileBrowserCardState extends State<_FileBrowserCard> {
  List<MoonrakerFileItem> _files = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final repo = context.read<PrinterController>().repo;
      if (repo == null) throw Exception('未连接');
      final files = await repo.listFiles(root: widget.root);
      files.sort((a, b) => a.path.compareTo(b.path));
      setState(() { _files = files; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: widget.title,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 18, color: Colors.grey),
          tooltip: '刷新',
          onPressed: _loading ? null : _load,
        ),
      ],
      child: _FileListBody(
        files: _files,
        loading: _loading,
        error: _error,
        root: widget.root,
        onChanged: _load,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 多 root 标签页卡（logs / docs / config_examples）
// ─────────────────────────────────────────────────────────────────────────────
class _MultiRootBrowserCard extends StatefulWidget {
  final List<String> roots;
  final String title;
  const _MultiRootBrowserCard({required this.roots, required this.title});

  @override
  State<_MultiRootBrowserCard> createState() => _MultiRootBrowserCardState();
}

class _MultiRootBrowserCardState extends State<_MultiRootBrowserCard>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final Map<String, List<MoonrakerFileItem>> _cache = {};
  final Map<String, bool>   _loading = {};
  final Map<String, String?> _error  = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: widget.roots.length, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _loadRoot(widget.roots[_tabs.index]);
    });
    _loadRoot(widget.roots[0]);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadRoot(String root) async {
    if (_loading[root] == true) return;
    setState(() { _loading[root] = true; _error[root] = null; });
    try {
      final repo = context.read<PrinterController>().repo;
      if (repo == null) throw Exception('未连接');
      final files = await repo.listFiles(root: root);
      files.sort((a, b) => a.path.compareTo(b.path));
      _cache[root] = files;
    } catch (e) {
      _error[root] = e.toString();
    } finally {
      setState(() { _loading[root] = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FluiddCard(
      title: widget.title,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 18, color: Colors.grey),
          tooltip: '刷新',
          onPressed: () => _loadRoot(widget.roots[_tabs.index]),
        ),
      ],
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: widget.roots.map((r) => Tab(text: r)).toList(),
            labelStyle: const TextStyle(fontSize: 12),
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(color: Colors.blue, width: 2),
            ),
          ),
          SizedBox(
            height: 400,
            child: TabBarView(
              controller: _tabs,
              children: widget.roots.map((root) {
                return _FileListBody(
                  files: _cache[root] ?? [],
                  loading: _loading[root] ?? false,
                  error: _error[root],
                  root: root,
                  onChanged: () => _loadRoot(root),
                  readOnly: root == 'logs', // logs 只读
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 文件列表 body（供两种卡复用）
// ─────────────────────────────────────────────────────────────────────────────
class _FileListBody extends StatelessWidget {
  final List<MoonrakerFileItem> files;
  final bool loading;
  final String? error;
  final String root;
  final bool readOnly;
  final VoidCallback onChanged;

  const _FileListBody({
    required this.files,
    required this.loading,
    required this.error,
    required this.root,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
      );
    }
    if (files.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('（空）', style: TextStyle(color: Colors.white38))),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: files.length,
      separatorBuilder: (_, index) => const Divider(color: Colors.white10, height: 1),
      itemBuilder: (context, i) {
        final file = files[i];
        return _FileRow(
          file: file,
          root: root,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 单行文件条目
// ─────────────────────────────────────────────────────────────────────────────
class _FileRow extends StatelessWidget {
  final MoonrakerFileItem file;
  final String root;
  final bool readOnly;
  final VoidCallback onChanged;

  const _FileRow({
    required this.file,
    required this.root,
    required this.readOnly,
    required this.onChanged,
  });

  IconData _iconFor(String name) {
    if (name.endsWith('.cfg'))  return Icons.settings_applications;
    if (name.endsWith('.conf')) return Icons.settings;
    if (name.endsWith('.log'))  return Icons.article_outlined;
    if (name.endsWith('.md'))   return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  void _openEditor(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FileEditorPage(
          root: root,
          path: file.path,
          readOnly: readOnly,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确认删除 ${file.path}？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      final repo = context.read<PrinterController>().repo!;
      await repo.deleteConfigFile(root: root, path: file.path);
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openEditor(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(_iconFor(file.path), size: 18, color: Colors.blue.shade300),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.path,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  if (file.size > 0)
                    Text(
                      _fmtSize(file.size),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                ],
              ),
            ),
            if (!readOnly)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () => _delete(context),
              ),
            const Icon(Icons.chevron_right, size: 16, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 文件编辑页（全屏路由）
// ─────────────────────────────────────────────────────────────────────────────
class _FileEditorPage extends StatefulWidget {
  final String root;
  final String path;
  final bool readOnly;

  const _FileEditorPage({
    required this.root,
    required this.path,
    required this.readOnly,
  });

  @override
  State<_FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends State<_FileEditorPage> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving   = false;
  String? _error;
  bool _dirty    = false;          // 是否有未保存改动

  @override
  void initState() {
    super.initState();
    _load();
    _ctrl.addListener(() {
      if (!_dirty) setState(() => _dirty = true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final repo = context.read<PrinterController>().repo;
      if (repo == null) throw Exception('未连接');
      final text = await repo.readFileText(root: widget.root, path: widget.path);
      _ctrl.text = text;
      setState(() { _dirty = false; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() { _saving = true; });
    try {
      final repo = context.read<PrinterController>().repo!;
      await repo.writeFileText(
        root: widget.root,
        path: widget.path,
        content: _ctrl.text,
      );
      setState(() { _dirty = false; });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  Future<bool> _onWillPop() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存的改动'),
        content: const Text('有未保存的修改，确定要离开吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续编辑')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),  child: const Text('放弃更改')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _onWillPop();
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF181A1B),
        appBar: AppBar(
          backgroundColor: const Color(0xFF212529),
          title: Row(
            children: [
              Text(
                widget.path,
                style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              ),
              if (_dirty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('已修改', style: TextStyle(color: Colors.orange, fontSize: 11)),
                ),
              ],
            ],
          ),
          actions: [
            if (!widget.readOnly)
              FilledButton.icon(
                onPressed: (_saving || !_dirty) ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save, size: 16),
                label: const Text('保存'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.blue.withValues(alpha: 0.3),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  )
                : TextField(
                    controller: _ctrl,
                    readOnly: widget.readOnly,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1A1D1F),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                      hintText: widget.readOnly ? '（只读）' : null,
                    ),
                  ),
      ),
    );
  }
}
