# 贡献指南 · Contributing to Stillwave

谢谢你愿意让这池水更好。任何大小的贡献都欢迎：一个 shader 参数的微调、一种新心境、一段英文文案，都算。

## 开始之前

1. Fork → 新建分支（`git checkout -b feat/my-thing`）→ 改动 → 提 PR
2. 开发环境：Xcode 16+（工程 objectVersion 77）；改 Swift 不需要 XcodeGen，
   改了 `KouShui/project.yml` 才需要 `xcodegen generate`
3. 提交前确认：双端编译通过（命令见下），网页原型改动在浏览器里目视过

```bash
# iOS 模拟器（连带嵌入 Watch App）
xcodebuild -project KouShui/KouShui.xcodeproj -scheme Stillwave \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/stillwave-dd build

# ⚠️ 不要用 -sdk iphonesimulator 编整个 scheme：会把 watchOS target 也用 iOS SDK 编译。
```

## 仓库的「单一事实源」原则

改动请注意从哪来、到哪去：

| 要改的东西 | 改这里 |
|---|---|
| 视觉 / 交互 / 触觉映射 | `soft-tap.html`（源头），再同步进 `KouShui/iOS/soft-tap.html`（字节级一致）|
| 五音律 / 心境 / 景参数（原生侧） | `KouShui/Shared/KouShuiModel.swift` |
| iPhone 视觉 | 不重写——WebView 承载原型；除非做 4.2 退路（原生 Canvas 重做）|
| Watch 视觉 | `KouShui/WatchApp/SoftTapWatch.swift` 的 `WaterField`，与 `soft-tap.html` 同一语言 |

## 好上手的方向（good first issues）

- **加一种「景」**：在 `soft-tap.html` 的 FRAG shader 加一个 `uStyle` 分支 +
  `WaterField` 加 2D 降级 + `KouShuiModel.swift` 的 `Backdrop` 加 case（颜色 + name）
- **加一种「心境」**：在 `soft-tap.html` 的心境表和 `KouShuiModel.swift` 的 `Mood` 各加一组
  轮廓参数（arch / drift / ripple / 句长 / 音区）
- **英文本地化**：界面文案目前硬编码中文，欢迎抽出 strings + 提供英文
- **Watch 触觉节奏**：`KouShui/WatchApp/HapticScore.swift` 的疏密编码值得细调

## 提交规范

- commit message 用祈使句，说清楚「为什么」：`fix: 快节奏连敲只发瞬态触觉，防硬件整条丢弃`
- 一个 PR 一件事。视觉改动请附截图（改景 / 改涟漪的强烈建议附前后对比）
- 改了触觉的，请在真机上验证过手感并在 PR 描述里写明设备型号

## 行为准则

见 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。保持善意，尊重彼此的时间。
