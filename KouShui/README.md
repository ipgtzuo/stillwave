# 叩音 · Stillwave — iOS + watchOS 工程

基于当前网页原型（`../soft-tap.html`）落地的可编译双端工程，并附带一整套上架材料。

## 现在这一步：先装到手机看效果

见 [`AppStore/06-真机试装.md`](AppStore/06-真机试装.md)：**免费 Apple ID 的 Personal Team 即可**，不用提审、不用付费账号。
代码侧已验证 arm64 真机编译（0 warning，产物含嵌入的 `KouShuiWatch.app`）；iPhone 已 USB 在线；`DEVELOPMENT_TEAM = 9RH9WL3PQ3` 已写进 `project.yml` 与 `KouShui.xcodeproj`，**不需要再手动选 Team**。
**App 已装到手机并已信任**：`叩音 / com.example.koushui / 1.0.0`，启动正常，真机截图确认 WebView 视觉与网页原型一致（水面、五音柱、回想墨符都在）。免费签名 7 天有效（2026-11-14 到期）。
`./scripts/install-device.sh [TEAM_ID] [UDID] [BUNDLE_PREFIX]` 作为备用（Team 自动推断）。

## iOS 端架构说明（2026-11-08 起）

用户真机反馈原生重写视觉与原型差距过大，已改为 **WebView 承载 + 原生接管触觉**：

- `iOS/soft-tap.html`：网页原型打包进 Bundle（`soft-tap.html` 的真机适配版 v11），负责全部视觉与交互。
- `iOS/StillwaveApp.swift`：全屏 WKWebView 容器；`WKUserScript` 包装 `playNote()`，把每次叩击的音级/力度/回声/长韵转发给原生 `SoftHaptics`（Core Haptics 四种材质）；另桥接「落指 / 抬手」实现触感跟随（落指垫一层极轻持续触感，按住蓄长韵时持续、抬手即停）；页面加载后由原生注入 `--sat/--sab` 安全区变量，铺满全屏且标题/底部文字让开刘海与 Home 横条；`navigator.vibrate` 不再走浏览器震动。
- **审核风险**：主要功能由内嵌网页承载，需在审核备注中说明原生层价值（触觉引擎、音频会话、后台策略），见 `AppStore/02-审核与隐私.md` 的 4.2 应对。若后续被 4.2 拒审，退路是把 WebView 视觉换成原生 Canvas 重做。

## 打开方式

双击 `KouShui.xcodeproj`（已生成，不需要装 XcodeGen）。
如果改过 `project.yml`，在目录里执行 `xcodegen generate` 重新生成即可。

本机验证环境：Xcode 27.2 / iOS 27.2 SDK / watchOS 27.2 SDK / Swift 6.4.2（Swift 5 语言模式）。
**双端 `BUILD SUCCEEDED`，0 warning。**

## 目录

```
KouShui/
├── project.yml                     XcodeGen 定义（可复现工程）
├── KouShui.xcodeproj/              直接打开
├── Shared/                        两个 target 共享
│   ├── KouShuiModel.swift          品牌名、三分损益律、四心境、五套景、可调参数、MelodyWalk
│   ├── SoftTone.swift              五音合成 + 离线多抽头混响（不依赖音频资源）
│   ├── WuxingGlyph.swift          五行象形墨符，Path 手绘
│   └── Overlays.swift              五音计数柱、旋律折线
├── iOS/
│   ├── StillwaveApp.swift          @main、WKWebView 容器、Core Haptics 桥接（SoftHaptics）、音频会话
│   ├── soft-tap.html               网页原型原样打包（零改动），承载全部视觉与交互
│   ├── Info.plist / PrivacyInfo.xcprivacy
│   └── Assets.xcassets/AppIcon.appiconset/  主图 1024（RGB 无 alpha）
├── WatchApp/
│   ├── SoftTapWatch.swift          @main、SoftTapEngine、连续波场、主界面
│   ├── HapticScore.swift           OutputMode / 触觉乐谱 / AudioPolicy / WristSession
│   ├── Info.plist / PrivacyInfo.xcprivacy
│   └── Assets.xcassets/AppIcon.appiconset/  watchOS 全套尺寸
├── AppStore/                       上架材料
│   ├── metadata.json                ASC 字段速查（含 TODO）
│   ├── 01-商店文案.md              中英文可复制文案 + 命名风险
│   ├── 02-审核与隐私.md            审核备注、隐私政策、支持页、拒审对照
│   ├── 03-发布流程.md              必改清单、打包上传、TestFlight、发布、回滚
│   ├── 04-推广计划.md              ASO、素材脚本、渠道节奏、指标
│   ├── 05-截图脚本.md              规格、构图、拍摄命令
│   └── 06-真机试装.md              免费账号装到手机 / 手表、一键脚本、排错
├── scripts/
│   └── install-device.sh           真机一键：编译 → 安装 → 启动
../appstore-kit.html                 上架材料总览页（可视化）
```

## 双端分工（不是把同一界面缩放两遍）

| | iPhone | Apple Watch |
|---|---|---|
| 触觉 | Core Haptics，可真正调 intensity / sharpness / attack / decay，四种材质 | 只有 `WKInterfaceDevice.play(.click)`；曲调靠**敲击疏密**编码（108→234ms） |
| 声音 | 可选，默认关；戴耳机更远 | **默认关闭**，静音优先；不提示戴耳机 |
| 屏幕 | 全屏水面，适合坐下来敲几分钟 | 熄屏后靠 `WKExtendedRuntimeSession(.mindfulness)` 继续播触觉 |
| 场景 | 书桌、夜里、戴耳机 | 开会、通勤、压力上来那 30 秒、单手 |

两端共享同一套五音律、心境规则、旋律游走与墨符，所以同一句在手机上敲、在表上回想，走向一致。

## 本机验证过的构建命令

```bash
# iOS scheme（连带嵌入 Watch App，各 target 用自己的 SDK）
xcodebuild -project KouShui.xcodeproj -scheme Stillwave \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/koushui-dd build

# 单独编 Watch
xcodebuild -project KouShui.xcodeproj -target KouShuiWatch -sdk watchsimulator \
  -configuration Debug CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO \
  SYMROOT=/tmp/koushui-watch-sym build

# arm64 真机 SDK 编译（免签名，只验证代码侧；产物含嵌入的 KouShuiWatch.app）
xcodebuild -project KouShui.xcodeproj -scheme Stillwave \
  -destination 'generic/platform=iOS' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/koushui-device-dd build
```

⚠️ 不要用 `-sdk iphonesimulator` 编整个 scheme：该参数全局生效，会把 watchOS target 也用 iOS SDK 编译。

## 上架前必改

见 `AppStore/03-发布流程.md` 第 1 节。最少要改：`project.yml` 的 `IOS_BUNDLE_ID` / `WATCH_BUNDLE_ID`（一处引用全站生效）、`DEVELOPMENT_TEAM`（现已填本机免费 Personal Team `9RH9WL3PQ3`，上架时换成正式 Team ID）、`metadata.json` 里所有 `TODO`、隐私/支持页上线、名称在 ASC 查重。

## 真编译 / 真安装推翻过的五个「以为没问题」

1. **`AVAudioUnitDelay` 在 watchOS 上不可用** → 共享合成器改成 PCM 里离线叠多抽头混响，双端同一份代码。
2. **Core Haptics 没有 `.hapticAttackTime` / `.hapticDecayTime`** → 正确是 `.attackTime` / `.decayTime`。
3. **watchOS 图标只给一张 1024 universal 会报错** → 必须补全套 watch 槽位（本工程已给 10 个尺寸 + marketing）。
4. **Watch Info.plist 必须同时有 `WKApplication = true` 与 `WKCompanionAppBundleIdentifier`** → 缺任一个，模拟器/真机的 `installd` 会拒绝安装整个 iOS 包。已设好，companion 值引用工程变量 `IOS_BUNDLE_ID`。
5. **iOS 首屏原本太暗** → 环境水纹透明度从 0.08–0.16 提到 0.17–0.34、文字提到 0.4–0.62；在模拟器里实截确认可辨。`AppStore/screenshots/` 有 1206×2622 的真实首屏 PNG + 无 alpha 的 JPG。

另外：Xcode 27 的 SwiftUI `@State` 是外部宏，在受限构建环境（CI / 沙箱）里 `swift-plugin-server` 可能起不来。本工程把所有 `@State` 移进 `@Published`，两端都不依赖宏插件，真机行为不变。

## 已知限制

- Swift 已通过 Xcode 完整编译（不只是语法解析），但**没有在真机上跑过**：Core Haptics 手感、Watch 熄屏触觉、勿扰态、耗电都必须在真机验证。
- 第一版不接 HealthKit、不联网、不收集数据，因此没有埋点，推广指标只能靠 ASC 数据与主动反馈。
- `TARGETED_DEVICE_FAMILY = 1`（只声明 iPhone），避免被强制要求 iPad 13″ 截图；iPad 仍可以 iPhone 兼容模式运行。
- 产品名已定「叩音」（取《文赋》「叩寂寞而求音」末二字），不再有谐音风险；英文名 Stillwave 不变。上架前仍需在 ASC 查重与商标检索（见 `AppStore/01-商店文案.md`）。
- 工程目录 `KouShui/`、target 名与 Bundle ID 占位 `com.example.koushui` 沿用旧拼音，属于技术标识（上架前本来就要换成你自己的反向域名）；中文显示名、商店文案、截图与图标预览已全站统一为「叩音」。
