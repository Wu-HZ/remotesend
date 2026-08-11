import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/config_provider.dart';
import '../providers/message_history_provider.dart';
import '../providers/webdav_provider.dart';
import '../util/theme_ext.dart';
import 'file_depot_screen.dart';
import 'settings_screen.dart';
import 'text_bridge_screen.dart';

/// Global provider for the currently selected tab index.
/// 0 = TextBridge, 1 = FileDepot, 2 = Settings.
final selectedTabProvider = StateProvider<int>((ref) => 0);

/// Main home screen with bottom navigation.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int get _selectedIndex => ref.watch(selectedTabProvider);

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(configProvider);
    final isConfigured = ref.watch(isConfiguredProvider);
    final l10n = AppLocalizations.of(context)!;

    return configAsync.when(
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('${l10n.failedToLoadConfig}\n$error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.read(configProvider.notifier).initialize();
                },
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
      ),
      data: (config) {
        // If not configured, go directly to settings screen
        if (!isConfigured && _selectedIndex != 2) {
          Future.microtask(() {
            ref.read(selectedTabProvider.notifier).state = 2;
          });
        }

        return _buildScaffold(l10n);
      },
    );
  }

  Widget _buildScaffold(AppLocalizations l10n) {
    // Use NavigationRail for wide windows, NavigationBar for narrow
    final width = MediaQuery.of(context).size.width;
    final useRail = width > 600;

    if (useRail) {
      final isWideDesktop = width >= 800;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: Theme.of(context).cardColorWithElevation,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                if (index != _selectedIndex) {
                  _refreshTab(index);
                }
                ref.read(selectedTabProvider.notifier).state = index;
              },
              extended: isWideDesktop,
              leading: isWideDesktop
                  ? Column(
                      children: [
                        const SizedBox(height: 20),
                        const Text(
                          'RemoteSend',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                      ],
                    )
                  : null,
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.text_fields_outlined),
                  selectedIcon: const Icon(Icons.text_fields),
                  label: Text(l10n.navText),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.folder_outlined),
                  selectedIcon: const Icon(Icons.folder),
                  label: Text(l10n.navFiles),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: Text(l10n.navSettings),
                ),
              ],
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      );
    }

    // Mobile layout with bottom navigation
    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index != _selectedIndex) {
            _refreshTab(index);
          }
          ref.read(selectedTabProvider.notifier).state = index;
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.text_fields_outlined),
            selectedIcon: const Icon(Icons.text_fields),
            label: l10n.navText,
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: const Icon(Icons.folder),
            label: l10n.navFiles,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }

  void _refreshTab(int index) {
    switch (index) {
      case 0:
        ref.read(messageHistoryProvider.notifier).refresh();
      case 1:
        try {
          ref.read(fileListProvider.notifier).refresh();
        } catch (_) {}
    }
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _selectedIndex,
      children: const [
        TextBridgeScreen(),
        FileDepotScreen(),
        SettingsScreen(),
      ],
    );
  }
}
