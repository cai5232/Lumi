# Lumi

Lumi 是 iOS 原生 SwiftUI 客户端。后端已拆分到独立仓库 [`cai5232/lumi-server`](https://github.com/cai5232/lumi-server)，用于部署到 VPS。

## 目录

- `ios/Lumi`：SwiftUI 原生客户端。聊天、图片输入、Markdown/HTML 消息卡片、MiniMax TTS、颜文字管理和 APNs 设置都在这里。
## 运行 iOS

直接双击 `ios/Lumi.xcodeproj` 打开 Xcode，选择 `Lumi` scheme 和 iPhone Simulator，然后运行即可。打开 `ios/Lumi/Preview.swift`，在右侧 Canvas 中可以看到 SwiftUI Preview；也可以直接按 ⌘R 启动模拟器。

最低版本建议 iOS 17。MiniMax TTS Key 保存于 iOS 钥匙串，合成音频保存在应用 Documents 目录，因此清理后台或强制结束应用不会删除语音文件。

耳机空间播放借鉴 [binaural-voice](https://github.com/Saekisui/binaural-voice) 的位置标签思路，并用 iOS 的耳机空间音频播放；未复制其 KU100 HRIR 数据文件。

客户端通过 `LumiAPIClient.baseURL` 调用 VPS 上的后端。后续可以继续接入模型流式输出、图片选择器、语音输入和上下文检索。
