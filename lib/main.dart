import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/config_provider.dart';
import 'providers/webdav_provider.dart';
import 'providers/upload_queue_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    // Window size with 2:3 aspect ratio (width:height)
    const double windowWidth = 420;
    const double windowHeight = 630;

    WindowOptions windowOptions = const WindowOptions(
      size: Size(windowWidth, windowHeight),
      minimumSize: Size(320, 480),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

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
  bool _isDragging = false;

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

    // Watch theme settings
    final themeMode = ref.watch(themeModeProvider);
    final primaryColor = ref.watch(primaryColorProvider);
    final seedColor = Color(primaryColor);

    // Convert string theme mode to ThemeMode enum
    ThemeMode flutterThemeMode;
    switch (themeMode) {
      case 'light':
        flutterThemeMode = ThemeMode.light;
      case 'dark':
        flutterThemeMode = ThemeMode.dark;
      default:
        flutterThemeMode = ThemeMode.system;
    }

    return MaterialApp(
      title: 'RemoteSend',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: flutterThemeMode,
      home: _buildAppWithDropTarget(),
    );
  }

  Widget _buildAppWithDropTarget() {
    final connectionStatus = ref.watch(filesConnectionStatusProvider);
    final isConnected = connectionStatus.state == WebDavConnectionState.connected;

    return DropTarget(
      onDragEntered: (details) {
        setState(() => _isDragging = true);
      },
      onDragExited: (details) {
        setState(() => _isDragging = false);
      },
      onDragDone: (details) {
        setState(() => _isDragging = false);
        if (isConnected) {
          _handleDroppedFiles(details.files);
        } else {
          _showNotConnectedMessage();
        }
      },
      child: Stack(
        children: [
          const HomeScreen(),
          // Global drag overlay
          if (_isDragging)
            Positioned.fill(
              child: Material(
                color: Colors.black.withAlpha(150),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.blue : Colors.orange,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isConnected ? Icons.cloud_upload : Icons.cloud_off,
                          size: 64,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isConnected
                              ? 'Drop files here to upload'
                              : 'Connect to WebDAV first',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (!isConnected) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Go to Settings to configure connection',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showNotConnectedMessage() {
    // Use a global key or context to show snackbar
    // Since we're at the app level, we need to use ScaffoldMessenger
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = this.context;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connect to WebDAV first to upload files'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }

  Future<void> _handleDroppedFiles(List<XFile> xFiles) async {
    if (xFiles.isEmpty) return;

    try {
      final filePaths = <String>[];
      final folderPaths = <String>[];

      for (final xFile in xFiles) {
        final path = xFile.path;
        if (await FileSystemEntity.isDirectory(path)) {
          folderPaths.add(path);
        } else if (await FileSystemEntity.isFile(path)) {
          filePaths.add(path);
        }
      }

      int addedCount = 0;

      // Add files to upload queue
      if (filePaths.isNotEmpty) {
        await ref.read(uploadQueueProvider.notifier).addFiles(filePaths);
        addedCount += filePaths.length;
      }

      // Add folders to upload queue
      for (final folderPath in folderPaths) {
        await ref.read(uploadQueueProvider.notifier).addFolder(folderPath);
        addedCount++;
      }

      if (addedCount > 0) {
        final message = folderPaths.isEmpty
            ? 'Added $addedCount file(s) to upload queue'
            : filePaths.isEmpty
                ? 'Added ${folderPaths.length} folder(s) to upload queue'
                : 'Added ${filePaths.length} file(s) and ${folderPaths.length} folder(s) to upload queue';

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.green,
              ),
            );
          }
        });
      }
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    }
  }

  Future<void> _autoConnect() async {
    final config = ref.read(configProvider).valueOrNull;
    if (config == null) return;

    // Connect text service if configured
    if (config.isTextConfigured) {
      final textConnectionNotifier = ref.read(textConnectionStatusProvider.notifier);
      final textSuccess = await textConnectionNotifier.testConnection();
      if (textSuccess) {
        await textConnectionNotifier.initializeFolderStructure();
      }
    }

    // Connect files service if configured
    if (config.isFilesConfigured) {
      final filesConnectionNotifier = ref.read(filesConnectionStatusProvider.notifier);
      final filesSuccess = await filesConnectionNotifier.testConnection();
      if (filesSuccess) {
        await filesConnectionNotifier.initializeFolderStructure();
      }
    }
  }
}
