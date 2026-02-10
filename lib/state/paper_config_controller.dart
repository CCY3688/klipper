import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../writing/model/paper_type.dart';
import '../writing/model/essay_grid.dart';
import '../writing/model/page.dart';

/// 纸张配置控制器
/// - 管理当前使用的纸张配置
/// - 管理已保存的纸张配置列表
/// - 持久化存储到 SharedPreferences
class PaperConfigController extends ChangeNotifier {
  static const _kSavedPapers = 'paper_configs';
  static const _kActivePaperIndex = 'paper_active_index';

  /// 已保存的纸张配置列表
  List<PaperConfig> _savedPapers = [];
  List<PaperConfig> get savedPapers => List.unmodifiable(_savedPapers);

  /// 当前激活/使用的纸张配置
  PaperConfig _activePaper = defaultGridPaper();
  PaperConfig get activePaper => _activePaper;

  /// 当前正在编辑预览的纸张配置（用于实时预览）
  PaperConfig _editingPaper = defaultGridPaper();
  PaperConfig get editingPaper => _editingPaper;

  /// 激活纸张在已保存列表中的索引（-1 表示不在列表中）
  int _activeIndex = 0;
  int get activeIndex => _activeIndex;

  PaperConfigController() {
    _loadFromStorage();
  }

  /// 从持久化存储加载
  Future<void> _loadFromStorage() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = sp.getString(_kSavedPapers);
      if (jsonStr != null) {
        final list = jsonDecode(jsonStr) as List;
        _savedPapers = list
            .map((e) => PaperConfig.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      
      if (_savedPapers.isEmpty) {
        // 首次启动：使用默认纸张类型
        _savedPapers = allDefaultPapers();
      }
      
      _activeIndex = sp.getInt(_kActivePaperIndex) ?? 0;
      if (_activeIndex >= _savedPapers.length) _activeIndex = 0;
      
      _activePaper = _savedPapers[_activeIndex];
      _editingPaper = _activePaper;
      notifyListeners();
    } catch (e) {
      // 加载失败时使用默认值
      _savedPapers = allDefaultPapers();
      _activeIndex = 0;
      _activePaper = _savedPapers[0];
      _editingPaper = _activePaper;
      notifyListeners();
    }
  }

  /// 保存到持久化存储
  Future<void> _saveToStorage() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_savedPapers.map((e) => e.toJson()).toList());
      await sp.setString(_kSavedPapers, jsonStr);
      await sp.setInt(_kActivePaperIndex, _activeIndex);
    } catch (e) {
      debugPrint('保存纸张配置失败: $e');
    }
  }

  /// 更新正在编辑的纸张配置（实时预览用，不保存）
  void updateEditing(PaperConfig config) {
    _editingPaper = config;
    notifyListeners();
  }

  /// 激活某个已保存的配置（一键导入）
  void activatePaper(int index) {
    if (index < 0 || index >= _savedPapers.length) return;
    _activeIndex = index;
    _activePaper = _savedPapers[index];
    _editingPaper = _activePaper;
    notifyListeners();
    _saveToStorage();
  }

  /// 将当前编辑配置保存为新的纸张类型
  void saveCurrentAsNew(String name) {
    final config = _editingPaper.copyWith(name: name);
    _savedPapers.add(config);
    _activeIndex = _savedPapers.length - 1;
    _activePaper = config;
    _editingPaper = config;
    notifyListeners();
    _saveToStorage();
  }

  /// 更新已有配置
  void updateSaved(int index, PaperConfig config) {
    if (index < 0 || index >= _savedPapers.length) return;
    _savedPapers[index] = config;
    if (index == _activeIndex) {
      _activePaper = config;
      _editingPaper = config;
    }
    notifyListeners();
    _saveToStorage();
  }

  /// 删除已保存的配置
  void deleteSaved(int index) {
    if (index < 0 || index >= _savedPapers.length) return;
    _savedPapers.removeAt(index);
    if (_savedPapers.isEmpty) {
      _savedPapers = allDefaultPapers();
    }
    if (_activeIndex >= _savedPapers.length) {
      _activeIndex = _savedPapers.length - 1;
    }
    _activePaper = _savedPapers[_activeIndex];
    _editingPaper = _activePaper;
    notifyListeners();
    _saveToStorage();
  }

  /// 恢复到默认类型
  void resetToDefaults() {
    _savedPapers = allDefaultPapers();
    _activeIndex = 0;
    _activePaper = _savedPapers[0];
    _editingPaper = _activePaper;
    notifyListeners();
    _saveToStorage();
  }

  /// 将当前编辑的配置应用为激活配置
  void applyEditing() {
    _activePaper = _editingPaper;
    // 如果当前激活配置在列表中，也更新列表中的项
    if (_activeIndex >= 0 && _activeIndex < _savedPapers.length) {
      _savedPapers[_activeIndex] = _activePaper;
    }
    notifyListeners();
    _saveToStorage();
  }

  // ===== 便捷转换方法：兼容旧代码 =====

  /// 将当前激活的 PaperConfig 转换为旧的 PageMm
  PageMm get activePage => PageMm(
    widthMm: _activePaper.pageWidthMm,
    heightMm: _activePaper.pageHeightMm,
  );

  /// 将当前激活的 PaperConfig 转换为旧的 EssayGridSpec
  EssayGridSpec get activeGrid => EssayGridSpec(
    cellMm: _activePaper.cellSizeMm,
    marginLeftMm: _activePaper.marginLeftMm,
    marginTopMm: _activePaper.marginTopMm,
    cols: _activePaper.cols,
    rows: _activePaper.rows,
  );
}
