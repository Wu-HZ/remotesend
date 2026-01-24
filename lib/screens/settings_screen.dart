import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_config.dart';
import '../providers/config_provider.dart';
import '../providers/webdav_provider.dart';

/// Settings screen with Connection, General, Download, and Others sections.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Connection settings controllers
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _isTesting = false;

  // Settings
  late double _refreshInterval;
  bool _autoDownload = false;
  bool _showNotification = true;

  @override
  void initState() {
    super.initState();
    _refreshInterval = 3.0;
    Future.microtask(_loadConfig);
  }

  void _loadConfig() {
    final config = ref.read(configProvider).valueOrNull;
    if (config != null) {
      _urlController.text = config.serverUrl;
      _usernameController.text = config.username;
      _passwordController.text = config.password;
      setState(() {
        _refreshInterval = config.refreshIntervalSeconds.toDouble();
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
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

    return _SettingsSection(
      title: 'Connection',
      icon: Icons.cloud,
      children: [
        // Connection Status Card
        _buildConnectionStatusCard(connectionStatus),
        const SizedBox(height: 16),

        // Server URL
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'WebDAV Server URL',
            hintText: 'https://example.com/webdav',
            prefixIcon: Icon(Icons.link),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        // Username
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(Icons.person),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),

        // Password
        TextField(
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
        ),
        const SizedBox(height: 16),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isTesting || _isSaving ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find),
                label: const Text('Test'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _isSaving || _isTesting ? null : _saveConfig,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ),
          ],
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

  Widget _buildConnectionStatusCard(ConnectionStatus status) {
    Color color;
    IconData icon;
    String text;

    switch (status.state) {
      case WebDavConnectionState.connected:
        color = Colors.green;
        icon = Icons.check_circle;
        text = 'Connected';
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
          subtitle: const Text('Ask every time'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showComingSoon('Download location'),
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

  // ==================== Actions ====================
  Future<void> _testConnection() async {
    if (_urlController.text.isEmpty ||
        _usernameController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all connection fields'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isTesting = true);

    try {
      await _saveConfigInternal();

      final webDavService = ref.read(webDavServiceProvider);
      final config = AppConfig(
        serverUrl: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      webDavService.initialize(config);

      final connectionNotifier = ref.read(connectionStatusProvider.notifier);
      final success = await connectionNotifier.testConnection();

      if (success) {
        final structureResult = await connectionNotifier.initializeFolderStructure();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                structureResult.isSuccess
                    ? 'Connected successfully!'
                    : 'Connected, but folder setup failed',
              ),
              backgroundColor: structureResult.isSuccess ? Colors.green : Colors.orange,
            ),
          );
        }
      } else if (mounted) {
        final status = ref.read(connectionStatusProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status.errorMessage ?? 'Connection failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);

    try {
      final success = await _saveConfigInternal();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Settings saved' : 'Failed to save'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _saveConfigInternal() async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    final newConfig = AppConfig(
      serverUrl: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      portableMode: currentConfig?.portableMode ?? false,
      refreshIntervalSeconds: _refreshInterval.toInt(),
    );
    return ref.read(configProvider.notifier).updateConfig(newConfig);
  }

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
      await _saveConfigInternal();

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
