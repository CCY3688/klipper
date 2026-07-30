import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'navigation_controller.dart';

/// 全局配置控制器
/// 对应 fluidd 的 ToolheadSettings + GeneralSettings，
/// 额外增加 Delta Writer 专属的书写配置
class SettingsController extends ChangeNotifier {
  // ── SharedPreferences keys ───────────────────────────────────────────
  static const _kXySpeed = 'set_xy_speed';
  static const _kZSpeed = 'set_z_speed';
  static const _kInvertX = 'set_invert_x';
  static const _kInvertY = 'set_invert_y';
  static const _kInvertZ = 'set_invert_z';
  static const _kPenDownZ = 'set_pen_down_z';
  static const _kPenUpZ = 'set_pen_up_z';
  static const _kWriteSpeed = 'set_write_speed';
  static const _kConfirmEstop = 'set_confirm_estop';
  static const _kSidebarPrefix = 'set_sidebar_visible_';

  // ── 运动控制 ─────────────────────────────────────────────────────────
  /// XY 移动速度 (mm/min)
  double xySpeed = 3000;

  /// Z 移动速度 (mm/min)
  double zSpeed = 600;

  /// 是否反转 X 轴
  bool invertX = false;

  /// 是否反转 Y 轴
  bool invertY = false;

  /// 是否反转 Z 轴
  bool invertZ = false;

  // ── 书写配置（Delta Writer 专属）─────────────────────────────────────
  /// 落笔时 Z 高度 (mm)，即笔头接触纸面的 Z 坐标
  double penDownZ = 0.0;

  /// 抬笔时 Z 高度 (mm)，行程净空
  double penUpZ = 5.0;

  /// 书写速度 (mm/min)
  double writeSpeed = 1500;

  // ── 应用行为 ───────────────────────────────────────────────────────
  /// 急停前是否弹出确认对话框
  bool confirmOnEstop = true;

  final Map<SidebarTab, bool> sidebarVisibility = {
    for (final item in sidebarItemDefinitions) item.tab: true,
  };

  SettingsController() {
    _load();
  }

  // ── 内部 ──────────────────────────────────────────────────────────────
  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    xySpeed = sp.getDouble(_kXySpeed) ?? 3000;
    zSpeed = sp.getDouble(_kZSpeed) ?? 600;
    invertX = sp.getBool(_kInvertX) ?? false;
    invertY = sp.getBool(_kInvertY) ?? false;
    invertZ = sp.getBool(_kInvertZ) ?? false;
    penDownZ = sp.getDouble(_kPenDownZ) ?? 0.0;
    penUpZ = sp.getDouble(_kPenUpZ) ?? 5.0;
    writeSpeed = sp.getDouble(_kWriteSpeed) ?? 1500;
    confirmOnEstop = sp.getBool(_kConfirmEstop) ?? true;
    for (final item in sidebarItemDefinitions) {
      sidebarVisibility[item.tab] =
          sp.getBool('$_kSidebarPrefix${item.tab.name}') ?? true;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kXySpeed, xySpeed);
    await sp.setDouble(_kZSpeed, zSpeed);
    await sp.setBool(_kInvertX, invertX);
    await sp.setBool(_kInvertY, invertY);
    await sp.setBool(_kInvertZ, invertZ);
    await sp.setDouble(_kPenDownZ, penDownZ);
    await sp.setDouble(_kPenUpZ, penUpZ);
    await sp.setDouble(_kWriteSpeed, writeSpeed);
    await sp.setBool(_kConfirmEstop, confirmOnEstop);
    for (final entry in sidebarVisibility.entries) {
      await sp.setBool('$_kSidebarPrefix${entry.key.name}', entry.value);
    }
  }

  // ── 公开 setter（改完自动持久化）──────────────────────────────────────
  void setXySpeed(double v) {
    xySpeed = v;
    notifyListeners();
    _save();
  }

  void setZSpeed(double v) {
    zSpeed = v;
    notifyListeners();
    _save();
  }

  void setInvertX(bool v) {
    invertX = v;
    notifyListeners();
    _save();
  }

  void setInvertY(bool v) {
    invertY = v;
    notifyListeners();
    _save();
  }

  void setInvertZ(bool v) {
    invertZ = v;
    notifyListeners();
    _save();
  }

  void setPenDownZ(double v) {
    penDownZ = v;
    notifyListeners();
    _save();
  }

  void setPenUpZ(double v) {
    penUpZ = v;
    notifyListeners();
    _save();
  }

  void setWriteSpeed(double v) {
    writeSpeed = v;
    notifyListeners();
    _save();
  }

  void setConfirmOnEstop(bool v) {
    confirmOnEstop = v;
    notifyListeners();
    _save();
  }

  void setSidebarVisible(SidebarTab tab, bool visible) {
    if (sidebarVisibility[tab] == visible) return;
    sidebarVisibility[tab] = visible;
    notifyListeners();
    _save();
  }
}
