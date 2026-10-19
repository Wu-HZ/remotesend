# Gotify 实时文本服务器开发设计

状态：已按本方案实现于当前工作区；实现与验证记录见文末，尚未提交。

设计基线：当前 `ad39ff4`，`AppConfig.currentVersion = 12`。

## 1. 目标与边界

在「设置 → Gotify」增加「注册为文本服务器」开关。

开启后，当前 Gotify 配置作为一个特殊服务器出现在文本服务器选择器中。选择该服务器后，可以直接通过 Gotify 实时发送、接收文本，不需要 WebDAV。

明确边界：

- 这是服务器注册能力，不是替换所有文本发送方式的全局开关。
- 普通 WebDAV 服务器继续保留现有文本历史、日期导航和文件功能。
- Gotify 服务器只支持实时文本，不能作为文件服务器。
- Gotify 模式不实现文本历史、日期查询、持久化聊天记录或历史补拉。
- 当前运行期间可以显示收发消息，便于确认结果；这只是内存中的实时会话，不是历史存储。
- 文件传输和现有 WebDAV 更新通知继续使用原实现。
- 本期不实现全局永久剪贴板监听、端到端加密、多套 Gotify 账号或离线文本投递。

## 2. 用户操作与设置

### 2.1 注册入口

在现有 Gotify 设置区增加：

```text
Gotify
  启用 Gotify                         [现有开关]
  配置连接                            [现有入口]
  注册为文本服务器                    [新增开关，默认关闭]
  目标设备                            [沿用现有设置]
  ……其他现有设置
```

行为约定：

1. 开关持久化保存，但开启时不自动改变当前文本服务器。
2. 开启后显示唯一的 `Gotify` 服务器，重复保存不新增重复条目；样式与 WebDAV 一致，文件按钮置灰。
3. 复用现有 Gotify 地址、应用令牌、客户端令牌和本机设备 ID，不另存一份凭据。
4. 凭据缺失或 Gotify 主开关关闭时，仍可保留注册状态；服务器显示「未配置／已停用」，禁止发送并提供配置提示。
5. 网络暂时断开只改变连接状态，不移除服务器、不自动切换到 WebDAV。
6. 取消注册时，若当前选中了 Gotify，原子切换到首个启用的 WebDAV 文本服务器；没有可用项则清空文本服务器选择。
7. 取消注册停止临时剪贴板自动发送，并清空 Gotify 实时会话；不影响文件服务器，也不关闭原有 WebDAV 的 Gotify 通知。
8. 修改 Gotify 地址或令牌导致连接身份变化时，停止自动发送、取消未提交的直传任务并清空旧连接的实时会话，避免不同账号的内容混在一起。

注册开关不加入 `_gotifyConnectionIdentityProvider`：单纯显示／隐藏文本服务器不应重建 WebSocket，开关由业务层实时响应。

### 2.2 服务器列表中的表现

- 文本页窄屏下拉框、宽屏侧栏都显示 `Gotify`，使用与 WebDAV 相同的图标和条目样式，不额外添加状态副标题或能力小字。
- 通用服务器管理列表使用同一个服务器卡片构建方法：名称、URL、启用、文本、文件按钮布局一致；Gotify 的文件按钮禁用并置灰。Gotify 配置弹窗同样支持 Emoji 图标，保存于 `GotifyConfig.emoji`，卡片、下拉菜单和侧栏统一显示；留空使用默认云图标，旧配置缺省为空，不改变连接身份或清空会话。
- 启用按钮直接绑定已有 Gotify 主开关，不另存第二套启用状态；长按编辑打开 Gotify 配置，长按删除只取消文本服务器注册，不关闭已有通知。
- 设置顶部连接状态也使用同一容器、颜色、图标和标签组件，只把 Gotify 连接状态映射到共同展示状态。
- 文件页、文件服务器设置、待发送文件的目标列表、跨服务器文件操作和拖放目标中都不出现该条目。

## 3. 服务器模型：虚拟端点，而不是伪造 WebDAV 配置

### 3.1 保留 `ServerConfig` 的职责

现有 `ServerConfig` 是 WebDAV 模型，其 `isConfigured` 要求 URL、用户名、密码。

不要构造一个空用户名／密码的 `ServerConfig` 来冒充 Gotify，也不要把应用令牌塞进 WebDAV 密码字段。这会把 Gotify 误送进连接测试、目录浏览、上传等代码。

建议增加运行时端点抽象，以下名称为建议命名：

```dart
enum ServerKind { webDav, gotify }

abstract class ServerEndpoint {
  String get id;
  String get name;
  ServerKind get kind;
  ServerCapabilities get capabilities;
}

// WebDavEndpoint 持有 ServerConfig。
// GotifyTextEndpoint 引用当前 Gotify 配置，不复制凭据。
```

能力矩阵：

| 能力 | WebDAV | Gotify |
|---|---|---|
| 发送／接收文本 | 支持 | 支持，专用直传协议 |
| 文件上传／下载／文件操作 | 支持 | 不支持 |
| 文本历史与日期导航 | 支持 | 不支持 |
| 远端存储用量／清空存储 | 支持 | 不支持 |
| 远端消息删除 | 沿用现状 | 不支持 |
| 清空当前实时会话 | 不新增 | 支持，仅清空内存 |

能力检查必须存在于配置校验和调用层，不能只靠隐藏按钮。

### 3.2 注册与选择

建议新增：

- `textServerEndpointsProvider`：启用的 WebDAV 端点，加上已注册的 Gotify 虚拟端点。
- `fileServerEndpointsProvider`：只返回启用且支持文件的 WebDAV 端点；现有文件侧仍可继续使用 `ServerConfig` 列表。
- `activeTextEndpointProvider`：解析当前选中的文本端点。
- `activeTextChannelStateProvider`：统一提供文本页需要的连接、发送状态和能力，不假定它是 WebDAV。

虚拟端点使用保留 ID，例如 `builtin:gotify:text`。当前仅有一份 Gotify 配置，因此只生成一个虚拟服务器。

设置增加：

```json
{
  "version": 13,
  "activeTextServerId": "builtin:gotify:text",
  "activeFilesServerId": "原有 WebDAV ID 或 null",
  "gotify": {
    "registerAsTextServer": true
  }
}
```

这是相关字段示意，不是完整配置文件。新字段缺失时默认 `false`。

必须同步处理：

- `GotifyConfig` 的构造、`copyWith`、JSON、相等性和哈希。
- `AppConfig` 版本迁移、文本可用性判断和配置导入校验。
- 文本服务器切换方法允许选择合法的虚拟 ID。
- 文件服务器切换方法明确拒绝 Gotify ID；配置文件被手工写坏时也不能进入文件传输流程。
- 取消注册和清空选择时使用能真正清除 ID 的更新方法，不能依赖当前 `copyWith(activeTextServerId: null)`，因为它会保留旧值。

**特别注意现有回退逻辑：** `AppConfig.activeTextServer` 在找不到 ID 时会回退到第一个 WebDAV 服务器。选中虚拟 ID 后不能沿用这条回退，否则页面看似选择 Gotify，实际却把文本写入 WebDAV。

旧的 `activeTextServerProvider` 保持 WebDAV 专用语义：选中 Gotify 时返回 `null`。新增通用端点解析用于文本页，不把 Gotify 交给 `webDavTextServiceProvider`。

仅配置并注册 Gotify、没有任何 WebDAV 时，也必须能进入文本页。需要检查 `isTextConfigured`、`isConfigured`、首页强制跳设置和 `main.dart` 自动连接流程，避免仍以 WebDAV 是否配置作为唯一条件。

## 4. 文本页：两种能力不同的呈现模式

### 4.1 WebDAV 模式

保持现状：日期选择、前后一天、历史列表、刷新、存储用量、远端清空等功能不变。

### 4.2 Gotify 模式

页面建议：

```text
[清空当前会话]                        [服务器选择] [刷新]

        同一套聊天气泡区域（头像、时间、点击复制、链接与展开）

[原有圆角输入框……] [粘贴发送] [临时自动发送] [发送]
```

规则：

- 不显示日期标题、日期切换、WebDAV 用量或清空远端存储按钮；右上角刷新保留相同图标和可点击状态，但在 Gotify 模式直接返回，不请求历史也不改变当前会话。
- 可提供「清空当前会话」，只清理当前内存，不删除 Gotify 服务端消息。
- 沿用 WebDAV 的头像、气泡、时间、链接、展开及点击复制样式；正常发送结果放在时间的悬停提示里，失败沿用错误条与重试，不另起状态面板。不做按天分组或按日期查询。
- 收发消息缓存在独立 `GotifyTextSessionProvider` 中，建议最多保留 200 条。
- 普通页面切换、切到其他服务器后再返回，不主动丢失本次运行的会话；重启应用、取消注册、连接身份变化或手动清空时清除。
- 当前查看 WebDAV 时收到 Gotify 直传文本，放入 Gotify 自己的会话，不写入 WebDAV 历史，也不强制切换页面。
- 无配置、停用和断线要给出 Gotify 对应提示，不能继续显示「请配置 WebDAV」。

按用户最新 UI 要求，两个通道共用 `TextBridgeScreen` 的同一个页面、气泡、输入区、空态和错误条，不再保留独立 Gotify 文本页或长期说明／状态面板。仅按能力隐藏日期和用量，刷新按钮保留但不执行 Gotify 历史请求；发送状态可作为时间的悬停提示，失败时沿用错误条与重试。数据读取仍需条件分流：Gotify 模式不能初始化 `messageHistoryProvider` 或日期 provider。

## 5. 专用实时文本协议

复用现有 Gotify REST、WebSocket 和 RemoteSend 事件封装，但新增独立事件类型：

```json
{
  "version": 1,
  "type": "text_direct",
  "eventId": "每条消息唯一 UUID",
  "senderDeviceId": "稳定的本机设备 ID",
  "senderName": "本机名称",
  "targetDeviceIds": [],
  "createdAt": "UTC ISO-8601 时间",
  "payload": {
    "contentType": "text/plain",
    "content": "实际文本，包括换行和 Unicode"
  }
}
```

约定：

- 事件仍放在 `extras["remotesend::event"]`，现有协议版本无需仅为增加类型而升级。
- `eventId` 同时作为消息 ID 和重试去重 ID，不额外生成不一致的第二个 ID。
- 不使用 `text_changed`，也不附加 `serverKey`、日期或 WebDAV 路径；旧事件仍专门表示「去 WebDAV 读取变更」。
- Gotify 的 `message` 可用「收到一条 RemoteSend 文本」等通用提示，正文只放在协议负载中，不重复存两份。
- 沿用现有目标设备设置：空列表广播给同一通道其他设备；非空列表按设备 ID 过滤。本机回声不作为新接收消息。
- 两端都需要支持新事件类型。可在设备公告里增加可选的 `text_direct_v1` 能力，用于提示旧版本设备；不得把筛选后为空的指定目标悄悄变成广播。
- 允许手动重试同一条失败消息，必须复用其 `eventId`。不承诺跨无限时间的严格 exactly-once。

应用令牌发送到哪个 Gotify application，客户端令牌必须能读取那个 application。客户端可能能读取多个 application，不能仅凭负载里自报的字段判断消息属于当前文本服务器：应通过受信任的 POST 响应取得当前 application ID，并校验入站 `GotifyMessage.applicationId`。可复用上线设备公告的响应取得该 ID；凭据变更时重新校验，未完成前显示初始化状态。

## 6. 发送流程：与历史存储解耦

增加统一文本发送入口，例如 `TextSendController.send()`，根据捕获的端点类型分发：

```text
手动发送／粘贴发送／临时剪贴板自动发送／系统分享文本
                         ↓
                 统一文本发送入口
                         ↓
          ┌──────────────┴───────────────┐
       WebDAV                          Gotify
  沿用消息文件读写               text_direct 专用发送
  沿用变更通知                   POST /message，正文在负载
```

Gotify 分支：

1. 检查端点已注册、Gotify 已启用、凭据完整且连接可用。
2. 以 `trim().isEmpty` 判断空文本；有效文本尽量保留原始内容，不为实时渠道额外破坏空格或换行。
3. 冻结端点 ID、连接身份、目标设备和消息 ID，加入内存中的串行发送队列。
4. 调用现有 `GotifyService.send()`，直接上传新事件，不读写 WebDAV。
5. POST 成功后显示「已发送至 Gotify」。这不等于所有目标设备已经收到；本期不做对端送达回执。
6. 断线、超时、认证错误或服务端拒绝时显示失败／结果不确定，保留可重试的文本，不假装发送成功。

**不能直接照搬现有 `_publish()`：** 它会先把事件写入持久化 outbox，并在恢复连接后自动重发。实时文本若复用该路径，可能把正文留在本地文件里，并在用户以为失败之后又发送出去。

建议新增专用的 `sendRealtimeText()`：复用底层 HTTP 服务和连接，不进入旧的持久化通知 outbox。网络失败时不自动转存 WebDAV、不偷偷切换服务器、不做持久化离线排队。内存待发送队列也需要上限（建议最多 100 条且总正文不超过 1 MiB）；满时明确拒绝新项，并停止临时自动发送，不静默覆盖较早的文本。

输入框、粘贴发送、临时监听和 `main.dart` 的系统分享文本必须走同一个发送入口，避免部分入口仍然直调 `messageHistoryProvider.sendMessage()`。文件分享及 Android「打开方式」仍走既有文件流程。

切换文本服务器时停止临时监听，清除尚未提交的自动发送项。已提交请求可能仍完成，但不能改投到新服务器，也不能把异步结果写进另一个端点的会话。

## 7. 接收流程：实时入站，不回读 WebDAV

```text
现有 Gotify WebSocket
        ↓
RemoteSend 协议解析、application/设备/事件 ID 校验
        ↓
   按事件类型分发
        ├─ text_changed → 原 WebDAV 刷新流程
        ├─ file_ready / file_received → 原文件流程
        └─ text_direct → Gotify 实时会话
```

`text_direct` 处理顺序：

1. 先检查注册开关、所属 application、协议、目标设备和是否来自本机。
2. 校验正文必须是字符串、非空，拒绝畸形或超限负载。
3. 按 `eventId` 去重，不按文本内容全局去重：用户主动发送两次同样的文本是两个合法消息。
4. 将所有合法消息按接收顺序追加到 Gotify 的内存会话，不能只保留批次里最后一条。
5. 若开启现有「自动复制最新接收文本」，一批到达时可只把最后一条复制到剪贴板，但不能因此丢掉会话里的前几条消息。
6. 写剪贴板复用 `TextClipboardService.writeText()`，防止临时自动发送把收到的内容再次发回去。
7. 更新消费状态／去重元数据，不调用 WebDAV 读写、历史刷新或存储用量接口。

注册关闭时，新事件应被忽略并推进消费元数据，不能持续积压成待处理任务。旧 WebDAV 通知的接收行为不因注册开关改变。

## 8. 无历史模式与现有补拉、持久化逻辑的隔离

这是需要专门开发的部分，不能只增加协议枚举。

### 8.1 明确区分实时帧与补拉结果

现有 Gotify 在启动／重连时会调用 `/message` 补拉最近 1–5 分钟通知；不需要为旧功能删除这条链路。

本期 `text_direct` 只处理实时 WebSocket 输入，不从补拉结果恢复文本会话，也不提供任何历史入口。启动补拉中遇到该类型时只推进消费元数据。

实现上为消息处理增加来源标识，例如 `live`、`catchUp`、`deferred`。连接建立期间暂存的 WebSocket 帧仍属于 `live`，不能误当成历史结果一并丢弃。

结论：本期不承诺设备离线期间的文本补收；断线时发送按钮禁用或返回失败。未来若要提供可靠离线投递，应作为独立能力设计。

### 8.2 不把正文写入通知运行态存储

现有 `GotifyRuntimeStore` 会持久化 outbox 和 `deferredInboundEvents`；后者包含完整事件负载。

新类型必须旁路这些正文持久化路径：

- 当前会话、未提交的发送项和直传后台暂存只保存在内存。
- 可以持久化服务器游标、application ID、已处理事件 ID等元数据。
- 不把直传正文写入 WebDAV、SharedPreferences、配置 JSON 或诊断日志。
- 复用事件总线时，也必须保证旧 `_processMessage()`／`deferEvent()` 不会先把新类型的完整负载持久化，再交给新处理器。

### 8.3 后台策略

扩展 `shouldDeferRemoteEventInBackground()`，把 `text_direct` 视为文本，而不是落到默认分支。

- 开启后台接收文本：按平台允许的运行状态处理实时消息，追加内存会话。
- 关闭后台接收文本：在有界内存队列中短暂暂存（建议最多 200 条），回到前台再处理；期限沿用当前通知回溯窗口，但按本机接收时间计时，过期则丢弃，避免远端时钟误差延长保留时间。达到容量上限时明确记录无正文的丢弃计数，不做无限积压。
- 这批暂存不能进入现有持久化 deferred 队列，进程退出后不恢复。
- Android 进程被杀后无法保持 WebSocket，此限制必须与「无离线补收」一起说明。

### 8.4 “无历史”不等于服务端不留存

RemoteSend 不提供历史功能、也不在本地保存正文，不代表 Gotify 服务端不会保存消息。Gotify 服务端仍可能留存事件正文。

目标设备 ID 只是应用层过滤，不是加密隔离。同一 Gotify application 的授权客户端可能读取消息。UI／文档应提示这一点，建议使用 HTTPS；本期不宣称端到端加密或服务端无痕。

## 9. 限制与失败处理

- 建议本期采用保守的产品上限，例如正文 UTF-8 编码后 32 KiB。这是应用自己的限制，不是宣称 Gotify 固定限制；具体服务端也可能设置更小请求上限。
- 超限直接提示，不自动分片、不转 WebDAV。HTTP 413 等服务端拒绝单独给出清晰提示。
- 请求超时可能是“服务端已接受、客户端未收到响应”，不能提示“对端未收到”。人工重试复用事件 ID，接收端尽力去重。
- 关闭注册、切换连接身份后，旧连接的回调不能进入新会话。
- 保留原有 WebDAV 通知 outbox、文件自动下载和设备发现；直传旁路不应破坏它们。

## 10. 主要修改点

| 文件／模块 | 计划改动 |
|---|---|
| `models/gotify_models.dart` | 注册字段、新事件类型、可选设备能力、后台文本判定 |
| `models/app_config.dart` | v13 迁移、虚拟文本端点选择与可用性、取消注册回退 |
| 新增 `models/server_endpoint.dart` | 服务器类型、能力、WebDAV／Gotify 运行时端点 |
| `providers/config_provider.dart` 与端点 provider | 文本端点注册与选择；文件能力校验 |
| `widgets/server_list_panel.dart` | 展示层支持不同类型条目；文件拖放仍只接收 WebDAV |
| `screens/settings_screen.dart` | Gotify 注册开关、说明、服务器条目入口 |
| `screens/text_bridge_screen.dart` | 按能力呈现；Gotify 不初始化日期／历史／用量逻辑 |
| 新增文本发送 controller／transport 适配层 | 统一所有文本发送入口，分发至两个后端 |
| 新增 `providers/gotify_text_session_provider.dart` | 有界内存会话、发送结果、直传消息去重与清空 |
| `services/gotify_service.dart` | 复用已有 REST／WS；只按需要扩展响应身份和错误分类 |
| `providers/gotify_provider.dart` | 非持久化直传发送；入站来源和 application 校验；旁路 outbox／历史恢复 |
| `providers/gotify_coordinator_provider.dart` | 新类型接收与剪贴板处理，不调 WebDAV |
| `main.dart` | 自动连接按端点分发；系统分享文本统一入口；支持无 WebDAV 的文本使用 |
| `services/gotify_runtime_store.dart` | 验证正文不落盘；元数据按需要兼容扩展 |
| 中英文本地化、文档和测试 | 状态提示、功能边界和回归验收 |

原有 WebDAV 存储协议不为此功能重写；新增抽象只承担端点能力与发送分发，不把两种服务器硬做成相同能力。

## 11. 开发顺序

1. **模型与能力隔离**：配置字段、迁移、虚拟端点、文本／文件选择校验，以及仅 Gotify 配置下的首页可用性。
2. **专用协议闭环**：两个升级客户端可直传正文；验证 application 与目标设备；不走 WebDAV、不进持久化通知 outbox。
3. **实时会话与页面**：有界内存消息、连接状态、无日期／历史 UI、清空本次会话。
4. **统一发送入口**：手动、粘贴、临时自动发送、系统分享文本均按当前端点分发；验证切换竞态。
5. **设置与兼容**：注册开关、列表展示、错误说明、能力提示；旧通知／文件传输回归。
6. **双端联调与发布**：Windows ↔ Android 实时收发、断线、后台、混合版本和无 WebDAV 场景。

## 12. 验收清单

### 配置和服务器能力

- [ ] 旧配置升级后默认不注册 Gotify 文本服务器，原服务器选择不变。
- [ ] 开关保存后重启仍有效，列表没有重复条目，凭据只存于 Gotify 原配置。
- [ ] 取消注册时原子回退／清空文本选择，文件服务器选择不变。
- [ ] Gotify 永不出现在文件目标中；手工写入错误文件服务器 ID 也被拒绝或修复。
- [ ] 没有任何 WebDAV，只配置 Gotify 时仍能进入文本页并收发。
- [ ] 断线不会悄悄切换服务器，也不会把 Gotify ID 解析成第一个 WebDAV。

### 实时文本

- [ ] 双端手动收发包含中文、换行、URL 和表情的文本。
- [ ] 指定目标、广播和本机回声过滤正确；其他 application 的直传消息不能进入当前会话。
- [ ] 连续多条消息全部进入会话，事件重投不重复；相同正文、不同 ID 的两条消息都保留。
- [ ] 手动、粘贴、临时自动发送和系统分享文本分发一致，Gotify 分支不产生 WebDAV 请求。
- [ ] 接收写剪贴板不会造成回环；关闭注册或切换端点会停止临时自动发送。
- [ ] 显示的是“已发送至 Gotify”，不是没有依据的“对端已收到”。

### 无历史与边界

- [ ] Gotify 页面无日期选择、WebDAV 用量或远端删除；刷新按钮始终可见，点击无网络和会话副作用。
- [ ] 切换页面再返回保留本次内存会话，重启／注销／换连接身份后不恢复旧正文。
- [ ] 启动／重连的 REST 补拉不重建直传历史，同时不误丢连接建立期间真正的实时 WS 帧。
- [ ] 检查配置、SharedPreferences、outbox、deferred 队列和日志，没有新增直传正文持久化。
- [ ] 断线、超时、令牌无效和超限有明确失败提示，不偷偷持久化重发或转用 WebDAV。
- [ ] 现有 WebDAV 文本历史、日期导航、Gotify 更新通知、文件下载与上传不受影响。
- [ ] Android 后台限制、仅实时语义、旧版本兼容和 Gotify 服务端仍会留存的事实已说明。

## 13. 实施与验证记录

- 已实现 v13 配置、默认关闭的注册开关、虚拟端点／能力、取消注册回退与文件目标校验。
- `TextBridgeScreen` 共用同一个文本页面，按能力选择数据来源并隐藏不适用组件；已移除独立 `GotifyTextScreen`。选择器／侧栏与发送控制器分别位于 `text_endpoint_selector.dart` 和 `text_send_provider.dart`。
- 实时正文通过 `text_direct` 事件直传；`GotifyTextSessionProvider` 维护有界 RAM 会话、发送队列、失败重试、后台暂存和剪贴板写入。
- `_processMessage` 区分补拉与实时帧；真实 POST 响应决定 application ID；既有运行态存储增加正文排除防线。
- 已通过全量 175 项 Dart 测试，包含本地模拟 Gotify 服务端上的两个真实 REST／WebSocket 客户端双向互通，以及设置、页面、剪贴板、无 WebDAV、去重、后台过期和隐私回归。UI 统一后新增卡片／禁用文件按钮、连接状态组件、聊天气泡与输入区样式的自动断言，并生成、目检了 `build/ui-previews/` 下三份预览。图标新增 JSON 兼容、保存／取消／清空、卡片／菜单／侧栏展示和会话保留回归；在线、离线点击 Gotify 刷新均无网络或会话副作用，测试以抛错覆盖禁止初始化 WebDAV 历史和日期 provider。
- Windows x64 与 Android ARM64 Release 包已在最终收尾变更后重新构建成功；原有 Android 文件导入的 7 项原生单元测试也通过。新增及核心改动模块定向静态检查无问题，全项目仍有 36 项既有警告／弃用提示未在本功能中处理。
- 尚未连接用户的实际 Gotify 部署和两台物理设备；真实设备后台存活、代理配置和不同服务端限制仍需安装后联调。上面的清单保留作为发布／真机验收清单，不把自动测试等同于真机验收。
