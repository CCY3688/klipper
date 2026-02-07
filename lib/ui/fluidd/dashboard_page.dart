import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/printer_controller.dart';
import 'panels/console_panel.dart';
import 'panels/move_panel.dart';
import 'panels/status_panel.dart';
import 'sidebar.dart';
import 'widgets/fluidd_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181A1B), // Main BG
      body: Row(
        children: [
          // 1. Sidebar
          const FluiddSidebar(),

          // 2. Main Content
          Expanded(
            child: Column(
              children: [
                // Top Header (Emergency Stop, connection status, etc)
                Container(
                  height: 48,
                  color: const Color(0xFF212529),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Fluidd (Flutter)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Consumer<PrinterController>(
                        builder: (context, c, _) => Chip(
                          label: Text(c.phase.name.toUpperCase()),
                          backgroundColor: _phaseColor(c.phase),
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Consumer<PrinterController>(
                         builder: (context, c, _) => IconButton(
                           icon: const Icon(Icons.power_settings_new, color: Colors.red),
                           onPressed: () {
                             // Disconnect action
                             c.disconnect();
                             Navigator.of(context).pop();
                           },
                           tooltip: 'Disconnect',
                         ),
                      )
                    ],
                  ),
                ),
                
                // Dashboard Grid
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Responsive logic: If wide enough, 2 columns.
                        final isWide = constraints.maxWidth > 900;
                        
                        if (isWide) {
                          return const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left Column: Status, Move, Macros
                              Expanded(
                                flex: 5,
                                child: Column(
                                  children: [
                                    StatusPanel(),
                                    MovePanel(),
                                    FluiddCard(
                                      title: 'Macros',
                                      child: Center(child: Text('Macros Placeholder', style: TextStyle(color: Colors.grey))),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 16),
                              // Right Column: Console, Jobs
                              Expanded(
                                flex: 6,
                                child: Column(
                                  children: [
                                    ConsolePanel(),
                                    FluiddCard(
                                      title: 'Job Queue',
                                      child: Center(child: Text('Job Queue Placeholder', style: TextStyle(color: Colors.grey))),
                                    )
                                  ],
                                ),
                              ),
                            ],
                          );
                        } else {
                          // Mobile: Stack everything
                          return const Column(
                            children: [
                               StatusPanel(),
                               MovePanel(),
                               FluiddCard(title: 'Macros', child: SizedBox(height: 50)),
                               ConsolePanel(),
                            ],
                          );
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _phaseColor(AppConnPhase phase) {
    if (phase == AppConnPhase.connected) return Colors.green.shade800;
    if (phase == AppConnPhase.error) return Colors.red.shade900;
    return Colors.grey.shade700;
  }
}
