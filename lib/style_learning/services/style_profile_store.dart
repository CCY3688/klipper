import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/style_params.dart';

class SavedStyleProfile {
  final StyleParams params;
  final String templateName;
  final int sampleCount;
  final DateTime savedAt;

  const SavedStyleProfile({
    required this.params,
    required this.templateName,
    required this.sampleCount,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'params': params.toJson(),
        'templateName': templateName,
        'sampleCount': sampleCount,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedStyleProfile.fromJson(Map<String, dynamic> json) {
    return SavedStyleProfile(
      params: StyleParams.fromJson(
        Map<String, dynamic>.from((json['params'] as Map?) ?? const {}),
      ),
      templateName: (json['templateName'] as String?) ?? '未命名模板',
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      savedAt: DateTime.tryParse((json['savedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class StyleProfileStore {
  static const _latestProfileKey = 'style_learning.latest_profile';

  Future<void> saveLatest(SavedStyleProfile profile) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_latestProfileKey, jsonEncode(profile.toJson()));
  }

  Future<SavedStyleProfile?> loadLatest() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_latestProfileKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SavedStyleProfile.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
