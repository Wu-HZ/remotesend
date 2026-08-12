# RemoteSend

轻量、便携、跨平台的 WebDAV 文本与文件传输工具。Windows & Android。

## 功能

- **文本桥接** — 聊天式界面，消息在设备间自动同步
- **文件仓库** — 上传、下载、管理文件，支持文件夹导航
- **传输队列** — 实时查看上传/下载进度，支持重试、清空
- **多服务器** — 配置多个 WebDAV 服务器，文本/文件可分别指定
- **拖拽上传** — 桌面端拖入文件即传，支持直接上传和待传两种模式
- **便携模式** — 配置文件放在软件目录下，适合 U 盘使用
- **跨平台** — Windows 和 Android
- **主题** — 浅色/深色/跟随系统，自定义强调色
- **Material You** — 支持动态取色
- **多语言** — 简体中文、English
- **无专用服务端** — 使用标准 WebDAV 协议（Nextcloud、Alist、群晖等）

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
2. 点击**添加服务器**，填入 WebDAV 信息
3. 点击**测试连接**验证
4. 分别为文本和文件选择要使用的服务器

### 文本传输
1. 进入**文本**页
2. 输入消息，点击发送
3. 消息在多设备间自动同步
4. 长按消息可删除

### 文件传输
1. 进入**文件**页
2. 点击 + 按钮上传文件或文件夹
3. 或直接将文件拖入窗口（桌面端）
4. 点击文件下载，长按查看删除等更多操作
5. 点击文件夹进入下一级

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
  "version": 4,
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
  "refreshIntervalSeconds": 3,
  "downloadLocation": "",
  "localName": "我的电脑",
  "themeMode": "system",
  "primaryColor": 4280391411,
  "useDynamicColor": true,
  "locale": "system",
  "dragMode": "instant",
  "chatOwnMessageLeft": false,
  "autoSyncEnabled": false
}
```

## 技术栈

- Flutter / Dart
- Riverpod 状态管理
- webdav_client + dio
- Material 3
- window_manager（桌面窗口）
- dynamic_color（Material You 取色）
- flutter_localizations（国际化）

## 开源协议

MIT License
