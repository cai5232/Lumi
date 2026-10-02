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
- `LUMI_MEMORY_API_URL`：记忆库地址，默认 `https://memorycore.zeabur.app`
- `LUMI_MEMORY_API_KEY`：可选，记忆库 API Key
- `LUMI_MEMORY_SEARCH_PATH`：可选，检索路径，默认 `/search`
- `LUMI_MEMORY_WRITE_PATH`：可选，写入路径，默认 `/memories`

`PORT` 由 Zeabur 自动注入，不需要手动填写。

## API

- `GET /health`
- `GET /v1/chats/:id`
- `POST /v1/chats/:id/messages`，JSON body：`{"content":"你好","systemPrompt":"可选"}`
- `POST /v1/memories`，JSON body：`{"content":"要记住的内容","threadId":"可选"}`
- `GET /v1/settings/proactive` / `PUT /v1/settings/proactive`：配置首次哨兵唤醒等待时间和主动消息
- `GET /v1/chats/:id/activity` / `POST /v1/chats/:id/activity`：查看或控制哨兵、睡眠、噩梦惊醒状态

当窗口估算 Token 达到 `LUMI_CONTEXT_LIMIT × LUMI_COMPACT_AT` 时，后端会自动把较早历史蒸馏为
`<context_summary>`（用户画像、关系动态、关键事实、当前话题），保留最近对话继续发送给模型；摘要会在后续压缩时增量合并。

每条消息会先由模型提取内部检索关键词，再向记忆库检索；关键词只用于记忆库请求，不会原样传给聊天模型。检索到的记忆正文会作为上下文注入模型。模型可在回复末尾使用内部 `<memory>...</memory>` 标记选择写入长期记忆，后端会移除该标记并在客户端显示“-------沈屿记下了这一刻-------”。
