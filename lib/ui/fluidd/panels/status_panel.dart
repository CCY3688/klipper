import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/printer_controller.dart';
import '../widgets/fluidd_card.dart';

class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key});

  Widget _buildRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PrinterController>();
    
    // Status color logic (simplified)
    Color statusColor = Colors.white;
    if (c.printState == 'printing') statusColor = Colors.greenAccent;
    else if (c.printState == 'error') statusColor = Colors.redAccent;
    else if (c.printState == 'paused') statusColor = Colors.yellowAccent;

    return FluiddCard(
      title: 'Status',
      child: Column(
        children: [
          _buildRow('State', c.printState.toUpperCase(), valueColor: statusColor),
          const Divider(color: Colors.white24),
          _buildRow('File', c.filename.isEmpty ? '--' : c.filename),
          _buildRow('Progress', '${(c.progress * 100).toStringAsFixed(1)} %'),
          const SizedBox(height: 8),
          LinearProgressIndicator( value: c.progress, backgroundColor: Colors.black26, color: Colors.blue ),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft, child: Text("Toolhead Position", style: TextStyle(color: Colors.grey, fontSize: 12))),
          if (c.toolheadPosition != null && c.toolheadPosition!.length >= 3) ...[
             const SizedBox(height: 4),
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 _CoordBadge(axis: 'X', val: c.toolheadPosition![0]),
                 _CoordBadge(axis: 'Y', val: c.toolheadPosition![1]),
                 _CoordBadge(axis: 'Z', val: c.toolheadPosition![2]),
               ],
             )
          ] else 
             const Text("--", style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}

class _CoordBadge extends StatelessWidget {
  final String axis;
  final double val;
  const _CoordBadge({required this.axis, required this.val});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
           Text('$axis: ', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
           Text(val.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
