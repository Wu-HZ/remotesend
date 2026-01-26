import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../providers/config_provider.dart';
import '../providers/webdav_provider.dart';
import '../services/webdav_service.dart';

/// Settings screen with Connection, General, Download, and Others sections.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isSaving = false;

  // Settings
  late double _refreshInterval;
  String _downloadLocation = '';
  bool _autoDownload = false;
  bool _showNotification = true;

  @override
  void initState() {
    super.initState();
    _refreshInterval = 3.0;
    Future.microtask(_loadConfig);
  }

  void _loadConfig() async {
    final config = ref.read(configProvider).valueOrNull;
    if (config != null) {
      setState(() {
        _refreshInterval = config.refreshIntervalSeconds.toDouble();
        _downloadLocation = config.downloadLocation;
      });
    }
    // If no download location set, get system default
    if (_downloadLocation.isEmpty) {
      final defaultPath = await _getSystemDownloadDirectory();
      if (mounted && defaultPath != null) {
        setState(() => _downloadLocation = defaultPath);
      }
    }
  }

  Future<String?> _getSystemDownloadDirectory() async {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        return p.join(userProfile, 'Downloads');
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return p.join(home, 'Downloads');
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connection Section
          _buildConnectionSection(l10n),
          const SizedBox(height: 24),

          // General Section
          _buildGeneralSection(l10n),
          const SizedBox(height: 24),

          // Download Section
          _buildDownloadSection(l10n),
          const SizedBox(height: 24),

          // Others Section
          _buildOthersSection(l10n),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==================== Connection Section ====================
  Widget _buildConnectionSection(AppLocalizations l10n) {
    final textConnectionStatus = ref.watch(textConnectionStatusProvider);
    final filesConnectionStatus = ref.watch(filesConnectionStatusProvider);
    final isPortableAvailable = ref.watch(portableModeAvailableProvider);
    final isPortableMode = ref.watch(isPortableModeProvider);
    final configService = ref.watch(configServiceProvider);
    final servers = ref.watch(serversListProvider);
    final textServer = ref.watch(activeTextServerProvider);
    final filesServer = ref.watch(activeFilesServerProvider);

    return _SettingsSection(
      title: l10n.sectionConnection,
      icon: Icons.cloud,
      children: [
        // Connection Status Card
        _buildConnectionStatusCard(l10n, textConnectionStatus, filesConnectionStatus, textServer, filesServer),
        const SizedBox(height: 16),

        // Configured Servers Section
        Row(
          children: [
            Text(
              l10n.configuredServers,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            Text(
              l10n.longPressToEditDelete,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (servers.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(100),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withAlpha(50),
              ),
            ),
            child: Center(
              child: Text(
                l10n.noServersConfigured,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...servers.map((server) => _buildServerTile(l10n, server, null)),

        const SizedBox(height: 12),

        // Add Server Button
        OutlinedButton.icon(
          onPressed: () => _showServerDialog(l10n),
          icon: const Icon(Icons.add),
          label: Text(l10n.addServer),
        ),

        // Local Name Setting
        const Divider(height: 32),
        _buildLocalNameTile(l10n),

        // Portable Mode (desktop only)
        if (isPortableAvailable) ...[
          const Divider(height: 32),
          SwitchListTile(
            title: Text(l10n.portableMode),
            subtitle: Text(
              isPortableMode
                  ? l10n.portableModeConfig(configService.portableConfigPath)
                  : l10n.portableModeDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            secondary: const Icon(Icons.usb),
            value: isPortableMode,
            onChanged: _isSaving ? null : (value) => _togglePortableMode(l10n, value),
          ),
        ],

        // Refresh Interval
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.timer),
          title: Text(l10n.refreshInterval),
          subtitle: Text(l10n.refreshIntervalSeconds(_refreshInterval.toInt())),
          contentPadding: EdgeInsets.zero,
        ),
        Slider(
          value: _refreshInterval,
          min: 1,
          max: 10,
          divisions: 9,
          label: '${_refreshInterval.toInt()}s',
          onChanged: (value) {
            setState(() => _refreshInterval = value);
          },
          onChangeEnd: (value) {
            _saveRefreshInterval(value.toInt());
          },
        ),
        Text(
          l10n.refreshIntervalDescription,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }

  Widget _buildServerTile(AppLocalizations l10n, ServerConfig server, ServerConfig? activeServer) {
    final config = ref.watch(configProvider).valueOrNull;
    final isTextServer = config?.activeTextServerId == server.id;
    final isFilesServer = config?.activeFilesServerId == server.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onLongPress: () => _showServerActions(l10n, server),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Server info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: TextStyle(
                        fontWeight: (isTextServer || isFilesServer) ? FontWeight.bold : FontWeight.normal,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server.serverUrl,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
              // Text/Files toggle buttons
              const SizedBox(width: 8),
              _buildFeatureToggle(
                label: l10n.textLabel,
                isSelected: isTextServer,
                onTap: () => _setServerForFeature(server.id, forText: true),
              ),
              const SizedBox(width: 4),
              _buildFeatureToggle(
                label: l10n.filesLabel,
                isSelected: isFilesServer,
                onTap: () => _setServerForFeature(server.id, forFiles: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureToggle({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline.withAlpha(50),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  void _showServerActions(AppLocalizations l10n, ServerConfig server) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(l10n.edit),
              onTap: () {
                Navigator.pop(sheetContext);
                _showServerDialog(l10n, server: server);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDeleteServer(l10n, server);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setServerForFeature(String serverId, {bool forText = false, bool forFiles = false}) async {
    setState(() => _isSaving = true);

    try {
      final success = await ref.read(configProvider.notifier).setServerForFeature(
            serverId,
            forText: forText,
            forFiles: forFiles,
          );

      if (success && mounted) {
        // Test connection for the updated service
        if (forText) {
          ref.read(textConnectionStatusProvider.notifier).testConnection();
        }
        if (forFiles) {
          ref.read(filesConnectionStatusProvider.notifier).testConnection();
        }
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildConnectionStatusCard(AppLocalizations l10n, ConnectionStatus textStatus, ConnectionStatus filesStatus, ServerConfig? textServer, ServerConfig? filesServer) {
    return Column(
      children: [
        _buildSingleConnectionStatus(l10n, l10n.textLabel, textStatus, textServer),
        const SizedBox(height: 8),
        _buildSingleConnectionStatus(l10n, l10n.filesLabel, filesStatus, filesServer),
      ],
    );
  }

  Widget _buildSingleConnectionStatus(AppLocalizations l10n, String label, ConnectionStatus status, ServerConfig? server) {
    Color color;
    IconData icon;
    String text;

    switch (status.state) {
      case WebDavConnectionState.connected:
        color = Colors.green;
        icon = Icons.check_circle;
        text = server != null ? server.name : l10n.connectionStatusConnected;
      case WebDavConnectionState.connecting:
        color = Colors.blue;
        icon = Icons.sync;
        text = l10n.connectionStatusConnecting;
      case WebDavConnectionState.error:
        color = Colors.red;
        icon = Icons.error;
        text = status.errorMessage ?? l10n.connectionStatusError;
      case WebDavConnectionState.disconnected:
        color = Colors.grey;
        icon = Icons.cloud_off;
        text = l10n.connectionStatusDisconnected;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalNameTile(AppLocalizations l10n) {
    final config = ref.watch(configProvider).valueOrNull;
    final localName = config?.localName ?? 'Unknown';

    return ListTile(
      leading: const Icon(Icons.person),
      title: Text(l10n.localName),
      subtitle: Text(localName),
      trailing: const Icon(Icons.edit),
      contentPadding: EdgeInsets.zero,
      onTap: () => _showLocalNameDialog(l10n, localName),
    );
  }

  void _showLocalNameDialog(AppLocalizations l10n, String currentName) {
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.localName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.localNameDescription,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: l10n.localName,
                hintText: l10n.localNameHint,
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;

              Navigator.pop(dialogContext);

              final config = ref.read(configProvider).valueOrNull;
              if (config != null) {
                final newConfig = config.copyWith(localName: newName);
                final success = await ref.read(configProvider.notifier).updateConfig(newConfig);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? l10n.nameUpdated : l10n.failedToSave),
                      backgroundColor: success ? Colors.green : Colors.red,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  // ==================== General Section ====================
  Widget _buildGeneralSection(AppLocalizations l10n) {
    final config = ref.watch(configProvider).valueOrNull;
    final themeMode = config?.themeMode ?? 'system';
    final primaryColor = config?.primaryColor ?? 0xFF2196F3;
    final useDynamicColor = config?.useDynamicColor ?? true;

    String themeModeText;
    switch (themeMode) {
      case 'light':
        themeModeText = l10n.themeLight;
      case 'dark':
        themeModeText = l10n.themeDark;
      default:
        themeModeText = l10n.themeSystem;
    }

    return _SettingsSection(
      title: l10n.sectionGeneral,
      icon: Icons.tune,
      children: [
        ListTile(
          leading: const Icon(Icons.brightness_6),
          title: Text(l10n.theme),
          subtitle: Text(themeModeText),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showThemeDialog(l10n),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome),
          title: Text(l10n.dynamicColor),
          subtitle: Text(l10n.dynamicColorDescription),
          value: useDynamicColor,
          onChanged: (value) => _saveDynamicColor(value),
        ),
        ListTile(
          leading: const Icon(Icons.palette),
          title: Text(l10n.color),
          subtitle: Text(useDynamicColor ? l10n.usingSystemColor : _getColorName(l10n, primaryColor)),
          trailing: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(primaryColor),
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withAlpha(100),
              ),
            ),
          ),
          enabled: !useDynamicColor,
          onTap: useDynamicColor ? null : () => _showColorPicker(l10n),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(l10n.language),
          subtitle: Text(_getLanguageName(l10n, config?.locale ?? 'system')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showLanguageDialog(l10n),
        ),
      ],
    );
  }

  String _getLanguageName(AppLocalizations l10n, String locale) {
    switch (locale) {
      case 'en':
        return l10n.languageEnglish;
      case 'zh':
        return l10n.languageChinese;
      default:
        return l10n.themeSystem;
    }
  }

  String _getColorName(AppLocalizations l10n, int colorValue) {
    final colorNames = {
      0xFF2196F3: l10n.colorBlue,
      0xFFF44336: l10n.colorRed,
      0xFF4CAF50: l10n.colorGreen,
      0xFFFF9800: l10n.colorOrange,
      0xFF9C27B0: l10n.colorPurple,
      0xFF00BCD4: l10n.colorCyan,
      0xFFE91E63: l10n.colorPink,
      0xFF009688: l10n.colorTeal,
      0xFF3F51B5: l10n.colorIndigo,
      0xFFFFEB3B: l10n.colorYellow,
      0xFF795548: l10n.colorBrown,
      0xFF607D8B: l10n.colorBlueGrey,
    };
    return colorNames[colorValue] ?? l10n.colorCustom;
  }

  // ==================== Download Section ====================
  Widget _buildDownloadSection(AppLocalizations l10n) {
    final displayPath = _downloadLocation.isNotEmpty
        ? _downloadLocation
        : l10n.systemDefault;

    return _SettingsSection(
      title: l10n.sectionDownload,
      icon: Icons.download,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.sync),
          title: Text(l10n.autoDownload),
          subtitle: Text(l10n.autoDownloadDescription),
          value: _autoDownload,
          onChanged: (value) {
            setState(() => _autoDownload = value);
            _showComingSoon(l10n, l10n.autoDownload);
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder),
          title: Text(l10n.downloadLocation),
          subtitle: Text(
            displayPath,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickDownloadLocation(l10n),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications),
          title: Text(l10n.showNotification),
          subtitle: Text(l10n.showNotificationDescription),
          value: _showNotification,
          onChanged: (value) {
            setState(() => _showNotification = value);
            _showComingSoon(l10n, l10n.showNotification);
          },
        ),
      ],
    );
  }

  Future<void> _pickDownloadLocation(AppLocalizations l10n) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l10n.selectDownloadLocation,
      initialDirectory: _downloadLocation.isNotEmpty ? _downloadLocation : null,
    );

    if (result != null) {
      setState(() => _downloadLocation = result);
      await _saveDownloadLocation(l10n, result);
    }
  }

  Future<void> _saveDownloadLocation(AppLocalizations l10n, String path) async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    if (currentConfig == null) return;

    final newConfig = currentConfig.copyWith(downloadLocation: path);
    final success = await ref.read(configProvider.notifier).updateConfig(newConfig);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? l10n.downloadLocationUpdated : l10n.failedToSave),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ==================== Others Section ====================
  Widget _buildOthersSection(AppLocalizations l10n) {
    return _SettingsSection(
      title: l10n.sectionOthers,
      icon: Icons.more_horiz,
      children: [
        ListTile(
          leading: const Icon(Icons.info),
          title: Text(l10n.about),
          subtitle: Text(l10n.aboutDescription),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAboutDialog(l10n),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: Text(l10n.sourceCode),
          subtitle: Text(l10n.sourceCodeUrl),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _showComingSoon(l10n, l10n.openGitHub),
        ),
        ListTile(
          leading: const Icon(Icons.favorite),
          title: Text(l10n.donation),
          subtitle: Text(l10n.donationDescription),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showComingSoon(l10n, l10n.donation),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip),
          title: Text(l10n.privacyPolicy),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showComingSoon(l10n, l10n.privacyPolicy),
        ),
      ],
    );
  }

  // ==================== Server Management Actions ====================
  void _showServerDialog(AppLocalizations l10n, {ServerConfig? server}) {
    showDialog(
      context: context,
      builder: (dialogContext) => _ServerEditDialog(
        l10n: l10n,
        server: server,
        onSave: (newServer) async {
          bool success;
          if (server == null) {
            success = await ref.read(configProvider.notifier).addServer(newServer);
          } else {
            success = await ref.read(configProvider.notifier).updateServer(newServer);
          }

          if (success && mounted) {
            // Test connections for servers that use this config
            final config = ref.read(configProvider).valueOrNull;
            if (config != null) {
              if (config.activeTextServerId == newServer.id) {
                ref.read(textConnectionStatusProvider.notifier).testConnection();
              }
              if (config.activeFilesServerId == newServer.id) {
                ref.read(filesConnectionStatusProvider.notifier).testConnection();
              }
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success
                    ? (server == null ? l10n.serverAdded : l10n.serverUpdated)
                    : l10n.failedToSaveServer),
                backgroundColor: success ? Colors.green : Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  void _confirmDeleteServer(AppLocalizations l10n, ServerConfig server) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteServer),
        content: Text(l10n.deleteServerConfirm(server.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await ref.read(configProvider.notifier).deleteServer(server.id);

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? l10n.serverDeleted : l10n.failedToDelete),
                  backgroundColor: success ? Colors.green : Colors.red,
                  duration: const Duration(seconds: 2),
                ),
              );

              // Test connections with new active servers (if any)
              if (success) {
                final config = ref.read(configProvider).valueOrNull;
                if (config != null) {
                  if (config.activeTextServer != null) {
                    ref.read(textConnectionStatusProvider.notifier).testConnection();
                  }
                  if (config.activeFilesServer != null) {
                    ref.read(filesConnectionStatusProvider.notifier).testConnection();
                  }
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  // ==================== Other Actions ====================
  Future<void> _saveRefreshInterval(int seconds) async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    if (currentConfig == null) return;

    final newConfig = currentConfig.copyWith(refreshIntervalSeconds: seconds);
    final success = await ref.read(configProvider.notifier).updateConfig(newConfig);

    if (success) {
      // Update auto-pull interval if it's running
      ref.read(autoPullProvider.notifier).updateRefreshInterval(seconds);
    }
  }

  Future<void> _togglePortableMode(AppLocalizations l10n, bool enable) async {
    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(configProvider.notifier);
      final success = enable
          ? await notifier.enablePortableMode()
          : await notifier.disablePortableMode();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? (enable ? l10n.portableModeEnabled : l10n.portableModeDisabled)
                  : l10n.failedToChangePortableMode,
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showThemeDialog(AppLocalizations l10n) {
    final config = ref.read(configProvider).valueOrNull;
    final currentTheme = config?.themeMode ?? 'system';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.theme),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: Text(l10n.themeSystem),
              value: 'system',
              groupValue: currentTheme,
              onChanged: (value) {
                Navigator.pop(dialogContext);
                _saveThemeMode(value!);
              },
            ),
            RadioListTile<String>(
              title: Text(l10n.themeLight),
              value: 'light',
              groupValue: currentTheme,
              onChanged: (value) {
                Navigator.pop(dialogContext);
                _saveThemeMode(value!);
              },
            ),
            RadioListTile<String>(
              title: Text(l10n.themeDark),
              value: 'dark',
              groupValue: currentTheme,
              onChanged: (value) {
                Navigator.pop(dialogContext);
                _saveThemeMode(value!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveThemeMode(String themeMode) async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    if (currentConfig == null) return;

    final newConfig = currentConfig.copyWith(themeMode: themeMode);
    await ref.read(configProvider.notifier).updateConfig(newConfig);
  }

  void _showColorPicker(AppLocalizations l10n) {
    final config = ref.read(configProvider).valueOrNull;
    final currentColor = config?.primaryColor ?? 0xFF2196F3;

    // Predefined Material colors
    final colors = [
      0xFF2196F3, // Blue
      0xFFF44336, // Red
      0xFF4CAF50, // Green
      0xFFFF9800, // Orange
      0xFF9C27B0, // Purple
      0xFF00BCD4, // Cyan
      0xFFE91E63, // Pink
      0xFF009688, // Teal
      0xFF3F51B5, // Indigo
      0xFFFFEB3B, // Yellow
      0xFF795548, // Brown
      0xFF607D8B, // Blue Grey
    ];

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.chooseColor),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((colorValue) {
              final isSelected = colorValue == currentColor;
              return GestureDetector(
                onTap: () {
                  Navigator.pop(dialogContext);
                  _savePrimaryColor(colorValue);
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color(colorValue),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(colorValue).withAlpha(100),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: _getContrastColor(Color(colorValue)),
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  Color _getContrastColor(Color color) {
    // Calculate luminance and return black or white for best contrast
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  Future<void> _savePrimaryColor(int colorValue) async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    if (currentConfig == null) return;

    final newConfig = currentConfig.copyWith(primaryColor: colorValue);
    await ref.read(configProvider.notifier).updateConfig(newConfig);
  }

  Future<void> _saveDynamicColor(bool useDynamicColor) async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    if (currentConfig == null) return;

    final newConfig = currentConfig.copyWith(useDynamicColor: useDynamicColor);
    await ref.read(configProvider.notifier).updateConfig(newConfig);
  }

  void _showLanguageDialog(AppLocalizations l10n) {
    final config = ref.read(configProvider).valueOrNull;
    final currentLocale = config?.locale ?? 'system';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.language),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: Text(l10n.themeSystem),
              value: 'system',
              groupValue: currentLocale,
              onChanged: (value) {
                Navigator.pop(dialogContext);
                _saveLocale(value!);
              },
            ),
            RadioListTile<String>(
              title: Text(l10n.languageEnglish),
              value: 'en',
              groupValue: currentLocale,
              onChanged: (value) {
                Navigator.pop(dialogContext);
                _saveLocale(value!);
              },
            ),
            RadioListTile<String>(
              title: Text(l10n.languageChinese),
              value: 'zh',
              groupValue: currentLocale,
              onChanged: (value) {
                Navigator.pop(dialogContext);
                _saveLocale(value!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveLocale(String locale) async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    if (currentConfig == null) return;

    final newConfig = currentConfig.copyWith(locale: locale);
    await ref.read(configProvider.notifier).updateConfig(newConfig);
  }

  void _showAboutDialog(AppLocalizations l10n) {
    showAboutDialog(
      context: context,
      applicationName: 'RemoteSend',
      applicationVersion: '1.0.0',
      applicationLegalese: l10n.aboutLegalese,
      children: [
        const SizedBox(height: 16),
        Text(l10n.aboutAppDescription),
      ],
    );
  }

  void _showComingSoon(AppLocalizations l10n, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.comingSoon(feature)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Dialog for adding/editing a server configuration.
class _ServerEditDialog extends ConsumerStatefulWidget {
  final AppLocalizations l10n;
  final ServerConfig? server;
  final Future<void> Function(ServerConfig server) onSave;

  const _ServerEditDialog({
    required this.l10n,
    this.server,
    required this.onSave,
  });

  @override
  ConsumerState<_ServerEditDialog> createState() => _ServerEditDialogState();
}

class _ServerEditDialogState extends ConsumerState<_ServerEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    if (widget.server != null) {
      _nameController.text = widget.server!.name;
      _urlController.text = widget.server!.serverUrl;
      _usernameController.text = widget.server!.username;
      _passwordController.text = widget.server!.password;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isEditing = widget.server != null;

    return AlertDialog(
      title: Text(isEditing ? l10n.editServer : l10n.addServer),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l10n.serverName,
                    hintText: l10n.serverNameHint,
                    prefixIcon: const Icon(Icons.label),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.serverNameRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: l10n.serverUrl,
                    hintText: l10n.serverUrlHint,
                    prefixIcon: const Icon(Icons.link),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.serverUrlRequired;
                    }
                    final uri = Uri.tryParse(value.trim());
                    if (uri == null || !uri.hasScheme) {
                      return l10n.serverUrlInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n.username,
                    prefixIcon: const Icon(Icons.person),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.usernameRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    prefixIcon: const Icon(Icons.lock),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.passwordRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Test Connection Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isTesting || _isSaving ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find),
                    label: Text(l10n.testConnection),
                  ),
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _testResult!.startsWith('Success')
                          ? Colors.green.withAlpha(20)
                          : Colors.red.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _testResult!.startsWith('Success')
                              ? Icons.check_circle
                              : Icons.error,
                          size: 16,
                          color: _testResult!.startsWith('Success')
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testResult!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _testResult!.startsWith('Success')
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _isSaving || _isTesting ? null : _saveServer,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? l10n.save : l10n.add),
        ),
      ],
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = widget.l10n;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      // Create a temporary service for testing
      final testService = WebDavService();
      final testServer = ServerConfig.create(
        name: _nameController.text.trim(),
        serverUrl: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      testService.initializeWithServer(testServer);
      final result = await testService.testConnection();

      if (result.isSuccess) {
        setState(() => _testResult = l10n.testConnectionSuccess);
      } else {
        setState(() => _testResult = l10n.testConnectionFailed(result.error?.userMessage ?? 'Unknown error'));
      }
    } catch (e) {
      setState(() => _testResult = l10n.testConnectionFailed(e.toString()));
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _saveServer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final ServerConfig newServer;
      if (widget.server != null) {
        newServer = widget.server!.copyWith(
          name: _nameController.text.trim(),
          serverUrl: _urlController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        newServer = ServerConfig.create(
          name: _nameController.text.trim(),
          serverUrl: _urlController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
      }

      await widget.onSave(newServer);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

/// A settings section with title, icon, and children.
class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          // Section Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
