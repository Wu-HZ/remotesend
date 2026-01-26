# RemoteSend

A lightweight, portable, cross-platform application to transfer text and files between devices using WebDAV.

## Features

- **Text Bridge** - Chat-like interface to send and sync messages between devices
- **File Depot** - Upload, download, and manage files with folder support
- **Transfer Queue** - Track upload and download progress in real-time
- **Multiple Servers** - Configure multiple WebDAV servers with separate selection for Text and Files
- **Drag & Drop** - Drop files directly onto the app window to upload (Desktop)
- **Portable Mode** - Run from USB drive on Windows without installation
- **Cross-Platform** - Works on Windows and Android
- **Themes** - Light, dark, or system theme with custom accent colors
- **Material You** - Dynamic color support on compatible systems
- **Multi-Language** - English and Chinese (Simplified) support
- **No Proprietary Server** - Uses standard WebDAV (Nextcloud, Alist, Synology NAS, etc.)

## Screenshots

| Text Bridge | File Depot | Settings |
|-------------|------------|----------|
| Chat-style messaging | File management | Server & theme config |

## Installation

### Windows
1. Download the release ZIP
2. Extract to any folder (USB drive for portable use)
3. Run `remotesend.exe`

### Android
1. Download the APK
2. Install and grant storage permissions

## Usage

### First Setup
1. Open the app and go to **Settings** tab
2. Tap **Add Server** to configure your WebDAV connection
3. Enter server name, URL, username, and password
4. Tap **Test Connection** to verify
5. Select the server for Text Bridge and/or File Depot
6. (Windows) Enable **Portable Mode** to save config next to the executable

### Text Transfer
1. Go to **Text** tab
2. Type a message and tap the send button
3. Messages sync automatically between devices
4. Long-press a message to delete it

### File Transfer
1. Go to **Files** tab
2. Use the **+** button to upload files or folders
3. Or drag and drop files onto the window (Desktop)
4. Tap a file to download, or long-press for more options
5. Navigate folders by tapping them

### Transfer Queue
- Access from the Files tab to view upload/download progress
- Open downloaded files or folders directly from the queue
- Clear completed transfers as needed

## WebDAV Server Structure

The app creates this structure on your server:
```
/RemoteSend/
├── TextBridge/
│   └── messages.json   # Synced chat messages
└── Files/              # Uploaded files and folders
```

## Building from Source

```bash
# Clone the repository
git clone https://github.com/Wu-HZ/remotesend.git
cd remotesend

# Install dependencies
flutter pub get

# Build Windows release
flutter build windows --release

# Build Android APK
flutter build apk --release
```

## Configuration

### Portable Mode (Windows)

Enable portable mode in Settings, or manually place `config.json` next to the executable:

```json
{
  "version": 4,
  "servers": [
    {
      "id": "unique-id",
      "name": "My Server",
      "serverUrl": "https://your-webdav-server.com/dav",
      "username": "your-username",
      "password": "your-password",
      "createdAt": "2025-01-01T00:00:00.000"
    }
  ],
  "activeTextServerId": "unique-id",
  "activeFilesServerId": "unique-id",
  "portableMode": true,
  "refreshIntervalSeconds": 3,
  "downloadLocation": "",
  "themeMode": "system",
  "primaryColor": 4280391411,
  "useDynamicColor": true,
  "locale": "system"
}
```

### Settings Overview

| Setting | Description |
|---------|-------------|
| Servers | Add, edit, or remove WebDAV server configurations |
| Text Server | Select which server to use for Text Bridge |
| Files Server | Select which server to use for File Depot |
| Portable Mode | Store config next to executable (Windows) |
| Refresh Interval | Auto-sync interval for Text Bridge (seconds) |
| Download Location | Default folder for downloaded files |
| Theme | Light, Dark, or System |
| Accent Color | Custom theme color or dynamic system color |
| Language | English, Chinese, or System default |

## Tech Stack

- Flutter / Dart
- Riverpod (State Management)
- webdav_client
- Material 3 Design
- window_manager (Desktop)
- dynamic_color (Material You)
- flutter_localizations (i18n)

## License

MIT License
