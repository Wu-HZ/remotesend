import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'l10n/app_localizations.dart';
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
    final useDynamicColor = ref.watch(useDynamicColorProvider);
    final localeString = ref.watch(localeProvider);

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

    // Convert locale string to Locale object
    Locale? appLocale;
    if (localeString != 'system') {
      appLocale = Locale(localeString);
    }

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightColorScheme;
        ColorScheme darkColorScheme;

        // Use dynamic color if available and enabled
        if (useDynamicColor && lightDynamic != null && darkDynamic != null) {
          lightColorScheme = lightDynamic.harmonized();
          darkColorScheme = darkDynamic.harmonized();
        } else {
          // Fall back to seed color
          final seedColor = Color(primaryColor);
          lightColorScheme = ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: Brightness.light,
          );
          darkColorScheme = ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: Brightness.dark,
          );
        }

        return MaterialApp(
          title: 'RemoteSend',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('zh'),
          ],
          locale: appLocale,
          theme: ThemeData(
            colorScheme: lightColorScheme,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: darkColorScheme,
            useMaterial3: true,
          ),
          themeMode: flutterThemeMode,
          home: _buildAppWithDropTarget(),
        );
      },
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
              child: Builder(
                builder: (context) {
                  final l10n = AppLocalizations.of(context);
                  return Material(
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
                                  ? (l10n?.dropFilesToUpload ?? 'Drop files here to upload')
                                  : (l10n?.connectToWebDavFirst ?? 'Connect to WebDAV first'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (!isConnected) ...[
                              const SizedBox(height: 8),
                              Text(
                                l10n?.goToSettingsToConfigureConnection ?? 'Go to Settings to configure connection',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.connectToWebDavFirstToUploadFiles ?? 'Connect to WebDAV first to upload files'),
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            final l10n = AppLocalizations.of(context);
            String message;
            if (folderPaths.isEmpty) {
              message = l10n?.addedFilesToQueue(filePaths.length) ?? 'Added ${filePaths.length} file(s) to upload queue';
            } else if (filePaths.isEmpty) {
              message = l10n?.addedFolders(folderPaths.length) ?? 'Added ${folderPaths.length} folder(s) to upload queue';
            } else {
              message = l10n?.addedFilesAndFolders(filePaths.length, folderPaths.length) ?? 'Added ${filePaths.length} file(s) and ${folderPaths.length} folder(s) to upload queue';
            }

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
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n?.error(e.toString()) ?? 'Error: $e'),
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
