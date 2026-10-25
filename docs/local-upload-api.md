# 本机上传 API（桌面版）

适用于在同一台电脑编译其他项目后，交给**正在运行的 RemoteSend** 上传。无需另行配置 WebDAV 凭据；文件进入现有传输队列，WebDAV 上传成功后按现有设置发送 Gotify 文件通知。Android 不提供此入口。

1. 在 RemoteSend **设置 → 本机上传 API** 中打开“允许本机脚本和 AI 上传”。状态应显示 `http://127.0.0.1:38764`；若端口被占用，关闭占用程序并重新开关。需要先配置并启用文件服务器。
2. **仅在使用 Python 脚本或 curl 时**，点“复制 API 令牌”，将令牌放在当前终端环境变量中，不要写进仓库、脚本参数或命令历史。Pi 插件可使用下文的一次性配置，无需每次设置环境变量。PowerShell：`$secret = Read-Host 'Paste RemoteSend token' -AsSecureString; $env:REMOTESEND_API_TOKEN = (New-Object System.Net.NetworkCredential('', $secret)).Password`；Bash：`read -rs REMOTESEND_API_TOKEN; export REMOTESEND_API_TOKEN`（粘贴令牌后回车）。如需撤销授权，点“重置令牌”或关闭接口。
3. 其他项目编译完运行（Python 3，仅用标准库；发行版 ZIP 内也附此脚本）：

   ```powershell
   flutter build apk --release
   python "C:\path\to\RemoteSend\remotesend_upload.py" "build\app\outputs\flutter-apk\app-release.apk"
   ```

   默认一直等到**实际上传完成**才返回成功（退出码 0），失败或超时返回非 0；标准输出为包含任务状态和远端路径的 JSON。`--no-wait` 仅入队即返回，不代表上传成功；`--timeout 7200` 延长等待时间。若必须沿用原文件名、允许覆盖远端同名文件，加 `--overwrite`；默认会给原文件名加随机后缀，不覆盖旧产物。AI 可以在其他项目编译结束后直接执行相同命令，不必注册 MCP 工具。

## Pi 插件（单独发布的仓库）

“通过 RemoteSend 上传”Pi 插件**本身**在独立的公开仓库 [Wu-HZ/remotesend-pi-upload](https://github.com/Wu-HZ/remotesend-pi-upload) 发布，其它设备可直接从 GitHub 下载、安装插件。该仓库只存插件源码和使用说明，不存编译产物；Pi 工具仍调用本机 RemoteSend 的 `/v1/uploads`，由 RemoteSend 上传到你已配置的 WebDAV 文件仓库。

在每台要使用的设备运行 `pi install git:github.com/Wu-HZ/remotesend-pi-upload`，更新用 `pi update git:github.com/Wu-HZ/remotesend-pi-upload`（正在运行的 Pi 再执行 `/reload`）。在 Pi 输入一次 **`/remotesend-config`**，在隐藏输入框中粘贴从 RemoteSend 设置复制的本机 API 令牌并按 Enter；令牌保存在 Pi 的用户配置 `~/.pi/agent/remotesend-upload.json`，以后在所有项目、每次启动 Pi 都自动读取。轮换令牌时再次运行该命令，`/remotesend-config status` 可查看配置状态，`/remotesend-config clear` 可删除保存的令牌。已有 `REMOTESEND_API_TOKEN` 环境变量时会优先使用它；日常使用不必设置环境变量。每台设备需要自己的 RemoteSend、WebDAV 配置和令牌。

编译后让 Pi 调用 `remotesend_upload`，传 `{"path":"build/app/outputs/flutter-apk/app-release.apk"}`，插件会等待真正上传完成并返回 WebDAV 中的远端路径。其它设备通过 RemoteSend 文件页浏览/下载产物，而 GitHub 仓库仅用于分发**插件**，不提供编译产物的 GitHub 下载链接。

## HTTP 协议

只监听 `127.0.0.1:38764`，默认关闭。所有请求需 `Authorization: Bearer <令牌>`，不接受浏览器 Origin，也不开放 CORS。文件路径是 **RemoteSend 所在电脑的绝对路径**；不是远端路径，也不是上传文件内容。仅支持文件，不支持目录和任意 WebDAV 路径。

- `POST /v1/uploads`，`Content-Type: application/json`，body 如 `{"path":"C:\\project\\build\\app.apk"}` 或 `{"path":"C:\\project\\build\\app.apk","overwrite":true}`。返回 HTTP 202 和 `{"id":"upload_0","status":"uploading","progress":0.0,"fileName":"app-<随机>.apk","remotePath":"/RemoteSend/Files/app-<随机>.apk"}`。202 **仅表示入队**。
- `GET /v1/uploads/{id}` 返回 HTTP 200，同样的状态字段：`pending`、`uploading`、`completed`、`failed`；失败带 `error`。脚本轮询直到 `completed`，`failed` 则报错。用户清空队列时任务将变为失败。状态仅保存在当前运行期内（最多保留约 500 个近期任务），不会跨重启保存。
- HTTP 400（参数/路径错误）、401（令牌错误）、403（非本机命令行来源）、409（同名目标正在上传）、413（body 过大）、429（任务过多）、503（文件服务器不可用）、500（内部错误）均返回 JSON `{"error":"..."}`。

示例（Bash；令牌通过变量传递，命令参数中不出现令牌）：

```bash
curl --noproxy '*' -X POST http://127.0.0.1:38764/v1/uploads \
  -H "Authorization: Bearer $REMOTESEND_API_TOKEN" \
  -H 'Content-Type: application/json' \
  --data "{\"path\":\"$(realpath build/artifact.zip)\"}"
```

**安全注意**：令牌授予从本机读取任意文件并上传到当前 WebDAV 文件服务器的权限；仅供可信的本机脚本和 AI 使用。RemoteSend 会把令牌保存在本机应用配置（便携模式为 exe 旁 `config.json`）中；不要提交或分享该配置。复制令牌后注意系统剪贴板中的残留。不要通过端口转发把此接口暴露到网络，也不要让 AI 将令牌写入其对话记录或构建日志。运行期间切换文件服务器可能使正在处理的任务失败（上传结果不确定），请不要在构建上传时切换。
