import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/printer_controller.dart';
import '../../state/settings_controller.dart';
import '../fluidd/widgets/fluidd_card.dart';

/// 配置页面 —— 参考 fluidd Settings.vue + ToolheadSettings.vue
/// 分四组：连接信息、运动控制、书写配置、应用行为
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: const Column(
            children: [
              _ConnectionInfoCard(),
              _MotionCard(),
              _WritingCard(),
              _AppCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. 连接信息（只读 + 断开按钮）
// ─────────────────────────────────────────────────────────────────────────────
class _ConnectionInfoCard extends StatelessWidget {
  const _ConnectionInfoCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PrinterController>();

    final stateColor = c.klippyReady ? Colors.greenAccent : Colors.orangeAccent;

    return FluiddCard(
      title: '连接信息',
      child: Column(
        children: [
          _InfoRow(label: '状态', value: c.phase.name.toUpperCase(), valueColor: stateColor),
          const Divider(color: Colors.white12, height: 20),
          _InfoRow(label: 'Klippy', value: c.klippyState),
          const Divider(color: Colors.white12, height: 20),
          _InfoRow(label: 'Moonraker 版本', value: c.moonrakerVersion.isEmpty ? '—' : c.moonrakerVersion),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                c.disconnect();
                Navigator.of(context).pop(); // 返回 ConnectionPage
              },
              icon: const Icon(Icons.power_settings_new, size: 16, color: Colors.redAccent),
              label: const Text('断开连接 / 修改地址', style: TextStyle(color: Colors.redAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. 运动控制（参考 fluidd ToolheadSettings）
// ─────────────────────────────────────────────────────────────────────────────
class _MotionCard extends StatelessWidget {
  const _MotionCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();

    return FluiddCard(
      title: '运动控制',
      child: Column(
        children: [
          // XY 速度
          _NumericRow(
            label: 'XY 移动速度',
            unit: 'mm/min',
            value: s.xySpeed,
            onChanged: s.setXySpeed,
          ),
          const Divider(color: Colors.white12, height: 20),
          // Z 速度
          _NumericRow(
            label: 'Z 移动速度',
            unit: 'mm/min',
            value: s.zSpeed,
            onChanged: s.setZSpeed,
          ),
          const Divider(color: Colors.white12, height: 20),
          // 反转轴
          _SwitchRow(
            label: '反转 X 轴',
            subtitle: '控制面板 X+ 方向取反',
            value: s.invertX,
            onChanged: s.setInvertX,
          ),
          const Divider(color: Colors.white12, height: 20),
          _SwitchRow(
            label: '反转 Y 轴',
            subtitle: '控制面板 Y+ 方向取反',
            value: s.invertY,
            onChanged: s.setInvertY,
          ),
          const Divider(color: Colors.white12, height: 20),
          _SwitchRow(
            label: '反转 Z 轴',
            subtitle: '控制面板 Z+ 方向取反',
            value: s.invertZ,
            onChanged: s.setInvertZ,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. 书写配置（Delta Writer 专属）
// ─────────────────────────────────────────────────────────────────────────────
class _WritingCard extends StatelessWidget {
  const _WritingCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();

    return FluiddCard(
      title: '书写配置',
      child: Column(
        children: [
          _NumericRow(
            label: '落笔高度 (pen-down Z)',
            unit: 'mm',
            value: s.penDownZ,
            allowNegative: true,
            onChanged: s.setPenDownZ,
          ),
          const Divider(color: Colors.white12, height: 20),
          _NumericRow(
            label: '抬笔高度 (pen-up Z)',
            unit: 'mm',
            value: s.penUpZ,
            onChanged: s.setPenUpZ,
          ),
          const Divider(color: Colors.white12, height: 20),
          _NumericRow(
            label: '书写速度',
            unit: 'mm/min',
            value: s.writeSpeed,
            onChanged: s.setWriteSpeed,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. 应用行为
// ─────────────────────────────────────────────────────────────────────────────
class _AppCard extends StatelessWidget {
  const _AppCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();

    return FluiddCard(
      title: '应用行为',
      child: _SwitchRow(
        label: '急停前确认',
        subtitle: '点击急停按钮时弹出二次确认对话框',
        value: s.confirmOnEstop,
        onChanged: s.setConfirmOnEstop,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 通用行组件
// ─────────────────────────────────────────────────────────────────────────────

/// 只读文本行（用于连接信息）
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// 开关行
class _SwitchRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.blue,
        ),
      ],
    );
  }
}

/// 数值输入行（带内联编辑）
class _NumericRow extends StatefulWidget {
  final String label;
  final String unit;
  final double value;
  final bool allowNegative;
  final ValueChanged<double> onChanged;

  const _NumericRow({
    required this.label,
    required this.unit,
    required this.value,
    this.allowNegative = false,
    required this.onChanged,
  });

  @override
  State<_NumericRow> createState() => _NumericRowState();
}

class _NumericRowState extends State<_NumericRow> {
  bool _editing = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(_NumericRow old) {
    super.didUpdateWidget(old);
    // 如果不在编辑中，跟随外部值变化
    if (!_editing && old.value != widget.value) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  void _submit() {
    final parsed = double.tryParse(_ctrl.text.trim());
    if (parsed != null) {
      if (!widget.allowNegative && parsed < 0) {
        _ctrl.text = _fmt(widget.value); // 拒绝负值
      } else {
        widget.onChanged(parsed);
      }
    } else {
      _ctrl.text = _fmt(widget.value); // 解析失败恢复
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        if (_editing)
          SizedBox(
            width: 100,
            height: 36,
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: InputDecoration(
                suffixText: widget.unit,
                suffixStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue.shade700),
                  borderRadius: BorderRadius.circular(4),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.blue),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              onSubmitted: (_) => _submit(),
              onTapOutside: (_) => _submit(),
            ),
          )
        else
          InkWell(
            onTap: () {
              _ctrl.text = _fmt(widget.value);
              setState(() => _editing = true);
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmt(widget.value),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.unit,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
