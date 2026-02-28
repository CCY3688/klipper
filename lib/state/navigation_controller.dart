import 'package:flutter/foundation.dart';

/// 侧边栏导航项枚举
enum SidebarTab {
  dashboard,      // 主控面板
  writing,        // 文本编辑/写作
  paperSettings,  // 纸张设置
  configure,      // 配置文件
  history,        // 历史记录
  settings,       // 设置
}

/// 侧边栏导航状态控制器
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
