# Project: RemoteSend

## Overview
A lightweight, portable, cross-platform (Windows & Android) application to manually transfer text and files between devices using WebDAV.

**Core Philosophy:**
- **Portable:** On Windows, runs from USB drive without installation. Config stored in `config.json` next to executable.
- **Serverless:** Uses standard WebDAV protocol (Nextcloud, Alist, Synology NAS, etc.). No proprietary servers.
- **Manual Control:** No background services. User explicitly chooses what to send/receive.

## Tech Stack
- **Framework:** Flutter (Dart)
- **State Management:** Riverpod
- **Key Dependencies:** `webdav_client`, `file_picker`, `path_provider`, `shared_preferences`

## Architecture

### WebDAV Layout
```
/RemoteSend/
├── buffer.txt      # Shared text content
└── Files/          # File storage directory
```

### Project Structure
```
lib/
├── main.dart
├── models/
│   └── app_config.dart         # Configuration model
├── providers/
│   ├── config_provider.dart    # Config state management
│   └── webdav_provider.dart    # WebDAV state management
├── services/
│   ├── config_service.dart     # Portable config logic
│   ├── webdav_service.dart     # WebDAV operations
│   └── webdav_exceptions.dart  # Error types
└── screens/
    ├── home_screen.dart        # Navigation shell
    ├── text_bridge_screen.dart # Text transfer UI
    ├── file_depot_screen.dart  # File transfer UI
    └── connection_screen.dart  # Settings UI
```

## Building

```bash
# Windows release
flutter build windows --release

# Android APK
flutter build apk --release
```

## Portable Mode (Windows)
Place `config.json` next to the executable:
```json
{
  "serverUrl": "https://your-webdav-server.com",
  "username": "your-username",
  "password": "your-password",
  "portableMode": true
}
```
