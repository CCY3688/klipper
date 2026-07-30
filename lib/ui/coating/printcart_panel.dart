import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/printcart/printcart_protocol.dart';
import '../../state/printcart_controller.dart';
import '../fluidd/widgets/fluidd_card.dart';

class PrintcartPanel extends StatefulWidget {
  const PrintcartPanel({super.key});

  @override
  State<PrintcartPanel> createState() => _PrintcartPanelState();
}

class _PrintcartPanelState extends State<PrintcartPanel> {
  PrintcartColor _color = PrintcartColor.cyan;
  int _nozzle = 0;
  int _repeats = 1;
  int _intervalMs = 100;
  bool _safetyConfirmed = false;
  String? _result;
  bool _resultIsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PrintcartController>().refreshPorts();
    });
  }

  Future<void> _fire(PrintcartController controller) async {
    if (!_safetyConfirmed || !controller.canFire) return;
    setState(() {
      _result = '正在执行单喷嘴测试...';
      _resultIsError = false;
    });
    try {
      await controller.fireSingleNozzle(
        color: _color,
        nozzle: _nozzle,
        repeats: _repeats,
        intervalMs: _intervalMs,
      );
      if (!mounted) return;
      setState(() {
        _result = '${_color.shortLabel} #${_nozzle + 1} 测试完成，高压已关闭';
        _resultIsError = false;
        _safetyConfirmed = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result = '$error';
        _resultIsError = true;
        _safetyConfirmed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PrintcartController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStageRail(controller),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final connection = _buildConnectionCard(controller);
            final firing = _buildFiringCard(controller);
            if (!wide) return Column(children: [connection, firing]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 390, child: connection),
                const SizedBox(width: 16),
                Expanded(child: firing),
              ],
            );
          },
        ),
        _buildHealthCard(controller),
      ],
    );
  }

  Widget _buildStageRail(PrintcartController controller) {
    final printheadReady = controller.isConnected && controller.hasSafeFirmware;
    return FluiddCard(
      title: '喷涂流程',
      subtitle: '第二阶段：静态喷射验收',
      scrollable: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final steps = [
            const _StageItem(
              index: 1,
              label: '联合运动',
              state: _StageState.complete,
            ),
            _StageItem(
              index: 2,
              label: '喷头连接',
              state: printheadReady ? _StageState.complete : _StageState.active,
            ),
            _StageItem(
              index: 3,
              label: '静态喷射',
              state: printheadReady ? _StageState.active : _StageState.pending,
            ),
            const _StageItem(
              index: 4,
              label: '曲面喷绘',
              state: _StageState.pending,
            ),
          ];
          return compact
              ? Wrap(spacing: 8, runSpacing: 8, children: steps)
              : Row(
                  children: steps.map((step) => Expanded(child: step)).toList(),
                );
        },
      ),
    );
  }

  Widget _buildConnectionCard(PrintcartController controller) {
    final connected = controller.isConnected;
    final safe = controller.hasSafeFirmware;
    return FluiddCard(
      title: '喷头连接',
      subtitle: connected ? (safe ? '协议 v2 就绪' : '需要更新固件') : 'USB 串口',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '刷新串口',
          onPressed: controller.busy ? null : controller.refreshPorts,
          icon: const Icon(Icons.refresh, size: 19),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(
              '${controller.selectedPort}:${controller.ports.length}:$connected',
            ),
            initialValue:
                controller.ports.any(
                  (port) => port.name == controller.selectedPort,
                )
                ? controller.selectedPort
                : null,
            decoration: const InputDecoration(
              labelText: '串口',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: controller.ports
                .map(
                  (port) => DropdownMenuItem(
                    value: port.name,
                    child: Text(
                      '${port.name}${port.isEspressifUsbJtag ? ' · ESP32-S3' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: connected || controller.busy
                ? null
                : controller.selectPort,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: controller.busy
                      ? null
                      : connected
                      ? controller.disconnect
                      : controller.connect,
                  icon: controller.busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(connected ? Icons.link_off : Icons.usb),
                  label: Text(connected ? '断开' : '连接'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: '读取控制器状态',
                onPressed: connected && safe && !controller.busy
                    ? controller.refreshStatus
                    : null,
                icon: const Icon(Icons.monitor_heart_outlined),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InfoLine(
            label: '固件',
            value: controller.firmwareIdentity ?? '--',
            color: safe ? Colors.greenAccent : Colors.orangeAccent,
          ),
          _InfoLine(
            label: '高压',
            value: controller.status?.highVoltageEnabled == true ? '开启' : '关闭',
            color: controller.status?.highVoltageEnabled == true
                ? Colors.redAccent
                : Colors.greenAccent,
          ),
          _InfoLine(
            label: '自动关闭',
            value: controller.status == null
                ? '--'
                : '${controller.status!.autoOffMs} ms',
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              controller.errorMessage!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFiringCard(PrintcartController controller) {
    final enabled = controller.canFire;
    return FluiddCard(
      title: '静态单喷嘴测试',
      subtitle: 'HP803 彩色墨盒 · 84 喷嘴/色',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<PrintcartColor>(
            segments: PrintcartColor.values
                .map(
                  (color) => ButtonSegment(
                    value: color,
                    label: Text('${color.shortLabel} ${color.displayName}'),
                  ),
                )
                .toList(),
            selected: {_color},
            showSelectedIcon: false,
            onSelectionChanged: controller.busy
                ? null
                : (value) => setState(() => _color = value.first),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: '上一个喷嘴',
                onPressed: _nozzle > 0 && !controller.busy
                    ? () => setState(() => _nozzle--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Slider(
                  value: _nozzle.toDouble(),
                  min: 0,
                  max: (PrintcartFrame.nozzlesPerColor - 1).toDouble(),
                  divisions: PrintcartFrame.nozzlesPerColor - 1,
                  label: '#${_nozzle + 1}',
                  onChanged: controller.busy
                      ? null
                      : (value) => setState(() => _nozzle = value.round()),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '#${_nozzle + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: '下一个喷嘴',
                onPressed:
                    _nozzle < PrintcartFrame.nozzlesPerColor - 1 &&
                        !controller.busy
                    ? () => setState(() => _nozzle++)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  initialValue: _repeats,
                  decoration: const InputDecoration(
                    labelText: '重复次数',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [1, 2, 3, 5, 10]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value 次'),
                        ),
                      )
                      .toList(),
                  onChanged: controller.busy
                      ? null
                      : (value) => setState(() => _repeats = value ?? 1),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  initialValue: _intervalMs,
                  decoration: const InputDecoration(
                    labelText: '喷射间隔',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [50, 100, 200, 500, 1000]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value ms'),
                        ),
                      )
                      .toList(),
                  onChanged: controller.busy
                      ? null
                      : (value) => setState(() => _intervalMs = value ?? 100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _safetyConfirmed,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('已放置吸墨介质，喷头下方及周边安全'),
            subtitle: const Text('确认仅对本次测试有效，执行后自动取消'),
            onChanged: enabled && !controller.busy
                ? (value) => setState(() => _safetyConfirmed = value ?? false)
                : null,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: enabled && _safetyConfirmed
                ? () => _fire(controller)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
            ),
            icon: controller.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.water_drop_outlined),
            label: const Text('执行单喷嘴测试'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            Text(
              _result!,
              style: TextStyle(
                color: _resultIsError ? Colors.redAccent : Colors.greenAccent,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHealthCard(PrintcartController controller) {
    final normal = controller.healthCount(_color, NozzleHealth.normal);
    final blocked = controller.healthCount(_color, NozzleHealth.blocked);
    return FluiddCard(
      title: '喷嘴健康记录',
      subtitle:
          '${_color.shortLabel} · 正常 $normal / 异常 $blocked / 未测 ${84 - normal - blocked}',
      scrollable: false,
      actions: [
        TextButton.icon(
          onPressed: controller.busy
              ? null
              : () => controller.clearHealth(_color),
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('清空本色'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: List.generate(PrintcartFrame.nozzlesPerColor, (index) {
              final health = controller.healthFor(_color, index);
              final selected = index == _nozzle;
              final color = switch (health) {
                NozzleHealth.unknown => Colors.white24,
                NozzleHealth.normal => Colors.green,
                NozzleHealth.blocked => Colors.redAccent,
              };
              return Tooltip(
                message: '${_color.shortLabel} #${index + 1}',
                child: InkWell(
                  onTap: controller.busy
                      ? null
                      : () => setState(() => _nozzle = index),
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.22),
                      border: Border.all(
                        color: selected ? Colors.lightBlueAccent : color,
                        width: selected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => controller.setHealth(
                          _color,
                          _nozzle,
                          NozzleHealth.normal,
                        ),
                  icon: const Icon(Icons.check, color: Colors.greenAccent),
                  label: Text('标记 #${_nozzle + 1} 正常'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => controller.setHealth(
                          _color,
                          _nozzle,
                          NozzleHealth.blocked,
                        ),
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  label: Text('标记 #${_nozzle + 1} 异常'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _StageState { complete, active, pending }

class _StageItem extends StatelessWidget {
  final int index;
  final String label;
  final _StageState state;

  const _StageItem({
    required this.index,
    required this.label,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StageState.complete => Colors.greenAccent,
      _StageState.active => Colors.lightBlueAccent,
      _StageState.pending => Colors.white38,
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            state == _StageState.complete
                ? Icons.check_circle
                : Icons.circle_outlined,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 7),
          Text('$index  $label', style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _InfoLine({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
