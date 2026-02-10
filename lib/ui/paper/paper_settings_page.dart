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

  @override
  void dispose() {
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    _nameController.dispose();
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

    return FluiddCard(
      title: '纸张参数',
      actions: [
        IconButton(
          icon: const Icon(Icons.restore, color: Colors.grey, size: 20),
          onPressed: () {
            ctrl.resetToDefaults();
          },
          tooltip: '恢复默认',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 纸张类型选择
          _buildSectionLabel('纸张类型'),
          const SizedBox(height: 8),
          _buildPaperTypeSelector(config.kind, (kind) {
            final defaults = _defaultForKind(kind);
            ctrl.updateEditing(config.copyWith(
              kind: kind,
              lineColorValue: defaults.lineColorValue,
              lineWidthMm: defaults.lineWidthMm,
            ));
          }),

          const SizedBox(height: 16),
          _buildSectionLabel('纸张尺寸'),
          const SizedBox(height: 8),
          _buildPaperSizePresetRow(config, ctrl),
          _buildNumericInputRow(
            label: '宽度',
            value: config.pageWidthMm,
            unit: 'mm',
            onChanged: (v) => ctrl.updateEditing(config.copyWith(pageWidthMm: v)),
          ),
          _buildNumericInputRow(
            label: '高度',
            value: config.pageHeightMm,
            unit: 'mm',
            onChanged: (v) => ctrl.updateEditing(config.copyWith(pageHeightMm: v)),
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
                  onChanged: (v) => ctrl.updateEditing(config.copyWith(marginLeftMm: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNumericInputRow(
                  label: '上',
                  value: config.marginTopMm,
                  unit: 'mm',
                  onChanged: (v) => ctrl.updateEditing(config.copyWith(marginTopMm: v)),
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
                  onChanged: (v) => ctrl.updateEditing(config.copyWith(marginRightMm: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNumericInputRow(
                  label: '下',
                  value: config.marginBottomMm,
                  unit: 'mm',
                  onChanged: (v) => ctrl.updateEditing(config.copyWith(marginBottomMm: v)),
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
            onChanged: (v) => ctrl.updateEditing(config.copyWith(cellSizeMm: v)),
          ),
          
          if (config.kind == PaperTypeKind.grid) ...[
            _buildNumericInputRow(
              label: '行间距',
              value: config.gridRowSpacingMm,
              unit: 'mm',
              onChanged: (v) => ctrl.updateEditing(config.copyWith(gridRowSpacingMm: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildNumericInputRow(
                    label: '指定列数',
                    value: config.customCols?.toDouble() ?? 0,
                    unit: '列',
                    onChanged: (v) => ctrl.updateEditing(config.copyWith(
                      customCols: v > 0 ? v.toInt() : null,
                    )),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumericInputRow(
                    label: '指定行数',
                    value: config.customRows?.toDouble() ?? 0,
                    unit: '行',
                    onChanged: (v) => ctrl.updateEditing(config.copyWith(
                      customRows: v > 0 ? v.toInt() : null,
                    )),
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
              onChanged: (v) => ctrl.updateEditing(config.copyWith(lineSpacingMm: v)),
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
                  onChanged: (v) => ctrl.updateEditing(config.copyWith(lineWidthMm: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNumericInputRow(
                  label: '字内补白',
                  value: config.cellPaddingMm,
                  unit: 'mm',
                  onChanged: (v) => ctrl.updateEditing(config.copyWith(cellPaddingMm: v)),
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
          // 应用和保存按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('应用'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    ctrl.applyEditing();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('纸张配置已应用')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('另存为'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _showSaveDialog(context, ctrl),
                ),
              ),
            ],
          ),
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
          icon: const Icon(Icons.restore, color: Colors.grey, size: 20),
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF2C3034),
                title: const Text('恢复默认', style: TextStyle(color: Colors.white)),
                content: const Text('确定要恢复所有默认纸张类型吗？自定义配置将被删除。',
                    style: TextStyle(color: Colors.white70)),
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
                    child: const Text('确定', style: TextStyle(color: Colors.red)),
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

  Widget _buildSavedPaperTile(BuildContext context, PaperConfigController ctrl, int index) {
    final paper = ctrl.savedPapers[index];
    final isActive = index == ctrl.activeIndex;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive ? Colors.blue.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: isActive
            ? Border.all(color: Colors.blue.withValues(alpha: 0.5), width: 1.5)
            : Border.all(color: Colors.white10, width: 1),
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
          '${_kindLabel(paper.kind)} · ${paper.cols}×${paper.rows} · ${paper.cellSizeMm}mm',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 一键导入按钮
            IconButton(
              icon: Icon(
                Icons.input,
                color: isActive ? Colors.blue : Colors.grey.shade500,
                size: 18,
              ),
              onPressed: () {
                ctrl.activatePaper(index);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已导入纸张: ${paper.name}')),
                );
              },
              tooltip: '一键导入到预览',
              visualDensity: VisualDensity.compact,
            ),
            // 加载到编辑器
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.grey, size: 18),
              onPressed: () {
                ctrl.updateEditing(paper);
              },
              tooltip: '加载到编辑器',
              visualDensity: VisualDensity.compact,
            ),
            // 删除按钮
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey, size: 18),
              onPressed: () {
                ctrl.deleteSaved(index);
              },
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        onTap: () {
          ctrl.updateEditing(paper);
        },
      ),
    );
  }

  /// 实时预览卡片
  Widget _buildPreviewCard(BuildContext context) {
    final ctrl = context.watch<PaperConfigController>();
    final config = ctrl.editingPaper;

    return FluiddCard(
      title: '纸张预览',
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
      child: AspectRatio(
        aspectRatio: config.pageWidthMm / config.pageHeightMm,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF333333),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.hardEdge,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final viewport = _fitViewport(size, config);

              return CustomPaint(
                size: size,
                painter: PaperTypePainter(
                  config: config,
                  viewport: viewport,
                ),
              );
            },
          ),
        ),
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

  Widget _buildSectionLabel(String text) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: Colors.blue),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildNumericInputRow({
    required String label,
    required double value,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
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
                  suffixText: unit,
                  suffixStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                controller: TextEditingController(text: value.toStringAsFixed(1))
                  ..selection = TextSelection.fromPosition(
                    TextPosition(offset: value.toStringAsFixed(1).length),
                  ),
                onSubmitted: (val) {
                  final d = double.tryParse(val);
                  if (d != null) onChanged(d);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaperSizePresetRow(PaperConfig config, PaperConfigController ctrl) {
    final presets = {
      'A4 (210x297)': const Size(210, 297),
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
            child: Text('预设尺寸', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                  hint: const Text('选择尺寸...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  dropdownColor: const Color(0xFF2C3034),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey),
                  items: presets.keys.map((String key) {
                    return DropdownMenuItem<String>(
                      value: key,
                      child: Text(key),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final size = presets[val]!;
                      ctrl.updateEditing(config.copyWith(
                        pageWidthMm: size.width,
                        pageHeightMm: size.height,
                      ));
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

  Widget _buildPaperTypeSelector(PaperTypeKind currentKind, ValueChanged<PaperTypeKind> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 70,
            child: Text('纸张类型', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                          color: isSelected ? Colors.blue.withValues(alpha: 0.2) : Colors.black12,
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
            child: Text('线条颜色', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          ...presetColors.map((c) {
            final isSelected = config.lineColorValue == c.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: c.$2,
                child: InkWell(
                  onTap: () => ctrl.updateEditing(config.copyWith(lineColorValue: c.$1)),
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

  void _showSaveDialog(BuildContext context, PaperConfigController ctrl) {
    _nameController.text = ctrl.editingPaper.name;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C3034),
        title: const Text('保存纸张配置', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: '配置名称',
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
            onPressed: () {
              final name = _nameController.text.trim();
              if (name.isNotEmpty) {
                ctrl.saveCurrentAsNew(name);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已保存纸张配置: $name')),
                );
              }
            },
            child: const Text('保存', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
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
