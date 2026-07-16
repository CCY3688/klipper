/// 用户字体控制器
///
/// 管理所有用户字体档案的加载、创建、删除和激活，
/// 以及 TTF 导入进度状态。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../writing/font/stroke_font.dart';
import '../writing/user_font/user_font_loader.dart';
import '../writing/user_font/user_font_profile.dart';
import '../writing/user_font/user_stroke_font.dart';

/// 用户字体导入状态
enum ImportStatus { idle, importing, done, failed }

/// 用户字体控制器
class UserFontController extends ChangeNotifier {
  // ── 档案列表 ───────────────────────────────────────────────────────
  List<UserFontProfile> _profiles = [];
  List<UserFontProfile> get profiles => List.unmodifiable(_profiles);

  // ── 激活的档案 ID ──────────────────────────────────────────────────
  String? _activeProfileId;
  String? get activeProfileId => _activeProfileId;

  /// 当前激活的档案（null = 使用标准字体）
  UserFontProfile? get activeProfile =>
      _profiles.where((p) => p.id == _activeProfileId).firstOrNull;

  // ── 标准字体缓存（外部注入，用于回退）─────────────────────────────
  StrokeFont? _standardFont;

  /// 构建激活的 UserStrokeFont（含回退）
  UserStrokeFont? get activeUserFont {
    final p = activeProfile;
    if (p == null) return null;
    return UserStrokeFont(profile: p, fallback: _standardFont);
  }

  // ── 导入进度 ───────────────────────────────────────────────────────
  ImportStatus _importStatus = ImportStatus.idle;
  ImportStatus get importStatus => _importStatus;

  FontLoadProgress? _importProgress;
  FontLoadProgress? get importProgress => _importProgress;

  String? _importError;
  String? get importError => _importError;

  final UserFontLoader _loader = UserFontLoader();

  // ─────────────────────────────────────────────────────────────────────
  // 初始化
  // ─────────────────────────────────────────────────────────────────────

  UserFontController() {
    _init();
  }

  Future<void> _init() async {
    _profiles = await UserFontProfile.loadAll();
    _activeProfileId = _defaultActiveProfileId(_profiles);
    notifyListeners();
  }

  String? _defaultActiveProfileId(List<UserFontProfile> profiles) {
    UserFontProfile? preferred;
    for (final profile in profiles) {
      final sourceName = profile.sourceFontFileName?.toLowerCase().trim();
      final displayName = profile.name.toLowerCase().trim();
      if ((sourceName?.contains('wo de zi ti') ?? false) ||
          displayName.contains('wo de zi ti')) {
        preferred = profile;
        break;
      }
    }
    return preferred?.id;
  }

  /// 注入标准字体（由上层在字体加载完成时调用）
  void setStandardFont(StrokeFont font) {
    _standardFont = font;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────
  // 档案管理
  // ─────────────────────────────────────────────────────────────────────

  /// 激活指定档案（传 null = 使用标准字体）
  void setActiveProfile(String? profileId) {
    _activeProfileId = profileId;
    notifyListeners();
  }

  /// 删除档案
  Future<void> deleteProfile(String profileId) async {
    final profile = _profiles.where((p) => p.id == profileId).firstOrNull;
    if (profile == null) return;

    await profile.delete();
    _profiles.removeWhere((p) => p.id == profileId);

    if (_activeProfileId == profileId) {
      _activeProfileId = null;
    }
    notifyListeners();
  }

  /// 重命名档案
  Future<void> renameProfile(String profileId, String newName) async {
    final profile = _profiles.where((p) => p.id == profileId).firstOrNull;
    if (profile == null) return;
    profile.name = newName;
    await profile.save();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────
  // TTF 导入
  // ─────────────────────────────────────────────────────────────────────

  /// 从 TTF 文件导入字体
  Future<UserFontProfile?> importFromTtf({
    required File ttfFile,
    required String profileName,
  }) async {
    if (_importStatus == ImportStatus.importing) return null;

    _importStatus = ImportStatus.importing;
    _importProgress = null;
    _importError = null;
    notifyListeners();

    try {
      final profile = await _loader.loadFromTtf(
        ttfFile: ttfFile,
        profileName: profileName,
        onProgress: (progress) {
          _importProgress = progress;
          notifyListeners();
        },
      );

      _profiles.insert(0, profile);
      _activeProfileId = profile.id;
      _importStatus = ImportStatus.done;
      notifyListeners();
      return profile;
    } catch (e) {
      _importStatus = ImportStatus.failed;
      _importError = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// 取消导入
  void cancelImport() {
    _loader.cancel();
    _importStatus = ImportStatus.idle;
    notifyListeners();
  }

  /// 重置导入状态
  void resetImportStatus() {
    _importStatus = ImportStatus.idle;
    _importProgress = null;
    _importError = null;
    notifyListeners();
  }
}
