import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_config.dart';
import '../models/server_config.dart';

/// Service for managing app configuration with portable mode support.
///
/// On Windows, checks for config.json next to executable for portable mode.
/// Falls back to SharedPreferences for non-portable storage.
class ConfigService {
  static const String _configFileName = 'config.json';
  static const String _prefsKeyConfig = 'config_v2';
  // Legacy keys for v1 migration
  static const String _prefsKeyServerUrl = 'serverUrl';
  static const String _prefsKeyUsername = 'username';
  static const String _prefsKeyPassword = 'password';
  static const String _prefsKeyPortableMode = 'portableMode';

  File? _portableConfigFile;
  SharedPreferences? _prefs;

  /// Get the path to the portable config file (next to executable on Windows).
  String get portableConfigPath {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final executableDir = p.dirname(Platform.resolvedExecutable);
      return p.join(executableDir, _configFileName);
    }
    // On mobile, portable mode is not supported
    return '';
  }

  /// Check if portable config file exists.
  bool get hasPortableConfig {
    if (portableConfigPath.isEmpty) return false;
    return File(portableConfigPath).existsSync();
  }

  /// Initialize the config service.
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    if (portableConfigPath.isNotEmpty) {
      _portableConfigFile = File(portableConfigPath);
    }
  }

  /// Load configuration from storage.
  ///
  /// Priority:
  /// 1. If portable config.json exists, load from there
  /// 2. Otherwise, load from SharedPreferences
  Future<AppConfig> loadConfig() async {
    // Try portable config first (desktop platforms)
    if (_portableConfigFile != null && _portableConfigFile!.existsSync()) {
      try {
        final content = await _portableConfigFile!.readAsString();
        final config = AppConfig.fromJsonString(content);
        // Migration may have occurred, save the new format
        if (config.version == AppConfig.currentVersion) {
          await _saveToPortableFile(config.copyWith(portableMode: true));
        }
        return config.copyWith(portableMode: true);
      } catch (e) {
        // If portable config is corrupted, fall back to prefs
        // but don't delete the file - let user handle it
      }
    }

    // Fall back to SharedPreferences
    return _loadFromPrefs();
  }

  /// Save configuration to storage.
  ///
  /// If portableMode is true, saves to config.json next to executable.
  /// Otherwise, saves to SharedPreferences.
  Future<bool> saveConfig(AppConfig config) async {
    if (config.portableMode && _portableConfigFile != null) {
      return _saveToPortableFile(config);
    } else {
      return _saveToPrefs(config);
    }
  }

  /// Create a new portable config file.
  Future<bool> enablePortableMode(AppConfig config) async {
    if (_portableConfigFile == null) {
      return false; // Not supported on this platform
    }

    final newConfig = config.copyWith(portableMode: true);
    final success = await _saveToPortableFile(newConfig);

    if (success) {
      // Clear SharedPreferences when switching to portable
      await _clearPrefs();
    }

    return success;
  }

  /// Delete portable config and switch to SharedPreferences.
  Future<bool> disablePortableMode(AppConfig config) async {
    if (_portableConfigFile == null) {
      return false;
    }

    // Save to SharedPreferences first
    final newConfig = config.copyWith(portableMode: false);
    final success = await _saveToPrefs(newConfig);

    if (success && _portableConfigFile!.existsSync()) {
      try {
        await _portableConfigFile!.delete();
      } catch (e) {
        // Failed to delete portable config, but prefs are saved
      }
    }

    return success;
  }

  /// Clear all stored configuration.
  Future<void> clearConfig() async {
    await _clearPrefs();

    if (_portableConfigFile != null && _portableConfigFile!.existsSync()) {
      try {
        await _portableConfigFile!.delete();
      } catch (e) {
        // Ignore deletion errors
      }
    }
  }

  // Private methods

  AppConfig _loadFromPrefs() {
    final prefs = _prefs;
    if (prefs == null) return AppConfig();

    // Try to load v2 config first
    final configJson = prefs.getString(_prefsKeyConfig);
    if (configJson != null) {
      try {
        return AppConfig.fromJsonString(configJson);
      } catch (e) {
        // Fall through to v1 migration
      }
    }

    // Check for v1 config (legacy keys)
    final hasV1Config = prefs.containsKey(_prefsKeyServerUrl) ||
        prefs.containsKey(_prefsKeyUsername);
    if (hasV1Config) {
      return _migrateFromPrefsV1(prefs);
    }

    return AppConfig();
  }

  AppConfig _migrateFromPrefsV1(SharedPreferences prefs) {
    final serverUrl = prefs.getString(_prefsKeyServerUrl) ?? '';
    final username = prefs.getString(_prefsKeyUsername) ?? '';
    final password = prefs.getString(_prefsKeyPassword) ?? '';
    final portableMode = prefs.getBool(_prefsKeyPortableMode) ?? false;

    List<ServerConfig> servers = [];
    String? activeServerId;

    if (serverUrl.isNotEmpty || username.isNotEmpty) {
      String name = 'My Server';
      if (serverUrl.isNotEmpty) {
        try {
          final uri = Uri.parse(serverUrl);
          name = uri.host.isNotEmpty ? uri.host : 'My Server';
        } catch (e) {
          name = 'My Server';
        }
      }

      final server = ServerConfig.create(
        name: name,
        serverUrl: serverUrl,
        username: username,
        password: password,
      );
      servers = [server];
      activeServerId = server.id;
    }

    final config = AppConfig(
      version: AppConfig.currentVersion,
      servers: servers,
      activeTextServerId: activeServerId,
      activeFilesServerId: activeServerId,
      portableMode: portableMode,
    );

    // Save migrated config and clean up legacy keys
    _saveToPrefs(config);
    _cleanupLegacyPrefsKeys(prefs);

    return config;
  }

  Future<void> _cleanupLegacyPrefsKeys(SharedPreferences prefs) async {
    await prefs.remove(_prefsKeyServerUrl);
    await prefs.remove(_prefsKeyUsername);
    await prefs.remove(_prefsKeyPassword);
    await prefs.remove(_prefsKeyPortableMode);
  }

  Future<bool> _saveToPrefs(AppConfig config) async {
    final prefs = _prefs;
    if (prefs == null) return false;

    try {
      await prefs.setString(_prefsKeyConfig, config.toJsonString());
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _saveToPortableFile(AppConfig config) async {
    if (_portableConfigFile == null) return false;

    try {
      await _portableConfigFile!.writeAsString(config.toJsonString());
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _clearPrefs() async {
    final prefs = _prefs;
    if (prefs == null) return;

    await prefs.remove(_prefsKeyConfig);
    // Also clean up any legacy keys
    await prefs.remove(_prefsKeyServerUrl);
    await prefs.remove(_prefsKeyUsername);
    await prefs.remove(_prefsKeyPassword);
    await prefs.remove(_prefsKeyPortableMode);
  }
}
