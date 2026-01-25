import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../models/app_config.dart';
import '../models/server_config.dart';
import '../providers/config_provider.dart';
import '../providers/webdav_provider.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connection Section
          _buildConnectionSection(),
          const SizedBox(height: 24),

          // General Section
          _buildGeneralSection(),
          const SizedBox(height: 24),

          // Download Section
          _buildDownloadSection(),
          const SizedBox(height: 24),

          // Others Section
          _buildOthersSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==================== Connection Section ====================
  Widget _buildConnectionSection() {
    final connectionStatus = ref.watch(connectionStatusProvider);
    final isPortableAvailable = ref.watch(portableModeAvailableProvider);
    final isPortableMode = ref.watch(isPortableModeProvider);
    final configService = ref.watch(configServiceProvider);
    final servers = ref.watch(serversListProvider);
    final activeServer = ref.watch(activeServerProvider);

    return _SettingsSection(
      title: 'Connection',
      icon: Icons.cloud,
      children: [
        // Connection Status Card
        _buildConnectionStatusCard(connectionStatus, activeServer),
        const SizedBox(height: 16),

        // Configured Servers Section
        Text(
          'Configured Servers',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
            child: const Center(
              child: Text(
                'No servers configured',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...servers.map((server) => _buildServerTile(server, activeServer)),

        const SizedBox(height: 12),

        // Add Server Button
        OutlinedButton.icon(
          onPressed: () => _showServerDialog(),
          icon: const Icon(Icons.add),
          label: const Text('Add Server'),
        ),

        // Portable Mode (desktop only)
        if (isPortableAvailable) ...[
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('Portable Mode'),
            subtitle: Text(
              isPortableMode
                  ? 'Config: ${configService.portableConfigPath}'
                  : 'Save config next to executable (for USB drives)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            secondary: const Icon(Icons.usb),
            value: isPortableMode,
            onChanged: _isSaving ? null : _togglePortableMode,
          ),
        ],

        // Refresh Interval
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.timer),
          title: const Text('Refresh interval'),
          subtitle: Text('${_refreshInterval.toInt()} seconds'),
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
          'Time to wait after each server request',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }

  Widget _buildServerTile(ServerConfig server, ServerConfig? activeServer) {
    final isActive = activeServer?.id == server.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: RadioListTile<String>(
        value: server.id,
        groupValue: activeServer?.id,
        onChanged: (value) {
          if (value != null) {
            _switchServer(value);
          }
        },
        title: Text(
          server.name,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          server.serverUrl,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        secondary: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            switch (action) {
              case 'edit':
                _showServerDialog(server: server);
                break;
              case 'delete':
                _confirmDeleteServer(server);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatusCard(ConnectionStatus status, ServerConfig? activeServer) {
    Color color;
    IconData icon;
    String text;

    switch (status.state) {
      case WebDavConnectionState.connected:
        color = Colors.green;
        icon = Icons.check_circle;
        text = activeServer != null ? '${activeServer.name} - Connected' : 'Connected';
      case WebDavConnectionState.connecting:
        color = Colors.blue;
        icon = Icons.sync;
        text = 'Connecting...';
      case WebDavConnectionState.error:
        color = Colors.red;
        icon = Icons.error;
        text = status.errorMessage ?? 'Connection error';
      case WebDavConnectionState.disconnected:
        color = Colors.grey;
        icon = Icons.cloud_off;
        text = 'Not connected';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }

  // ==================== General Section ====================
  Widget _buildGeneralSection() {
    return _SettingsSection(
      title: 'General',
      icon: Icons.tune,
      children: [
        ListTile(
          leading: const Icon(Icons.brightness_6),
          title: const Text('Theme'),
          subtitle: const Text('System default'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showThemeDialog(),
        ),
        ListTile(
          leading: const Icon(Icons.palette),
          title: const Text('Color'),
          subtitle: const Text('Blue'),
          trailing: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          onTap: () => _showComingSoon('Color settings'),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: const Text('Language'),
          subtitle: const Text('English'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showComingSoon('Language settings'),
        ),
      ],
    );
  }

  // ==================== Download Section ====================
  Widget _buildDownloadSection() {
    final displayPath = _downloadLocation.isNotEmpty
        ? _downloadLocation
        : 'System default';

    return _SettingsSection(
      title: 'Download',
      icon: Icons.download,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.sync),
          title: const Text('Auto-download'),
          subtitle: const Text('Automatically download new files when detected'),
          value: _autoDownload,
          onChanged: (value) {
            setState(() => _autoDownload = value);
            _showComingSoon('Auto-download');
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder),
          title: const Text('Download location'),
          subtitle: Text(
            displayPath,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickDownloadLocation,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications),
          title: const Text('Show notification'),
          subtitle: const Text('Notify when download completes'),
          value: _showNotification,
          onChanged: (value) {
            setState(() => _showNotification = value);
            _showComingSoon('Notification setting');
          },
        ),
      ],
    );
  }

  Future<void> _pickDownloadLocation() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select download location',
      initialDirectory: _downloadLocation.isNotEmpty ? _downloadLocation : null,
    );

    if (result != null) {
      setState(() => _downloadLocation = result);
      await _saveDownloadLocation(result);
    }
  }

  Future<void> _saveDownloadLocation(String path) async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    if (currentConfig == null) return;

    final newConfig = currentConfig.copyWith(downloadLocation: path);
    final success = await ref.read(configProvider.notifier).updateConfig(newConfig);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Download location updated' : 'Failed to save'),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ==================== Others Section ====================
  Widget _buildOthersSection() {
    return _SettingsSection(
      title: 'Others',
      icon: Icons.more_horiz,
      children: [
        ListTile(
          leading: const Icon(Icons.info),
          title: const Text('About'),
          subtitle: const Text('RemoteSend v1.0.0'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAboutDialog(),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('Source code'),
          subtitle: const Text('github.com/Wu-HZ/remotesend'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _showComingSoon('Open GitHub'),
        ),
        ListTile(
          leading: const Icon(Icons.favorite),
          title: const Text('Donation'),
          subtitle: const Text('Support the development'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showComingSoon('Donation'),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip),
          title: const Text('Privacy Policy'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showComingSoon('Privacy Policy'),
        ),
      ],
    );
  }

  // ==================== Server Management Actions ====================
  Future<void> _switchServer(String serverId) async {
    setState(() => _isSaving = true);

    try {
      final success = await ref.read(configProvider.notifier).switchServer(serverId);

      if (success && mounted) {
        // Reinitialize WebDAV connection
        final config = ref.read(configProvider).valueOrNull;
        if (config != null) {
          final webDavService = ref.read(webDavServiceProvider);
          webDavService.initialize(config);
          ref.read(connectionStatusProvider.notifier).testConnection();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server switched'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showServerDialog({ServerConfig? server}) {
    showDialog(
      context: context,
      builder: (dialogContext) => _ServerEditDialog(
        server: server,
        onSave: (newServer) async {
          bool success;
          if (server == null) {
            success = await ref.read(configProvider.notifier).addServer(newServer);
          } else {
            success = await ref.read(configProvider.notifier).updateServer(newServer);
          }

          if (success && mounted) {
            // If this is a new server or we're editing the active server, reinitialize
            final config = ref.read(configProvider).valueOrNull;
            if (config != null && config.activeServerId == newServer.id) {
              final webDavService = ref.read(webDavServiceProvider);
              webDavService.initialize(config);
              ref.read(connectionStatusProvider.notifier).testConnection();
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success
                    ? (server == null ? 'Server added' : 'Server updated')
                    : 'Failed to save server'),
                backgroundColor: success ? Colors.green : Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  void _confirmDeleteServer(ServerConfig server) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Server'),
        content: Text('Are you sure you want to delete "${server.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await ref.read(configProvider.notifier).deleteServer(server.id);

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? 'Server deleted' : 'Failed to delete'),
                  backgroundColor: success ? Colors.green : Colors.red,
                  duration: const Duration(seconds: 2),
                ),
              );

              // Reinitialize WebDAV with new active server (if any)
              if (success) {
                final config = ref.read(configProvider).valueOrNull;
                if (config != null && config.activeServer != null) {
                  final webDavService = ref.read(webDavServiceProvider);
                  webDavService.initialize(config);
                  ref.read(connectionStatusProvider.notifier).testConnection();
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
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

  Future<void> _togglePortableMode(bool enable) async {
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
                  ? 'Portable mode ${enable ? 'enabled' : 'disabled'}'
                  : 'Failed to change portable mode',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('System default'),
              value: 'system',
              groupValue: 'system',
              onChanged: (_) => Navigator.pop(context),
            ),
            RadioListTile<String>(
              title: const Text('Light'),
              value: 'light',
              groupValue: 'system',
              onChanged: (_) {
                Navigator.pop(context);
                _showComingSoon('Theme setting');
              },
            ),
            RadioListTile<String>(
              title: const Text('Dark'),
              value: 'dark',
              groupValue: 'system',
              onChanged: (_) {
                Navigator.pop(context);
                _showComingSoon('Theme setting');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'RemoteSend',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2025 Wu-HZ',
      children: [
        const SizedBox(height: 16),
        const Text(
          'A lightweight, portable app to transfer text and files between devices using WebDAV.',
        ),
      ],
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - coming soon'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Dialog for adding/editing a server configuration.
class _ServerEditDialog extends ConsumerStatefulWidget {
  final ServerConfig? server;
  final Future<void> Function(ServerConfig server) onSave;

  const _ServerEditDialog({
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
    final isEditing = widget.server != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Server' : 'Add Server'),
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
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g., Home NAS',
                    prefixIcon: Icon(Icons.label),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'WebDAV Server URL',
                    hintText: 'https://example.com/webdav',
                    prefixIcon: Icon(Icons.link),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a server URL';
                    }
                    final uri = Uri.tryParse(value.trim());
                    if (uri == null || !uri.hasScheme) {
                      return 'Please enter a valid URL';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
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
                      return 'Please enter a password';
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
                    label: const Text('Test Connection'),
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving || _isTesting ? null : _saveServer,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final webDavService = ref.read(webDavServiceProvider);
      final tempConfig = AppConfig(
        servers: [
          ServerConfig.create(
            name: _nameController.text.trim(),
            serverUrl: _urlController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          ),
        ],
        activeServerId: 'temp',
      );

      // Create a temporary config just for testing
      final testConfig = AppConfig(
        servers: tempConfig.servers,
        activeServerId: tempConfig.servers.first.id,
      );

      webDavService.initialize(testConfig);
      await webDavService.testConnection();

      setState(() => _testResult = 'Success! Connection established.');
    } catch (e) {
      setState(() => _testResult = 'Failed: ${e.toString()}');
    } finally {
      setState(() => _isTesting = false);

      // Restore original config
      final config = ref.read(configProvider).valueOrNull;
      if (config != null && config.isConfigured) {
        ref.read(webDavServiceProvider).initialize(config);
      }
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
