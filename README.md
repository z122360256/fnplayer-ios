# FnPlayer 飞牛弹幕播放器（iOS 16+）
原生 SwiftUI App：连接飞牛 NAS 播放视频 + 自定义弹幕 API（Docker 部署的 danmu-api）。
## 功能
- 连接飞牛 NAS（地址/账号/密码，Token 自动识别）
- 媒体库浏览（自动适配常见接口格式）
- AVPlayer 视频播放（支持 mp4 / m3u8，http 直连）
- 弹幕：滚动/顶部/底部三轨道、字号/速度/透明度/显示区域/屏蔽词
- 弹幕 API 在 App 内手动填写（设置页），支持 him-v2 / 通用两种协议，可测试连通
- 发送弹幕（昵称可配置）
## CI 云端编译（无需 Mac）
推送到 main 后 GitHub Actions 自动编译，产出**未签名 ipa**：
Actions 页 → Build iOS IPA → Artifacts → `FnPlayer-unsigned-ipa`
## 安装到 iPhone（侧载，免开发者账号）
任选其一：
1. **Sideloadly**（Windows/Mac）：数据线连 iPhone，把 ipa 拖进去，填 Apple ID 自动签名安装
2. **AltStore / SideStore**：安装后用 Apple ID 签名（7 天有效期，可续签）
3. **TrollStore**（仅特定系统版本支持）：永久签名
4. 有 Apple 开发者账号：Xcode 打开工程直接真机签名
> 未签名 ipa 无法直接安装，必须用以上工具签名后安装。
## 使用
1. 打开 App → 填飞牛 NAS 地址（如 http://192.168.1.10:5666）→ 账号密码 → 连接
2. 设置页填入 danmu-api 地址（如 http://192.168.1.20:8080）→ 测试连通 → 保存
3. 选视频播放，底部输入框发弹幕
## 说明
- 飞牛影视私有接口未公开，媒体库浏览按常见接口格式做了自适应；如您的版本接口不同，可先用「播放直链」方式播放 NAS 视频，后续版本持续适配。