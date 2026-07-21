import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_config.dart';
import '../models/server_config.dart';
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

  /// Add a new server to the configuration.
  Future<bool> addServer(ServerConfig server) async {
    final currentConfig = state.valueOrNull;
    if (currentConfig == null) return false;

    final updatedServers = [...currentConfig.servers, server];
    final newConfig = currentConfig.copyWith(
      servers: updatedServers,
      // If this is the first server, make it active for both text and files
      activeTextServerId: currentConfig.activeTextServerId ?? server.id,
      activeFilesServerId: currentConfig.activeFilesServerId ?? server.id,
    );

    return updateConfig(newConfig);
  }

  /// Update an existing server configuration.
  Future<bool> updateServer(ServerConfig server) async {
    final currentConfig = state.valueOrNull;
    if (currentConfig == null) return false;

    final updatedServers = currentConfig.servers.map((s) {
      return s.id == server.id ? server : s;
    }).toList();

    final newConfig = currentConfig.copyWith(servers: updatedServers);
    return updateConfig(newConfig);
  }

  /// Delete a server from the configuration.
  Future<bool> deleteServer(String serverId) async {
    final currentConfig = state.valueOrNull;
    if (currentConfig == null) return false;

    final updatedServers = currentConfig.servers
        .where((s) => s.id != serverId)
        .toList();

    // If deleting the active text server, select another one
    String? newTextServerId = currentConfig.activeTextServerId;
    if (currentConfig.activeTextServerId == serverId) {
      newTextServerId = updatedServers.isNotEmpty ? updatedServers.first.id : null;
    }

    // If deleting the active files server, select another one
    String? newFilesServerId = currentConfig.activeFilesServerId;
    if (currentConfig.activeFilesServerId == serverId) {
      newFilesServerId = updatedServers.isNotEmpty ? updatedServers.first.id : null;
    }

    final newConfig = currentConfig.copyWithNullActiveServers(
      servers: updatedServers,
      clearText: newTextServerId == null,
      clearFiles: newFilesServerId == null,
    ).copyWith(
      activeTextServerId: newTextServerId,
      activeFilesServerId: newFilesServerId,
    );

    return updateConfig(newConfig);
  }

  /// Switch the active server for Text Bridge.
  Future<bool> switchTextServer(String serverId) async {
    final currentConfig = state.valueOrNull;
    if (currentConfig == null) return false;

    // Verify the server exists
    final serverExists = currentConfig.servers.any((s) => s.id == serverId);
    if (!serverExists) return false;

    // Update lastUsed timestamp for the server
    final updatedServers = currentConfig.servers.map((s) {
      if (s.id == serverId) {
        return s.copyWith(lastUsed: DateTime.now());
      }
      return s;
    }).toList();

    final newConfig = currentConfig.copyWith(
      servers: updatedServers,
      activeTextServerId: serverId,
    );

    return updateConfig(newConfig);
  }

  /// Switch the active server for File Depot.
  Future<bool> switchFilesServer(String serverId) async {
    final currentConfig = state.valueOrNull;
    if (currentConfig == null) return false;

    // Verify the server exists
    final serverExists = currentConfig.servers.any((s) => s.id == serverId);
    if (!serverExists) return false;

    // Update lastUsed timestamp for the server
    final updatedServers = currentConfig.servers.map((s) {
      if (s.id == serverId) {
        return s.copyWith(lastUsed: DateTime.now());
      }
      return s;
    }).toList();

    final newConfig = currentConfig.copyWith(
      servers: updatedServers,
      activeFilesServerId: serverId,
    );

    return updateConfig(newConfig);
  }

  /// Set server for a specific feature (text or files).
  Future<bool> setServerForFeature(String serverId, {required bool forText, required bool forFiles}) async {
    final currentConfig = state.valueOrNull;
    if (currentConfig == null) return false;

    // Verify the server exists
    final serverExists = currentConfig.servers.any((s) => s.id == serverId);
    if (!serverExists) return false;

    final newConfig = currentConfig.copyWith(
      activeTextServerId: forText ? serverId : currentConfig.activeTextServerId,
      activeFilesServerId: forFiles ? serverId : currentConfig.activeFilesServerId,
    );

    return updateConfig(newConfig);
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
    state = AsyncValue.data(AppConfig());
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

/// Provider for the list of all configured servers.
final serversListProvider = Provider<List<ServerConfig>>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.servers,
    orElse: () => [],
  );
});

/// Provider for the active server for Text Bridge.
final activeTextServerProvider = Provider<ServerConfig?>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.activeTextServer,
    orElse: () => null,
  );
});

/// Provider for the active server for File Depot.
final activeFilesServerProvider = Provider<ServerConfig?>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.activeFilesServer,
    orElse: () => null,
  );
});

/// Provider for the currently active server (backward-compatible, defaults to text).
final activeServerProvider = Provider<ServerConfig?>((ref) {
  return ref.watch(activeTextServerProvider);
});

/// Provider to check if text is configured.
final isTextConfiguredProvider = Provider<bool>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.isTextConfigured,
    orElse: () => false,
  );
});

/// Provider to check if files is configured.
final isFilesConfiguredProvider = Provider<bool>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.isFilesConfigured,
    orElse: () => false,
  );
});

/// Provider for the current theme mode ('system', 'light', 'dark').
final themeModeProvider = Provider<String>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.themeMode,
    orElse: () => 'system',
  );
});

/// Provider for the primary color as int.
final primaryColorProvider = Provider<int>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.primaryColor,
    orElse: () => 0xFF009688, // Default teal
  );
});

/// Provider for whether to use dynamic color.
final useDynamicColorProvider = Provider<bool>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.useDynamicColor,
    orElse: () => true,
  );
});

/// Provider for the current locale ('system', 'en', 'zh').
final localeProvider = Provider<String>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.locale,
    orElse: () => 'system',
  );
});
