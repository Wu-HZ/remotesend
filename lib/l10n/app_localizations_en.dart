// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'RemoteSend';

  @override
  String get gotifyTextServer => 'Gotify · Live text';

  @override
  String get gotifyRegisterTextServer => 'Register as a text server';

  @override
  String get gotifyRegisterTextHint =>
      'Live text only. No files, history, or dates. Enable this option on both devices using compatible RemoteSend versions.';

  @override
  String get gotifySessionNotice =>
      'This session is kept in memory only. No local history or offline delivery. Gotify may still retain message content on its server.';

  @override
  String get gotifyRealtimeEmpty => 'No live text yet';

  @override
  String get gotifyClearSession => 'Clear current session';

  @override
  String get gotifyTextNotReady =>
      'Gotify is disabled, unconfigured, or not connected yet.';

  @override
  String get gotifyTextEmpty => 'Enter some text to send.';

  @override
  String get gotifyTextTooLarge =>
      'Text exceeds the 32 KiB UTF-8 limit or the server request limit.';

  @override
  String get gotifyTextQueueFull =>
      'The live text queue is full. Wait and retry; new text was not sent.';

  @override
  String get gotifyTextSendFailed =>
      'Could not send to Gotify. Check the connection or credentials and retry.';

  @override
  String get gotifyTextUncertain =>
      'The request timed out. Gotify may have accepted it; retrying uses the same message ID.';

  @override
  String get gotifyTextCapabilityUnknown =>
      'Live text support is unconfirmed. Check the version and registration on this device; WebDAV notifications are unaffected.';

  @override
  String get gotifyTextSending => 'Sending…';

  @override
  String get gotifyTextSent => 'Sent to Gotify';

  @override
  String gotifyDroppedTexts(int count) {
    return '$count background messages expired or exceeded the memory limit.';
  }

  @override
  String get autoClearTransferHistory => 'Auto-clear successful transfers';

  @override
  String get autoClearTransferHistoryHint =>
      'Keep successful records for 5 minutes, then clear when idle. Failed tasks and files are kept.';

  @override
  String get openFileAccessDenied =>
      'Cannot read this file. Open it again from the source app and allow file access.';

  @override
  String get openFileUnavailable =>
      'The file is missing or the source app cannot provide it. Please select it again.';

  @override
  String get openFileImportFailed =>
      'Could not import the file. Check available storage and try again.';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get takeAnotherPhoto => 'Take another photo';

  @override
  String get addPendingFiles => 'Add files';

  @override
  String get sendToServerLabel => 'Tap to send to a server';

  @override
  String get cameraPermissionDenied =>
      'Camera access is unavailable. Allow camera access in system settings and try again.';

  @override
  String get cameraUnavailable =>
      'No camera or camera app is available on this device.';

  @override
  String get photoFileAccessFailed =>
      'Could not save the photo. Check available storage and try again.';

  @override
  String get cameraCaptureFailed => 'Could not take a photo. Please try again.';

  @override
  String get cameraRecoveryFailed =>
      'Could not recover the last photo. Please take it again.';

  @override
  String get photoPreviewUnavailable =>
      'Preview unavailable. You can still send this image as a file.';

  @override
  String get navText => 'Text';

  @override
  String get navFiles => 'Files';

  @override
  String get navSettings => 'Settings';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get rename => 'Rename';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get clear => 'Clear';

  @override
  String get close => 'Close';

  @override
  String get open => 'Open';

  @override
  String get confirm => 'Confirm';

  @override
  String get failedToLoadConfig => 'Failed to load configuration:';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get selectDate => 'Select Date';

  @override
  String get previousDay => 'Previous day';

  @override
  String get nextDay => 'Next day';

  @override
  String get refresh => 'Refresh';

  @override
  String get clearSelection => 'Clear selection';

  @override
  String get selectAll => 'Select all';

  @override
  String selectedItems(Object count) {
    return '$count selected';
  }

  @override
  String get switchServer => 'Switch server';

  @override
  String get configureWebDavToSync =>
      'Configure WebDAV connection in Settings to sync';

  @override
  String get notConnectedTestInSettings =>
      'Not connected. Test connection in Settings';

  @override
  String get configureWebDavToUseFileDepot =>
      'Configure WebDAV connection in Settings to use File Depot';

  @override
  String get noMessagesYet => 'No messages yet';

  @override
  String get noMessagesOnThisDay => 'No messages on this day';

  @override
  String get sendMessageToGetStarted => 'Send a message to get started';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get sendClipboardContent => 'Send clipboard content';

  @override
  String get startClipboardAutoSend => 'Temporarily auto-send clipboard text';

  @override
  String get stopClipboardAutoSend => 'Auto-sending · Click to stop';

  @override
  String get clipboardAutoSendHint =>
      'Temporary auto-send is on for newly copied text only. Leaving the text page turns it off. On desktop, copy in any app; on mobile, return to this page.';

  @override
  String get clipboardAutoSendReadFailed =>
      'Cannot read the clipboard. Auto-send stopped. Check clipboard access permissions.';

  @override
  String get clipboardAutoSendFailed =>
      'Sending failed. Auto-send stopped. Check the connection and retry manually.';

  @override
  String get messageMarkedForDeletion => 'Message marked for deletion';

  @override
  String get undo => 'Undo';

  @override
  String get couldNotOpenLink => 'Could not open link';

  @override
  String errorOpeningLink(Object error) {
    return 'Error opening link: $error';
  }

  @override
  String get typeAMessage => 'Type a message...';

  @override
  String get fileDepot => 'File';

  @override
  String get goBack => 'Go back';

  @override
  String get openDownloadFolder => 'Open download folder';

  @override
  String downloadingFile(Object fileName) {
    return 'Downloading: $fileName';
  }

  @override
  String downloadingFileWithProgress(
    Object fileName,
    Object current,
    Object total,
  ) {
    return 'Downloading: $fileName ($current/$total)';
  }

  @override
  String uploadingFile(Object fileName, Object current, Object total) {
    return 'Uploading: $fileName ($current/$total)';
  }

  @override
  String get uploadingEllipsis => 'Uploading...';

  @override
  String filesUploaded(Object completed, Object total) {
    return '$completed/$total files uploaded';
  }

  @override
  String filesDownloaded(Object completed, Object total) {
    return '$completed/$total files downloaded';
  }

  @override
  String get idle => 'Idle';

  @override
  String get connectToWebDavToViewFiles => 'Connect to WebDAV to view files';

  @override
  String get noFilesYet => 'No files yet';

  @override
  String get emptyFolder => 'Empty folder';

  @override
  String get tapFileOrFolderToUpload =>
      'Tap the File or Folder button to upload';

  @override
  String get thisFolderIsEmpty => 'This folder is empty';

  @override
  String get folder => 'Folder';

  @override
  String get file => 'File';

  @override
  String get download => 'Download';

  @override
  String get downloadFolder => 'Download Folder';

  @override
  String get uploadToServer => 'Upload to Server';

  @override
  String get selectTargetServer => 'Select target server';

  @override
  String uploadingToServer(Object name, Object server) {
    return 'Uploading $name to $server';
  }

  @override
  String uploadedToServer(Object name, Object server) {
    return 'Uploaded $name to $server';
  }

  @override
  String uploadedItemsToServer(Object count, Object server) {
    return 'Uploaded $count items to $server';
  }

  @override
  String uploadToServerFailed(Object server) {
    return 'Could not upload to $server';
  }

  @override
  String get moveToFolder => 'Move to Folder';

  @override
  String get moveHere => 'Move Here';

  @override
  String get filesRoot => 'Files';

  @override
  String get noSubfolders => 'No subfolders';

  @override
  String moved(Object name) {
    return 'Moved: $name';
  }

  @override
  String get failedToMoveFile => 'Failed to move item';

  @override
  String draggingItemsSuffix(Object count) {
    return 'and $count items';
  }

  @override
  String movedItems(Object count) {
    return 'Moved $count items';
  }

  @override
  String get createFolder => 'Create Folder';

  @override
  String get folderNameHint => 'Enter a folder name';

  @override
  String get folderNameRequired => 'Please enter a folder name';

  @override
  String get folderNameInvalid => 'Folder name cannot contain path separators';

  @override
  String folderCreated(Object name) {
    return 'Folder created: $name';
  }

  @override
  String get failedToCreateFolder => 'Failed to create folder';

  @override
  String todayTime(Object time) {
    return 'Today $time';
  }

  @override
  String yesterdayTime(Object time) {
    return 'Yesterday $time';
  }

  @override
  String daysAgo(Object days) {
    return '$days days ago';
  }

  @override
  String get couldNotAccessFiles => 'Could not access files';

  @override
  String get pasteClipboardFiles => 'Paste and send images or files';

  @override
  String get clipboardUnavailable => 'Clipboard is unavailable';

  @override
  String get clipboardNoFilesOrImages =>
      'No sendable images or files found in the clipboard';

  @override
  String addedFilesToQueue(Object count) {
    return 'Added $count file(s) to upload queue';
  }

  @override
  String get selectFolderToUpload => 'Select folder to upload';

  @override
  String addedFolderToQueue(Object name) {
    return 'Added folder \"$name\" to upload queue';
  }

  @override
  String downloaded(Object name) {
    return 'Downloaded: $name';
  }

  @override
  String get downloadedStatus => 'Downloaded';

  @override
  String alreadyDownloaded(Object name) {
    return 'Already downloaded: $name';
  }

  @override
  String get openFolder => 'Open folder';

  @override
  String get downloadFailed => 'Download failed';

  @override
  String downloadedFolderWithCount(Object name, Object count) {
    return 'Downloaded folder \"$name\" ($count files)';
  }

  @override
  String get deleteFile => 'Delete File';

  @override
  String deleteFileConfirm(Object name) {
    return 'Are you sure you want to delete \"$name\"?\n\nThis cannot be undone.';
  }

  @override
  String deleted(Object name) {
    return 'Deleted: $name';
  }

  @override
  String get failedToDeleteFile => 'Failed to delete file';

  @override
  String get renameFile => 'Rename File';

  @override
  String get renameFileHint => 'Enter a new name';

  @override
  String get renameFileNameRequired => 'Please enter a name';

  @override
  String get renameFileNameInvalid => 'Name cannot contain path separators';

  @override
  String renamed(Object name) {
    return 'Renamed: $name';
  }

  @override
  String get failedToRenameFile => 'Failed to rename file';

  @override
  String get transferQueue => 'Transfer Queue';

  @override
  String get retryFailed => 'Retry failed';

  @override
  String get clearCompleted => 'Clear completed';

  @override
  String get clearAll => 'Clear all';

  @override
  String get transferQueueEmpty => 'Transfer queue is empty';

  @override
  String get filesWillAppearHere => 'Files will appear here when transferring';

  @override
  String uploadStatus(Object status) {
    return 'Upload: $status';
  }

  @override
  String downloadStatus(Object status) {
    return 'Download: $status';
  }

  @override
  String filesCount(Object count) {
    return '$count files';
  }

  @override
  String filesProgress(Object completed, Object total) {
    return '$completed/$total files';
  }

  @override
  String get elapsed => 'Elapsed';

  @override
  String get duration => 'Duration';

  @override
  String get remaining => 'remaining';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusUploading => 'Uploading';

  @override
  String get statusDownloading => 'Downloading';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusIdle => 'Idle';

  @override
  String get clearQueue => 'Clear Queue';

  @override
  String get clearQueueConfirm =>
      'Are you sure you want to clear the entire upload queue? This will cancel any ongoing uploads.';

  @override
  String get openFileFolderNotSupported =>
      'Open folder not supported on this platform';

  @override
  String failedToOpenFolder(Object error) {
    return 'Failed to open folder: $error';
  }

  @override
  String get fileNotFound => 'File not found';

  @override
  String get openFileNotSupported => 'Open file not supported on this platform';

  @override
  String failedToOpenFile(Object error) {
    return 'Failed to open file: $error';
  }

  @override
  String get openFile => 'Open file';

  @override
  String get settings => 'Settings';

  @override
  String get sectionConnection => 'Connection';

  @override
  String get sectionGeneral => 'General';

  @override
  String get sectionDownload => 'Download';

  @override
  String get sectionOthers => 'Others';

  @override
  String get configuredServers => 'Servers';

  @override
  String get longPressToEditDelete => 'Long press to edit/delete';

  @override
  String get noServersConfigured => 'No servers configured';

  @override
  String get addServer => 'Add Server';

  @override
  String get editServer => 'Edit Server';

  @override
  String get deleteServer => 'Delete Server';

  @override
  String deleteServerConfirm(Object name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get serverAdded => 'Server added';

  @override
  String get serverUpdated => 'Server updated';

  @override
  String get serverDeleted => 'Server deleted';

  @override
  String get failedToSaveServer => 'Failed to save server';

  @override
  String get failedToDelete => 'Failed to delete';

  @override
  String get textLabel => 'Text';

  @override
  String get filesLabel => 'Files';

  @override
  String get enabledLabel => 'Enabled';

  @override
  String get disabledLabel => 'Disabled';

  @override
  String get localName => 'Local Name';

  @override
  String get localNameHint => 'e.g., My Phone';

  @override
  String get localNameDescription =>
      'This name will be shown in Text Bridge messages sent from this device.';

  @override
  String get nameUpdated => 'Name updated';

  @override
  String get failedToSave => 'Failed to save';

  @override
  String get portableMode => 'Portable Mode';

  @override
  String get portableModeDescription =>
      'Save config next to executable (for USB drives)';

  @override
  String portableModeConfig(Object path) {
    return 'Config: $path';
  }

  @override
  String get portableModeEnabled => 'Portable mode enabled';

  @override
  String get portableModeDisabled => 'Portable mode disabled';

  @override
  String get portableModeDisableConfirm =>
      'Disabling portable mode will store config in system directories instead.\n\nIt is recommended to keep it enabled (config stays next to the app).';

  @override
  String get dataLocation => 'Data location';

  @override
  String get dataLocationSystem => 'System directory';

  @override
  String get dataLocationPortable => 'Portable';

  @override
  String get failedToChangePortableMode => 'Failed to change portable mode';

  @override
  String get connectionStatusConnected => 'Connected';

  @override
  String get connectionStatusConnecting => 'Connecting...';

  @override
  String get connectionStatusError => 'Connection error';

  @override
  String get connectionStatusDisconnected => 'Not connected';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System default';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get startPage => 'Startup page';

  @override
  String get startPageDescription => 'Applied the next time the app starts';

  @override
  String get startPageText => 'Text page';

  @override
  String get startPageFiles => 'Files page';

  @override
  String get dynamicColor => 'Dynamic Color';

  @override
  String get dynamicColorDescription =>
      'Use system accent color (Material You)';

  @override
  String get usingSystemColor => 'Using system color';

  @override
  String get color => 'Color';

  @override
  String get chooseColor => 'Choose Color';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorRed => 'Red';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorPurple => 'Purple';

  @override
  String get colorCyan => 'Cyan';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorTeal => 'Teal';

  @override
  String get colorIndigo => 'Indigo';

  @override
  String get colorYellow => 'Yellow';

  @override
  String get colorBrown => 'Brown';

  @override
  String get colorBlueGrey => 'Blue Grey';

  @override
  String get colorCustom => 'Custom';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => 'Chinese (Simplified)';

  @override
  String get autoDownload => 'Auto-download';

  @override
  String get autoDownloadDescription =>
      'Automatically download new files when detected';

  @override
  String get downloadLocation => 'Download location';

  @override
  String get systemDownloadsOption => 'System Downloads (default)';

  @override
  String get portableDownloadsOption => 'Downloads next to app (USB-friendly)';

  @override
  String get customDownloadsOption => 'Custom folder';

  @override
  String get effectiveDownloadPath => 'Current download path';

  @override
  String get downloadServerSubdirectoryNote =>
      'Files are stored in a subfolder for each server. Changing location does not move existing downloads.';

  @override
  String get portableDownloadsHint =>
      'Enable Portable Mode too, so this setting travels with the app.';

  @override
  String get systemDefault => 'System default';

  @override
  String get downloadLocationUpdated => 'Download location updated';

  @override
  String get selectDownloadLocation => 'Select download location';

  @override
  String get showNotification => 'Show notification';

  @override
  String get showNotificationDescription => 'Notify when download completes';

  @override
  String get about => 'About';

  @override
  String get aboutDescription => 'RemoteSend v1.1.0';

  @override
  String get aboutLegalese => '© 2026 Wu-HZ';

  @override
  String get aboutAppDescription =>
      'A lightweight, portable app to transfer text and files between devices using WebDAV.';

  @override
  String get sourceCode => 'Source code';

  @override
  String get sourceCodeUrl => 'github.com/Wu-HZ/remotesend';

  @override
  String get openGitHub => 'Open GitHub';

  @override
  String get donation => 'Donation';

  @override
  String get donationDescription => 'Support the development';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get changelog => 'Changelog';

  @override
  String get changelog_1_1_0_1 =>
      'Adaptive icon (SVG design, fills tablet icon area)';

  @override
  String get changelog_1_1_0_2 => 'Settings page footer logo with theme tint';

  @override
  String get changelog_1_1_0_3 =>
      'Auto-sync persistence (survives app restart)';

  @override
  String get changelog_1_1_0_4 => 'Own messages on left layout option';

  @override
  String get changelog_1_1_0_5 =>
      'Portable mode as data-location picker dialog';

  @override
  String get changelog_1_1_0_6 =>
      'Full English localization (no hardcoded Chinese left)';

  @override
  String get changelog_1_1_0_7 =>
      'Content max-width 700px, pending page same constraint';

  @override
  String get changelog_1_1_0_8 =>
      'NavigationRail adapts to screen width (tablet landscape)';

  @override
  String get changelog_1_1_0_9 => 'APK slimmed to 19.5MB (arm64 only + minify)';

  @override
  String get changelog_1_1_0_10 => 'Settings entry row height unified';

  @override
  String get changelog_1_1_0_11 => 'Config import/export (JSON sharing)';

  @override
  String get changelog_1_1_0_12 => 'Storage usage widget with clear button';

  @override
  String get changelog_1_1_0_13 => 'Server enable/disable toggle';

  @override
  String get changelog_1_1_0_14 => 'Server emoji icon picker';

  @override
  String get changelog_1_1_0_15 => 'Drag & drop with instant/pending modes';

  @override
  String get changelog_1_1_0_16 =>
      'Upload failure auto-fallback to pending page';

  @override
  String get changelog_1_1_0_17 =>
      'Error messages show HTTP status, URL, auth details';

  @override
  String get changelog_1_1_0_18 =>
      'Serialized init to avoid concurrent PROPFIND';

  @override
  String get changelog_1_0_0_1 =>
      'WebDAV-based text bridge with chat interface';

  @override
  String get changelog_1_0_0_2 =>
      'File depot with folder navigation & multi-file upload';

  @override
  String get changelog_1_0_0_3 =>
      'Multi-server support with separate text/files selection';

  @override
  String get changelog_1_0_0_4 =>
      'Upload/download queue with progress tracking';

  @override
  String get changelog_1_0_0_5 => 'Auto-pull for new messages';

  @override
  String get changelog_1_0_0_6 =>
      'Theme mode, color picker, dynamic color (Material You)';

  @override
  String get changelog_1_0_0_7 => 'English/Chinese localization';

  @override
  String get changelog_1_0_0_8 => 'Window size/position remembered on desktop';

  @override
  String get changelog_1_0_0_9 =>
      'Portable mode (config.json next to executable)';

  @override
  String get changelog_1_0_0_10 => 'Original app icon design';

  @override
  String comingSoon(Object feature) {
    return '$feature - coming soon';
  }

  @override
  String get serverName => 'Name';

  @override
  String get serverNameHint => 'e.g., Home NAS';

  @override
  String get serverNameRequired => 'Please enter a name';

  @override
  String get serverUrl => 'WebDAV Server URL';

  @override
  String get serverUrlHint => 'https://example.com/webdav';

  @override
  String get serverUrlRequired => 'Please enter a server URL';

  @override
  String get serverUrlInvalid => 'Please enter a valid URL';

  @override
  String get username => 'Username';

  @override
  String get usernameRequired => 'Please enter a username';

  @override
  String get password => 'Password';

  @override
  String get passwordRequired => 'Please enter a password';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get testConnectionSuccess => 'Success! Connection established.';

  @override
  String testConnectionFailed(Object error) {
    return 'Failed: $error';
  }

  @override
  String error(Object message) {
    return 'Error: $message';
  }

  @override
  String get dropFilesToUpload => 'Drop files here to upload';

  @override
  String get chatOwnMessageLeftLabel => 'Show own messages on left';

  @override
  String get chatOwnMessageLeftDescription =>
      'Place your own messages on the left side like remote messages';

  @override
  String get connectToWebDavFirst => 'Connect to WebDAV first';

  @override
  String get goToSettingsToConfigureConnection =>
      'Go to Settings to configure connection';

  @override
  String get connectToWebDavFirstToUploadFiles =>
      'Connect to WebDAV first to upload files';

  @override
  String addedFilesAndFolders(Object files, Object folders) {
    return 'Added $files file(s) and $folders folder(s) to upload queue';
  }

  @override
  String addedFolders(Object count) {
    return 'Added $count folder(s) to upload queue';
  }

  @override
  String get sectionTransferSetting => 'Transfer';

  @override
  String get sectionDataSetting => 'Data';

  @override
  String get dragModeLabel => 'Drag & drop mode';

  @override
  String get dragModeInstant => 'Instant upload';

  @override
  String get dragModeInstantDesc =>
      'Upload files immediately to current server';

  @override
  String get dragModePending => 'Pending page';

  @override
  String get dragModePendingDesc => 'Select a server after dropping files';

  @override
  String get importConfig => 'Import config';

  @override
  String get exportConfig2 => 'Export config';

  @override
  String get selectFile => 'Select file';

  @override
  String get exportButton => 'Export';

  @override
  String get exportConfigTitle => 'Export configuration';

  @override
  String get exportConfigWarning =>
      'The exported file contains server passwords and Gotify tokens in plaintext. Keep it safe.';

  @override
  String get continueExport => 'Continue export';

  @override
  String get configExported => 'Config exported';

  @override
  String configExportFailed(Object error) {
    return 'Export failed: $error';
  }

  @override
  String get configFileExported => 'Config file exported';

  @override
  String get invalidConfigFile => 'Invalid config file';

  @override
  String get noServersFoundInConfig => 'No servers found (duplicate URL check)';

  @override
  String importedServers(Object count) {
    return 'Imported $count servers';
  }

  @override
  String importFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String get remoteSendConfig => 'RemoteSend config';

  @override
  String get pendingUploadTitle => 'Pending upload';

  @override
  String get selectedFilesLabel => 'Selected files';

  @override
  String fileCountLabel(Object count) {
    return 'Files: $count';
  }

  @override
  String totalSizeLabel(Object size) {
    return 'Size: $size';
  }

  @override
  String get selectServerLabel => 'Select server';

  @override
  String get dropFilesToStart => 'Drop files to start';

  @override
  String get currentServerLabel => 'Current server';

  @override
  String get expandText => 'Expand ↓';

  @override
  String get collapseText => 'Collapse ↑';

  @override
  String get openLink => 'Open';

  @override
  String get storageUsed => 'Used space';

  @override
  String get clearStorageTitle => 'Confirm deletion';

  @override
  String clearStorageConfirm(Object description) {
    return 'This will delete $description. This cannot be undone.';
  }

  @override
  String get deleteLabel => 'Delete';

  @override
  String get deleteFailedRetry => 'Delete failed, please retry';

  @override
  String get portableConfigPathFallback => 'config.json next to app';

  @override
  String get emojiHint => 'Only one emoji (Win+.)';

  @override
  String clearAllFiles(Object name) {
    return 'All files on $name';
  }

  @override
  String clearAllTexts(Object name) {
    return 'All texts on $name';
  }

  @override
  String get gotifySection => 'Gotify real-time events';

  @override
  String get gotifyEnabled => 'Enable Gotify';

  @override
  String get gotifyConfigure => 'Gotify connection';

  @override
  String get gotifyServerUrl => 'Gotify server URL';

  @override
  String get gotifyServerUrlHint => 'https://gotify.example.com';

  @override
  String get gotifyAppToken => 'Application token';

  @override
  String get gotifyClientToken => 'Client token';

  @override
  String get gotifyTokenStorageNotice =>
      'Tokens are displayed and stored in plaintext in the app configuration.';

  @override
  String get gotifyStatusDisabled => 'Disabled';

  @override
  String get gotifyStatusConnecting => 'Connecting...';

  @override
  String get gotifyStatusConnected => 'Connected';

  @override
  String get gotifyStatusReconnecting => 'Reconnecting...';

  @override
  String get gotifyStatusError => 'Connection error';

  @override
  String gotifyPendingEvents(Object count) {
    return '$count event(s) waiting to be sent';
  }

  @override
  String gotifyTextLatency(Object total, Object webdav) {
    return 'Last text event: total $total ms · WebDAV $webdav ms';
  }

  @override
  String gotifyFileLatency(Object total, Object webdav) {
    return 'Last file event: total $total ms · WebDAV list $webdav ms';
  }

  @override
  String get gotifyTest => 'Test';

  @override
  String get gotifyTestSuccess => 'Gotify connection succeeded';

  @override
  String gotifyTestFailed(Object error) {
    return 'Gotify connection failed: $error';
  }

  @override
  String get gotifyCredentialsRequired =>
      'Enter the server URL, application token, and client token';

  @override
  String get gotifyHistoryLookback => 'Reconnect message lookback';

  @override
  String get gotifyAutoCopyText => 'Copy newest received text';

  @override
  String get gotifyReceiveTextInBackground => 'Receive text in background';

  @override
  String get gotifyReceiveFilesInBackground => 'Receive files in background';

  @override
  String gotifyHistoryLookbackMinutes(Object count) {
    return '$count min';
  }

  @override
  String get gotifyTargets => 'Default receiving devices';

  @override
  String get gotifyAllDevices => 'All other devices';

  @override
  String get gotifyNoDevices => 'No other RemoteSend devices discovered yet';

  @override
  String get gotifyDeviceDiscoveryHint =>
      'Open RemoteSend on another configured device to discover it.';

  @override
  String get autoDownloadWifiOnly => 'Only on Wi-Fi or Ethernet';

  @override
  String get autoDownloadLimit => 'Auto-download size limit';

  @override
  String get autoDownloadUnlimited => 'Unlimited';

  @override
  String get countdownSeconds => 's';

  @override
  String get clipboardSyncTitle => 'Clipboard sync';

  @override
  String get clipboardSyncHistoryTitle => 'Clipboard sharing history';

  @override
  String get clipboardSyncHistoryLocalOnly =>
      'History files and archives stay on this device and are never uploaded to Gotify or WebDAV. Sync text still passes through Gotify temporarily and deletion is requested. After 30 days records are archived by month, not deleted.';

  @override
  String get clipboardSyncHistoryRecent => 'Last 30 days';

  @override
  String get clipboardSyncHistoryArchive => 'Monthly archive';

  @override
  String get clipboardSyncHistoryEmpty => 'No clipboard sharing records';

  @override
  String get clipboardSyncHistorySent => 'Sent';

  @override
  String get clipboardSyncHistoryReceived => 'Received';

  @override
  String get clipboardSyncHistoryClear => 'Clear all records';

  @override
  String get clipboardSyncHistoryClearConfirm =>
      'This deletes recent records and all local archives. This cannot be undone.';

  @override
  String get clipboardSyncHistoryOpen => 'View local sharing history';

  @override
  String get clipboardSyncNotice =>
      'Global clipboard sync uses your existing Gotify connection and target-device setting.';

  @override
  String get clipboardSyncStart => 'Start sync';

  @override
  String get clipboardSyncStop => 'Stop sync';

  @override
  String get clipboardSyncStopped => 'Stopped';

  @override
  String get clipboardSyncConnecting => 'Connecting / requesting Root';

  @override
  String get clipboardSyncWaiting => 'Connected; waiting for peer handshake';

  @override
  String get clipboardSyncRunning => 'Synchronization running';

  @override
  String get clipboardSyncReconnecting =>
      'Disconnected; reconnecting (no replay)';

  @override
  String get clipboardSyncPaused => 'Paused while device is locked';

  @override
  String get clipboardSyncFailed => 'Synchronization stopped with an error';

  @override
  String clipboardSyncCounts(int peers, int sent, int received) {
    return 'Ready peers: $peers · Sent: $sent · Applied: $received';
  }

  @override
  String get clipboardSyncNotification =>
      'Allow notifications so the ongoing sync service and Stop action stay visible.';

  @override
  String clipboardSyncError(String code) {
    return 'Sync issue ($code). Check the Gotify connection and Android Root authorization.';
  }

  @override
  String get clipboardSyncExclusive =>
      'Global clipboard sync is enabled. Stop it before using temporary auto-send.';

  @override
  String get clipboardSyncSimpleNotice =>
      'Turn this on on both devices. It reuses RemoteSend’s existing Gotify text channel and receiving-device setting—no extra key or pairing. Clipboard text is sent in plain text to Gotify; the server can read and retain it. Use HTTPS.';

  @override
  String get clipboardSyncUsesGotifyTargets =>
      'Using the existing Gotify receiving-device setting:';

  @override
  String get rootClipboardTitle => 'Root clipboard diagnostics';

  @override
  String get rootClipboardNotice =>
      'Experimental bridge only, not cross-device sync. Nothing is uploaded or saved. Root authorization is requested only when you start. Leaving this page stops the bridge; switching to another app keeps this test session running while RemoteSend stays alive.';

  @override
  String get rootClipboardSteps =>
      '1. Start and authorize in your root manager.\n2. Copy text in another app, then return and check the change count.\n3. Read metadata, or write a test and paste it in another app. Also test lock/unlock. Clipboard contents are never displayed here.';

  @override
  String get rootClipboardUnsupported =>
      'These diagnostics are available on Android only.';

  @override
  String get rootClipboardStart => 'Authorize and start';

  @override
  String get rootClipboardStop => 'Stop bridge';

  @override
  String get rootClipboardRead => 'Read metadata';

  @override
  String get rootClipboardProbe => 'Write test text';

  @override
  String get rootClipboardProbeConfirm =>
      'This replaces your phone\'s clipboard, then reads it back to verify a fixed test containing spaces and a newline. The previous contents are not restored. Continue?';

  @override
  String get rootClipboardIdle => 'Stopped';

  @override
  String get rootClipboardStarting =>
      'Starting or stopping… Root authorization may take up to 60 seconds.';

  @override
  String get rootClipboardActive => 'Bridge connected (not network sync)';

  @override
  String rootClipboardChanges(int count) {
    return 'Observed changes: $count';
  }

  @override
  String rootClipboardEnvironment(int sdk, int uid, int user, String api) {
    return 'Android API $sdk · UID $uid · user $user\nInterface: $api';
  }

  @override
  String rootClipboardMetadata(String kind, String bytes, String origin) {
    return '$kind · $bytes bytes · $origin';
  }

  @override
  String get rootClipboardKindText => 'Plain text';

  @override
  String get rootClipboardKindEmpty => 'Empty text';

  @override
  String get rootClipboardKindOther => 'Non-text content skipped';

  @override
  String get rootClipboardKindSensitive => 'Sensitive content skipped';

  @override
  String get rootClipboardKindLarge => 'Text over 32 KiB skipped';

  @override
  String get rootClipboardKindUnavailable =>
      'Empty or currently unreadable (for example, locked)';

  @override
  String get rootClipboardOriginBridge => 'Bridge-originated write';

  @override
  String get rootClipboardOriginOther => 'Other source';

  @override
  String get rootClipboardProbePassed =>
      'Test write/read matched exactly, including whitespace.';

  @override
  String get rootClipboardProbeFailed =>
      'The test did not match, or the clipboard changed before verification.';

  @override
  String rootClipboardError(String code) {
    return 'Bridge error ($code). Check root authorization and system compatibility. You can retry after a timeout.';
  }
}
