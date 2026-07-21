import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'RemoteSend'**
  String get appTitle;

  /// No description provided for @navText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get navText;

  /// No description provided for @navFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get navFiles;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @failedToLoadConfig.
  ///
  /// In en, this message translates to:
  /// **'Failed to load configuration:'**
  String get failedToLoadConfig;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select Date'**
  String get selectDate;

  /// No description provided for @autoSyncOn.
  ///
  /// In en, this message translates to:
  /// **'Auto-sync ON'**
  String get autoSyncOn;

  /// No description provided for @autoSyncOff.
  ///
  /// In en, this message translates to:
  /// **'Auto-sync OFF'**
  String get autoSyncOff;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @switchServer.
  ///
  /// In en, this message translates to:
  /// **'Switch server'**
  String get switchServer;

  /// No description provided for @configureWebDavToSync.
  ///
  /// In en, this message translates to:
  /// **'Configure WebDAV connection in Settings to sync'**
  String get configureWebDavToSync;

  /// No description provided for @notConnectedTestInSettings.
  ///
  /// In en, this message translates to:
  /// **'Not connected. Test connection in Settings'**
  String get notConnectedTestInSettings;

  /// No description provided for @configureWebDavToUseFileDepot.
  ///
  /// In en, this message translates to:
  /// **'Configure WebDAV connection in Settings to use File Depot'**
  String get configureWebDavToUseFileDepot;

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYet;

  /// No description provided for @noMessagesOnThisDay.
  ///
  /// In en, this message translates to:
  /// **'No messages on this day'**
  String get noMessagesOnThisDay;

  /// No description provided for @sendMessageToGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Send a message to get started'**
  String get sendMessageToGetStarted;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @messageMarkedForDeletion.
  ///
  /// In en, this message translates to:
  /// **'Message marked for deletion'**
  String get messageMarkedForDeletion;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @couldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get couldNotOpenLink;

  /// No description provided for @errorOpeningLink.
  ///
  /// In en, this message translates to:
  /// **'Error opening link: {error}'**
  String errorOpeningLink(Object error);

  /// No description provided for @typeAMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeAMessage;

  /// No description provided for @fileDepot.
  ///
  /// In en, this message translates to:
  /// **'File Depot'**
  String get fileDepot;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// No description provided for @openDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Open download folder'**
  String get openDownloadFolder;

  /// No description provided for @downloadingFile.
  ///
  /// In en, this message translates to:
  /// **'Downloading: {fileName}'**
  String downloadingFile(Object fileName);

  /// No description provided for @downloadingFileWithProgress.
  ///
  /// In en, this message translates to:
  /// **'Downloading: {fileName} ({current}/{total})'**
  String downloadingFileWithProgress(
    Object fileName,
    Object current,
    Object total,
  );

  /// No description provided for @uploadingFile.
  ///
  /// In en, this message translates to:
  /// **'Uploading: {fileName} ({current}/{total})'**
  String uploadingFile(Object fileName, Object current, Object total);

  /// No description provided for @uploadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get uploadingEllipsis;

  /// No description provided for @filesUploaded.
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total} files uploaded'**
  String filesUploaded(Object completed, Object total);

  /// No description provided for @idle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get idle;

  /// No description provided for @connectToWebDavToViewFiles.
  ///
  /// In en, this message translates to:
  /// **'Connect to WebDAV to view files'**
  String get connectToWebDavToViewFiles;

  /// No description provided for @noFilesYet.
  ///
  /// In en, this message translates to:
  /// **'No files yet'**
  String get noFilesYet;

  /// No description provided for @emptyFolder.
  ///
  /// In en, this message translates to:
  /// **'Empty folder'**
  String get emptyFolder;

  /// No description provided for @tapFileOrFolderToUpload.
  ///
  /// In en, this message translates to:
  /// **'Tap the File or Folder button to upload'**
  String get tapFileOrFolderToUpload;

  /// No description provided for @thisFolderIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get thisFolderIsEmpty;

  /// No description provided for @folder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @downloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Download Folder'**
  String get downloadFolder;

  /// No description provided for @todayTime.
  ///
  /// In en, this message translates to:
  /// **'Today {time}'**
  String todayTime(Object time);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days} days ago'**
  String daysAgo(Object days);

  /// No description provided for @couldNotAccessFiles.
  ///
  /// In en, this message translates to:
  /// **'Could not access files'**
  String get couldNotAccessFiles;

  /// No description provided for @addedFilesToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added {count} file(s) to upload queue'**
  String addedFilesToQueue(Object count);

  /// No description provided for @selectFolderToUpload.
  ///
  /// In en, this message translates to:
  /// **'Select folder to upload'**
  String get selectFolderToUpload;

  /// No description provided for @addedFolderToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added folder \"{name}\" to upload queue'**
  String addedFolderToQueue(Object name);

  /// No description provided for @downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded: {name}'**
  String downloaded(Object name);

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get downloadFailed;

  /// No description provided for @downloadedFolderWithCount.
  ///
  /// In en, this message translates to:
  /// **'Downloaded folder \"{name}\" ({count} files)'**
  String downloadedFolderWithCount(Object name, Object count);

  /// No description provided for @deleteFile.
  ///
  /// In en, this message translates to:
  /// **'Delete File'**
  String get deleteFile;

  /// No description provided for @deleteFileConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?\n\nThis cannot be undone.'**
  String deleteFileConfirm(Object name);

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted: {name}'**
  String deleted(Object name);

  /// No description provided for @failedToDeleteFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete file'**
  String get failedToDeleteFile;

  /// No description provided for @transferQueue.
  ///
  /// In en, this message translates to:
  /// **'Transfer Queue'**
  String get transferQueue;

  /// No description provided for @retryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry failed'**
  String get retryFailed;

  /// No description provided for @clearCompleted.
  ///
  /// In en, this message translates to:
  /// **'Clear completed'**
  String get clearCompleted;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @transferQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Transfer queue is empty'**
  String get transferQueueEmpty;

  /// No description provided for @filesWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Files will appear here when transferring'**
  String get filesWillAppearHere;

  /// No description provided for @uploadStatus.
  ///
  /// In en, this message translates to:
  /// **'Upload: {status}'**
  String uploadStatus(Object status);

  /// No description provided for @downloadStatus.
  ///
  /// In en, this message translates to:
  /// **'Download: {status}'**
  String downloadStatus(Object status);

  /// No description provided for @filesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String filesCount(Object count);

  /// No description provided for @filesProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total} files'**
  String filesProgress(Object completed, Object total);

  /// No description provided for @elapsed.
  ///
  /// In en, this message translates to:
  /// **'Elapsed'**
  String get elapsed;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'remaining'**
  String get remaining;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get statusUploading;

  /// No description provided for @statusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get statusDownloading;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @statusIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get statusIdle;

  /// No description provided for @clearQueue.
  ///
  /// In en, this message translates to:
  /// **'Clear Queue'**
  String get clearQueue;

  /// No description provided for @clearQueueConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear the entire upload queue? This will cancel any ongoing uploads.'**
  String get clearQueueConfirm;

  /// No description provided for @openFileFolderNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Open folder not supported on this platform'**
  String get openFileFolderNotSupported;

  /// No description provided for @failedToOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Failed to open folder: {error}'**
  String failedToOpenFolder(Object error);

  /// No description provided for @fileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found'**
  String get fileNotFound;

  /// No description provided for @openFileNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Open file not supported on this platform'**
  String get openFileNotSupported;

  /// No description provided for @failedToOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to open file: {error}'**
  String failedToOpenFile(Object error);

  /// No description provided for @openFile.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get openFile;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @sectionConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get sectionConnection;

  /// No description provided for @sectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get sectionGeneral;

  /// No description provided for @sectionDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get sectionDownload;

  /// No description provided for @sectionOthers.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get sectionOthers;

  /// No description provided for @configuredServers.
  ///
  /// In en, this message translates to:
  /// **'Configured Servers'**
  String get configuredServers;

  /// No description provided for @longPressToEditDelete.
  ///
  /// In en, this message translates to:
  /// **'Long press to edit/delete'**
  String get longPressToEditDelete;

  /// No description provided for @noServersConfigured.
  ///
  /// In en, this message translates to:
  /// **'No servers configured'**
  String get noServersConfigured;

  /// No description provided for @addServer.
  ///
  /// In en, this message translates to:
  /// **'Add Server'**
  String get addServer;

  /// No description provided for @editServer.
  ///
  /// In en, this message translates to:
  /// **'Edit Server'**
  String get editServer;

  /// No description provided for @deleteServer.
  ///
  /// In en, this message translates to:
  /// **'Delete Server'**
  String get deleteServer;

  /// No description provided for @deleteServerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteServerConfirm(Object name);

  /// No description provided for @serverAdded.
  ///
  /// In en, this message translates to:
  /// **'Server added'**
  String get serverAdded;

  /// No description provided for @serverUpdated.
  ///
  /// In en, this message translates to:
  /// **'Server updated'**
  String get serverUpdated;

  /// No description provided for @serverDeleted.
  ///
  /// In en, this message translates to:
  /// **'Server deleted'**
  String get serverDeleted;

  /// No description provided for @failedToSaveServer.
  ///
  /// In en, this message translates to:
  /// **'Failed to save server'**
  String get failedToSaveServer;

  /// No description provided for @failedToDelete.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete'**
  String get failedToDelete;

  /// No description provided for @textLabel.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textLabel;

  /// No description provided for @filesLabel.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get filesLabel;

  /// No description provided for @localName.
  ///
  /// In en, this message translates to:
  /// **'Local Name'**
  String get localName;

  /// No description provided for @localNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., My Phone'**
  String get localNameHint;

  /// No description provided for @localNameDescription.
  ///
  /// In en, this message translates to:
  /// **'This name will be shown in Text Bridge messages sent from this device.'**
  String get localNameDescription;

  /// No description provided for @nameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Name updated'**
  String get nameUpdated;

  /// No description provided for @failedToSave.
  ///
  /// In en, this message translates to:
  /// **'Failed to save'**
  String get failedToSave;

  /// No description provided for @portableMode.
  ///
  /// In en, this message translates to:
  /// **'Portable Mode'**
  String get portableMode;

  /// No description provided for @portableModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Save config next to executable (for USB drives)'**
  String get portableModeDescription;

  /// No description provided for @portableModeConfig.
  ///
  /// In en, this message translates to:
  /// **'Config: {path}'**
  String portableModeConfig(Object path);

  /// No description provided for @portableModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Portable mode enabled'**
  String get portableModeEnabled;

  /// No description provided for @portableModeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Portable mode disabled'**
  String get portableModeDisabled;

  /// No description provided for @failedToChangePortableMode.
  ///
  /// In en, this message translates to:
  /// **'Failed to change portable mode'**
  String get failedToChangePortableMode;

  /// No description provided for @refreshInterval.
  ///
  /// In en, this message translates to:
  /// **'Sync interval'**
  String get refreshInterval;

  /// No description provided for @refreshIntervalSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} seconds'**
  String refreshIntervalSeconds(Object seconds);

  /// No description provided for @refreshIntervalDescription.
  ///
  /// In en, this message translates to:
  /// **'Auto-sync polling interval'**
  String get refreshIntervalDescription;

  /// No description provided for @connectionStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectionStatusConnected;

  /// No description provided for @connectionStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connectionStatusConnecting;

  /// No description provided for @connectionStatusError.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get connectionStatusError;

  /// No description provided for @connectionStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get connectionStatusDisconnected;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @dynamicColor.
  ///
  /// In en, this message translates to:
  /// **'Dynamic Color'**
  String get dynamicColor;

  /// No description provided for @dynamicColorDescription.
  ///
  /// In en, this message translates to:
  /// **'Use system accent color (Material You)'**
  String get dynamicColorDescription;

  /// No description provided for @usingSystemColor.
  ///
  /// In en, this message translates to:
  /// **'Using system color'**
  String get usingSystemColor;

  /// No description provided for @color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// No description provided for @chooseColor.
  ///
  /// In en, this message translates to:
  /// **'Choose Color'**
  String get chooseColor;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorBlue;

  /// No description provided for @colorRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorRed;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorGreen;

  /// No description provided for @colorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorOrange;

  /// No description provided for @colorPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get colorPurple;

  /// No description provided for @colorCyan.
  ///
  /// In en, this message translates to:
  /// **'Cyan'**
  String get colorCyan;

  /// No description provided for @colorPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get colorPink;

  /// No description provided for @colorTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get colorTeal;

  /// No description provided for @colorIndigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get colorIndigo;

  /// No description provided for @colorYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get colorYellow;

  /// No description provided for @colorBrown.
  ///
  /// In en, this message translates to:
  /// **'Brown'**
  String get colorBrown;

  /// No description provided for @colorBlueGrey.
  ///
  /// In en, this message translates to:
  /// **'Blue Grey'**
  String get colorBlueGrey;

  /// No description provided for @colorCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get colorCustom;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Simplified)'**
  String get languageChinese;

  /// No description provided for @autoDownload.
  ///
  /// In en, this message translates to:
  /// **'Auto-download'**
  String get autoDownload;

  /// No description provided for @autoDownloadDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically download new files when detected'**
  String get autoDownloadDescription;

  /// No description provided for @downloadLocation.
  ///
  /// In en, this message translates to:
  /// **'Download location'**
  String get downloadLocation;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @downloadLocationUpdated.
  ///
  /// In en, this message translates to:
  /// **'Download location updated'**
  String get downloadLocationUpdated;

  /// No description provided for @selectDownloadLocation.
  ///
  /// In en, this message translates to:
  /// **'Select download location'**
  String get selectDownloadLocation;

  /// No description provided for @showNotification.
  ///
  /// In en, this message translates to:
  /// **'Show notification'**
  String get showNotification;

  /// No description provided for @showNotificationDescription.
  ///
  /// In en, this message translates to:
  /// **'Notify when download completes'**
  String get showNotificationDescription;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'RemoteSend v1.0.0'**
  String get aboutDescription;

  /// No description provided for @aboutLegalese.
  ///
  /// In en, this message translates to:
  /// **'© 2025 Wu-HZ'**
  String get aboutLegalese;

  /// No description provided for @aboutAppDescription.
  ///
  /// In en, this message translates to:
  /// **'A lightweight, portable app to transfer text and files between devices using WebDAV.'**
  String get aboutAppDescription;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get sourceCode;

  /// No description provided for @sourceCodeUrl.
  ///
  /// In en, this message translates to:
  /// **'github.com/Wu-HZ/remotesend'**
  String get sourceCodeUrl;

  /// No description provided for @openGitHub.
  ///
  /// In en, this message translates to:
  /// **'Open GitHub'**
  String get openGitHub;

  /// No description provided for @donation.
  ///
  /// In en, this message translates to:
  /// **'Donation'**
  String get donation;

  /// No description provided for @donationDescription.
  ///
  /// In en, this message translates to:
  /// **'Support the development'**
  String get donationDescription;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'{feature} - coming soon'**
  String comingSoon(Object feature);

  /// No description provided for @serverName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get serverName;

  /// No description provided for @serverNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Home NAS'**
  String get serverNameHint;

  /// No description provided for @serverNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get serverNameRequired;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Server URL'**
  String get serverUrl;

  /// No description provided for @serverUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com/webdav'**
  String get serverUrlHint;

  /// No description provided for @serverUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a server URL'**
  String get serverUrlRequired;

  /// No description provided for @serverUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid URL'**
  String get serverUrlInvalid;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a username'**
  String get usernameRequired;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a password'**
  String get passwordRequired;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

  /// No description provided for @testConnectionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success! Connection established.'**
  String get testConnectionSuccess;

  /// No description provided for @testConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String testConnectionFailed(Object error);

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String error(Object message);

  /// No description provided for @dropFilesToUpload.
  ///
  /// In en, this message translates to:
  /// **'Drop files here to upload'**
  String get dropFilesToUpload;

  /// No description provided for @connectToWebDavFirst.
  ///
  /// In en, this message translates to:
  /// **'Connect to WebDAV first'**
  String get connectToWebDavFirst;

  /// No description provided for @goToSettingsToConfigureConnection.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings to configure connection'**
  String get goToSettingsToConfigureConnection;

  /// No description provided for @connectToWebDavFirstToUploadFiles.
  ///
  /// In en, this message translates to:
  /// **'Connect to WebDAV first to upload files'**
  String get connectToWebDavFirstToUploadFiles;

  /// No description provided for @addedFilesAndFolders.
  ///
  /// In en, this message translates to:
  /// **'Added {files} file(s) and {folders} folder(s) to upload queue'**
  String addedFilesAndFolders(Object files, Object folders);

  /// No description provided for @addedFolders.
  ///
  /// In en, this message translates to:
  /// **'Added {count} folder(s) to upload queue'**
  String addedFolders(Object count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
