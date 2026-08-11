import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:share_handler/share_handler.dart';
import 'l10n/app_localizations.dart';
import 'providers/config_provider.dart';
import 'providers/message_history_provider.dart';
import 'providers/webdav_provider.dart';
import 'providers/upload_queue_provider.dart';
import 'providers/pending_upload_provider.dart';
import 'screens/home_screen.dart';
import 'services/window_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    const double defaultWidth = 420;
    const double defaultHeight = 630;
    final windowService = WindowService();
    final savedState = await windowService.load();

    final windowOptions = const WindowOptions(
      size: Size(defaultWidth, defaultHeight),
      minimumSize: Size(320, 480),
      center: true,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    final windowCloseHandler = _WindowCloseHandler(windowService);
    windowManager.addListener(windowCloseHandler);

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (savedState != null && savedState.rect != null) {
        await windowManager.setBounds(savedState.rect!);
        if (savedState.isMaximized) {
          await windowManager.maximize();
        }
      }

      await windowManager.show();
      await windowManager.focus();

      windowCloseHandler.saveCurrentState();
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
    _initShareHandler();
    // Initialize config on app start
    Future.microtask(() {
      ref.read(configProvider.notifier).initialize();
    });
  }

  void _initShareHandler() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final handler = ShareHandlerPlatform.instance;

    // Cold start — app launched via share intent
    handler.getInitialSharedMedia().then((media) {
      if (media != null) _processSharedMedia(media);
    });

    // Warm start — share received while app is running
    handler.sharedMediaStream.listen((media) {
      _processSharedMedia(media);
    });
  }

  void _processSharedMedia(SharedMedia media) {
    bool hasText = false;
    bool hasFiles = false;

    // Text shares → TextBridge
    if (media.content != null && media.content!.trim().isNotEmpty) {
      ref.read(messageHistoryProvider.notifier).sendMessage(
        media.content!.trim(),
      );
      hasText = true;
    }

    // File shares → Upload queue
    final attachmentsList = <String>[];
    for (final a in media.attachments ?? <SharedAttachment?>[]) {
      if (a?.path case final p?) {
        attachmentsList.add(p);
      }
    }

    if (attachmentsList.isNotEmpty) {
      ref.read(uploadQueueProvider.notifier).addFiles(attachmentsList);
      hasFiles = true;
    }

    // Switch to the appropriate tab
    if (hasFiles) {
      ref.read(selectedTabProvider.notifier).state = 1;
    } else if (hasText) {
      ref.read(selectedTabProvider.notifier).state = 0;
    }
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

        String? fontFamily;
        if (Platform.isWindows) {
          final effectiveLocale = localeString == 'system'
              ? Platform.localeName
              : localeString;
          if (effectiveLocale.startsWith('zh')) {
            fontFamily = 'Microsoft YaHei UI';
          } else {
            fontFamily = 'Segoe UI Variable Display';
          }
        }

        final lightInputBorder = OutlineInputBorder(
          borderSide: BorderSide(color: lightColorScheme.secondaryContainer),
          borderRadius: BorderRadius.circular(5),
        );

        final darkInputBorder = OutlineInputBorder(
          borderSide: BorderSide(color: darkColorScheme.secondaryContainer),
          borderRadius: BorderRadius.circular(5),
        );

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
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: lightColorScheme.secondaryContainer,
              border: lightInputBorder,
              focusedBorder: lightInputBorder,
              enabledBorder: lightInputBorder,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            fontFamily: fontFamily,
          ),
          darkTheme: ThemeData(
            colorScheme: darkColorScheme,
            useMaterial3: true,
            navigationBarTheme: const NavigationBarThemeData(
              iconTheme: WidgetStatePropertyAll(IconThemeData(color: Colors.white)),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: darkColorScheme.secondaryContainer,
              border: darkInputBorder,
              focusedBorder: darkInputBorder,
              enabledBorder: darkInputBorder,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            fontFamily: fontFamily,
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
        final config = ref.read(configProvider).valueOrNull;
        final dragMode = config?.dragMode ?? 'instant';
        if (dragMode == 'pending' || isConnected) {
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

    final config = ref.read(configProvider).valueOrNull;
    final dragMode = config?.dragMode ?? 'instant';

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

      final allPaths = [...filePaths, ...folderPaths];
      if (allPaths.isEmpty) return;

      if (dragMode == 'pending') {
        ref.read(pendingUploadProvider.notifier).addFiles(allPaths);
        // Switch to file depot tab
        ref.read(selectedTabProvider.notifier).state = 1;
        return;
      }

      // Instant mode: upload directly
      int addedCount = 0;

      if (filePaths.isNotEmpty) {
        await ref.read(uploadQueueProvider.notifier).addFiles(filePaths);
        addedCount += filePaths.length;
      }

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

class _WindowCloseHandler with WindowListener {
  final WindowService windowService;
  _WindowCloseHandler(this.windowService);

  void _saveState() async {
    try {
      final isMaximized = await windowManager.isMaximized();
      final frame = await windowManager.getBounds();
      await windowService.save(
        WindowState.fromRect(frame, isMaximized: isMaximized),
      );
    } catch (_) {}
  }

  void saveCurrentState() => _saveState();

  @override
  void onWindowResize() => _saveState();

  @override
  void onWindowMove() => _saveState();

  @override
  void onWindowMaximize() => _saveState();

  @override
  void onWindowUnmaximize() => _saveState();
}
