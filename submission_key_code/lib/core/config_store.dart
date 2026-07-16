import 'package:shared_preferences/shared_preferences.dart';
import 'moonraker_config.dart';
import '../data/moonraker/moonraker_repository.dart';

class ConfigStore {
  static const _kHost = 'mr_host';
  static const _kPort = 'mr_port';
  static const _kApiKey = 'mr_api_key';
  static const _kUseHttps = 'mr_https';
  static const _kProfile = 'mr_profile';

  Future<void> save(MoonrakerConfig config, StatusProfile profile) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kHost, config.host);
    await sp.setInt(_kPort, config.port);
    await sp.setString(_kApiKey, config.apiKey ?? '');
    await sp.setBool(_kUseHttps, config.useHttps);
    await sp.setString(_kProfile, profile.name);
  }

  Future<(MoonrakerConfig, StatusProfile)?> load() async {
    final sp = await SharedPreferences.getInstance();
    final host = sp.getString(_kHost);
    final port = sp.getInt(_kPort);
    if (host == null || port == null) return null;

    final apiKey = sp.getString(_kApiKey) ?? '';
    final useHttps = sp.getBool(_kUseHttps) ?? false;
    final profileStr = sp.getString(_kProfile) ?? StatusProfile.basic.name;
    final profile = StatusProfile.values.firstWhere(
      (e) => e.name == profileStr,
      orElse: () => StatusProfile.basic,
    );

    final cfg = MoonrakerConfig(
      host: host,
      port: port,
      apiKey: apiKey.isEmpty ? null : apiKey,
      useHttps: useHttps,
    );
    return (cfg, profile);
  }
}