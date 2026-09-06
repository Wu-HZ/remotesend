# RemoteSend

轻量、便携、跨平台的设备间文本与文件传输工具。WebDAV 存储数据，Gotify 提供可选的实时事件。Windows & Android。

## 功能

- **文本桥接** — 聊天式界面，通过 Gotify 通知其他设备一次性拉取新文本
- **文件仓库** — 上传、下载、管理文件，支持文件夹导航和事件驱动的自动下载
- **传输队列** — 实时查看上传/下载进度，支持重试、清空
- **多服务器** — 配置多个 WebDAV 服务器，文本/文件可分别指定
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

### 文件传输
1. 进入**文件**页
2. 点击 + 按钮上传文件或文件夹
3. 或直接将文件拖入窗口（桌面端）
4. 上传完成后，Gotify 会通知全部其他设备或设置中选择的指定设备
5. 接收设备收到事件后会对当前文件目录执行一次刷新，不会轮询 WebDAV
6. 接收设备还可按本机策略自动下载（开关、网络类型、大小上限和目录）

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
  "version": 10,
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
  "localName": "我的电脑",
  "themeMode": "system",
  "primaryColor": 4280391411,
  "useDynamicColor": true,
  "locale": "system",
  "dragMode": "instant",
  "chatOwnMessageLeft": false,
  "gotify": {
    "enabled": true,
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
