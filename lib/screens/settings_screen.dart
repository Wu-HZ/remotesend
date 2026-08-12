import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(16),
          children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                l10n.settings,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          // Connection Section
          _buildConnectionSection(l10n),
          const SizedBox(height: 24),

          // General Section
          _buildGeneralSection(l10n),
          const SizedBox(height: 24),

          // Download Section
          _buildDownloadSection(l10n),
          const SizedBox(height: 24),

          // Transfer Section
          _buildTransferSection(l10n),
          const SizedBox(height: 24),

          // Data Section
          _buildDataSection(l10n),
          const SizedBox(height: 24),

          // Others Section
          _buildOthersSection(l10n),
          const SizedBox(height: 32),

          // Footer
          Center(
            child: Text(
              'RemoteSend',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Version: 1.0.0',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          Center(
            child: Text(
              '\u00a9 ${DateTime.now().year}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => _showAboutDialog(l10n),
              icon: const Icon(Icons.info_outline, size: 16),
              label: Text(l10n.about),
            ),
          ),
          const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    ),
    );
  }

  // ==================== Connection Section ====================
  Widget _buildConnectionSection(AppLocalizations l10n) {
    final textConnectionStatus = ref.watch(textConnectionStatusProvider);
    final filesConnectionStatus = ref.watch(filesConnectionStatusProvider);
    final isPortableAvailable = ref.watch(portableModeAvailableProvider);
    final isPortableMode = ref.watch(isPortableModeProvider);
    final servers = ref.watch(serversListProvider);
    final textServer = ref.watch(activeTextServerProvider);
    final filesServer = ref.watch(activeFilesServerProvider);
    final config = ref.watch(configProvider).valueOrNull;
    final localName = config?.localName ?? 'Unknown';

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

        ...servers.map((server) => _buildServerTile(l10n, server, null)),

        Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline.withAlpha(60),
            ),
          ),
          child: InkWell(
            onTap: () => _showServerDialog(l10n),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.addServer,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Local Name Setting
        _ButtonEntry(
          label: l10n.localName,
          buttonLabel: localName,
          onTap: () => _showLocalNameDialog(l10n, localName),
        ),

        // Portable Mode (desktop only)
        // Data Location (desktop only)
        if (isPortableAvailable) ...[
          _ButtonEntry(
            label: l10n.dataLocation,
            buttonLabel: isPortableMode ? l10n.dataLocationPortable : l10n.dataLocationSystem,
            onTap: () => _showDataLocationDialog(l10n, isPortableMode),
          ),
        ],

        // Sync Interval
        _ButtonEntry(
          label: l10n.refreshInterval,
          buttonLabel: l10n.refreshIntervalSeconds(_refreshInterval.toInt()),
          onTap: () => _showSyncIntervalDialog(l10n),
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          child: server.emoji.isNotEmpty
                              ? Text(server.emoji,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 18))
                              : Icon(Icons.cloud,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          server.name,
                          style: TextStyle(
                            fontWeight: (isTextServer || isFilesServer)
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 15,
                          ),
                        ),
                      ],
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
              // Enable/disable toggle
              _buildFeatureToggle(
                label: server.enabled ? l10n.enabledLabel : l10n.disabledLabel,
                isSelected: server.enabled,
                onTap: () =>
                    ref.read(configProvider.notifier).toggleServerEnabled(server.id),
              ),
              const SizedBox(width: 4),
              // Text/Files toggle buttons
              const SizedBox(width: 4),
              _buildFeatureToggle(
                label: l10n.textLabel,
                isSelected: isTextServer,
                onTap: server.enabled
                    ? () => _setServerForFeature(server.id, forText: true)
                    : null,
                enabled: server.enabled,
              ),
              const SizedBox(width: 4),
              _buildFeatureToggle(
                label: l10n.filesLabel,
                isSelected: isFilesServer,
                onTap: server.enabled
                    ? () => _setServerForFeature(server.id, forFiles: true)
                    : null,
                enabled: server.enabled,
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
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveSelected = isSelected && enabled;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: effectiveSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: effectiveSelected ? colorScheme.primary : colorScheme.outline.withAlpha(50),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: effectiveSelected ? FontWeight.w600 : FontWeight.normal,
              color: effectiveSelected ? colorScheme.onPrimary : colorScheme.onSurface,
            ),
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
    final primaryColor = config?.primaryColor ?? 0xFF009688;
    final useDynamicColor = config?.useDynamicColor ?? true;
    final chatOwnLeft = config?.chatOwnMessageLeft ?? false;

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
        _ButtonEntry(
          label: l10n.theme,
          buttonLabel: themeModeText,
          onTap: () => _showThemeDialog(l10n),
        ),
        _BooleanEntry(
          label: l10n.dynamicColor,
          value: useDynamicColor,
          onChanged: (value) => _saveDynamicColor(value),
        ),
        _ButtonEntry(
          label: l10n.color,
          buttonLabel: useDynamicColor ? l10n.usingSystemColor : _getColorName(l10n, primaryColor),
          enabled: !useDynamicColor,
          onTap: () => _showColorPicker(l10n),
        ),
        _ButtonEntry(
          label: l10n.language,
          buttonLabel: _getLanguageName(l10n, config?.locale ?? 'system'),
          onTap: () => _showLanguageDialog(l10n),
        ),
        _BooleanEntry(
          label: l10n.chatOwnMessageLeftLabel,
          value: chatOwnLeft,
          onChanged: (value) => _saveChatOwnMessageLeft(l10n, value),
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

  // ==================== Transfer Section ====================
  Widget _buildTransferSection(AppLocalizations l10n) {
    final config = ref.watch(configProvider).valueOrNull;
    final dragMode = config?.dragMode ?? 'instant';

    return _SettingsSection(
      title: '传输',
      icon: Icons.swap_horiz,
      children: [
        _ButtonEntry(
          label: '拖拽上传模式',
          buttonLabel: dragMode == 'instant' ? '直接上传' : '待传页面',
          onTap: () => _showDragModeDialog(l10n, dragMode),
        ),
      ],
    );
  }

  void _showDragModeDialog(AppLocalizations l10n, String currentMode) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('拖拽上传模式'),
        children: [
          RadioListTile<String>(
            title: const Text('直接上传'),
            subtitle: const Text('拖入文件后立即传输到当前服务器'),
            value: 'instant',
            groupValue: currentMode,
            onChanged: (v) {
              Navigator.pop(ctx);
              _saveDragMode(l10n, v!);
            },
          ),
          RadioListTile<String>(
            title: const Text('待传页面'),
            subtitle: const Text('拖入后选择服务器再传输'),
            value: 'pending',
            groupValue: currentMode,
            onChanged: (v) {
              Navigator.pop(ctx);
              _saveDragMode(l10n, v!);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveDragMode(AppLocalizations l10n, String mode) async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    if (currentConfig == null) return;
    final newConfig = currentConfig.copyWith(dragMode: mode);
    await ref.read(configProvider.notifier).updateConfig(newConfig);
  }

  Future<void> _saveChatOwnMessageLeft(AppLocalizations l10n, bool value) async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    if (currentConfig == null) return;
    final newConfig = currentConfig.copyWith(chatOwnMessageLeft: value);
    await ref.read(configProvider.notifier).updateConfig(newConfig);
  }

  // ==================== Data Section ====================
  Widget _buildDataSection(AppLocalizations l10n) {
    return _SettingsSection(
      title: '数据',
      icon: Icons.folder_open,
      children: [
        _ButtonEntry(
          label: '导入配置',
          buttonLabel: '选择文件',
          onTap: () => _importConfig(l10n),
        ),
        _ButtonEntry(
          label: '导出配置',
          buttonLabel: '导出',
          onTap: () => _exportConfig(l10n),
        ),
      ],
    );
  }

  Future<void> _importConfig(AppLocalizations l10n) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      String content;
      if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else if (file.bytes != null) {
        content = String.fromCharCodes(file.bytes!);
      } else {
        return;
      }

      if (!mounted) return;
      final count =
          ref.read(configProvider.notifier).importFromString(content);

      if (!mounted) return;
      if (count == -1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('文件格式错误'),
              backgroundColor: Colors.red),
        );
      } else if (count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('没有新服务器可导入（URL 重复）'),
              backgroundColor: Colors.orange),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('已导入 $count 个服务器'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('导入失败: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportConfig(AppLocalizations l10n) async {
    final jsonStr = ref.read(configProvider.notifier).exportToString();
    if (jsonStr == null) return;

    // Warn about plaintext passwords
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出配置'),
        content: const Text('配置文件包含服务器密码（明文），请妥善保管。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续导出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Mobile: save to temp and share
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/remotesend_config.json');
        await file.writeAsString(jsonStr);
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'RemoteSend 配置',
        );
      } else {
        // Desktop: save to chosen location
        final result = await FilePicker.platform.saveFile(
          dialogTitle: '保存配置文件',
          fileName: 'remotesend_config.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (result != null) {
          await File(result).writeAsString(jsonStr);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('配置已导出'),
                  backgroundColor: Colors.green),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('导出失败: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
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
        _BooleanEntry(
          label: l10n.autoDownload,
          value: _autoDownload,
          onChanged: (value) {
            setState(() => _autoDownload = value);
            _showComingSoon(l10n, l10n.autoDownload);
          },
        ),
        _ButtonEntry(
          label: l10n.downloadLocation,
          buttonLabel: displayPath,
          onTap: () => _pickDownloadLocation(l10n),
        ),
        _BooleanEntry(
          label: l10n.showNotification,
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
        _ButtonEntry(
          label: l10n.about,
          buttonLabel: l10n.open,
          onTap: () => _showAboutDialog(l10n),
        ),
        _ButtonEntry(
          label: l10n.sourceCode,
          buttonLabel: l10n.open,
          onTap: () => _showComingSoon(l10n, l10n.openGitHub),
        ),
        _ButtonEntry(
          label: l10n.donation,
          buttonLabel: l10n.open,
          onTap: () => _showComingSoon(l10n, l10n.donation),
        ),
        _ButtonEntry(
          label: l10n.privacyPolicy,
          buttonLabel: l10n.open,
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
  void _showSyncIntervalDialog(AppLocalizations l10n) {
    double tempValue = _refreshInterval;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.refreshInterval),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.refreshIntervalDescription,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('1s'),
                  Expanded(
                    child: Slider(
                      value: tempValue,
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '${tempValue.toInt()}s',
                      onChanged: (value) {
                        setDialogState(() => tempValue = value);
                      },
                    ),
                  ),
                  Text('10s'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _saveRefreshInterval(tempValue.toInt());
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveRefreshInterval(int seconds) async {
    setState(() => _refreshInterval = seconds.toDouble());

    final currentConfig = ref.read(configProvider).valueOrNull;
    if (currentConfig == null) return;

    final newConfig = currentConfig.copyWith(refreshIntervalSeconds: seconds);
    final success = await ref.read(configProvider.notifier).updateConfig(newConfig);

    if (success) {
      // Update auto-pull interval if it's running
      ref.read(autoPullProvider.notifier).updateRefreshInterval(seconds);
    }
  }

  void _showDataLocationDialog(AppLocalizations l10n, bool isPortable) {
    final configService = ref.read(configServiceProvider);
    final portablePath = configService.portableConfigPath;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.dataLocation),
        children: [
          RadioListTile<bool>(
            title: Text(l10n.dataLocationSystem),
            subtitle: const Text('Windows: %LOCALAPPDATA%\\com.remotesend.remote_send\\shared_prefs.json'),
            value: false,
            groupValue: isPortable,
            onChanged: (v) {
              Navigator.pop(ctx);
              if (v != isPortable) _saveDataLocation(l10n, v!);
            },
          ),
          RadioListTile<bool>(
            title: Text(l10n.dataLocationPortable),
            subtitle: Text(portablePath.isNotEmpty ? portablePath : '软件目录/config.json'),
            value: true,
            groupValue: isPortable,
            onChanged: (v) {
              Navigator.pop(ctx);
              if (v != isPortable) _saveDataLocation(l10n, v!);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveDataLocation(AppLocalizations l10n, bool portable) async {
    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(configProvider.notifier);
      final success = portable
          ? await notifier.enablePortableMode()
          : await notifier.disablePortableMode();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? (portable ? l10n.portableModeEnabled : l10n.portableModeDisabled)
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
  final _emojiController = TextEditingController();
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
      _emojiController.text = widget.server!.emoji;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _emojiController.dispose();
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
                // Emoji icon
                TextFormField(
                  controller: _emojiController,
                  decoration: const InputDecoration(
                    labelText: 'Emoji',
                    prefixIcon: Icon(Icons.emoji_emotions),
                    border: OutlineInputBorder(),
                    helperText: '仅支持一个表情 (Win+.)',
                    helperMaxLines: 1,
                  ),
                  maxLength: 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 16),
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

  /// Keep only the first visible character (handles multi-codepoint emoji).
  String _trimEmoji(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.characters.first;
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
          emoji: _trimEmoji(_emojiController.text),
        );
      } else {
        newServer = ServerConfig.create(
          name: _nameController.text.trim(),
          serverUrl: _urlController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          emoji: _trimEmoji(_emojiController.text),
        );
      }

      await widget.onSave(newServer);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _SettingsEntry extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingsEntry({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 10),
          SizedBox(width: 150, child: child),
        ],
      ),
    );
  }
}

class _BooleanEntry extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BooleanEntry({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SettingsEntry(
      label: label,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              color: theme.inputDecorationTheme.fillColor,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: theme.colorScheme.primary,
                activeThumbColor: theme.colorScheme.onPrimary,
                inactiveThumbColor: theme.colorScheme.outline,
                inactiveTrackColor: theme.colorScheme.surface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonEntry extends StatelessWidget {
  final String label;
  final String buttonLabel;
  final bool enabled;
  final VoidCallback onTap;

  const _ButtonEntry({
    required this.label,
    required this.buttonLabel,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsEntry(
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: Theme.of(context).inputDecorationTheme.fillColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            padding: EdgeInsets.zero,
          ),
          onPressed: enabled ? onTap : null,
          child: Center(
            child: Text(
              buttonLabel,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.only(left: 15, right: 15, top: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
