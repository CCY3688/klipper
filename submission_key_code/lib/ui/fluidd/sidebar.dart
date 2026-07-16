import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/navigation_controller.dart';

class FluiddSidebar extends StatelessWidget {
  const FluiddSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationController>();

    return Container(
      width: 64,
      color: const Color(0xFF212529),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    const Icon(Icons.edit_note, color: Colors.blue, size: 32),
                    const SizedBox(height: 32),
                    _SideItem(
                      icon: Icons.dashboard,
                      tooltip: '控制面板',
                      isActive: nav.currentTab == SidebarTab.dashboard,
                      onTap: () => nav.switchTo(SidebarTab.dashboard),
                    ),
                    _SideItem(
                      icon: Icons.precision_manufacturing_outlined,
                      tooltip: '参数校准',
                      isActive:
                          nav.currentTab == SidebarTab.parameterCalibration,
                      onTap: () =>
                          nav.switchTo(SidebarTab.parameterCalibration),
                    ),
                    _SideItem(
                      icon: Icons.terrain,
                      tooltip: '曲面',
                      isActive: nav.currentTab == SidebarTab.surface,
                      onTap: () => nav.switchTo(SidebarTab.surface),
                    ),
                    _SideItem(
                      icon: Icons.route,
                      tooltip: '运动重现',
                      isActive: nav.currentTab == SidebarTab.motionReplay,
                      onTap: () => nav.switchTo(SidebarTab.motionReplay),
                    ),
                    _SideItem(
                      icon: Icons.local_fire_department_outlined,
                      tooltip: '激光',
                      isActive: nav.currentTab == SidebarTab.fontWriting,
                      onTap: () => nav.switchTo(SidebarTab.fontWriting),
                    ),
                    _SideItem(
                      icon: Icons.tune,
                      tooltip: '配置',
                      isActive: nav.currentTab == SidebarTab.configure,
                      onTap: () => nav.switchTo(SidebarTab.configure),
                    ),
                    _SideItem(
                      icon: Icons.history,
                      tooltip: '历史记录',
                      isActive: nav.currentTab == SidebarTab.history,
                      onTap: () => nav.switchTo(SidebarTab.history),
                    ),
                    _SideItem(
                      icon: Icons.font_download_outlined,
                      tooltip: '用户字体',
                      isActive: nav.currentTab == SidebarTab.userFont,
                      onTap: () => nav.switchTo(SidebarTab.userFont),
                    ),
                    const Spacer(),
                    _SideItem(
                      icon: Icons.settings,
                      tooltip: '设置',
                      isActive: nav.currentTab == SidebarTab.settings,
                      onTap: () => nav.switchTo(SidebarTab.settings),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _SideItem({
    required this.icon,
    this.tooltip,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: isActive
                ? const Border(left: BorderSide(color: Colors.blue, width: 3))
                : null,
            color: isActive ? Colors.white10 : null,
          ),
          child: Icon(icon, color: isActive ? Colors.blue : Colors.grey),
        ),
      ),
    );
  }
}
