# 运行验证记录

## 已验证环境
- Windows 11、Git Bash、Python 3.12.2、JDK 20.0.2。
- Flutter 3.38.6 / Dart 3.10.7；Flutter 与 Pub 缓存位于 D 盘。
- Android SDK 已安装；USB 调试已授权；实机 Android 15、arm64。
- 同时存在一个 Android 9 模拟器，因此驱动必须显式选择设备或只自动选择唯一已授权真机。

## 本次会话中实际遇到的问题
1. 常规 Flutter Android 构建访问 Gradle 代理 `127.0.0.1:7897` 被拒绝。用 curl 验证 Google Maven 与 Maven Central 直连均返回 200；仅在该次 Gradle 命令加入空代理 host 和 nonProxyHosts 参数后成功下载。不改全局代理配置。
2. 新 image_picker_android 的 AndroidX 依赖要求 AGP >= 8.9.1，项目原版本为 8.7.3。当前工作区调整为 AGP 8.9.1、Kotlin 2.3.20。
3. Kotlin 2.3.20 不再接受 Kotlin DSL 中的 `kotlinOptions.jvmTarget`。当前工作区迁移到 `kotlin.compilerOptions.jvmTarget.set(JvmTarget.JVM_11)`，与 Java 11 target 保持一致。
4. Python 在 Windows 的默认输出编码导致中文层级文本乱码；驱动固定 UTF-8 输出。
5. ADB 层级中的导航标签包含换行及“第几个标签”提示，不能直接按整个标签字符串相等查找；根据第一行匹配，再取真实 bounds，不能写死手机坐标。

## 已完成的真实交互（编写驱动前）
- Gradle assembleDebug 构建成功。
- adb install -r 返回 Success，保留原应用配置，不卸载、不清除数据。
- am start -W 返回 Status: ok。
- 通过 uiautomator 找到文件导航并点击，截图显示文件页与拍照按钮；已实际查看截图。
- Flutter 全量测试：45 项通过。

## 驱动验证（2026-10-01）
- `doctor` 成功：自动发现 Flutter、Android SDK 和唯一已授权真机，并忽略同时在线的模拟器。
- 驱动遵循本机既有 PUB_CACHE，实际为 D:/SDK/Pub/Cache；它与 SDK、仓库仍在同一盘，没有改动全局配置。
- 首次 `run` 完成构建和安装，但手机锁屏导致导航超时；检查层级只有 com.android.systemui，未截取锁屏。用户解锁后重试。
- `drive` 成功启动、根据层级 bounds 点击文件导航并截图；已查看 PNG，确认文件页和拍照按钮正常。
- 完整 `--direct run` 成功：Gradle BUILD SUCCESSFUL、安装 Success、启动 Status: ok，并输出 camera_button_visible=true。截图保存在被 Git 忽略的 build/run-remotesend 下。
- 独立 screenshot 命令成功，应用测试 45 项通过，驱动测试 7 项通过；stop 成功停止应用。
- 写完说明后的新 shell 整套复验中，手机再次锁屏，界面检查按预期失败，后续串联命令未执行。各说明命令此前都已单独或在完整链路中执行成功；不把该最后一次串联复验记录为通过。需要解锁并持续亮屏，驱动不会修改手机自动锁屏设置。

## 验证边界
- 这是 Windows 主机驱动 Android 实机的记录，不是 Linux 容器或全新空白机器的验证。
- 尚未验证 SDK/JDK 从零安装、iOS 运行、相机快门操作、真实照片上传。
- 构建版本修复仍是独立的未提交产品改动，本技能提交不包含这些改动；驱动不会隐式修补产品代码。
