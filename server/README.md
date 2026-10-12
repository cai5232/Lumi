# Lumi Server

Lumi 的后端 API，独立部署在 VPS。

睡眠状态机参考并移植自 [leofratu/llm-sleep](https://github.com/leofratu/llm-sleep)（MIT License）。这里保留其 N1/N2/N3/REM、梦境、噩梦和反思的行为语义，但以当前 Node 后端的数据结构和模型调用接口实现，避免把不兼容的 Python CLI 原样混入服务。

## 本地运行

```bash
npm install
npm run dev
```

默认端口为 `8787`，数据保存在 `data/threads.json`。生产环境请通过 `LUMI_DATA_DIR` 指定持久化目录，并把模型服务的密钥放在 Zeabur 环境变量中，不要写入代码或 iOS 客户端。

Zeabur 环境变量：

- `LUMI_MODEL_API_URL`：OpenAI 兼容的 Chat Completions 完整地址
- `LUMI_MODEL_API_KEY`：模型服务 API Key
- `LUMI_MODEL_NAME`：模型名称
- `LUMI_SYSTEM_PROMPT`：可选的默认系统提示词；客户端发送的 `systemPrompt` 会优先使用
- `LUMI_DATA_DIR`：建议设为 `/data`，并在 Zeabur 挂载持久化 Volume 到 `/data`
- `LUMI_CONTEXT_LIMIT`：可选，单个聊天窗口的估算 Token 上限，默认 `200000`
- `LUMI_COMPACT_AT`：可选，达到上限的比例后触发压缩，默认 `0.86`
- `LUMI_COMPACT_TAIL_TOKENS`：可选，压缩后保留的最近对话量，默认 `20000`
- `LUMI_SLEEP_DELAY_MINUTES`：说“晚安”等告别词后进入睡眠前的等待分钟数，默认 `60`
- `LUMI_SLEEP_HOURS`：正常睡眠周期小时数，默认 `5.5`
- `LUMI_SLEEP_CYCLES`：每晚 N1→N2→N3→REM 的循环次数，默认 `3`
- `LUMI_SLEEP_INSOMNIA_PROBABILITY`：入睡即失眠并直接回到哨兵模式的概率，默认 `0.15`
- `LUMI_CALL_INVITE_SECONDS`：主动来电响铃后转为未接留言的时间，默认 `30`
- `LUMI_CALL_LINGER_SECONDS`：说晚安后电话保留的时间提示，默认 `18`
- `APNS_TEAM_ID`、`APNS_KEY_ID`、`APNS_PRIVATE_KEY`：Apple Push Notifications 的 Team ID、Key ID 和 `.p8` 私钥。私钥可用 `\\n` 表示换行
- `APNS_BUNDLE_ID`：推送主题，默认 `com.cai5232.LumiPush`；VoIP 推送主题会自动追加 `.voip`
- `LUMI_PUSH_API_TOKEN`：iOS 与服务器交换推送令牌、更新勿扰和调用服务端通话 API 共用的 Bearer 口令
- `LUMI_MEMORY_API_URL`：记忆库地址，默认 `https://memorycore.zeabur.app`
- `LUMI_MEMORY_API_KEY`：可选，记忆库 API Key
- `LUMI_MEMORY_SEARCH_PATH`：可选，检索路径，默认 `/search`
- `LUMI_MEMORY_WRITE_PATH`：可选，写入路径，默认 `/memories`

`PORT` 由 Zeabur 自动注入，不需要手动填写。

## MCP 工具

MCP 服务器在后端配置，iPhone Lumi「设置 → MCP 服务器」只显示服务器、工具数量与 HTTP/SSE 类型，并允许逐台启用或停用。配置服务器后，先调用 `POST /v1/mcp/servers/:id/connect` 读取工具。聊天会按需调用已启用的只读工具；可能发送、写入或修改数据的工具需要用户确认。支持 Streamable HTTP 与传统 SSE，不支持 Kelivo 桌面版 STDIO 传输。

配置和服务器凭证保存在 `LUMI_DATA_DIR/mcp-clients.json`，建议挂载持久化卷。在该文件中维护服务器条目（`id`、`name`、`url`、`transport`、`headers`、`enabled`）；`transport` 可设为 `streamable-http` 或 `sse`。示例：

```json
{
  "servers": [
    {
      "id": "my-mcp",
      "name": "My MCP",
      "enabled": true,
      "url": "https://example.com/sse",
      "transport": "sse",
      "headers": {},
      "tools": []
    }
  ],
  "revision": 0
}
```

连接后后端会缓存工具清单。接口使用现有 `LUMI_PUSH_API_TOKEN` 鉴权：`GET /v1/mcp/servers`、`PATCH /v1/mcp/servers/:id`（只改 `enabled`）、`POST /v1/mcp/servers/:id/connect`、`POST /v1/mcp/servers/:id/tools/:tool/call`。服务器地址限公开 HTTPS，并禁止自动跟随重定向。Kelivo 来源和 AGPL-3.0 许可见 `THIRD_PARTY_NOTICES.md`。

## API

### 一起听（Duetto）

Lumi 内置 Duetto 的完整听歌房页面与服务：在 iOS 首页打开“一起听”即可进入；公网地址也可通过 `/together-listen` 或 `/pkg/index.html` 打开。Duetto 的 `/api/*`、静态资源 `/pkg/*` 和实时同步 WebSocket `/ws` 由 Lumi 主服务转发到仅监听本机的内置服务。

包含网易云歌单/搜索/每日推荐/私人 FM/歌词与翻译/歌手主页/评论/红心与歌单编辑、播放器队列与循环/随机模式、同步房间和聊天、歌词引用与提问、歌曲听后分析和回忆档案、AI DJ、模型与提示词设置、五套主题及自定义外观。详细操作见 `duetto/GUIDE.md`。

该内置服务使用 Node.js `node:sqlite`，生产 Node 版本需为 22.5 或更高。SQLite 档案、独立 PIN 和网易云凭据保存在 `${LUMI_DATA_DIR}/duetto`（未设置时为 `data/duetto`）。Duetto 源码与 MIT 许可保存在 `duetto/`。

- `GET /health`
- `GET /v1/chats/:id`
- `POST /v1/chats/:id/messages`，JSON body：`{"content":"你好","systemPrompt":"可选"}`
- `POST /v1/memories`，JSON body：`{"content":"要记住的内容","threadId":"可选"}`
- `GET /v1/settings/proactive` / `PUT /v1/settings/proactive`：配置首次哨兵唤醒等待时间和主动消息
- `GET /v1/chats/:id/activity` / `POST /v1/chats/:id/activity`：查看或控制哨兵、睡眠、噩梦惊醒状态
- `GET /v1/music/netease/status|qr|qr/check?key=...`：网易云账号状态与二维码登录
- `GET /v1/music/netease/search?q=...`、`GET /v1/music/netease/song-url?id=...`：搜索歌曲、获取当前可用音源
- `GET /v1/music/room/state?room=main` / `PUT /v1/music/room/state`：读取或更新听歌房播放状态；状态保存在 `LUMI_DATA_DIR/music-room-state.json`
- `GET /v1/music/room/messages?room=main` / `POST /v1/music/room/messages`：读取或发送听歌房消息
- `POST /v1/music/netease/logout`：退出已连接账号

所有 `/v1/music/*` 接口使用 `LUMI_PUSH_API_TOKEN` Bearer 鉴权。网易云扫码会话保存在持久化目录的 `ncm-cookie.txt`，文件权限限制为当前服务用户；请为 `LUMI_DATA_DIR` 配置持久化卷。依赖由 `npm install` 安装。

当窗口估算 Token 达到 `LUMI_CONTEXT_LIMIT × LUMI_COMPACT_AT` 时，后端会自动把较早历史蒸馏为
`<context_summary>`（用户画像、关系动态、关键事实、当前话题），保留最近对话继续发送给模型；摘要会在后续压缩时增量合并。

每条消息会先由模型提取内部检索关键词，再向记忆库检索；关键词只用于记忆库请求，不会原样传给聊天模型。检索到的记忆正文会作为上下文注入模型。模型可在回复末尾使用内部 `<memory>...</memory>` 标记选择写入长期记忆，后端会移除该标记并在客户端显示“-------沈屿记下了这一刻-------”。
