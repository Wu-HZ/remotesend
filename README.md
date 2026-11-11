# RemoteSend

轻量、便携、跨平台的设备间文本与文件传输工具。WebDAV 存储数据，Gotify 提供可选的实时事件。Windows & Android。

## 功能

- **文本桥接** — WebDAV 模式保留历史与日期；可将 Gotify 注册为仅支持实时文本的服务器，直接收发正文
- **临时自动发送** — 文本页一键开启剪贴板文本自动发送，随时停止，不保存开启状态
- **文件仓库** — 上传、下载、管理文件，支持文件夹导航和事件驱动的自动下载
- **Android 打开方式** — 在其他应用选择“用 RemoteSend 打开”文件，导入待发送列表，确认后再发送
- **传输队列** — 实时查看上传/下载进度，支持重试、清空；可开关成功记录的 5 分钟自动清理（默认开启），失败任务保留
- **多服务器** — 配置多个 WebDAV 服务器，文本/文件可分别指定
- **可配置启动页** — 启动时默认进入文本页或文件页
- **拖拽上传** — 桌面端拖入文件即传，支持直接上传和待传两种模式
- **便携模式** — 配置文件放在软件目录下，适合 U 盘使用
- **跨平台** — Windows 和 Android
- **主题** — 浅色/深色/跟随系统，自定义强调色
- **Material You** — 支持动态取色
- **多语言** — 简体中文、English
- **自托管友好** — 支持标准 WebDAV（Nextcloud、Alist、群晖等）和自建 Gotify

## 安装

### Windows
1. 下载发布页的 ZIP 包
2. 解压到任意目录（U 盘即为便携模式）
3. 运行 `remote_send.exe`

### Android
1. 下载 APK 安装
2. 授予存储权限

## 使用

### 初次配置
1. 打开应用，进入**设置**
2. 点击**添加服务器**，填入 WebDAV 信息并测试连接
3. 分别为文本和文件选择要使用的服务器
4. 如需实时接收，建议在 Gotify 中创建专用用户，并在该用户下创建 RemoteSend 应用和客户端
5. 在每台设备填写相同的 Gotify 地址和应用令牌，并填写各自的客户端令牌
6. 开启 Gotify 后打开其他设备上的 RemoteSend，以完成设备发现

### 文本传输
1. 进入**文本**页
2. 输入消息，点击发送
3. Gotify 通知目标设备从 WebDAV 拉取本次更新
4. 接收设备可独立开启“自动复制最新接收文本”，每批只复制最新新增的一条；来源服务器只需已配置并启用，不必是当前选中的文本服务器
5. 未配置 Gotify 时可使用右上角按钮手动刷新
6. 长按消息可删除

#### Gotify 实时文本服务器

1. 两台设备均升级到支持此功能的版本，在 **设置 → Gotify** 配置同一 Gotify 应用的地址和应用令牌，以及各自可读取该应用的客户端令牌；设备 ID 应不同。
2. 启用 Gotify，并在两端开启 **注册为文本服务器**（默认关闭）。注册不会自动切换当前文本服务器。
3. 在文本页的服务器选择器中选择 **Gotify**，或在设置的服务器条目上选择“文本”。条目与 WebDAV 使用相同样式，“文件”按钮置灰不可用；顶部连接状态和文本聊天界面也保持相同样式，仅隐藏不支持的日期和用量组件，右上角刷新按钮保留；在 Gotify 模式下点击不会读取历史或改变当前会话。即使没有 WebDAV，也可使用这个入口。
4. 等待连接就绪后，手动发送、粘贴发送、临时剪贴板自动发送和系统分享文本都通过 Gotify 直传；沿用目标设备设置。

服务器条目的启用按钮对应 Gotify 主开关；长按可编辑连接及 Emoji 图标（与 WebDAV 相同，留空恢复默认云图标），或删除这个文本服务器注册，删除注册不会关闭原有 Gotify 通知。注册开关下不额外显示功能说明。

Gotify 服务器不能作为文件目标。它只有当前运行期间的内存会话（最多 200 条），没有文本历史、日期导航或离线投递；重启、取消注册或切换连接身份会清空会话。断线不会转存 WebDAV，也不会在以后从持久化队列偷偷补发。超时可能意味着服务端已接收，界面会明确标记结果不确定；手动重试复用消息 ID。

正文上限为 32 KiB（UTF-8，服务端可能限制得更小）。RemoteSend 不持久化直传正文，但 Gotify 服务端仍可能留存；目标设备过滤不等于端到端加密，建议使用 HTTPS。已有 WebDAV 文本历史、文件传输和更新通知不变。

#### 临时自动发送剪贴板

点击发送按钮旁的自动发送图标开启，图标高亮并显示“正在自动发送 · 点击停止”。开启后只发送新复制的非空文本，不发送剪贴板原有内容，也不会改动输入框草稿。悬停或长按状态文字可查看使用提示。

- Windows 可切到其他应用逐段复制，RemoteSend 会按检测顺序排队发送；应用内复制及自动复制的接收文本不会回传，避免循环。
- 手机受系统限制，只能在 RemoteSend 前台读取剪贴板；从其他应用返回文本页后发送当前最后一条文本，无法收集后台期间的全部复制记录。
- 约每 0.5 秒检测一次，相同内容不会连续重复发送，检测间隔内的多次快速复制可能只读到最后一条。
- 再次点击图标或状态文字即可停止；离开文本页、切换服务器、断开连接或读取/发送失败也会停止，重新进入或重启不会自动开启。
- 停止会清空尚未发送的队列，已开始的发送可能仍会完成。失败后请检查连接并手动重试。

此功能仅为当前文本页的临时会话，不会注册全局或永久后台监听。

#### 全局剪贴板同步（Windows ⇄ Android）

两端进入 **设置 → Gotify → 剪贴板同步**，打开开关即可；复用已有 Gotify 连接，无需同步密钥、设备 ID 或额外配对。发送目标沿用 **默认接收设备**（选“所有其他设备”时也广播剪贴板）。**本机共享记录**保存在应用本地：最近 30 天显示在最近列表，之后按月归档，不自动删除；可手动清空，不上传 Gotify/WebDAV。支持 Windows 与 Android 双向同步，与文本页当前选择无关。

- 只观察纯文本，保留空格和换行；首次启动只建立基线，不发送已有剪贴板。仅发送变化的最新内容，跳过空文本、NUL、超过 32 KiB 和系统标记的敏感剪贴板。非 Android Windows/macOS 管理的私密标记也会遵守；Android 锁屏期间暂停读写。
- 复用 Gotify 实时文本通道和现有令牌，不使用独立的同步密钥。剪贴板正文会以明文 HTTPS 请求经过 Gotify，服务端可读取；发送成功后软件会请求删除该 Gotify 消息（尽力而为，删除失败时仍可能按服务器策略保留）。
- 手动开启全局同步后会记住开关状态；重新打开 RemoteSend 时会恢复同步（Windows 重建会话，Android 服务仍在则接管状态，已退出则在已授予通知权限的前提下重新启动服务，可能再次触发 Root 管理器授权）。手动关闭或通过 Android 常驻通知停止后不会再自动恢复。Android 首次点击开启仍需允许通知并授权 Root；不会在开机后无须打开应用就自行启动。系统杀进程后的保活取决于 Root 管理器、ROM 和省电策略。
- 断线不会补发或重放；重连及锁屏状态变化会重建会话，旧会话／过期消息会丢弃。不会读取 Gotify 历史；握手控制消息和已发送的剪贴板消息都会请求从 Gotify 删除，但失败时服务器可能仍保留。
- Windows 收到并成功写入剪贴板后，会在当前屏幕右下角显示带 RemoteSend 图标、接收提示和正文预览的浮层，不抢占当前应用焦点；长文本只截取浮层预览，实际剪贴板和本机记录保留完整内容。系统托盘通知仍是辅助提醒；提示文案遵循应用语言设置。全局同步与文本页“临时自动发送”互斥；停止全局同步后，临时功能不会自动恢复。使用系统剪贴板会让获准设备能读取新复制内容；应用会按上述规则在本机保存共享记录，但不上传这份历史。剪贴板本身、接收设备和相关系统组件仍属于信任边界。系统未标记敏感的密码内容无法可靠识别。

这是显式选择的 Gotify 同步通道，不等同于在设备间自动同步所有聊天消息。详见 [剪贴板同步协议与平台说明](docs/design/clipboard-sync-root-bridge.md)。

#### Android Root 剪贴板桥接验证（实验）

进入 **设置 → 其他 → Root 剪贴板诊断**，手动点击“授权并启动”，在 Magisk / KernelSU 等管理器中批准 Root 请求。桥接进程实际使用 shell UID 2000，避免以 Root 身份长期处理剪贴板；不安装模块、不修改 SELinux 或系统剪贴板权限。

- 切到其他应用复制文本，返回查看变更次数和元数据；不展示或保存正文，不上传到 Gotify。
- “读取元数据”用于验证读权限；“写入测试文本”需确认，会覆盖当前剪贴板，再核对原文（含换行、空格和 Unicode）。
- 返回退出诊断页或停止桥接会清理进程；切换到其他应用不会主动停止，但本阶段不提供独立保活或开机自启。
- 已标记敏感、非文本或超过 32 KiB 的内容会跳过；锁屏时可能暂不可读。并非所有密码软件都会标记敏感内容。

Root 桥接已在设备上验证；Android 后台常驻仍受 Root 管理器和厂商省电策略影响。安装新版本后请实测 Windows ⇄ Android 双向粘贴；详见 [Root 桥接与同步设计](docs/design/clipboard-sync-root-bridge.md)。

### 文件传输
1. 进入**文件**页
2. 点击 + 按钮上传文件或文件夹
3. 或直接将文件拖入窗口（桌面端）
4. 上传完成后，Gotify 会通知全部其他设备或设置中选择的指定设备
5. 接收设备收到事件后会对当前文件目录执行一次刷新，不会轮询 WebDAV
6. 接收设备还可按本机策略自动下载（开关、网络类型、大小上限和目录）

Android 也可在文件管理器或其他应用的“打开方式／使用其他应用打开”中选择 RemoteSend。支持 `content://` 和 `file://` 文件，不接管网页链接；文件会先复制到应用私有暂存区并加入待发送列表，无论普通分享是否设为立即发送，都需要你确认发送。支持未启动和已运行时接收；需要来源应用提供可读取的文件及临时访问授权，原文件不会被修改或删除。部分应用自行限制可选应用时，仍可能不会显示 RemoteSend。

桌面版还可在 **设置 → 本机上传 API** 中手动开启仅供本机脚本/AI 使用的上传入口。编译其他项目后运行 `python remotesend_upload.py <产物路径>` 即可复用 RemoteSend 的文件服务器、传输队列及 Gotify 通知；软件必须保持运行。Pi 专用的“通过 RemoteSend 上传”插件在独立仓库 [remotesend-pi-upload](https://github.com/Wu-HZ/remotesend-pi-upload) 发布，供其它设备下载安装。详见 [本机上传 API 使用说明](docs/local-upload-api.md)。

传输队列页顶部可开启或关闭“自动清理成功记录”，默认开启，选择会保存并在重启后恢复。关闭时停止自动清理，重新开启后现有成功记录重新计时 5 分钟。

开启后上传/下载成功记录各自保留 5 分钟，到期自动从任务列表移除；若队列仍在传输，则等空闲后清理到期记录。失败和等待中的任务保留，取消/手动清空的行为不变。清理仅移除任务记录，不删除文件，也不影响文件列表中的“已下载”标记；无需打开传输队列页面也会自动清理。

已下载文件通过大小、修改时间和 WebDAV ETag 判断远端版本；版本未变时不会重复下载。远端同名文件更新后会重新下载，如果本地旧文件仍存在，则使用 `文件名 (1).扩展名` 等可用名称保存，避免覆盖或因文件正被占用而失败。

> 当前 Gotify WebSocket 仅在 RemoteSend 运行期间保持连接；重新上线时只接收本机设置的最近 1–5 分钟事件（默认 3 分钟），更早的事件会被丢弃。每台设备可分别控制后台文本和文件接收，默认后台接收文本、暂停文件；回到前台时处理回溯期内的暂存通知。Android 进程被系统回收后也会恢复仍在回溯期内的后台通知。Windows 窗口失焦即视为后台。RemoteSend 不会自动轮询 WebDAV。
>
> Gotify 设置区会显示最近文本和文件事件的总响应时间及其中的 WebDAV 操作耗时，用于判断延迟来自实时通知还是存储服务器；总响应时间依赖发送端与接收端的系统时钟基本同步。

## WebDAV 目录结构

```
/RemoteSend/
├── Messages/              # 按日期存储的消息
│   └── yyyy-MM-dd.json
└── Files/                 # 上传的文件和文件夹
```

## 从源码构建

```bash
git clone https://github.com/Wu-HZ/remotesend.git
cd remotesend

# 安装依赖
flutter pub get

# 生成多语言文件（必须）
flutter gen-l10n

# 生成图标
pip install Pillow
python generate_icon.py

# Windows
flutter build windows --release

# Android
flutter build apk --release --target-platform android-arm64
```

## 配置

### 便携模式

在设置中将数据位置选为"便携模式"，或在 exe 旁手动创建 `config.json`：

```json
{
  "version": 15,
  "servers": [
    {
      "id": "uuid",
      "name": "我的服务器",
      "serverUrl": "https://example.com/dav",
      "username": "用户名",
      "password": "密码",
      "emoji": "☁️",
      "enabled": true,
      "createdAt": "2026-01-01T00:00:00.000"
    }
  ],
  "activeTextServerId": "uuid",
  "activeFilesServerId": "uuid",
  "portableMode": true,
  "downloadLocation": "",
  "androidFolderOpenerComponent": "",
  "androidFolderOpenerLabel": "",
  "localName": "我的电脑",
  "themeMode": "system",
  "primaryColor": 4280391411,
  "useDynamicColor": true,
  "locale": "system",
  "dragMode": "instant",
  "startPage": "text",
  "chatOwnMessageLeft": false,
  "autoClearTransferHistory": true,
  "localUploadApiEnabled": false,
  "localUploadApiToken": "",
  "gotify": {
    "enabled": true,
    "registerAsTextServer": false,
    "serverUrl": "https://gotify.example.com",
    "appToken": "应用令牌",
    "clientToken": "本设备客户端令牌",
    "deviceId": "设备 UUID",
    "autoDownloadEnabled": true,
    "wifiOnly": true,
    "maxAutoDownloadBytes": 1073741824,
    "targetDeviceIds": [],
    "autoCopyTextEnabled": false,
    "receiveTextInBackground": true,
    "receiveFilesInBackground": false,
    "historyLookbackMinutes": 3
  }
}
```

设置中的「下载位置」可选系统下载文件夹（默认）、程序旁的 Downloads（适合 U 盘）或自定义文件夹。选程序旁下载时，请同时启用便携模式保存配置；`downloadLocation` 会保存为 `portable://Downloads`，每次运行时按当前程序位置解析。实际文件存放在 `程序目录/Downloads/服务器子目录/`；切换位置不会移动已有文件。

Android 可在「设置 → 下载 → 打开下载文件夹的应用」查看各应用图标、名称与包名并选择 MT 管理器等已安装应用，以后在文件页或传输队列点「打开下载文件夹」时直接打开所选应用，不再依赖系统“始终”的记录。默认仍由系统选择；如果选定的应用卸载或不支持该目录，会提示返回设置重新选择。

## 技术栈

- Flutter / Dart
- Riverpod 状态管理
- webdav_client + dio（WebDAV 与 Gotify REST）
- Gotify WebSocket（实时事件与离线恢复）
- Material 3
- window_manager（桌面窗口）
- dynamic_color（Material You 取色）
- flutter_localizations（国际化）

## 致谢

本项目的 UI 设计大量参考了 [LocalSend](https://github.com/localsend/localsend)，在此表示感谢。

## 开源协议

Apache License 2.0
