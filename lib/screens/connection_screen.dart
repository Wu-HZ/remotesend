import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_config.dart';
import '../providers/config_provider.dart';
import '../providers/webdav_provider.dart';

/// Screen for configuring WebDAV connection settings.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    // Load existing config into form
    Future.microtask(_loadConfig);
  }

  void _loadConfig() {
    final config = ref.read(configProvider).valueOrNull;
    if (config != null) {
      _urlController.text = config.serverUrl;
      _usernameController.text = config.username;
      _passwordController.text = config.password;
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
    final configAsync = ref.watch(configProvider);
    final isPortableAvailable = ref.watch(portableModeAvailableProvider);
    final isPortableMode = ref.watch(isPortableModeProvider);
    final configService = ref.watch(configServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Server URL
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'WebDAV Server URL',
                  hintText: 'https://example.com/webdav',
                  prefixIcon: Icon(Icons.cloud),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a server URL';
                  }
                  if (!value.startsWith('http://') &&
                      !value.startsWith('https://')) {
                    return 'URL must start with http:// or https://';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Username
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Password
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
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
              const SizedBox(height: 24),

              // Portable Mode Toggle (only on desktop)
              if (isPortableAvailable) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.usb),
                            const SizedBox(width: 8),
                            Text(
                              'Portable Mode',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Save credentials to config.json next to the executable. '
                          'Perfect for USB drives.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          title: Text(
                            isPortableMode ? 'Enabled' : 'Disabled',
                          ),
                          subtitle: Text(
                            isPortableMode
                                ? 'Config saved to: ${configService.portableConfigPath}'
                                : 'Config saved to app storage',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          value: isPortableMode,
                          onChanged: _isSaving
                              ? null
                              : (value) => _togglePortableMode(value),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

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
                      label: const Text('Test Connection'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving || _isTesting ? null : _saveConfig,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Save'),
                    ),
                  ),
                ],
              ),

              // Status indicator
              if (configAsync.hasValue) ...[
                const SizedBox(height: 24),
                _buildStatusCard(configAsync.value!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(AppConfig config) {
    final isConfigured = config.isConfigured;
    final connectionStatus = ref.watch(connectionStatusProvider);

    // Determine status to display
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (!isConfigured) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
      statusText = 'Please enter your WebDAV credentials.';
    } else {
      switch (connectionStatus.state) {
        case WebDavConnectionState.connected:
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
          statusText = 'Connected and ready to sync.';
          if (connectionStatus.lastChecked != null) {
            final ago = DateTime.now().difference(connectionStatus.lastChecked!);
            if (ago.inMinutes < 1) {
              statusText += ' (verified just now)';
            } else if (ago.inMinutes < 60) {
              statusText += ' (verified ${ago.inMinutes}m ago)';
            }
          }
        case WebDavConnectionState.connecting:
          statusColor = Colors.blue;
          statusIcon = Icons.sync;
          statusText = 'Testing connection...';
        case WebDavConnectionState.error:
          statusColor = Colors.red;
          statusIcon = Icons.error;
          statusText = connectionStatus.errorMessage ?? 'Connection error.';
        case WebDavConnectionState.disconnected:
          statusColor = Colors.grey;
          statusIcon = Icons.cloud_off;
          statusText = 'Configured. Click "Test Connection" to verify.';
      }
    }

    return Card(
      color: statusColor.withAlpha(25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                statusText,
                style: TextStyle(color: statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePortableMode(bool enable) async {
    setState(() => _isSaving = true);

    try {
      // First save current form values
      await _saveConfigInternal();

      // Then toggle portable mode
      final notifier = ref.read(configProvider.notifier);
      bool success;
      if (enable) {
        success = await notifier.enablePortableMode();
      } else {
        success = await notifier.disablePortableMode();
      }

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
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isTesting = true);

    try {
      // Save config first so WebDAV service can use it
      await _saveConfigInternal();

      // Initialize the WebDAV service with current config
      final webDavService = ref.read(webDavServiceProvider);
      final config = AppConfig(
        serverUrl: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      webDavService.initialize(config);

      // Test connection
      final connectionNotifier = ref.read(connectionStatusProvider.notifier);
      final success = await connectionNotifier.testConnection();

      if (success) {
        // Also try to create folder structure
        final structureResult = await connectionNotifier.initializeFolderStructure();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                structureResult.isSuccess
                    ? 'Connection successful! RemoteSend folder ready.'
                    : 'Connected, but failed to create folder structure: ${structureResult.error?.userMessage}',
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
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final success = await _saveConfigInternal();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Configuration saved' : 'Failed to save configuration',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool> _saveConfigInternal() async {
    final currentConfig = ref.read(configProvider).valueOrNull;
    final newConfig = AppConfig(
      serverUrl: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      portableMode: currentConfig?.portableMode ?? false,
    );

    return ref.read(configProvider.notifier).updateConfig(newConfig);
  }
}
