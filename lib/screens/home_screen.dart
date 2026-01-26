import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/config_provider.dart';
import 'file_depot_screen.dart';
import 'settings_screen.dart';
import 'text_bridge_screen.dart';

/// Main home screen with bottom navigation.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

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
            setState(() => _selectedIndex = 2);
          });
        }

        return _buildScaffold(l10n);
      },
    );
  }

  Widget _buildScaffold(AppLocalizations l10n) {
    // Use NavigationRail for desktop, NavigationBar for mobile
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final width = MediaQuery.of(context).size.width;
    final useRail = isDesktop && width > 600;

    if (useRail) {
      // Desktop layout with side rail
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              labelType: NavigationRailLabelType.all,
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
            const VerticalDivider(thickness: 1, width: 1),
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
          setState(() => _selectedIndex = index);
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

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const TextBridgeScreen();
      case 1:
        return const FileDepotScreen();
      case 2:
        return const SettingsScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}
