// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'RemoteSend';

  @override
  String get navText => '文本';

  @override
  String get navFiles => '文件';

  @override
  String get navSettings => '设置';

  @override
  String get retry => '重试';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get add => '添加';

  @override
  String get clear => '清除';

  @override
  String get close => '关闭';

  @override
  String get open => '打开';

  @override
  String get confirm => '确认';

  @override
  String get failedToLoadConfig => '加载配置失败：';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String get selectDate => '选择日期';

  @override
  String get autoSyncOn => '自动同步已开启';

  @override
  String get autoSyncOff => '自动同步已关闭';

  @override
  String get refresh => '刷新';

  @override
  String get switchServer => '切换服务器';

  @override
  String get configureWebDavToSync => '请在设置中配置WebDAV连接以同步';

  @override
  String get notConnectedTestInSettings => '未连接，请在设置中测试连接';

  @override
  String get configureWebDavToUseFileDepot => '请在设置中配置WebDAV连接以使用文件仓库';

  @override
  String get noMessagesYet => '暂无消息';

  @override
  String get noMessagesOnThisDay => '当天没有消息';

  @override
  String get sendMessageToGetStarted => '发送一条消息开始吧';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get sendClipboardContent => '发送剪贴板内容';

  @override
  String get messageMarkedForDeletion => '消息已标记删除';

  @override
  String get undo => '撤销';

  @override
  String get couldNotOpenLink => '无法打开链接';

  @override
  String errorOpeningLink(Object error) {
    return '打开链接时出错：$error';
  }

  @override
  String get typeAMessage => '输入消息...';

  @override
  String get fileDepot => '文件仓库';

  @override
  String get goBack => '返回';

  @override
  String get openDownloadFolder => '打开下载文件夹';

  @override
  String downloadingFile(Object fileName) {
    return '正在下载：$fileName';
  }

  @override
  String downloadingFileWithProgress(
    Object fileName,
    Object current,
    Object total,
  ) {
    return '正在下载：$fileName（$current/$total）';
  }

  @override
  String uploadingFile(Object fileName, Object current, Object total) {
    return '正在上传：$fileName（$current/$total）';
  }

  @override
  String get uploadingEllipsis => '正在上传...';

  @override
  String filesUploaded(Object completed, Object total) {
    return '已上传 $completed/$total 个文件';
  }

  @override
  String filesDownloaded(Object completed, Object total) {
    return '已下载 $completed/$total 个文件';
  }

  @override
  String get idle => '空闲';

  @override
  String get connectToWebDavToViewFiles => '连接WebDAV以查看文件';

  @override
  String get noFilesYet => '暂无文件';

  @override
  String get emptyFolder => '空文件夹';

  @override
  String get tapFileOrFolderToUpload => '点击文件或文件夹按钮上传';

  @override
  String get thisFolderIsEmpty => '此文件夹为空';

  @override
  String get folder => '文件夹';

  @override
  String get file => '文件';

  @override
  String get download => '下载';

  @override
  String get downloadFolder => '下载文件夹';

  @override
  String todayTime(Object time) {
    return '今天 $time';
  }

  @override
  String daysAgo(Object days) {
    return '$days天前';
  }

  @override
  String get couldNotAccessFiles => '无法访问文件';

  @override
  String addedFilesToQueue(Object count) {
    return '已添加 $count 个文件到上传队列';
  }

  @override
  String get selectFolderToUpload => '选择要上传的文件夹';

  @override
  String addedFolderToQueue(Object name) {
    return '已添加文件夹 $name 到上传队列';
  }

  @override
  String downloaded(Object name) {
    return '已下载：$name';
  }

  @override
  String get openFolder => '打开文件夹';

  @override
  String get downloadFailed => '下载失败';

  @override
  String downloadedFolderWithCount(Object name, Object count) {
    return '已下载文件夹 $name（$count个文件）';
  }

  @override
  String get deleteFile => '删除文件';

  @override
  String deleteFileConfirm(Object name) {
    return '确定要删除 $name 吗？\n\n此操作无法撤销。';
  }

  @override
  String deleted(Object name) {
    return '已删除：$name';
  }

  @override
  String get failedToDeleteFile => '删除文件失败';

  @override
  String get transferQueue => '传输队列';

  @override
  String get retryFailed => '重试失败项';

  @override
  String get clearCompleted => '清除已完成';

  @override
  String get clearAll => '清除全部';

  @override
  String get transferQueueEmpty => '传输队列为空';

  @override
  String get filesWillAppearHere => '传输文件时会显示在这里';

  @override
  String uploadStatus(Object status) {
    return '上传：$status';
  }

  @override
  String downloadStatus(Object status) {
    return '下载：$status';
  }

  @override
  String filesCount(Object count) {
    return '$count 个文件';
  }

  @override
  String filesProgress(Object completed, Object total) {
    return '$completed/$total 个文件';
  }

  @override
  String get elapsed => '已用时间';

  @override
  String get duration => '总时长';

  @override
  String get remaining => '剩余';

  @override
  String get statusPending => '等待中';

  @override
  String get statusUploading => '上传中';

  @override
  String get statusDownloading => '下载中';

  @override
  String get statusCompleted => '已完成';

  @override
  String get statusFailed => '失败';

  @override
  String get statusIdle => '空闲';

  @override
  String get clearQueue => '清空队列';

  @override
  String get clearQueueConfirm => '确定要清空整个上传队列吗？这将取消所有正在进行的上传。';

  @override
  String get openFileFolderNotSupported => '此平台不支持打开文件夹';

  @override
  String failedToOpenFolder(Object error) {
    return '打开文件夹失败：$error';
  }

  @override
  String get fileNotFound => '文件未找到';

  @override
  String get openFileNotSupported => '此平台不支持打开文件';

  @override
  String failedToOpenFile(Object error) {
    return '打开文件失败：$error';
  }

  @override
  String get openFile => '打开文件';

  @override
  String get settings => '设置';

  @override
  String get sectionConnection => '连接';

  @override
  String get sectionGeneral => '通用';

  @override
  String get sectionDownload => '下载';

  @override
  String get sectionOthers => '其他';

  @override
  String get configuredServers => '服务器';

  @override
  String get longPressToEditDelete => '长按编辑/删除';

  @override
  String get noServersConfigured => '未配置服务器';

  @override
  String get addServer => '添加服务器';

  @override
  String get editServer => '编辑服务器';

  @override
  String get deleteServer => '删除服务器';

  @override
  String deleteServerConfirm(Object name) {
    return '确定要删除 $name 吗？';
  }

  @override
  String get serverAdded => '服务器已添加';

  @override
  String get serverUpdated => '服务器已更新';

  @override
  String get serverDeleted => '服务器已删除';

  @override
  String get failedToSaveServer => '保存服务器失败';

  @override
  String get failedToDelete => '删除失败';

  @override
  String get textLabel => '文本';

  @override
  String get filesLabel => '文件';

  @override
  String get enabledLabel => '已启用';

  @override
  String get disabledLabel => '已禁用';

  @override
  String get localName => '本地名称';

  @override
  String get localNameHint => '例如：我的手机';

  @override
  String get localNameDescription => '此名称将显示在从该设备发送的文本消息中。';

  @override
  String get nameUpdated => '名称已更新';

  @override
  String get failedToSave => '保存失败';

  @override
  String get portableMode => '便携模式';

  @override
  String get portableModeDescription => '将配置保存在程序旁边（用于U盘）';

  @override
  String portableModeConfig(Object path) {
    return '配置：$path';
  }

  @override
  String get portableModeEnabled => '便携模式已启用';

  @override
  String get portableModeDisabled => '便携模式已禁用';

  @override
  String get failedToChangePortableMode => '更改便携模式失败';

  @override
  String get refreshInterval => '同步间隔';

  @override
  String refreshIntervalSeconds(Object seconds) {
    return '$seconds 秒';
  }

  @override
  String get refreshIntervalDescription => '自动同步的轮询间隔';

  @override
  String get connectionStatusConnected => '已连接';

  @override
  String get connectionStatusConnecting => '连接中...';

  @override
  String get connectionStatusError => '连接错误';

  @override
  String get connectionStatusDisconnected => '未连接';

  @override
  String get theme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get dynamicColor => '动态颜色';

  @override
  String get dynamicColorDescription => '使用系统强调色（Material You）';

  @override
  String get usingSystemColor => '使用系统颜色';

  @override
  String get color => '颜色';

  @override
  String get chooseColor => '选择颜色';

  @override
  String get colorBlue => '蓝色';

  @override
  String get colorRed => '红色';

  @override
  String get colorGreen => '绿色';

  @override
  String get colorOrange => '橙色';

  @override
  String get colorPurple => '紫色';

  @override
  String get colorCyan => '青色';

  @override
  String get colorPink => '粉色';

  @override
  String get colorTeal => '蓝绿色';

  @override
  String get colorIndigo => '靛蓝色';

  @override
  String get colorYellow => '黄色';

  @override
  String get colorBrown => '棕色';

  @override
  String get colorBlueGrey => '蓝灰色';

  @override
  String get colorCustom => '自定义';

  @override
  String get language => '语言';

  @override
  String get languageEnglish => '英语';

  @override
  String get languageChinese => '简体中文';

  @override
  String get autoDownload => '自动下载';

  @override
  String get autoDownloadDescription => '检测到新文件时自动下载';

  @override
  String get downloadLocation => '下载位置';

  @override
  String get systemDefault => '系统默认';

  @override
  String get downloadLocationUpdated => '下载位置已更新';

  @override
  String get selectDownloadLocation => '选择下载位置';

  @override
  String get showNotification => '显示通知';

  @override
  String get showNotificationDescription => '下载完成时通知';

  @override
  String get about => '关于';

  @override
  String get aboutDescription => 'RemoteSend v1.0.0';

  @override
  String get aboutLegalese => '© 2025 Wu-HZ';

  @override
  String get aboutAppDescription => '一款轻量级、便携的应用，用于通过WebDAV在设备之间传输文本和文件。';

  @override
  String get sourceCode => '源代码';

  @override
  String get sourceCodeUrl => 'github.com/Wu-HZ/remotesend';

  @override
  String get openGitHub => '打开GitHub';

  @override
  String get donation => '捐赠';

  @override
  String get donationDescription => '支持开发';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String comingSoon(Object feature) {
    return '$feature - 即将推出';
  }

  @override
  String get serverName => '名称';

  @override
  String get serverNameHint => '例如：家庭NAS';

  @override
  String get serverNameRequired => '请输入名称';

  @override
  String get serverUrl => 'WebDAV服务器URL';

  @override
  String get serverUrlHint => 'https://example.com/webdav';

  @override
  String get serverUrlRequired => '请输入服务器URL';

  @override
  String get serverUrlInvalid => '请输入有效的URL';

  @override
  String get username => '用户名';

  @override
  String get usernameRequired => '请输入用户名';

  @override
  String get password => '密码';

  @override
  String get passwordRequired => '请输入密码';

  @override
  String get testConnection => '测试连接';

  @override
  String get testConnectionSuccess => '成功！已建立连接。';

  @override
  String testConnectionFailed(Object error) {
    return '失败：$error';
  }

  @override
  String error(Object message) {
    return '错误：$message';
  }

  @override
  String get dropFilesToUpload => '拖放文件到此处上传';

  @override
  String get chatOwnMessageLeftLabel => '自己消息显示在左侧';

  @override
  String get chatOwnMessageLeftDescription => '将自己的消息也放在左侧，与远程消息对齐';

  @override
  String get connectToWebDavFirst => '请先连接WebDAV';

  @override
  String get goToSettingsToConfigureConnection => '前往设置配置连接';

  @override
  String get connectToWebDavFirstToUploadFiles => '请先连接WebDAV以上传文件';

  @override
  String addedFilesAndFolders(Object files, Object folders) {
    return '已添加 $files 个文件和 $folders 个文件夹到上传队列';
  }

  @override
  String addedFolders(Object count) {
    return '已添加 $count 个文件夹到上传队列';
  }
}
