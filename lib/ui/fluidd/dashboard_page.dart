import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/printer_controller.dart';
import '../../state/navigation_controller.dart';
import '../writing/writing_page.dart';
import '../paper/paper_settings_page.dart';
import '../../style_learning/ui/style_learning_workspace_page.dart';
import 'panels/console_panel.dart';
import 'panels/move_panel.dart';
import 'panels/status_panel.dart';
import 'panels/paper_preview_panel.dart';
import 'panels/tasks_panel.dart';
import 'sidebar.dart';
import 'widgets/klippy_status_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationController>();
    
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
                      Text(
                        _getPageTitle(nav.currentTab),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
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
                
                // Page Content based on current tab
                Expanded(
                  child: _buildPageContent(nav.currentTab),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  String _getPageTitle(SidebarTab tab) {
    switch (tab) {
      case SidebarTab.dashboard:
        return 'Delta Writer - 控制面板';
      case SidebarTab.writing:
        return 'Delta Writer - 文本编辑';
      case SidebarTab.paperSettings:
        return 'Delta Writer - 纸张设置';
      case SidebarTab.styleLearning:
        return 'Delta Writer - 风格学习';
      case SidebarTab.history:
        return 'Delta Writer - 历史记录';
      case SidebarTab.settings:
        return 'Delta Writer - 设置';
    }
  }
  
  Widget _buildPageContent(SidebarTab tab) {
    switch (tab) {
      case SidebarTab.dashboard:
        return _buildDashboardContent();
      case SidebarTab.writing:
        return const WritingPage();
      case SidebarTab.paperSettings:
        return const PaperSettingsPage();
      case SidebarTab.styleLearning:
        return const StyleLearningWorkspacePage();
      case SidebarTab.history:
        return _buildPlaceholderPage('历史记录', Icons.history);
      case SidebarTab.settings:
        return _buildPlaceholderPage('设置', Icons.settings);
    }
  }
  
  Widget _buildPlaceholderPage(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          Text(
            '$title - 开发中',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 18),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDashboardContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Consumer<PrinterController>(
        builder: (context, c, _) {
          final isWide = MediaQuery.of(context).size.width > 900;
          final showKlippyCard = !c.klippyReady && c.phase == AppConnPhase.connected;
          
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Klippy Status (if needed), Status, Move, Macros
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      if (showKlippyCard) const KlippyStatusCard(),
                      const StatusPanel(),
                      const MovePanel(),
                      const PaperPreviewPanel(),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Right Column: Console, Jobs
                const Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      ConsolePanel(),
                      TasksPanel(),
                    ],
                  ),
                ),
              ],
            );
          } else {
            // Mobile: Stack everything
            return Column(
              children: [
                if (showKlippyCard) const KlippyStatusCard(),
                const StatusPanel(),
                const MovePanel(),
                const PaperPreviewPanel(),
                const ConsolePanel(),
              ],
            );
          }
        },
      ),
    );
  }

  Color _phaseColor(AppConnPhase phase) {
    if (phase == AppConnPhase.connected) return Colors.green.shade800;
    if (phase == AppConnPhase.error) return Colors.red.shade900;
    return Colors.grey.shade700;
  }
}
