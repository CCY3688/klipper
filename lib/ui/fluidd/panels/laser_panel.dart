import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../state/printer_controller.dart';
import '../widgets/fluidd_card.dart';

class LaserPanel extends StatefulWidget {
  const LaserPanel({super.key});

  @override
  State<LaserPanel> createState() => _LaserPanelState();
}

class _LaserPanelState extends State<LaserPanel> {
  static const double _minPower = 0;
  static const double _maxPower = 100;

  final TextEditingController _powerController = TextEditingController(
    text: '0',
  );
  final FocusNode _powerFocus = FocusNode();
  double _power = 0;
  bool _sending = false;

  @override
  void dispose() {
    _powerController.dispose();
    _powerFocus.dispose();
    super.dispose();
  }

  void _setPower(double value, {bool updateText = true}) {
    final next = value.clamp(_minPower, _maxPower).roundToDouble();
    setState(() => _power = next);
    if (updateText) {
      _powerController.text = next.round().toString();
      _powerController.selection = TextSelection.collapsed(
        offset: _powerController.text.length,
      );
    }
  }

  void _commitInput() {
    final parsed = double.tryParse(_powerController.text.trim());
    if (parsed == null) {
      _setPower(_power);
      return;
    }
    _setPower(parsed);
  }

  Future<void> _sendPower(PrinterController controller, double value) async {
    if (_sending) return;
    setState(() => _sending = true);
    final error = await controller.setLaserPower(value, maxPower: _maxPower);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PrinterController>();
    final connected = context.select<PrinterController, bool>(
      (c) => c.phase == AppConnPhase.connected,
    );
    final enabled = connected && !_sending;

    return FluiddCard(
      title: '激光强度',
      scrollable: false,
      actions: [
        IconButton(
          tooltip: '关闭激光',
          icon: const Icon(Icons.power_settings_new, color: Colors.redAccent),
          onPressed: enabled
              ? () {
                  _setPower(0);
                  _sendPower(controller, 0);
                }
              : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.light_mode, color: Colors.amber, size: 20),
              Expanded(
                child: Slider(
                  value: _power,
                  min: _minPower,
                  max: _maxPower,
                  divisions: _maxPower.toInt(),
                  label: _power.round().toString(),
                  onChanged: enabled ? (value) => _setPower(value) : null,
                  onChangeEnd: enabled
                      ? (value) => _sendPower(controller, value)
                      : null,
                ),
              ),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: _powerController,
                  focusNode: _powerFocus,
                  enabled: enabled,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: '%',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (text) {
                    final parsed = double.tryParse(text);
                    if (parsed != null) {
                      _setPower(parsed, updateText: false);
                    }
                  },
                  onSubmitted: (_) {
                    _commitInput();
                    _sendPower(controller, _power);
                  },
                  onEditingComplete: _commitInput,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: _sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt, size: 16),
                  label: Text(_sending ? '发送中' : '应用强度'),
                  onPressed: enabled
                      ? () {
                          _commitInput();
                          _sendPower(controller, _power);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: OutlinedButton(
                  onPressed: enabled
                      ? () {
                          _setPower(0);
                          _sendPower(controller, 0);
                        }
                      : null,
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
