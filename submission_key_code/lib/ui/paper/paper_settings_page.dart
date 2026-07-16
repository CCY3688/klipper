import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/paper_config_controller.dart';
import '../../writing/model/paper_type.dart';
import '../../writing/render/paper_type_painter.dart';
import '../../writing/render/viewport.dart' as kp;
import '../fluidd/widgets/fluidd_card.dart';

/// 纸张设置页面
/// - 左侧：参数调节面板 + 保存栏
/// - 右侧：实时纸张预览
class PaperSettingsPage extends StatefulWidget {
  const PaperSettingsPage({super.key});

  @override
  State<PaperSettingsPage> createState() => _PaperSettingsPageState();
}

class _PaperSettingsPageState extends State<PaperSettingsPage> {
  final _leftScrollController = ScrollController();
  final _rightScrollController = ScrollController();
  final _nameController = TextEditingController();
  final _editorNameController = TextEditingController();
  final _previewTextController = TextEditingController(text: '你好世界');
  PaperConfig? _syncedNameConfig;

  @override
  void dispose() {
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    _nameController.dispose();
    _editorNameController.dispose();
    _previewTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：参数面板 + 保存栏
          Expanded(
            flex: 4,
            child: Scrollbar(
              controller: _leftScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _leftScrollController,
                child: Column(
                  children: [
                    _buildParamsCard(context),
                    const SizedBox(height: 8),
                    _buildSavedPapersCard(context),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 右侧：实时预览
          Expanded(
            flex: 6,
            child: Scrollbar(
              controller: _rightScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _rightScrollController,
                padding: const EdgeInsets.only(right: 12),
                child: _buildPreviewCard(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 参数调节面板
  Widget _buildParamsCard(BuildContext context) {
    final ctrl = context.watch<PaperConfigController>();
    final config = ctrl.editingPaper;
    final isEditingSaved = ctrl.isEditingSavedPaper;
    final hasChanges = ctrl.hasEditingChanges;
    final statusText = isEditingSaved
        ? hasChanges
              ? '正在修改：${ctrl.editingSourceName}'
              : '正在编辑：${ctrl.editingSourceName}'
        : '未保存的新配置';

    return FluiddCard(
      title: '纸张参数',
      subtitle: statusText,
      actions: [
        IconButton(
          icon: const Icon(
            Icons.note_add_outlined,
            color: Colors.grey,
            size: 20,
          ),
          onPressed: () => ctrl.createDraft(name: '新纸张配置'),
          tooltip: '新建配置',
        ),
        IconButton(
          icon: const Icon(Icons.restore, color: Colors.grey, size: 20),
          onPressed: () {
            ctrl.discardEditingChanges();
          },
          tooltip: '放弃当前修改',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNameEditor(config, ctrl),
          const SizedBox(height: 16),

          // 纸张类型选择
          _buildSectionLabel('纸张类型'),
          const SizedBox(height: 8),
          _buildPaperTypeSelector(config.kind, (kind) {
            final defaults = _defaultForKind(kind);
            ctrl.updateEditing(
              config.copyWith(
                kind: kind,
                lineColorValue: defaults.lineColorValue,
                lineWidthMm: defaults.lineWidthMm,
              ),
            );
          }),

          const SizedBox(height: 16),
          _buildSectionLabel('纸张尺寸'),
          const SizedBox(height: 8),
          _buildPaperSizePresetRow(config, ctrl),
          _buildNumericInputRow(
            label: '宽度',
            value: config.pageWidthMm,
            unit: 'mm',
            minValue: 1,
            onChanged: (v) =>
                ctrl.updateEditing(config.copyWith(pageWidthMm: v)),
          ),
          _buildNumericInputRow(
            label: '高度',
            value: config.pageHeightMm,
            unit: 'mm',
            minValue: 1,
            onChanged: (v) =>
                ctrl.updateEditing(config.copyWith(pageHeightMm: v)),
          ),

          const SizedBox(height: 16),
          _buildSectionLabel('边距'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildNumericInputRow(
                  label: '左',
                  value: config.marginLeftMm,
                  unit: 'mm',
                  onChanged: (v) =>
                      ctrl.updateEditing(config.copyWith(marginLeftMm: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNumericInputRow(
                  label: '上',
                  value: config.marginTopMm,
                  unit: 'mm',
                  onChanged: (v) =>
                      ctrl.updateEditing(config.copyWith(marginTopMm: v)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _buildNumericInputRow(
                  label: '右',
                  value: config.marginRightMm,
                  unit: 'mm',
                  onChanged: (v) =>
                      ctrl.updateEditing(config.copyWith(marginRightMm: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNumericInputRow(
                  label: '下',
                  value: config.marginBottomMm,
                  unit: 'mm',
                  onChanged: (v) =>
                      ctrl.updateEditing(config.copyWith(marginBottomMm: v)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          _buildSectionLabel(_cellSizeLabel(config.kind)),
          const SizedBox(height: 8),
          _buildNumericInputRow(
            label: _cellSizeLabel(config.kind),
            value: config.cellSizeMm,
            unit: 'mm',
            minValue: 0.1,
            onChanged: (v) =>
                ctrl.updateEditing(config.copyWith(cellSizeMm: v)),
          ),

          if (config.kind == PaperTypeKind.grid) ...[
            _buildNumericInputRow(
              label: '行间距',
              value: config.gridRowSpacingMm,
              unit: 'mm',
              minValue: 0,
              onChanged: (v) =>
                  ctrl.updateEditing(config.copyWith(gridRowSpacingMm: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildNumericInputRow(
                    label: '指定列数',
                    value: config.customCols?.toDouble() ?? 0,
                    unit: '列',
                    onChanged: (v) => ctrl.updateEditing(
                      config.copyWith(customCols: v > 0 ? v.toInt() : null),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumericInputRow(
                    label: '指定行数',
                    value: config.customRows?.toDouble() ?? 0,
                    unit: '行',
                    onChanged: (v) => ctrl.updateEditing(
                      config.copyWith(customRows: v > 0 ? v.toInt() : null),
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (config.kind == PaperTypeKind.horizontal ||
              config.kind == PaperTypeKind.letter)
            _buildNumericInputRow(
              label: '行高/间距',
              value: config.lineSpacingMm,
              unit: 'mm',
              minValue: 0.1,
              onChanged: (v) =>
                  ctrl.updateEditing(config.copyWith(lineSpacingMm: v)),
            ),

          const SizedBox(height: 16),
          _buildSectionLabel('样式与对齐'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildNumericInputRow(
                  label: '线宽',
                  value: config.lineWidthMm,
                  unit: 'mm',
                  minValue: 0,
                  onChanged: (v) =>
                      ctrl.updateEditing(config.copyWith(lineWidthMm: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNumericInputRow(
                  label: '字内补白',
                  value: config.cellPaddingMm,
                  unit: 'mm',
                  minValue: 0,
                  onChanged: (v) =>
                      ctrl.updateEditing(config.copyWith(cellPaddingMm: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildColorPicker(config, ctrl),

          const SizedBox(height: 16),
          // 信息汇总行
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前布局: ${config.cols} 列 × ${config.rows} 行',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '格子尺寸: ${config.effectiveCellWidth.toStringAsFixed(1)} × ${config.effectiveCellHeight.toStringAsFixed(1)} mm',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '可用面积: ${(config.pageWidthMm - config.marginLeftMm - config.marginRightMm).toStringAsFixed(1)} × ${(config.pageHeightMm - config.marginTopMm - config.marginBottomMm).toStringAsFixed(1)} mm',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          _buildEditorActions(context, ctrl),
        ],
      ),
    );
  }

  /// 已保存的纸张类型列表
  Widget _buildSavedPapersCard(BuildContext context) {
    final ctrl = context.watch<PaperConfigController>();

    return FluiddCard(
      title: '纸张配置库',
      actions: [
        IconButton(
          icon: const Icon(Icons.add, color: Colors.grey, size: 20),
          onPressed: () => ctrl.createDraft(name: '新纸张配置'),
          tooltip: '新建配置',
        ),
        IconButton(
          icon: const Icon(Icons.restore, color: Colors.grey, size: 20),
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF2C3034),
                title: const Text(
                  '恢复默认',
                  style: TextStyle(color: Colors.white),
                ),
                content: const Text(
                  '确定要恢复所有默认纸张类型吗？自定义配置将被删除。',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () {
                      ctrl.resetToDefaults();
                      Navigator.pop(ctx);
                    },
                    child: const Text(
                      '确定',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
          },
          tooltip: '恢复默认纸张类型',
        ),
      ],
      child: Column(
        children: [
          for (int i = 0; i < ctrl.savedPapers.length; i++)
            _buildSavedPaperTile(context, ctrl, i),
        ],
      ),
    );
  }

  Widget _buildSavedPaperTile(
    BuildContext context,
    PaperConfigController ctrl,
    int index,
  ) {
    final paper = ctrl.savedPapers[index];
    final isActive = index == ctrl.activeIndex;
    final isEditing = index == ctrl.editingIndex;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.blue.withValues(alpha: 0.15)
            : isEditing
            ? Colors.amber.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? Colors.blue.withValues(alpha: 0.55)
              : isEditing
              ? Colors.amber.withValues(alpha: 0.45)
              : Colors.white10,
          width: isActive || isEditing ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          _kindIcon(paper.kind),
          color: isActive ? Colors.blue : Colors.grey,
          size: 24,
        ),
        title: Text(
          paper.name,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white70,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          '${_kindLabel(paper.kind)} · ${paper.cols}×${paper.rows} · ${paper.cellSizeMm}mm'
          '${isActive ? ' · 当前使用' : ''}'
          '${isEditing ? ' · 编辑中' : ''}',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.playlist_add_check,
                color: isActive ? Colors.blue : Colors.grey.shade500,
                size: 18,
              ),
              onPressed: () {
                ctrl.activatePaper(index);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已设为当前纸张: ${paper.name}')),
                );
              },
              tooltip: '设为当前纸张',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(
                Icons.edit_outlined,
                color: Colors.grey,
                size: 18,
              ),
              onPressed: () {
                ctrl.loadToEditor(index);
              },
              tooltip: '编辑此配置',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey, size: 18),
              onPressed: () => _confirmDelete(context, ctrl, index),
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        onTap: () {
          ctrl.loadToEditor(index);
        },
      ),
    );
  }

  /// 实时预览卡片 — 支持输入样本文本查看布局效果
  Widget _buildPreviewCard(BuildContext context) {
    final ctrl = context.watch<PaperConfigController>();
    final config = ctrl.editingPaper;

    return FluiddCard(
      title: '纸张预览',
      scrollable: false,
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${_kindLabel(config.kind)} · ${config.cols}×${config.rows}',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 样本文本输入
          TextField(
            controller: _previewTextController,
            maxLines: 2,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              hintText: '输入样本文本查看纸张效果...',
              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              isDense: true,
              filled: true,
              fillColor: Colors.black26,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.grey.shade800),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.grey.shade800),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Colors.blue, width: 1),
              ),
              suffixIcon: _previewTextController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 16,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        _previewTextController.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          // 纸张预览画布
          AspectRatio(
            aspectRatio: config.pageWidthMm / config.pageHeightMm,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.hardEdge,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final viewport = _fitViewport(size, config);

                  return CustomPaint(
                    size: size,
                    painter: PaperTypePainter(
                      config: config,
                      viewport: viewport,
                    ),
                    foregroundPainter: _previewTextController.text.isNotEmpty
                        ? _SampleTextPainter(
                            text: _previewTextController.text,
                            config: config,
                            viewport: viewport,
                          )
                        : null,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  kp.Viewport _fitViewport(Size size, PaperConfig config) {
    const padding = 10.0;
    final availW = (size.width - padding * 2).clamp(1.0, double.infinity);
    final availH = (size.height - padding * 2).clamp(1.0, double.infinity);

    double scale = availW / config.pageWidthMm;
    if (config.pageHeightMm * scale > availH) {
      scale = availH / config.pageHeightMm;
    }
    scale = scale.clamp(0.2, 30.0);

    final contentW = config.pageWidthMm * scale;
    final contentH = config.pageHeightMm * scale;
    final pan = Offset(
      (size.width - contentW) / 2,
      (size.height - contentH) / 2,
    );

    return kp.Viewport(scale: scale, pan: pan);
  }

  // ===== 辅助 widgets =====

  Widget _buildNameEditor(PaperConfig config, PaperConfigController ctrl) {
    if (_syncedNameConfig != config) {
      _editorNameController.text = config.name;
      _editorNameController.selection = TextSelection.collapsed(
        offset: _editorNameController.text.length,
      );
      _syncedNameConfig = config;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('配置名称'),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: TextField(
            controller: _editorNameController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: '输入配置名称',
              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.grey.shade800),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.grey.shade800),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Colors.blue, width: 1),
              ),
            ),
            onChanged: (value) {
              final updated = config.copyWith(name: value);
              _syncedNameConfig = updated;
              ctrl.updateEditing(updated);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditorActions(BuildContext context, PaperConfigController ctrl) {
    final canSaveToSource = ctrl.isEditingSavedPaper;
    final canDiscard = ctrl.hasEditingChanges;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('设为当前纸张'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  ctrl.applyEditing();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已设为当前纸张，配置库未被修改')),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存修改'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: canSaveToSource
                      ? Colors.blue
                      : Colors.grey.shade600,
                  side: BorderSide(
                    color: canSaveToSource ? Colors.blue : Colors.white24,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: canSaveToSource
                    ? () => _saveToSource(context, ctrl)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('另存为新配置'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _showSaveAsDialog(context, ctrl),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('放弃修改'),
                style: TextButton.styleFrom(
                  foregroundColor: canDiscard
                      ? Colors.grey.shade300
                      : Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: canDiscard ? ctrl.discardEditingChanges : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: Colors.blue),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildNumericInputRow({
    required String label,
    required double value,
    required String unit,
    required ValueChanged<double> onChanged,
    double? minValue,
  }) {
    return _NumericInputRow(
      label: label,
      value: value,
      unit: unit,
      onChanged: onChanged,
      minValue: minValue,
    );
  }

  Widget _buildPaperSizePresetRow(
    PaperConfig config,
    PaperConfigController ctrl,
  ) {
    final presets = {
      'A4 (297x210)': const Size(297, 210),
      'A3 (297x420)': const Size(297, 420),
      'A5 (148x210)': const Size(148, 210),
      'B5 (176x250)': const Size(176, 250),
      'Legal (216x356)': const Size(216, 356),
      'Letter (216x279)': const Size(216, 279),
    };

    String? currentKey;
    presets.forEach((key, size) {
      if ((size.width - config.pageWidthMm).abs() < 1 &&
          (size.height - config.pageHeightMm).abs() < 1) {
        currentKey = key;
      }
    });

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 70,
            child: Text(
              '预设尺寸',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade800),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: currentKey,
                  hint: const Text(
                    '选择尺寸...',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  dropdownColor: const Color(0xFF2C3034),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  isExpanded: true,
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: Colors.grey,
                  ),
                  items: presets.keys.map((String key) {
                    return DropdownMenuItem<String>(
                      value: key,
                      child: Text(key),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final size = presets[val]!;
                      ctrl.updateEditing(
                        config.copyWith(
                          pageWidthMm: size.width,
                          pageHeightMm: size.height,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaperTypeSelector(
    PaperTypeKind currentKind,
    ValueChanged<PaperTypeKind> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 70,
            child: Text(
              '纸张类型',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: PaperTypeKind.values.map((kind) {
                final isSelected = kind == currentKind;
                return InkWell(
                  onTap: () => onChanged(kind),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue.withValues(alpha: 0.2)
                              : Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? Colors.blue : Colors.white10,
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          _kindIcon(kind),
                          color: isSelected ? Colors.blue : Colors.grey,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _kindLabel(kind),
                        style: TextStyle(
                          color: isSelected ? Colors.blue : Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker(PaperConfig config, PaperConfigController ctrl) {
    final presetColors = [
      (0xFFF48FB1, '粉红'),
      (0xFF90CAF9, '淡蓝'),
      (0xFFA5D6A7, '淡绿'),
      (0xFFFFCC80, '橙黄'),
      (0xFFCE93D8, '淡紫'),
      (0xFF80CBC4, '青绿'),
      (0xFFBCAAA4, '灰棕'),
      (0xFF000000, '黑色'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(
            width: 70,
            child: Text(
              '线条颜色',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          ...presetColors.map((c) {
            final isSelected = config.lineColorValue == c.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: c.$2,
                child: InkWell(
                  onTap: () =>
                      ctrl.updateEditing(config.copyWith(lineColorValue: c.$1)),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Color(c.$1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.white24,
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _saveToSource(BuildContext context, PaperConfigController ctrl) {
    final name = ctrl.editingPaper.name.trim();
    if (name.isEmpty) {
      _showMessage(context, '配置名称不能为空');
      return;
    }

    final duplicate = ctrl.indexOfName(name, exceptIndex: ctrl.editingIndex);
    if (duplicate != -1) {
      _showMessage(context, '已存在同名配置，请先改名');
      return;
    }

    if (ctrl.saveEditingToSource(name: name)) {
      _showMessage(context, '已保存修改: $name');
    }
  }

  void _showSaveAsDialog(BuildContext context, PaperConfigController ctrl) {
    _nameController.text = ctrl.editingPaper.name.trim().isEmpty
        ? '未命名纸张'
        : ctrl.editingPaper.name.trim();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C3034),
        title: const Text('另存为新配置', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: '新配置名称',
            labelStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              if (name.isEmpty) {
                _showMessage(context, '配置名称不能为空');
                return;
              }

              final duplicate = ctrl.indexOfName(name);
              if (duplicate != -1) {
                Navigator.pop(ctx);
                final overwrite = await _confirmOverwrite(
                  context,
                  ctrl.savedPapers[duplicate].name,
                );
                if (!context.mounted) return;
                if (overwrite != true) return;

                final updated = ctrl.editingPaper.copyWith(name: name);
                ctrl.updateSaved(duplicate, updated);
                _showMessage(context, '已覆盖配置: $name');
              } else {
                ctrl.saveCurrentAsNew(name);
                Navigator.pop(ctx);
                _showMessage(context, '已另存为: $name');
              }
            },
            child: const Text('另存为', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmOverwrite(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C3034),
        title: const Text('覆盖已有配置？', style: TextStyle(color: Colors.white)),
        content: Text(
          '“$name” 已存在。是否用当前编辑内容覆盖它？',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('覆盖', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    PaperConfigController ctrl,
    int index,
  ) {
    final paper = ctrl.savedPapers[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C3034),
        title: const Text('删除纸张配置', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定删除“${paper.name}”吗？',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ctrl.deleteSaved(index);
              Navigator.pop(ctx);
              _showMessage(context, '已删除: ${paper.name}');
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _kindLabel(PaperTypeKind kind) {
    switch (kind) {
      case PaperTypeKind.grid:
        return '格子纸';
      case PaperTypeKind.horizontal:
        return '横线格';
      case PaperTypeKind.letter:
        return '信纸笺';
      case PaperTypeKind.blank:
        return '空白纸';
    }
  }

  IconData _kindIcon(PaperTypeKind kind) {
    switch (kind) {
      case PaperTypeKind.grid:
        return Icons.grid_on;
      case PaperTypeKind.horizontal:
        return Icons.horizontal_rule;
      case PaperTypeKind.letter:
        return Icons.view_column_outlined;
      case PaperTypeKind.blank:
        return Icons.crop_portrait;
    }
  }

  PaperConfig _defaultForKind(PaperTypeKind kind) {
    switch (kind) {
      case PaperTypeKind.grid:
        return defaultGridPaper();
      case PaperTypeKind.horizontal:
        return defaultHorizontalPaper();
      case PaperTypeKind.letter:
        return defaultLetterPaper();
      case PaperTypeKind.blank:
        return defaultBlankPaper();
    }
  }

  String _cellSizeLabel(PaperTypeKind kind) {
    switch (kind) {
      case PaperTypeKind.grid:
        return '格子参数';
      case PaperTypeKind.horizontal:
        return '字格宽度';
      case PaperTypeKind.letter:
        return '列宽';
      case PaperTypeKind.blank:
        return '字格大小';
    }
  }
}

class _NumericInputRow extends StatefulWidget {
  final String label;
  final double value;
  final String unit;
  final ValueChanged<double> onChanged;
  final double? minValue;

  const _NumericInputRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.onChanged,
    this.minValue,
  });

  @override
  State<_NumericInputRow> createState() => _NumericInputRowState();
}

class _NumericInputRowState extends State<_NumericInputRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late double _lastEmittedValue;

  @override
  void initState() {
    super.initState();
    _lastEmittedValue = widget.value;
    _controller = TextEditingController(text: _formatValue(widget.value));
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _NumericInputRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;

    _lastEmittedValue = widget.value;
    if (!_focusNode.hasFocus) {
      _setControllerText(_formatValue(widget.value));
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              widget.label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: Colors.grey.shade800),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: Colors.grey.shade800),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Colors.blue, width: 1),
                  ),
                  suffixText: widget.unit,
                  suffixStyle: const TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
                onChanged: _emitValidValue,
                onSubmitted: (_) => _commitText(),
                onTapOutside: (_) => _focusNode.unfocus(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commitText();
    }
  }

  void _commitText() {
    final text = _controller.text.trim();
    final value = double.tryParse(text);
    if (!_isValidValue(value)) {
      _setControllerText(_formatValue(widget.value));
      return;
    }

    _emitValue(value!);
    _setControllerText(_formatValue(value));
  }

  void _emitValidValue(String text) {
    final value = double.tryParse(text.trim());
    if (_isValidValue(value)) {
      _emitValue(value!);
    }
  }

  bool _isValidValue(double? value) {
    if (value == null || !value.isFinite) {
      return false;
    }
    final minValue = widget.minValue;
    if (minValue != null && value < minValue) {
      return false;
    }
    return true;
  }

  void _emitValue(double value) {
    if (value == _lastEmittedValue) return;
    if (!_isValidValue(value)) return;
    _lastEmittedValue = value;
    widget.onChanged(value);
  }

  void _setControllerText(String text) {
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String _formatValue(double value) => value.toStringAsFixed(1);
}

/// 样本文本 Painter — 在纸张预览上绘制真实文字来模拟书写效果
class _SampleTextPainter extends CustomPainter {
  final String text;
  final PaperConfig config;
  final kp.Viewport viewport;

  _SampleTextPainter({
    required this.text,
    required this.config,
    required this.viewport,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty) return;

    final chars = text.replaceAll('\n', '').split('');
    final cols = config.cols;
    if (cols <= 0) return;

    final cellW = config.effectiveCellWidth;
    final cellH = config.effectiveCellHeight;
    final pad = config.cellPaddingMm;
    final rowSpacing = config.kind == PaperTypeKind.grid
        ? config.gridRowSpacingMm
        : 0;

    // 背景色块 — 用醒目颜色直观看到格子填充
    final bgPaint = Paint()
      ..color = const Color(0xFF4FC3F7).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFF4FC3F7).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int i = 0; i < chars.length; i++) {
      final row = i ~/ cols;
      final col = i % cols;

      final xMm = config.marginLeftMm + col * cellW + pad;
      final yMm = config.marginTopMm + row * (cellH + rowSpacing) + pad;

      final innerW = cellW - pad * 2;
      final innerH = cellH - pad * 2;
      if (xMm + innerW > config.pageWidthMm - config.marginRightMm) continue;
      if (yMm + innerH > config.pageHeightMm - config.marginBottomMm) continue;

      final x = xMm * viewport.scale + viewport.pan.dx;
      final y = yMm * viewport.scale + viewport.pan.dy;
      final w = innerW * viewport.scale;
      final h = innerH * viewport.scale;

      // 在格子里绘制填充色块
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(w * 0.1),
      );
      canvas.drawRRect(rect, bgPaint);
      canvas.drawRRect(rect, borderPaint);

      // 绘制文字
      if (w > 4 && h > 4) {
        final fontSize = (h * 0.7).clamp(4.0, 48.0);
        final textSpan = TextSpan(
          text: chars[i],
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
        );
        final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
          ..layout(maxWidth: w);
        // 居中绘制
        tp.paint(
          canvas,
          Offset(x + (w - tp.width) / 2, y + (h - tp.height) / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SampleTextPainter oldDelegate) =>
      text != oldDelegate.text ||
      config != oldDelegate.config ||
      viewport != oldDelegate.viewport;
}
