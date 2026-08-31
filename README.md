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
4. 未配置 Gotify 时可使用右上角按钮手动刷新
5. 长按消息可删除

### 文件传输
1. 进入**文件**页
2. 点击 + 按钮上传文件或文件夹
3. 或直接将文件拖入窗口（桌面端）
4. 上传完成后，Gotify 会通知全部其他设备或设置中选择的指定设备
5. 接收设备可按本机策略自动下载（开关、网络类型、大小上限和目录）
6. 未启用自动下载时仍可手动刷新并下载

> 当前 Gotify WebSocket 仅在 RemoteSend 运行期间保持连接；应用重新连接时会从 Gotify 恢复遗漏事件。RemoteSend 不会自动轮询 WebDAV。

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
  "version": 7,
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
    "targetDeviceIds": []
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
