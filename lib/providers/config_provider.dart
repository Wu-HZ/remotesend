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
      // If this is the first server, make it active
      activeServerId: currentConfig.activeServerId ?? server.id,
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

    // If deleting the active server, select another one
    String? newActiveServerId = currentConfig.activeServerId;
    if (currentConfig.activeServerId == serverId) {
      newActiveServerId = updatedServers.isNotEmpty ? updatedServers.first.id : null;
    }

    final newConfig = newActiveServerId != null
        ? currentConfig.copyWith(
            servers: updatedServers,
            activeServerId: newActiveServerId,
          )
        : currentConfig.copyWithNullActiveServer(servers: updatedServers);

    return updateConfig(newConfig);
  }

  /// Switch to a different active server.
  Future<bool> switchServer(String serverId) async {
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
      activeServerId: serverId,
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

/// Provider for the list of all configured servers.
final serversListProvider = Provider<List<ServerConfig>>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.servers,
    orElse: () => [],
  );
});

/// Provider for the currently active server.
final activeServerProvider = Provider<ServerConfig?>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.activeServer,
    orElse: () => null,
  );
});
