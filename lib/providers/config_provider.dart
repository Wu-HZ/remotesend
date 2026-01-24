import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_config.dart';
import '../services/config_service.dart';

/// Provider for the ConfigService singleton.
final configServiceProvider = Provider<ConfigService>((ref) {
  return ConfigService();
});

/// State notifier for managing app configuration.
class ConfigNotifier extends StateNotifier<AsyncValue<AppConfig>> {
  final ConfigService _configService;

  ConfigNotifier(this._configService) : super(const AsyncValue.loading());

  /// Initialize and load configuration.
  Future<void> initialize() async {
    state = const AsyncValue.loading();
    try {
      await _configService.initialize();
      final config = await _configService.loadConfig();
      state = AsyncValue.data(config);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Update and persist configuration.
  Future<bool> updateConfig(AppConfig newConfig) async {
    final previousState = state;

    try {
      state = AsyncValue.data(newConfig);
      final success = await _configService.saveConfig(newConfig);
      if (!success) {
        state = previousState;
        return false;
      }
      return true;
    } catch (e, st) {
      state = previousState;
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Enable portable mode (save config to JSON file).
  Future<bool> enablePortableMode() async {
    final currentConfig = state.valueOrNull;
    if (currentConfig == null) return false;

    try {
      final success = await _configService.enablePortableMode(currentConfig);
      if (success) {
        state = AsyncValue.data(currentConfig.copyWith(portableMode: true));
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  /// Disable portable mode (switch to SharedPreferences).
  Future<bool> disablePortableMode() async {
    final currentConfig = state.valueOrNull;
    if (currentConfig == null) return false;

    try {
      final success = await _configService.disablePortableMode(currentConfig);
      if (success) {
        state = AsyncValue.data(currentConfig.copyWith(portableMode: false));
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  /// Clear all configuration.
  Future<void> clearConfig() async {
    await _configService.clearConfig();
    state = const AsyncValue.data(AppConfig());
  }
}

/// Provider for the configuration state.
final configProvider =
    StateNotifierProvider<ConfigNotifier, AsyncValue<AppConfig>>((ref) {
  final configService = ref.watch(configServiceProvider);
  return ConfigNotifier(configService);
});

/// Convenience provider to check if config is ready and valid.
final isConfiguredProvider = Provider<bool>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.isConfigured,
    orElse: () => false,
  );
});

/// Provider for portable mode status.
final isPortableModeProvider = Provider<bool>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.portableMode,
    orElse: () => false,
  );
});

/// Provider to check if portable mode is available on current platform.
final portableModeAvailableProvider = Provider<bool>((ref) {
  final configService = ref.watch(configServiceProvider);
  return configService.portableConfigPath.isNotEmpty;
});
