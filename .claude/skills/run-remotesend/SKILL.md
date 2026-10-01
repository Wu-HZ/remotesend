---
name: run-remotesend
description: 构建、安装、启动、运行、测试和截图 RemoteSend（build/run/start/test/screenshot）。用户要求在 Android 真机上运行、覆盖安装或查看界面时使用；通过 Python 驱动调用 Flutter、Gradle 和 ADB，完成真实导航与截图。
---

# RemoteSend 真机运行

所有路径相对于仓库根目录。主要入口是 `.claude/skills/run-remotesend/driver.py`，不是只打开一个窗口。已验证 **Windows 11 + Android 15 arm64 真机**；没有声称验证 Linux/iOS 或从零安装 SDK。

## 运行：agent 路径

先让用户连接、授权并解锁手机，构建过程中保持亮屏。以下命令在本次会话实际执行成功：

```bash
python .claude/skills/run-remotesend/driver.py doctor
python .claude/skills/run-remotesend/driver.py --direct run
```

`run` 顺序执行依赖解析、arm64 debug APK 构建、`adb install -r`、启动、点击文件导航、截图。APK 是本次成功构建的产物，不会在构建失败后安装旧包。

成功时输出 PNG 的绝对路径和 `camera_button_visible`。**随后用 Read 查看 PNG**；不能仅凭启动成功或该布尔值认定界面正常。截图及对应 JSON 在 `build/run-remotesend/`，受 Git 忽略；可能包含用户文件名，不提交或上传这些产物。

已安装当前版本、只需验证界面时：

```bash
python .claude/skills/run-remotesend/driver.py drive
python .claude/skills/run-remotesend/driver.py screenshot
```

驱动只点击导航，不点击相机快门、上传、删除或修改设置。应用启动本身仍可能按用户既有配置连接 WebDAV/Gotify。

## 前置环境与发现规则

已验证：Python 3.12.2、Flutter 3.38.6 / Dart 3.10.7、JDK 20.0.2、Gradle Wrapper 8.12，以及已安装的 Android SDK/平台工具。驱动仅用 Python 标准库，不需要 pip 安装。

- Flutter：优先 `FLUTTER_ROOT`，其次 `android/local.properties`，最后 `D:/SDK/flutter`。
- Android SDK：优先 `ANDROID_SDK_ROOT` / `ANDROID_HOME`，其次 local.properties，最后 Windows 的 LOCALAPPDATA 下 Android/sdk。
- Pub 缓存：保留已有 `PUB_CACHE`；未设置时使用 Flutter 根目录同级的 `Pub`。不要无故迁移 SDK 或缓存到 C 盘。
- Java：设置有效的 `JAVA_HOME`，或使用 PATH 中的 Java。
- local.properties 缺失时才创建 SDK 路径，不覆盖已有文件。
- 自动选择唯一已授权真机，忽略模拟器；有多台真机时使用驱动全局选项 `--device` 或 `ANDROID_SERIAL` 指定。序列号不写死在技能里。

全新机器需要先准备上述工具并接受 Android SDK 许可；本次没有执行工具的全新安装，因此不提供未经验证的安装命令。

## 构建与安装边界

`run` 已包含完整构建，不需要手工调用 Flutter install。APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`。只构建 arm64，遇到非 arm64 设备明确失败。

`--direct` 仅在本次 Gradle 进程上设置空 HTTP/HTTPS 代理 host 和通配 nonProxyHosts，解决本机失效代理；**不修改全局 Gradle 配置**。本次直连仓库已验证可达。依赖必须经代理访问的环境不要使用该选项。

安装始终使用 `-r`。签名冲突、USB 安装被拒等情况直接停止，**不得自动卸载或清空应用数据**；需要用户另行决定。

## 测试与结束

真实界面验收之后再执行测试，测试不能代替手机验证：

```bash
python .claude/skills/run-remotesend/driver.py test
python -m unittest discover -s .claude/skills/run-remotesend -p test_driver.py
```

本次分别通过 45 项应用测试、7 项驱动测试。测试后确认没有用户正在操作的未发送内容，再停止应用：

```bash
python .claude/skills/run-remotesend/driver.py stop
```

`stop` 仅停止本应用进程；不卸载、不清除存储，但不保证内存中的草稿继续存在。人工使用时也可以通过上述 run 命令安装后，直接在手机上操作。

## 实际遇到的问题

- **`127.0.0.1:7897 ... Connection refused`**：Gradle 全局代理不可用。已验证的处理是上述 `--direct`，不是修改项目仓库或全局代理。
- **AndroidX 要求 AGP >= 8.9.1**：本次拍照依赖对应的工作区使用 `android/settings.gradle.kts` 中 AGP 8.9.1、Kotlin 2.3.20；这是产品构建配置，不由驱动隐式修补。
- **`Using 'jvmTarget: String' is an error`**：本次在 `android/app/build.gradle.kts` 把旧 kotlinOptions 迁移到 `kotlin.compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)`，Java target 保持 11。
- **启动返回 ok，但找不到导航**：实测为手机锁屏，层级只有 com.android.systemui。请用户解锁后重试 drive；不要代为解锁或截取锁屏。构建成功和安装成功不代表界面验证完成。
- **导航文案带换行和标签序号**：驱动匹配首行文本，用 ADB 实际 bounds 定位，兼容中英文，不复用旧截图的固定坐标。
- **Windows 中文输出乱码**：驱动固定 Python 输出为 UTF-8；二进制截图用 exec-out 直接读取，避免文本重定向破坏 PNG。

详细执行记录与验证边界见同目录 `NOTES.md`。本技能仅记录本次成功路径，不包含相机拍摄和远端上传的自动验收。
