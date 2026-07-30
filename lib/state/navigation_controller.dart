import 'package:flutter/material.dart';

enum SidebarTab {
  dashboard,
  parameterCalibration,
  surface,
  coating,
  motionReplay,
  fontWriting,
  configure,
  history,
  userFont,
  simulation,
  settings,
}

class SidebarItemDefinition {
  final SidebarTab tab;
  final IconData icon;
  final String label;

  const SidebarItemDefinition({
    required this.tab,
    required this.icon,
    required this.label,
  });
}

const sidebarItemDefinitions = <SidebarItemDefinition>[
  SidebarItemDefinition(
    tab: SidebarTab.dashboard,
    icon: Icons.dashboard,
    label: '控制面板',
  ),
  SidebarItemDefinition(
    tab: SidebarTab.parameterCalibration,
    icon: Icons.precision_manufacturing_outlined,
    label: '参数校准',
  ),
  SidebarItemDefinition(
    tab: SidebarTab.surface,
    icon: Icons.terrain,
    label: '曲面',
  ),
  SidebarItemDefinition(
    tab: SidebarTab.coating,
    icon: Icons.format_paint_outlined,
    label: '喷涂',
  ),
  SidebarItemDefinition(
    tab: SidebarTab.motionReplay,
    icon: Icons.route,
    label: '运动重现',
  ),
  SidebarItemDefinition(
    tab: SidebarTab.fontWriting,
    icon: Icons.local_fire_department_outlined,
    label: '激光',
  ),
  SidebarItemDefinition(
    tab: SidebarTab.configure,
    icon: Icons.tune,
    label: '配置',
  ),
  SidebarItemDefinition(
    tab: SidebarTab.history,
    icon: Icons.history,
    label: '历史记录',
  ),
  SidebarItemDefinition(
    tab: SidebarTab.userFont,
    icon: Icons.font_download_outlined,
    label: '用户字体',
  ),
  SidebarItemDefinition(
    tab: SidebarTab.simulation,
    icon: Icons.precision_manufacturing,
    label: '仿真验证',
  ),
];

class NavigationController extends ChangeNotifier {
  SidebarTab _currentTab = SidebarTab.dashboard;

  SidebarTab get currentTab => _currentTab;

  void switchTo(SidebarTab tab) {
    if (_currentTab != tab) {
      _currentTab = tab;
      notifyListeners();
    }
  }
}
