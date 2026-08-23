import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _serverSidebarCollapsedKey = 'server_sidebar_collapsed';

/// Shared persisted state for the server sidebars on the text and file pages.
class ServerSidebarCollapsedNotifier extends StateNotifier<bool> {
  ServerSidebarCollapsedNotifier() : super(false) {
    _load();
  }

  bool _changedBeforeLoad = false;

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!_changedBeforeLoad) {
        state = preferences.getBool(_serverSidebarCollapsedKey) ?? false;
      }
    } catch (_) {
      // Keep the default expanded state if preferences cannot be read.
    }
  }

  Future<void> setCollapsed(bool collapsed) async {
    _changedBeforeLoad = true;
    state = collapsed;

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_serverSidebarCollapsedKey, collapsed);
    } catch (_) {
      // The visual state still changes even if persistence is unavailable.
    }
  }
}

final serverSidebarCollapsedProvider =
    StateNotifierProvider<ServerSidebarCollapsedNotifier, bool>(
      (ref) => ServerSidebarCollapsedNotifier(),
    );
