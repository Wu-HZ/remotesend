import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/config_provider.dart';
import 'providers/webdav_provider.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: RemoteSendApp(),
    ),
  );
}

class RemoteSendApp extends ConsumerStatefulWidget {
  const RemoteSendApp({super.key});

  @override
  ConsumerState<RemoteSendApp> createState() => _RemoteSendAppState();
}

class _RemoteSendAppState extends ConsumerState<RemoteSendApp> {
  bool _autoConnectAttempted = false;

  @override
  void initState() {
    super.initState();
    // Initialize config on app start
    Future.microtask(() {
      ref.read(configProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch config and auto-connect when configured
    ref.listen<AsyncValue<dynamic>>(configProvider, (previous, next) {
      next.whenData((config) {
        if (!_autoConnectAttempted && config.isConfigured) {
          _autoConnectAttempted = true;
          _autoConnect();
        }
      });
    });

    return MaterialApp(
      title: 'RemoteSend',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }

  Future<void> _autoConnect() async {
    // Initialize WebDAV service with config
    final config = ref.read(configProvider).valueOrNull;
    if (config == null || !config.isConfigured) return;

    final webDavService = ref.read(webDavServiceProvider);
    webDavService.initialize(config);

    // Test connection silently
    final connectionNotifier = ref.read(connectionStatusProvider.notifier);
    final success = await connectionNotifier.testConnection();

    // If connected, ensure folder structure exists
    if (success) {
      await connectionNotifier.initializeFolderStructure();
    }
  }
}
