# Lumi

Lumi 是一个 iOS 原生聊天应用骨架：SwiftUI 客户端 + 无状态 HTTP API + 可持久化上下文存储。

## 目录

- `ios/Lumi`：SwiftUI 原生客户端。聊天详情页、thinking 状态、连续消息列表和输入栏从这里开始。
- `server`：Node.js 后端。提供聊天记录、消息发送和记忆上下文接口。

## 运行后端

```bash
cd server
npm install
npm run dev
```

默认监听 `http://localhost:8787`。生产环境通过 `LUMI_DATA_DIR` 指定持久化目录，并通过环境变量注入模型服务配置，不把 API key 放进客户端。

## 运行 iOS

直接双击 `ios/Lumi.xcodeproj` 打开 Xcode，选择 `Lumi` scheme 和 iPhone Simulator，然后运行即可。打开 `ios/Lumi/Preview.swift`，在右侧 Canvas 中可以看到 SwiftUI Preview；也可以直接按 ⌘R 启动模拟器。

最低版本建议 iOS 17。将 `LumiAPIClient.baseURL` 改为开发机地址（真机使用局域网 IP，模拟器可用 `127.0.0.1`）。

客户端与后端的边界已经固定，后续可以直接接入模型流式输出、图片选择器、语音输入和上下文检索。
