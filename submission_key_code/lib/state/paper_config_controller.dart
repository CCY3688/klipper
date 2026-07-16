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
  static const _kActivePaper = 'paper_active_config';

  /// 已保存的纸张配置列表
  List<PaperConfig> _savedPapers = [];
  List<PaperConfig> get savedPapers => List.unmodifiable(_savedPapers);

  /// 当前激活/使用的纸张配置
  PaperConfig _activePaper = defaultGridPaper();
  PaperConfig get activePaper => _activePaper;

  /// 当前正在编辑预览的纸张配置（用于实时预览）
  PaperConfig _editingPaper = defaultGridPaper();
  PaperConfig get editingPaper => _editingPaper;

  /// 正在编辑的配置在 savedPapers 中的来源索引（-1 表示新建/未保存草稿）
  int _editingIndex = 0;
  int get editingIndex => _editingIndex;

  /// 激活纸张在已保存列表中的索引（-1 表示不在列表中）
  int _activeIndex = 0;
  int get activeIndex => _activeIndex;

  bool get isEditingSavedPaper => _isValidIndex(_editingIndex);
  bool get hasEditingChanges {
    if (!isEditingSavedPaper) {
      return _editingIndex != _activeIndex || _editingPaper != _activePaper;
    }
    return _editingPaper != _savedPapers[_editingIndex];
  }

  String get editingSourceName =>
      isEditingSavedPaper ? _savedPapers[_editingIndex].name : '未保存配置';

  bool get isActiveSavedPaper => _isValidIndex(_activeIndex);

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

      final storedActiveIndex = sp.getInt(_kActivePaperIndex) ?? 0;
      final activeJsonStr = sp.getString(_kActivePaper);
      if (_isValidIndex(storedActiveIndex)) {
        _activeIndex = storedActiveIndex;
        _activePaper = _savedPapers[_activeIndex];
      } else if (storedActiveIndex == -1 && activeJsonStr != null) {
        _activeIndex = -1;
        _activePaper = PaperConfig.fromJson(
          jsonDecode(activeJsonStr) as Map<String, dynamic>,
        );
      } else {
        _activeIndex = 0;
        _activePaper = _savedPapers[0];
      }
      _editingPaper = _activePaper;
      _editingIndex = _activeIndex;
      notifyListeners();
    } catch (e) {
      // 加载失败时使用默认值
      _savedPapers = allDefaultPapers();
      _activeIndex = 0;
      _activePaper = _savedPapers[0];
      _editingPaper = _activePaper;
      _editingIndex = 0;
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
      await sp.setString(_kActivePaper, jsonEncode(_activePaper.toJson()));
    } catch (e) {
      debugPrint('保存纸张配置失败: $e');
    }
  }

  /// 更新正在编辑的纸张配置（实时预览用，不保存）
  void updateEditing(PaperConfig config) {
    _editingPaper = config;
    notifyListeners();
  }

  /// 激活某个已保存的配置，不影响编辑器中的草稿。
  void activatePaper(int index) {
    if (!_isValidIndex(index)) return;
    _activeIndex = index;
    _activePaper = _savedPapers[index];
    notifyListeners();
    _saveToStorage();
  }

  /// 新建一个未保存草稿。默认基于当前编辑内容复制，避免打断用户正在调的参数。
  void createDraft({PaperConfig? from, String? name}) {
    final base = from ?? _editingPaper;
    _editingPaper = base.copyWith(name: _uniqueName(name ?? '${base.name} 副本'));
    _editingIndex = -1;
    notifyListeners();
  }

  /// 放弃当前未保存修改，回到编辑来源。
  void discardEditingChanges() {
    if (isEditingSavedPaper) {
      _editingPaper = _savedPapers[_editingIndex];
    } else {
      _editingPaper = _activePaper;
      _editingIndex = _activeIndex;
    }
    notifyListeners();
  }

  /// 将当前编辑配置保存为新的纸张类型
  int saveCurrentAsNew(String name) {
    final wasActiveDraft = _activeIndex == -1 && _activePaper == _editingPaper;
    final config = _editingPaper.copyWith(name: name);
    _savedPapers.add(config);
    _editingIndex = _savedPapers.length - 1;
    _editingPaper = config;
    if (wasActiveDraft) {
      _activeIndex = _editingIndex;
      _activePaper = config;
    }
    notifyListeners();
    _saveToStorage();
    return _editingIndex;
  }

  /// 更新已有配置
  bool updateSaved(int index, PaperConfig config) {
    if (!_isValidIndex(index)) return false;
    final wasActiveDraft = _activeIndex == -1 && _activePaper == _editingPaper;
    _savedPapers[index] = config;
    if (index == _activeIndex || wasActiveDraft) {
      _activeIndex = index;
      _activePaper = config;
    }
    _editingPaper = config;
    _editingIndex = index;
    notifyListeners();
    _saveToStorage();
    return true;
  }

  /// 将当前编辑内容保存回其来源配置。
  bool saveEditingToSource({String? name}) {
    if (!isEditingSavedPaper) return false;
    final trimmedName = name?.trim();
    final config = _editingPaper.copyWith(
      name: trimmedName == null || trimmedName.isEmpty
          ? _editingPaper.name
          : trimmedName,
    );
    return updateSaved(_editingIndex, config);
  }

  /// 将编辑器中的配置加载到指定索引
  void loadToEditor(int index) {
    if (!_isValidIndex(index)) return;
    _editingPaper = _savedPapers[index];
    _editingIndex = index;
    notifyListeners();
  }

  /// 删除已保存的配置
  void deleteSaved(int index) {
    if (!_isValidIndex(index)) return;
    final deletingActive = index == _activeIndex;
    final deletingEditing = index == _editingIndex;
    _savedPapers.removeAt(index);
    if (_savedPapers.isEmpty) {
      _savedPapers = allDefaultPapers();
    }

    if (deletingActive) {
      _activeIndex = index >= _savedPapers.length
          ? _savedPapers.length - 1
          : index;
      _activePaper = _savedPapers[_activeIndex];
    } else if (_activeIndex > index) {
      _activeIndex--;
    } else if (!isActiveSavedPaper) {
      _activeIndex = -1;
    }

    if (deletingEditing) {
      if (isActiveSavedPaper) {
        _editingIndex = _activeIndex;
        _editingPaper = _savedPapers[_editingIndex];
      } else {
        _editingIndex = -1;
        _editingPaper = _activePaper;
      }
    } else if (_editingIndex > index) {
      _editingIndex--;
    }
    notifyListeners();
    _saveToStorage();
  }

  /// 恢复到默认类型
  void resetToDefaults() {
    _savedPapers = allDefaultPapers();
    _activeIndex = 0;
    _editingIndex = 0;
    _activePaper = _savedPapers[0];
    _editingPaper = _activePaper;
    notifyListeners();
    _saveToStorage();
  }

  /// 将当前编辑的配置应用为激活配置
  void applyEditing() {
    _activePaper = _editingPaper;
    if (isEditingSavedPaper && _savedPapers[_editingIndex] == _editingPaper) {
      _activeIndex = _editingIndex;
    } else {
      _activeIndex = -1;
    }
    notifyListeners();
    _saveToStorage();
  }

  int indexOfName(String name, {int? exceptIndex}) {
    final normalized = name.trim();
    for (int i = 0; i < _savedPapers.length; i++) {
      if (i == exceptIndex) continue;
      if (_savedPapers[i].name == normalized) return i;
    }
    return -1;
  }

  bool _isValidIndex(int index) => index >= 0 && index < _savedPapers.length;

  String _uniqueName(String preferred) {
    final base = preferred.trim().isEmpty ? '未命名纸张' : preferred.trim();
    if (indexOfName(base) == -1) return base;

    var counter = 2;
    while (indexOfName('$base $counter') != -1) {
      counter++;
    }
    return '$base $counter';
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
