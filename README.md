# RemoteSend

A lightweight, portable, cross-platform application to transfer text and files between devices using WebDAV.

## Features

- **Text Bridge** - Share text snippets between devices via a remote buffer
- **File Depot** - Upload, download, and manage files on your WebDAV server
- **Portable Mode** - Run from USB drive on Windows without installation
- **Cross-Platform** - Works on Windows and Android
- **No Proprietary Server** - Uses standard WebDAV (Nextcloud, Alist, Synology NAS, etc.)

## Screenshots

| Text Bridge | File Depot | Connection |
|-------------|------------|------------|
| Send/receive text | Upload/download files | Configure WebDAV |

## Installation

### Windows
1. Download the release ZIP
2. Extract to any folder (USB drive for portable use)
3. Run `remote_send.exe`

### Android
1. Download the APK
2. Install and grant storage permissions

## Usage

### First Setup
1. Open the app and go to **Connection** tab
2. Enter your WebDAV server URL, username, and password
3. Click **Test Connection** to verify
4. (Windows) Enable **Portable Mode** to save config next to the executable

### Text Transfer
1. Go to **Text** tab
2. Type or paste text
3. Click **Push** to upload to server
4. On another device, click **Pull** to download

### File Transfer
1. Go to **Files** tab
2. Click **Upload** button to select and upload files
3. Tap any file to download
4. Long-press or use menu to delete

## WebDAV Server Structure

The app creates this structure on your server:
```
/RemoteSend/
├── buffer.txt      # Shared text content
└── Files/          # Uploaded files
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

## Portable Mode (Windows)

To use portable mode, place `config.json` next to the executable:
```json
{
  "serverUrl": "https://your-webdav-server.com",
  "username": "your-username",
  "password": "your-password",
  "portableMode": true
}
```

## Tech Stack

- Flutter / Dart
- Riverpod (State Management)
- webdav_client
- file_picker
- Material 3 Design

## License

MIT License
