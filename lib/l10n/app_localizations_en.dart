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
  String get autoSyncOn => 'Auto-sync ON';

  @override
  String get autoSyncOff => 'Auto-sync OFF';

  @override
  String get refresh => 'Refresh';

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
  String get fileDepot => 'File Depot';

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
  String todayTime(Object time) {
    return 'Today $time';
  }

  @override
  String daysAgo(Object days) {
    return '$days days ago';
  }

  @override
  String get couldNotAccessFiles => 'Could not access files';

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
  String get failedToChangePortableMode => 'Failed to change portable mode';

  @override
  String get refreshInterval => 'Sync interval';

  @override
  String refreshIntervalSeconds(Object seconds) {
    return '$seconds seconds';
  }

  @override
  String get refreshIntervalDescription => 'Auto-sync polling interval';

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
  String get aboutDescription => 'RemoteSend v1.0.0';

  @override
  String get aboutLegalese => '© 2025 Wu-HZ';

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
}
