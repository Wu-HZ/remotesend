# 本地 WebDAV MCP

`webdav_mcp_server.py` 恢复 `webdav_upload`、`webdav_download`、`webdav_list`、`webdav_mkdir`、`webdav_delete` 五个工具。服务只在本地通过 stdio 启动，不在网络上监听端口。

1. 本机安装 Python 依赖：`python -m pip install mcp webdav4`。
2. 将 `tools/webdav_mcp.example.json` 复制到项目根目录的 `.mcp.json`，把三个 `REPLACE_ME` 替换为自己的 WebDAV URL、用户名和密码；`.mcp.json` 已被 Git 忽略，请勿提交或分享。推荐 HTTPS；HTTP 也可用于可信内网，但用户名、密码和传输内容将以明文经过网络。
3. 在 Pi 中执行 `/reload`，通过 `mcp({ connect: "webdav" })` 验证注册。
4. 构建 APK 后，调用 `webdav_upload`，参数示例：`local_path=build/app/outputs/flutter-apk/app-release.apk`，`remote_path=/RemoteSend/Files/RemoteSend-Android.apk`，`overwrite=true`。更新现有 APK 必须显式允许覆盖。

脚本对配置的 WebDAV 地址直连，不使用系统代理；这是为了避免内网 WebDAV 被代理接管并返回 502。脚本和示例配置可纳入版本控制，凭据只放在本机 `.mcp.json`。运行 `python -m unittest discover -s tools -p 'test_webdav_mcp_server.py'` 可离线测试工具行为。
