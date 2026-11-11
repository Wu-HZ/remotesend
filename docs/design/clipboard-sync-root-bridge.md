# Windows ⇄ Android 剪贴板同步：Root 桥接验证

## 当前范围

用户目标是两端任意应用内复制后，另一端可直接粘贴。已确认可接受 Root，必要时再考虑 Magisk / LSPosed。

先验证 Android 系统访问能力，再接入完整网络同步。本次只实现可安装的诊断入口：

- Android 设置 → 其他 → Root 剪贴板诊断。
- 手动授权、启动、停止，其他应用复制时统计变化，读取元数据。
- 需二次确认的固定测试文本写入及原样读回校验。
- 不添加 Gotify 同步协议，不发送网络请求，不改变现有临时自动发送行为。
- 不安装 Magisk 模块、不 Hook system_server、不调整 appops、SELinux 或系统权限。
- 不承诺 Android 全后台保活；当前辅助进程与应用进程和诊断页面绑定。

## 权限与运行结构

```text
Flutter 诊断页（只有元数据进入页面状态）
  ⇅ MethodChannel / EventChannel
Android 主进程桥接处理器
  ⇅ 私有 stdin/stdout 管道，JSON 单行帧
su 2000 -c <固定的 app_process 启动命令>
  ⇅ com.android.shell 身份的 Android Clipboard Binder
Android 系统剪贴板
```

Root 管理器授权应用启动 UID 2000 辅助进程，而不是让处理剪贴板的进程长期以 UID 0 运行。Android 在普通应用无焦点时限制读取剪贴板；AOSP 对 shell 包具备后台读取权限的情况有专门支持。仅把现有普通应用进程变成后台服务不能解决这一限制。

辅助入口位于已安装 APK，R8 明确保留 `RootClipboardDaemon.main`。不下载或释放外部可执行脚本。唯一命令字符串只包含正确引用的 APK 路径和从应用 UID 推导的 Android 用户编号；剪贴板正文只通过管道作为 JSON 数据传输，不进入命令行、环境变量或日志。

IPC 不开放 TCP、本地 socket 或导出的 Android service。只支持启动、读、写和停止，没有任意 shell 命令接口。拒绝不是 shell UID 的辅助进程。

## 系统接口适配

通过系统自带的 `IClipboard.Stub.asInterface` 获取 Binder，按实际方法参数匹配已知签名：

- `package`
- `package, userId`
- `package, attributionTag, userId`
- `package, attributionTag, userId, deviceId`

监听器使用系统 `IOnPrimaryClipChangedListener` 接口及 Binder 回调。包固定为 `com.android.shell`，虚拟设备编号固定为默认设备 0；用户编号来自应用 UID，不接受 Dart 任意指定其他用户。旧接口不具备用户参数时，非主用户直接拒绝，不静默读取主用户剪贴板。

未知 OEM 签名、权限拒绝或隐藏 API 不兼容都应报告失败，不通过更改系统设置“修复”。上述接口匹配并不等于已在所有 Android 7–16 ROM 真机验证。

参考：

- [AOSP Android 14 IClipboard](https://android.googlesource.com/platform/frameworks/base/+/android-14.0.0_r1/core/java/android/content/IClipboard.aidl)
- [AOSP Android 14 ClipboardService](https://android.googlesource.com/platform/frameworks/base/+/android-14.0.0_r1/services/core/java/com/android/server/clipboard/ClipboardService.java)

## 正文与生命周期规则

- 只读取纯文本、单项剪贴板，不将 URI、Intent、图片或 HTML 强制转换成文本。
- 先检查描述中的 `android.content.extra.IS_SENSITIVE`，敏感内容不读取正文。获取实际 ClipData 后再次检查，防止两次读取之间剪贴板变化。
- 按 UTF-8 限制正文 32 KiB，不 trim，保留换行、空格和多字节字符。
- 系统未提供内容（如锁屏）显示“空或暂不可读”，不宣称已验证后台可读，也不绕过锁屏读取。
- 连续监听事件按 100ms 合并。事件只传元数据到 Flutter，不在 Flutter 后台消息队列缓存正文。
- 显式读和测试写入的返回值可临时包含正文，以核对是否原样；诊断 provider 只存种类、字节数、来源标记、次数和固定错误码，没有正文历史。
- 桥接写入给 ClipDescription 附加随机来源标记，元数据可识别自身写入。这只是未来防回环的基础，还不是已实现网络防回环协议。
- JSON 帧上限 256 Ki 字符，未结束帧、过大帧和不合规范的响应终止会话。
- 启动授权超时 60 秒；原生读写超时 5 秒。待处理请求至多 8 个，写命令串行发送。
- 取消授权等待、停止、页面退出、Activity 销毁会关闭输入管道并终止子进程。辅助进程在调用系统 Binder 前即开始监视输入，见 EOF 后移除系统监听并退出；即使 Binder 卡住，也由独立的 1 秒退出看门狗终止进程。应用进程死亡同样关闭管道。
- 请求和事件带会话隔离，迟到的启动结果、读结果和旧会话事件不能恢复已停止的状态。
- 不输出剪贴板正文、Root 管理器原始输出或可能携带正文的异常消息／堆栈。

写入测试会覆盖当前剪贴板，不会恢复旧内容。已交给系统的写入不能在事后撤销；停止只阻止后续工作。

## 真机验收

1. 安装 ARM64 Release APK，记录手机型号、Android 版本和 Root 管理器版本。
2. 打开诊断页：不得自动弹出 Root 授权，不得修改剪贴板。
3. 点击“授权并启动”。分别测试拒绝、允许和等待超时，失败后能重试；未 Root 的手机应安全失败。
4. 允许后应显示 shell UID **2000**、Android API、当前用户和接口签名。UID 2000 是预期的最小权限设计，不是提权失败。
5. 在其他应用复制不同纯文本，保持 RemoteSend 后台一段时间，返回观察计数是否增加。请勿用真实密码测试。
6. 点击“读取元数据”，确认字节数和类型；页面不应出现正文。
7. 复制含前后空格、换行、中文、Emoji 的文本，确认字节计数正常。
8. 复制文件／图片、超过 32 KiB 的文本、系统明确标记敏感的测试内容，确认跳过；不声称可以自动识别所有密码。
9. 点击“写入测试文本”：取消不得改动剪贴板；确认后应校验完全一致，并可到其他应用粘贴确认。来源应显示桥接自身写入；若 ROM 丢弃附加标记，需要单独记录。
10. 锁屏后可暂不可读，解锁后重试。不得为了测试关闭锁屏安全机制。
11. 停止或返回退出页面后，再复制不应继续产生本次会话事件；重新启动的计数重置。
12. 测试启动中取消、快速退出、应用强制停止和再次进入；无孤立的 `remotesend-clipboard` 辅助进程。强制停止不是让守护进程绕过用户操作自动复活的理由。

本机 ADB 当前未连接设备，因此自动测试与 APK 构建不代替以上真机验收。

常见固定诊断码：

| 代码 | 排查方向 |
| --- | --- |
| `root_unavailable` | 无 su、授权被拒绝、辅助进程启动失败 |
| `startup_timeout` | Root 授权或启动超过 60 秒，可停止后重试 |
| `wrong_identity` | Root 管理器未按请求启动 shell UID 2000 |
| `unsupported_api` | ROM 的系统 Binder／隐藏 API 签名不支持 |
| `permission_denied` | 系统拒绝 shell 访问或当前用户权限不满足 |
| `request_timeout` / `disconnected` | 系统调用超时或进程／管道断开 |
| `invalid_response` | 辅助进程响应协议不符，已停止，不显示原始输出 |

## 第二阶段：复用 Gotify 文本通道的 Windows ⇄ Android 同步

- 复用已真机确认的 Root Binder 桥接、现有 Gotify 地址／应用令牌／客户端令牌和 Gotify“默认接收设备”设置。没有独立剪贴板密钥、指纹、第二套设备 ID 白名单或发送／接收方向；两端开启同步即可。Gotify 目标设备列表非空时按该列表路由；为空时使用现有“所有其他设备”广播语义。
- 剪贴板帧仍有独立事件类型，以免被误当作文本页聊天消息；正文直接使用与现有 Gotify 实时文本相同的明文载荷，经已配置的连接传输。**Gotify 服务端可以读取或保留剪贴板正文。请使用 HTTPS，勿依赖同步系统密码／验证码。**
- 新增开关外不增加配对流程。`ClipboardSyncConfig` 只保存 enabled 标记和运行所需的 Gotify 配置快照；前一版短暂试验的 v1 密钥／peer 字段会忽略并迁移到 v2，不再作为设置要求。同步选项和本机共享记录入口位于 **设置 → Gotify**。
- 同步配置快照仍由 Android `noBackupFilesDir` + Android Keystore AES-GCM、Windows `%LocalAppData%/RemoteSend` + 当前用户 DPAPI 保护。剪贴板共享记录另存于应用本机私有支持目录；Android 云备份和设备迁移规则明确排除此目录。记录近 30 天显示在最近列表，超过 30 天按月归档并继续保留，直到用户手动清空；不会上传 Gotify/WebDAV。该记录文件不是端到端加密。
- Android 用户显式开启同步后，将启用状态保存在加密配置中；下次打开 RemoteSend 时，如服务仍运行则接管状态，若已停止且仍有通知权限则恢复 `remoteMessaging` 前台服务与 headless Flutter engine（可能再次请求 Root 授权）。用户手动关闭或通过通知停止会持久化关闭；不会在开机后不打开应用就自行启动。关闭 UI 不停止正在运行的服务。Root 访问和厂商后台保活是两个不同限制。
- 每次启动先建立不发送的剪贴板基线。新变化合并为最新内容；本地复制优先于等待写入的远端内容；自写通过 OS clipboard sequence／Android ClipDescription origin 标记防回环。遇锁屏／系统长暂停时换运行 session 并重新握手，拒绝旧 session／超过 15 秒消息。停止或断线不排队、不离线补发，也不读 Gotify 历史。
- 仍只同步新复制的单项纯文本，保留空格和换行；尊重 Android 敏感标记、Windows 剪贴板历史／云同步排除标记；跳过空白、非文本、NUL、超过 32 KiB。OS 剪贴板与 Gotify 服务端仍是信任边界。
- FGS 与诊断页共用 Android 单一桥接租约，避免多个 Root helper 同时争用系统剪贴板。控制握手消息和成功发送的剪贴板数据消息都会请求 Gotify 删除各自刚创建的消息；删除依赖 Gotify 客户端令牌权限且为尽力而为，失败时服务器仍可能保留。客户端不拉历史。
- Windows 使用 runner 专用 MethodChannel + 500ms 原生读取，不引入此前已撤回的剪贴板通知增强。Windows 最小化／失焦时仍运行；退出程序会结束本机会话。

### 自动化验证

- 全量 Dart 与 Android 原生测试、同步及本机历史定向测试通过；Windows x64 与 Android ARM64 Release 构建成功。
- loopback Gotify REST/WebSocket 双客户端测试覆盖现有目标路由、双向空格／Unicode 明文、快速复制合并、本地复制优先、敏感内容、锁屏、过期帧丢弃、断线不补发和重连基线；没有读取历史接口。
- 开关测试确认没有额外密钥／peer 配置，目标列表读取现有 Gotify 设置；同时覆盖未曾开启时不自动 Root、已开启后重启恢复、Android service 接管、用户停止及 Gotify 连接变更。本机历史测试覆盖 30 天归档、月度分组及清空，不调用云端服务。

### 最终真机验收

Root 桥接已由用户报告可靠；请在简化版安装后确认 Windows 复制→手机任意 App 粘贴、手机其他 App 复制→Windows 粘贴、两端 Gotify 接收设备设置能互相路由，锁屏不覆盖已有内容，通知停止立即停止，断网期间复制在重连后不补发。剪贴板正文与现有实时文本相同，Gotify 服务器可读／保留；这是刻意复用文本通道而非端到端加密的取舍。
