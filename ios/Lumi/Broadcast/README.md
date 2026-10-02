# Lumi 屏幕共享扩展

在 Xcode 里给 `Lumi` 工程新增 **Broadcast Upload Extension**，Bundle Identifier 使用 `com.cai5232.Lumi.BroadcastUpload`，把 `LumiBroadcastUploadHandler.swift` 加入扩展 target，并把 `BroadcastPickerView.swift` 加入主 App target。主 App 用 `BroadcastPickerView(preferredExtension: "com.cai5232.Lumi.BroadcastUpload")` 唤起系统直播面板；首次直播必须由用户在系统面板点击开始。

扩展会将缩小后的 JPEG 帧发送到 `POST /v1/chats/default/screen-share/frame`，服务端保留最新帧并提供 `GET /v1/chats/default/screen-share/frame` 和 `GET /v1/chats/default/screen-share/status`。
