# Project: RemoteSend

## Overview
A lightweight, portable, cross-platform (Windows & Android) application for manual text and file transfer between devices using WebDAV.

**Core Philosophy:**
- **Portable:** On Windows, runs from USB drive without installation. Config stored in `config.json` next to executable.
- **Serverless:** Uses standard WebDAV protocol (Nextcloud, Alist, Synology NAS, etc.). No proprietary servers.
- **Manual Control:** No background services. User explicitly chooses what to send/receive.

## Tech Stack
- **Framework:** Flutter 3.x / Dart 3.x
- **State Management:** Riverpod (`flutter_riverpod`)
- **WebDAV:** `webdav_client` with `dio` for HTTP
- **Localization:** `flutter_localizations` + `intl` (ARB files)
- **Desktop:** `window_manager`, `desktop_drop`
- **Theming:** `dynamic_color` (Material You)

## Architecture

### Project Structure
```
lib/
├── main.dart                 # App entry, window setup, drag-drop handler
├── models/
│   ├── app_config.dart       # Main config with multi-server support (v4)
│   ├── server_config.dart    # Individual WebDAV server config
│   ├── text_message.dart     # Chat message model
│   ├── upload_queue.dart     # Upload task model
│   └── download_queue.dart   # Download task model
├── providers/
│   ├── config_provider.dart          # Config state + server management
│   ├── webdav_provider.dart          # WebDAV services + connection status
│   ├── upload_queue_provider.dart    # Upload queue management
│   ├── download_state_provider.dart  # Download state management
│   └── message_history_provider.dart # Chat message sync
├── services/
│   ├── config_service.dart     # Portable config load/save logic
│   ├── webdav_service.dart     # WebDAV operations (CRUD, upload, download)
│   └── webdav_exceptions.dart  # Typed WebDAV errors
├── screens/
│   ├── home_screen.dart           # Navigation shell (Rail/Bar)
│   ├── text_bridge_screen.dart    # Chat-style text messaging
│   ├── file_depot_screen.dart     # File browser with folder navigation
│   ├── transfer_queue_screen.dart # Upload/download progress
│   └── settings_screen.dart       # Server, theme, language settings
└── l10n/
    ├── app_localizations.dart     # Generated localization class
    ├── app_localizations_en.dart  # English translations
    └── app_localizations_zh.dart  # Chinese translations
```

### WebDAV Folder Structure
```
/RemoteSend/
├── TextBridge/
│   └── messages.json   # Synced chat messages
└── Files/              # User-uploaded files and folders
```

### Key Providers

| Provider | Type | Purpose |
|----------|------|---------|
| `configProvider` | `AsyncNotifierProvider` | App configuration state |
| `activeTextServerProvider` | `Provider<ServerConfig?>` | Selected server for Text Bridge |
| `activeFilesServerProvider` | `Provider<ServerConfig?>` | Selected server for File Depot |
| `webDavTextServiceProvider` | `Provider<WebDavService>` | WebDAV client for text operations |
| `webDavFilesServiceProvider` | `Provider<WebDavService>` | WebDAV client for file operations |
| `textConnectionStatusProvider` | `StateNotifierProvider` | Text service connection state |
| `filesConnectionStatusProvider` | `StateNotifierProvider` | Files service connection state |
| `fileListProvider` | `StateNotifierProvider` | Remote file list with navigation |
| `uploadQueueProvider` | `StateNotifierProvider` | Upload queue with progress |
| `downloadStateProvider` | `StateNotifierProvider` | Download state tracking |
| `messageHistoryProvider` | `StateNotifierProvider` | Chat message sync |

### State Pattern
Uses immutable state classes with `copyWith`:
```dart
class ConnectionStatus {
  final WebDavConnectionState state;
  final String? errorMessage;
  final DateTime? lastChecked;

  ConnectionStatus copyWith({...}) => ConnectionStatus(...);
}

class ConnectionNotifier extends StateNotifier<ConnectionStatus> {
  Future<bool> testConnection() async {...}
}
```

### Result Pattern
WebDAV operations return `WebDavResult<T>` for typed error handling:
```dart
final result = await _service.listFiles();
if (result.isSuccess) {
  // Use result.data
} else {
  // Handle result.error?.userMessage
}
```

## Building

```bash
# Install dependencies
flutter pub get

# Generate localizations
flutter gen-l10n

# Windows release
flutter build windows --release

# Android APK
flutter build apk --release

# Run analysis
flutter analyze
```

## Configuration

### Config Version History
- **v1:** Single server (serverUrl, username, password)
- **v2:** Multi-server with single activeServerId
- **v3:** Separate activeTextServerId / activeFilesServerId
- **v4:** Added theme, color, dynamic color, locale settings

### Current Config Structure (v4)
```json
{
  "version": 4,
  "servers": [
    {
      "id": "uuid",
      "name": "Server Name",
      "serverUrl": "https://...",
      "username": "...",
      "password": "...",
      "createdAt": "ISO8601"
    }
  ],
  "activeTextServerId": "uuid",
  "activeFilesServerId": "uuid",
  "portableMode": true,
  "refreshIntervalSeconds": 3,
  "downloadLocation": "",
  "localName": "RandomName42",
  "themeMode": "system",
  "primaryColor": 4280391411,
  "useDynamicColor": true,
  "locale": "system"
}
```

## Localization

ARB files in `lib/l10n/`:
- `app_en.arb` - English (source)
- `app_zh.arb` - Chinese Simplified

Usage pattern:
```dart
final l10n = AppLocalizations.of(context)!;
Text(l10n.navFiles)
Text(l10n.uploadingFile(fileName))  // Parameterized
```

For nullable context (e.g., in callbacks):
```dart
final l10n = AppLocalizations.of(context);
Text(l10n?.someString ?? 'Fallback')
```

## Code Style

- **Widgets:** `ConsumerWidget` / `ConsumerStatefulWidget` for Riverpod
- **Navigation:** Desktop uses `NavigationRail`, mobile uses `NavigationBar`
- **Dialogs:** Pass `AppLocalizations l10n` as parameter to dialog methods
- **State classes:** Immutable with `copyWith` pattern
- **Error handling:** Use `WebDavResult<T>` wrapper, show `userMessage` to user
- **File paths:** Use `package:path` for cross-platform path handling

## Common Tasks

### Add a new setting
1. Add field to `AppConfig` in `app_config.dart`
2. Update `copyWith`, `toJson`, `fromJson`
3. Add provider in `config_provider.dart`
4. Add UI in `settings_screen.dart`

### Add a new localized string
1. Add to `lib/l10n/app_en.arb` with key
2. Add translation to `lib/l10n/app_zh.arb`
3. Run `flutter gen-l10n`
4. Use via `AppLocalizations.of(context)!.keyName`

### Add a new WebDAV operation
1. Add method to `WebDavService` returning `WebDavResult<T>`
2. Handle in provider/notifier
3. Call from screen widget
