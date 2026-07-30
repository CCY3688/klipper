import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/navigation_controller.dart';
import '../../state/printer_controller.dart';
import '../calibration/parameter_calibration_page.dart';
import '../coating/coating_page.dart';
import '../emm/emm_replay_page.dart';
import '../simulation/simulation_page.dart';
import '../surface/surface_page.dart';
import '../writing/user_font_page.dart';
import '../writing/writing_page.dart';
import 'configure_page.dart';
import 'panels/camera_panel.dart';
import 'panels/console_panel.dart';
import 'panels/move_panel.dart';
import 'panels/status_panel.dart';
import 'panels/tasks_panel.dart';
import 'settings_page.dart';
import 'sidebar.dart';
import 'widgets/klippy_status_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationController>();

    return Scaffold(
      backgroundColor: const Color(0xFF181A1B),
      body: Row(
        children: [
          const FluiddSidebar(),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 48,
                  color: const Color(0xFF212529),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        _getPageTitle(nav.currentTab),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Consumer<PrinterController>(
                        builder: (context, c, _) => Chip(
                          label: Text(_phaseLabel(c.phase)),
                          backgroundColor: _phaseColor(c.phase),
                          labelStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Consumer<PrinterController>(
                        builder: (context, c, _) =>
                            _buildKlipperScreenRestartButton(context, c),
                      ),
                      const SizedBox(width: 8),
                      Consumer<PrinterController>(
                        builder: (context, c, _) => IconButton(
                          icon: const Icon(
                            Icons.power_settings_new,
                            color: Colors.red,
                          ),
                          onPressed: () {
                            c.disconnect();
                            Navigator.of(context).pop();
                          },
                          tooltip: '断开连接',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildPageContent(nav.currentTab)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKlipperScreenRestartButton(
    BuildContext context,
    PrinterController c,
  ) {
    final canRestart =
        c.phase == AppConnPhase.connected && !c.klipperScreenRestarting;

    return Tooltip(
      message: '重启 KlipperScreen',
      child: TextButton.icon(
        onPressed: canRestart
            ? () => _confirmRestartKlipperScreen(context, c)
            : null,
        icon: c.klipperScreenRestarting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.lightBlueAccent,
                  ),
                ),
              )
            : const Icon(Icons.restart_alt, size: 18),
        label: const Text('重启 screen'),
        style: TextButton.styleFrom(
          foregroundColor: Colors.lightBlueAccent,
          disabledForegroundColor: Colors.grey,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Future<void> _confirmRestartKlipperScreen(
    BuildContext context,
    PrinterController c,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重启 screen'),
        content: const Text('将通过 Moonraker 重启 KlipperScreen 服务，界面会短暂中断。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('重启'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在重启 screen...')));

    final error = await c.restartKlipperScreen();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error == null ? '已发送重启 screen 指令' : '重启失败: $error'),
        backgroundColor: error == null ? null : Colors.redAccent,
      ),
    );
  }

  String _getPageTitle(SidebarTab tab) {
    switch (tab) {
      case SidebarTab.dashboard:
        return 'Delta Writer - 控制面板';
      case SidebarTab.motionReplay:
        return 'Delta Writer - 运动重现';
      case SidebarTab.coating:
        return 'Delta Writer - 喷涂';
      case SidebarTab.simulation:
        return 'Delta Writer - 仿真验证';
      case SidebarTab.fontWriting:
        return 'Delta Writer - 激光';
      case SidebarTab.surface:
        return 'Delta Writer - 曲面';
      case SidebarTab.parameterCalibration:
        return 'Delta Writer - 参数校准';
      case SidebarTab.configure:
        return 'Delta Writer - 配置';
      case SidebarTab.history:
        return 'Delta Writer - 历史记录';
      case SidebarTab.userFont:
        return 'Delta Writer - 用户字体';
      case SidebarTab.settings:
        return 'Delta Writer - 设置';
    }
  }

  Widget _buildPageContent(SidebarTab tab) {
    switch (tab) {
      case SidebarTab.dashboard:
        return _buildDashboardContent();
      case SidebarTab.motionReplay:
        return const EmmReplayPage();
      case SidebarTab.coating:
        return const CoatingPage();
      case SidebarTab.simulation:
        return const SimulationPage();
      case SidebarTab.fontWriting:
        return const WritingPage();
      case SidebarTab.surface:
        return const SurfacePage();
      case SidebarTab.parameterCalibration:
        return const ParameterCalibrationPage();
      case SidebarTab.configure:
        return const ConfigurePage();
      case SidebarTab.history:
        return _buildPlaceholderPage('历史记录', Icons.history);
      case SidebarTab.userFont:
        return const UserFontPage();
      case SidebarTab.settings:
        return const SettingsPage();
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
          final showKlippyCard =
              !c.klippyReady && c.phase == AppConnPhase.connected;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      if (showKlippyCard) const KlippyStatusCard(),
                      const StatusPanel(),
                      const MovePanel(),
                      const CameraPanel(),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  flex: 6,
                  child: Column(children: [ConsolePanel(), TasksPanel()]),
                ),
              ],
            );
          }
          return Column(
            children: [
              if (showKlippyCard) const KlippyStatusCard(),
              const StatusPanel(),
              const MovePanel(),
              const CameraPanel(),
              const ConsolePanel(),
            ],
          );
        },
      ),
    );
  }

  String _phaseLabel(AppConnPhase phase) {
    switch (phase) {
      case AppConnPhase.idle:
        return '空闲';
      case AppConnPhase.connecting:
        return '连接中';
      case AppConnPhase.connected:
        return '已连接';
      case AppConnPhase.reconnecting:
        return '重连中';
      case AppConnPhase.disconnected:
        return '已断开';
      case AppConnPhase.error:
        return '错误';
    }
  }

  Color _phaseColor(AppConnPhase phase) {
    if (phase == AppConnPhase.connected) return Colors.green.shade800;
    if (phase == AppConnPhase.error) return Colors.red.shade900;
    return Colors.grey.shade700;
  }
}
