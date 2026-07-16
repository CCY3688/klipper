import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/printer_controller.dart';
import '../../../state/settings_controller.dart';
import '../widgets/fluidd_card.dart';

class MovePanel extends StatefulWidget {
  const MovePanel({super.key});

  @override
  State<MovePanel> createState() => _MovePanelState();
}

class _MovePanelState extends State<MovePanel> {
  double _stepInfo = 10.0; // Default 10mm

  // 应用轴反转：若反转则取反距离值
  String _xDelta(double step, SettingsController s) {
    final v = s.invertX ? -step : step;
    return v >= 0 ? '$v' : '$v';
  }

  String _yDelta(double step, SettingsController s) {
    final v = s.invertY ? -step : step;
    return v >= 0 ? '$v' : '$v';
  }

  String _zDelta(double step, SettingsController s) {
    final v = s.invertZ ? -step : step;
    return v >= 0 ? '$v' : '$v';
  }

  Future<void> _sendGcodeWithFeedback(
    PrinterController controller,
    String script,
  ) async {
    final error = await controller.sendGcode(script);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<PrinterController>();
    final s = context.watch<SettingsController>();

    return FluiddCard(
      title: '工具头',
      actions: [
        TextButton.icon(
          onPressed: () => c.home(),
          icon: const Icon(Icons.home, size: 16, color: Colors.blue),
          label: const Text('全部', style: TextStyle(color: Colors.blue)),
        ),
      ],
      child: Column(
        children: [
          // Homing Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _HomeBtn(axis: 'X', onPressed: () => c.home('X')),
              _HomeBtn(axis: 'Y', onPressed: () => c.home('Y')),
              _HomeBtn(axis: 'Z', onPressed: () => c.home('Z')),
            ],
          ),
          const SizedBox(height: 16),
          // Directional Arrows
          Row(
            children: [
              // XY Pad
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _ArrowBtn(
                      icon: Icons.arrow_upward,
                      label: 'Y+',
                      onPressed: () => _sendGcodeWithFeedback(
                        c,
                        'G91\nG1 Y${_yDelta(_stepInfo, s)} F${s.xySpeed.toInt()}\nG90',
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ArrowBtn(
                          icon: Icons.arrow_back,
                          label: 'X-',
                          onPressed: () => _sendGcodeWithFeedback(
                            c,
                            'G91\nG1 X${_xDelta(-_stepInfo, s)} F${s.xySpeed.toInt()}\nG90',
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.api, color: Colors.grey),
                        const SizedBox(width: 8),
                        _ArrowBtn(
                          icon: Icons.arrow_forward,
                          label: 'X+',
                          onPressed: () => _sendGcodeWithFeedback(
                            c,
                            'G91\nG1 X${_xDelta(_stepInfo, s)} F${s.xySpeed.toInt()}\nG90',
                          ),
                        ),
                      ],
                    ),
                    _ArrowBtn(
                      icon: Icons.arrow_downward,
                      label: 'Y-',
                      onPressed: () => _sendGcodeWithFeedback(
                        c,
                        'G91\nG1 Y${_yDelta(-_stepInfo, s)} F${s.xySpeed.toInt()}\nG90',
                      ),
                    ),
                  ],
                ),
              ),
              // Z Pad
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    _ArrowBtn(
                      icon: Icons.arrow_upward,
                      label: 'Z+',
                      color: Colors.blueAccent,
                      onPressed: () => _sendGcodeWithFeedback(
                        c,
                        'G91\nG1 Z${_zDelta(_stepInfo, s)} F${s.zSpeed.toInt()}\nG90',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Icon(Icons.height, color: Colors.grey, size: 16),
                    const SizedBox(height: 12),
                    _ArrowBtn(
                      icon: Icons.arrow_downward,
                      label: 'Z-',
                      color: Colors.blueAccent,
                      onPressed: () => _sendGcodeWithFeedback(
                        c,
                        'G91\nG1 Z${_zDelta(-_stepInfo, s)} F${s.zSpeed.toInt()}\nG90',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Step Selection
          Wrap(
            spacing: 8,
            children: [0.1, 1.0, 10.0, 50.0, 100.0].map((step) {
              final isSelected = _stepInfo == step;
              return ChoiceChip(
                label: Text('$step'),
                selected: isSelected,
                onSelected: (v) => setState(() => _stepInfo = step),
                selectedColor: Colors.blue,
                backgroundColor: const Color(0xFF1E1E1E),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ), // Match Fluidd square chips
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _HomeBtn extends StatelessWidget {
  final String axis;
  final VoidCallback onPressed;
  const _HomeBtn({required this.axis, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.blueGrey),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text('$axis 归零', style: const TextStyle(color: Colors.white70)),
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onPressed;

  const _ArrowBtn({
    required this.icon,
    required this.label,
    this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF3A3F44),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: color ?? Colors.white70),
      ),
    );
  }
}
