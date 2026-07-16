/// 用户字体管理页面
///
/// 提供 TTF 导入、档案管理（激活/重命名/删除）
/// 以及字形预览功能。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/user_font_controller.dart';
import '../../writing/model/glyph.dart';
import '../../writing/user_font/user_font_profile.dart';
import '../../writing/user_font/user_stroke_font.dart';
import 'glyph_debug_page.dart';
import 'widgets/glyph_widgets.dart';

class UserFontPage extends StatefulWidget {
  const UserFontPage({super.key});

  @override
  State<UserFontPage> createState() => _UserFontPageState();
}

class _UserFontPageState extends State<UserFontPage> {
  // ─────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<UserFontController>(
      builder: (context, ctrl, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('用户字体风格'),
            actions: [
              if (ctrl.importStatus != ImportStatus.importing)
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '导入 TTF 字体',
                  onPressed: () => _startImport(ctrl),
                ),
            ],
          ),
          body: _buildBody(ctrl),
        );
      },
    );
  }

  Widget _buildBody(UserFontController ctrl) {
    return Column(
      children: [
        // 导入进度条
        if (ctrl.importStatus == ImportStatus.importing)
          _ImportProgressCard(ctrl: ctrl),

        // 导入失败提示
        if (ctrl.importStatus == ImportStatus.failed)
          _ErrorBanner(
            message: ctrl.importError ?? '导入失败',
            onDismiss: ctrl.resetImportStatus,
          ),

        // 当前激活字体指示
        _ActiveFontBanner(ctrl: ctrl),

        // 字体档案列表
        Expanded(
          child: ctrl.profiles.isEmpty
              ? _EmptyState(onImport: () => _startImport(ctrl))
              : _ProfileList(
                  ctrl: ctrl,
                  onRename: _renameProfile,
                  onPreview: (p) => _showPreviewSheet(p),
                  onDebug: (p) => _openDebugPage(p),
                ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 操作
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _startImport(UserFontController ctrl) async {
    // 1. 选择 TTF 文件
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 TTF/OTF 字体文件',
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf', 'TTF', 'OTF'],
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.first.path;
    if (filePath == null) return;

    // 2. 询问档案名称
    final name = await _askProfileName(
      defaultName: result.files.first.name.replaceAll(
        RegExp(r'\.(ttf|otf)$', caseSensitive: false),
        '',
      ),
    );
    if (name == null) return;

    // 3. 开始导入
    if (!mounted) return;
    await ctrl.importFromTtf(ttfFile: File(filePath), profileName: name);
  }

  Future<String?> _askProfileName({required String defaultName}) {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('字体档案名称'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '例如：我的手写体',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(ctx, name);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameProfile(UserFontController ctrl, String profileId) async {
    final profile = ctrl.profiles.where((p) => p.id == profileId).firstOrNull;
    if (profile == null) return;

    final controller = TextEditingController(text: profile.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名字体档案'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = controller.text.trim();
              if (n.isNotEmpty) Navigator.pop(ctx, n);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await ctrl.renameProfile(profileId, newName);
    }
  }

  Future<void> _openDebugPage(UserFontProfile profile) async {
    // 需要用户选择 TTF 文件（profile 只存了文件名，不存路径）
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择原始 TTF 文件（${profile.sourceFontFileName ?? "字体文件"}）',
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf', 'TTF', 'OTF'],
    );
    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.first.path;
    if (filePath == null || !mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GlyphDebugPage(
          ttfFile: File(filePath),
          initialChar: profile.learnedGlyphs.keys.firstOrNull ?? '大',
        ),
      ),
    );
  }

  void _showPreviewSheet(UserFontProfile profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GlyphPreviewSheet(profile: profile),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 子组件
// ─────────────────────────────────────────────────────────────────────────

/// 导入进度卡片
class _ImportProgressCard extends StatelessWidget {
  final UserFontController ctrl;
  const _ImportProgressCard({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final progress = ctrl.importProgress;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  progress != null && progress.currentChar.isNotEmpty
                      ? '正在处理：${progress.currentChar}'
                      : '正在解析字体...',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                if (progress != null)
                  Text(
                    '${progress.current} / ${progress.total}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress?.ratio,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: ctrl.cancelImport,
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 错误横幅
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      content: Text(
        '导入失败：$message',
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
      actions: [TextButton(onPressed: onDismiss, child: const Text('关闭'))],
    );
  }
}

/// 激活字体横幅
class _ActiveFontBanner extends StatelessWidget {
  final UserFontController ctrl;
  const _ActiveFontBanner({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final active = ctrl.activeProfile;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: active != null
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            active != null ? Icons.font_download : Icons.font_download_off,
            size: 20,
            color: active != null
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              active != null
                  ? '当前使用：${active.name}  （已学 ${active.learnedCount} 字）'
                  : '当前使用：标准字体',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: active != null
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (active != null)
            TextButton(
              onPressed: () => ctrl.setActiveProfile(null),
              child: const Text('切换回标准'),
            ),
        ],
      ),
    );
  }
}

/// 空状态提示
class _EmptyState extends StatelessWidget {
  final VoidCallback onImport;
  const _EmptyState({required this.onImport});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.font_download_outlined,
            size: 64,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text('还没有导入字体档案', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '导入你制作的 TTF/OTF 字体文件\n系统将自动提取字形用于手写打印',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('导入 TTF 字体'),
            onPressed: onImport,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _showHelpDialog(context),
            child: const Text('如何制作个人 TTF 字体？'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('如何制作个人字体'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('推荐工具：', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('• 字体管家（iFont）- 免费，手机端可描字'),
              Text('• 造字工房 - 网页端，上传手写图片自动生成'),
              Text('• FontForge - 专业开源字体编辑器'),
              SizedBox(height: 12),
              Text('步骤：', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('1. 打印描字模板（A4，每格一个汉字）'),
              Text('2. 手写填写后拍照/扫描上传'),
              Text('3. 工具自动生成 TTF 文件'),
              Text('4. 在本页面导入该 TTF 文件'),
              SizedBox(height: 12),
              Text(
                '建议至少覆盖 100 个常用汉字以获得较好效果。',
                style: TextStyle(color: Colors.orange),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('了解了'),
          ),
        ],
      ),
    );
  }
}

/// 档案列表
class _ProfileList extends StatelessWidget {
  final UserFontController ctrl;
  final Future<void> Function(UserFontController, String) onRename;
  final void Function(UserFontProfile) onPreview;
  final void Function(UserFontProfile) onDebug;

  const _ProfileList({
    required this.ctrl,
    required this.onRename,
    required this.onPreview,
    required this.onDebug,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: ctrl.profiles.length,
      itemBuilder: (ctx, i) {
        final profile = ctrl.profiles[i];
        final isActive = ctrl.activeProfileId == profile.id;
        return _ProfileCard(
          profile: profile,
          isActive: isActive,
          onActivate: () => ctrl.setActiveProfile(isActive ? null : profile.id),
          onRename: () => onRename(ctrl, profile.id),
          onDelete: () => _confirmDelete(ctx, ctrl, profile),
          onPreview: () => onPreview(profile),
          onDebug: () => onDebug(profile),
        );
      },
    );
  }

  void _confirmDelete(
    BuildContext context,
    UserFontController ctrl,
    UserFontProfile profile,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除字体档案'),
        content: Text('确定删除「${profile.name}」？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ctrl.deleteProfile(profile.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 单个档案卡片
class _ProfileCard extends StatelessWidget {
  final UserFontProfile profile;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onPreview;
  final VoidCallback onDebug;

  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.onActivate,
    required this.onRename,
    required this.onDelete,
    required this.onPreview,
    required this.onDebug,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isActive ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onActivate,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 激活指示图标
              Icon(
                isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
              const SizedBox(width: 12),
              // 档案信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '已学 ${profile.learnedCount} 个字形  •  '
                      '来源：${profile.sourceFontFileName ?? "TTF 文件"}  •  '
                      '${_formatDate(profile.updatedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isActive
                            ? theme.colorScheme.onPrimaryContainer.withValues(
                                alpha: 0.8,
                              )
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (profile.processingProgress < 1.0) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: profile.processingProgress,
                      ),
                      Text(
                        '处理中 ${(profile.processingProgress * 100).toInt()}%',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              // 预览按钮
              IconButton(
                icon: const Icon(Icons.visibility_outlined),
                tooltip: '预览字形',
                onPressed: onPreview,
              ),
              // 操作菜单
              PopupMenuButton<_Action>(
                onSelected: (action) {
                  switch (action) {
                    case _Action.rename:
                      onRename();
                    case _Action.delete:
                      onDelete();
                    case _Action.debug:
                      onDebug();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _Action.rename,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('重命名'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _Action.debug,
                    child: ListTile(
                      leading: Icon(Icons.bug_report_outlined),
                      title: Text('笔画调试'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _Action.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('删除'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

enum _Action { rename, delete, debug }

// ─────────────────────────────────────────────────────────────────────────
// 字形预览底部面板
// ─────────────────────────────────────────────────────────────────────────

class _GlyphPreviewSheet extends StatefulWidget {
  final UserFontProfile profile;
  const _GlyphPreviewSheet({required this.profile});

  @override
  State<_GlyphPreviewSheet> createState() => _GlyphPreviewSheetState();
}

class _GlyphPreviewSheetState extends State<_GlyphPreviewSheet> {
  final _textCtrl = TextEditingController(text: '你好世界一二三');

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repairedFont = UserStrokeFont(profile: widget.profile);
    final glyphs = <String, Glyph>{
      for (final entry in widget.profile.learnedGlyphs.entries)
        entry.key: repairedFont.richGlyphOf(entry.key) ?? entry.value,
    };
    final allChars = glyphs.keys.toList()..sort();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 拖拽把手 ──
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // ── 标题行 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.profile.name}  字形预览',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  label: Text('已学 ${glyphs.length} 字'),
                  labelStyle: theme.textTheme.labelSmall,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          const Divider(height: 20),
          // ── 文字输入框 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _textCtrl,
              decoration: InputDecoration(
                labelText: '输入文字实时预览',
                hintText: '例如：你好世界',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _textCtrl.clear();
                    setState(() {});
                  },
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          // ── 文字渲染行 ──
          SizedBox(
            height: 80,
            child: _textCtrl.text.isEmpty
                ? Center(
                    child: Text(
                      '在上方输入文字查看字形效果',
                      style: TextStyle(color: theme.colorScheme.outlineVariant),
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: _textCtrl.text.characters
                        .map(
                          (ch) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GlyphTile(
                              character: ch,
                              glyph: glyphs[ch],
                              size: 64,
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          Divider(
            height: 24,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          // ── 全部字形网格标题 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '全部已学字形',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ── 字形网格 ──
          Expanded(
            child: allChars.isEmpty
                ? Center(
                    child: Text(
                      '尚无字形数据',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  )
                : GridView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 72,
                          mainAxisExtent: 84,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                    itemCount: allChars.length,
                    itemBuilder: (ctx, i) {
                      final ch = allChars[i];
                      return GlyphTile(character: ch, glyph: glyphs[ch]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
