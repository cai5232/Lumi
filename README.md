# Lumi

Lumi 是 iOS 原生 SwiftUI 客户端。后端已拆分到独立仓库 [`cai5232/lumi-server`](https://github.com/cai5232/lumi-server)，用于部署到 VPS。

## 目录

- `ios/Lumi`：SwiftUI 原生客户端。聊天详情页、thinking 状态、连续消息列表和输入栏从这里开始。
## 运行 iOS

直接双击 `ios/Lumi.xcodeproj` 打开 Xcode，选择 `Lumi` scheme 和 iPhone Simulator，然后运行即可。打开 `ios/Lumi/Preview.swift`，在右侧 Canvas 中可以看到 SwiftUI Preview；也可以直接按 ⌘R 启动模拟器。

最低版本建议 iOS 17。将 `LumiAPIClient.baseURL` 改为开发机地址（真机使用局域网 IP，模拟器可用 `127.0.0.1`）。

客户端通过 `LumiAPIClient.baseURL` 调用 VPS 上的后端。后续可以继续接入模型流式输出、图片选择器、语音输入和上下文检索。
