# 架构与设计语言 · Architecture

这篇文档讲三件事：**视觉从哪来**、**触觉怎么保证每一次都有**、**双端如何共享同一套语言**。
读完你就能知道：改一个涟漪要动几处、为什么手表端没有 WebView、哪些坑我们已经替你踩过。

## 1. 视觉的单一事实源：`soft-tap.html`

所有视觉（五套景、涟漪、月光、雨夜、旋律线）的源头都是网页原型 `soft-tap.html`：

- WebGL 路径：GLSL fragment shader 实现水面、涟漪、月光、各景的环境层
- 2D Canvas 降级路径：无 WebGL 的环境用同一套语言的简化版
- iOS 端把这个文件**字节级原样**打进 Bundle（`KouShui/iOS/soft-tap.html`），
  由 WKWebView 全屏承载——所以 iPhone 上的观感就是网页原型的观感

```
soft-tap.html（设计源头）
   ├── 浏览器直接打开（网页版）
   └── KouShui/iOS/soft-tap.html（Bundle 资源，必须与源文件一致）
          └── StillwaveApp.swift：WKWebView 容器
                ├── WKUserScript 包装 playNote() → 原生 SoftHaptics（Core Haptics）
                ├── 桥接 pointerdown/up → 落指触感跟随（beginHold/endHold）
                └── 加载后注入 --sat/--sab 安全区变量（铺满全屏、让开刘海/横条）
```

**改视觉的正确姿势**：先改 `soft-tap.html` 并在浏览器目视验证，再原样复制进
`KouShui/iOS/soft-tap.html`，最后（如需要）在 Watch 端的 `WaterField` 用 SwiftUI Canvas
重绘同款。CI 里有一步会 diff 两个 html 确保一致。

### 景的分层（shader 里的通用骨架）

每套景都是三层叠加，这也是你自己加景时的模板：

1. **水面基底**（tex）：各景有自己的水/纸/雾质地
2. **环境层**（extra）：景的性格所在——墨池的水纹月光、雨夜的「夜雨落池」
   （雨丝 + 雨点落水涟漪 + 灯光倒影光带）、松雾的雾带
3. **叩击层**：涟漪环 + 波前扰动 + 落点光晕，与所有景共享

> 雨夜的设计立意值得记住：**天也在叩水**——环境雨点与用户叩击共用同一套涟漪语言，
> 只是更小更淡，安静不抢戏。

所有按像素写的尺寸都要乘 `pxs = uRes.x / 390`（以 390pt 屏为基准），
否则 dpr=3 的真机上珠子、雨丝会小到看不见。

## 2. 触觉链路：每一次落指必震

### iPhone

```
网页 playNote(degree, strength, …)
  → WKScriptMessageHandler 桥接（18ms 去抖，物理上不可能吞掉一次敲击）
    → Core Haptics CHHapticEngine
        连敲（<280ms）只发瞬态事件、余韵封顶 0.4s   ← 防硬件级「整条丢弃」
        播放失败 → 重启引擎重试一次
        再失败 → UIImpactFeedbackGenerator(.soft) 兜底
    → 回到前台自动重启引擎（didBecomeActive）
```

踩过的坑：每叩一条近 1 秒的连续余韵触觉，快速连敲时多条长触觉叠在马达上会被
**硬件整条丢弃**——表现就是「有的敲有感觉、有的没有」。修复即上文的
「快节奏只发瞬态 + 余韵封顶」。

### Apple Watch

只有 `WKInterfaceDevice.play(.click)` 一种触觉。曲调信息完全由**敲击疏密**编码：
108→234ms 的间隔序列。熄屏后靠 `WKExtendedRuntimeSession(.mindfulness)` 继续
播触觉（正念练习的审核语义，不滥用后台）。

同样踩过坑：`minInterval` 节流 0.22s 会把 220ms 内的连敲**静默吞掉**——这是
Watch 版「有的敲没感觉」的根因，现为 0.12s（守住系统 100ms 硬件下限）。

## 3. Watch 端：没有 WebView，怎么办

watchOS 没有 WebKit。Watch 端用 SwiftUI `Canvas`（24fps TimelineView）按同一套
设计语言原生重绘：

- 横向水纹只是 alpha≈0.02–0.03 的肌理，绝不抢戏
- 月光：中央柔光 radialGradient，随环境呼吸、叩击让位
- 叩击涟漪：主环（r = age·speed）+ 后随环（落后一个波长）+ 落点光晕
  （rr = 26 + age·60，与网页 2D 同参数）
- 雨夜：灯光倒影竖直光带 + 雨丝 + 程序化雨点涟漪（时间分槽 + hash 落点）

坑：`GraphicsContext` 是值类型且 watchOS 没有 `saveGState`——局部变换画在
变换过的**副本**上即可；Canvas 闭包太长会触发 Swift 类型检查超时——
拆成独立方法 + 全部显式类型标注。

## 4. 五音与旋律：随机，但有曲调

- 五音（宫商角徵羽）来自三分损益律，音高由 `Shared/SoftTone.swift` 纯代码合成
  （PCM 离线叠多抽头混响，不依赖音频资源——因为 `AVAudioUnitDelay` 在 watchOS 不可用）
- `MelodyWalk` 是随机游走：心境给出音区、跨度、句长、收束方式的轮廓，
  每次叩击落在轮廓内「听起来对」的下一个音上；高八度（按住）不计入句子
- 敲完一句稍等，水面「回想」：把刚敲的句子按原节奏、更轻更疏地重播一遍

## 5. 已知限制与审核备注

- 主要视觉由内嵌网页承载：App Store 审核备注需说明原生层价值（触觉引擎、
  音频会话、后台策略），详见 `KouShui/AppStore/02-审核与隐私.md`；
  若被 4.2 拒审，退路是原生 Canvas 重做视觉
- 免费 Personal Team 签名 7 天有效；上架前需换正式 Team 与自己的 Bundle ID
  （`KouShui/project.yml` 一处引用全站生效）
- `TARGETED_DEVICE_FAMILY = 1`（只声明 iPhone），iPad 以兼容模式运行
