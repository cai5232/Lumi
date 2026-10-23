# Lumi

Lumi 是 iOS 原生 SwiftUI 客户端。后端已拆分到独立仓库 [`cai5232/lumi-server`](https://github.com/cai5232/lumi-server)，用于部署到 VPS。

## 目录

- `ios/Lumi`：SwiftUI 原生客户端。聊天、图片输入、Markdown/HTML 消息卡片、MiniMax TTS、颜文字管理和 APNs 设置都在这里。
## 运行 iOS

直接双击 `ios/Lumi.xcodeproj` 打开 Xcode，选择 `Lumi` scheme 和 iPhone Simulator，然后运行即可。打开 `ios/Lumi/Preview.swift`，在右侧 Canvas 中可以看到 SwiftUI Preview；也可以直接按 ⌘R 启动模拟器。

最低版本建议 iOS 17。MiniMax TTS Key 保存于 iOS 钥匙串，合成音频保存在应用 Documents 目录，因此清理后台或强制结束应用不会删除语音文件。

耳机空间播放借鉴 [binaural-voice](https://github.com/Saekisui/binaural-voice) 的位置标签思路，并用 iOS 的耳机空间音频播放；未复制其 KU100 HRIR 数据文件。

客户端通过 `LumiAPIClient.baseURL` 调用 VPS 上的后端。后续可以继续接入模型流式输出、图片选择器、语音输入和上下文检索。

## 即时指令

聊天页支持 AI 发出的倒计时指令：点按右侧药丸展开，左右滑动中的左滑超过 64pt 标记完成，上下拖动调整位置，长按 0.62 秒取消。展开卡片也提供完成、取消和切换指令按钮。计时按服务端发出时间计算，离开前台后仍继续；超时后保留并显示正向计时。完成用时会在下一次聊天中提供给 AI，取消不产生反馈。

客户端在前台每 15 秒同步，收到消息、回到前台或聊天更新时也会刷新。接口使用现有 Push API Token；服务地址为当前 Coolify 生产域名 `https://lumi-api.yanvn.top`。需配合 lumi-server 的即时指令接口发布。本次提供原生聊天页组件，未启用可选的锁屏 / 灵动岛 Live Activity。

客户端工程包含当前完整原生界面：以聊天为入口，保留外观设置、抽屉、贴纸、睡前电台、模型请求记录和已有交互优化。即时指令叠加在该界面上。修正发布的构建号为 3。
