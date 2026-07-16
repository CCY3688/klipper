import 'package:flutter/foundation.dart';

enum SidebarTab {
  dashboard,
  parameterCalibration,
  surface,
  motionReplay,
  fontWriting,
  configure,
  history,
  userFont,
  settings,
}

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
