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
      color: const Color(0xFF212529), // Dark background for sidebar
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.edit_note, color: Colors.blue, size: 32), // Logo: Writing focused
          const SizedBox(height: 32),
          _SideItem(
            icon: Icons.dashboard,
            tooltip: '控制面板',
            isActive: nav.currentTab == SidebarTab.dashboard,
            onTap: () => nav.switchTo(SidebarTab.dashboard),
          ),
          _SideItem(
            icon: Icons.text_fields, // 文本编辑图标
            tooltip: '文本编辑',
            isActive: nav.currentTab == SidebarTab.writing,
            onTap: () => nav.switchTo(SidebarTab.writing),
          ),
          _SideItem(
            icon: Icons.history,
            tooltip: '历史记录',
            isActive: nav.currentTab == SidebarTab.history,
            onTap: () => nav.switchTo(SidebarTab.history),
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
          child: Icon(
            icon, 
            color: isActive ? Colors.blue : Colors.grey,
          ),
        ),
      ),
    );
  }
}
