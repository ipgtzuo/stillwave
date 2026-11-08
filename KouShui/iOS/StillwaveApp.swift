//
//  StillwaveApp.swift
//  叩音 · Stillwave — iOS App target
//
//  iPhone 是「坐下来敲几分钟」的那一端：Core Haptics 能真正调强度 / 锐度 /
//  渐入 / 消散，水面全屏铺开，声音与回响完整。
//  Watch 是「压力上来那 30 秒」的那一端：默认静音、熄屏可用、单手。
//  两端共享 Shared/ 里的五音律、心境、景、墨符与旋律生成规则，
//  所以同一句在手机上敲、在表上回想，走向完全一致。
//
//  ⚠️ 合规：文案只写「片刻安静 / 放松」，不写治疗、改善睡眠、降低血压、
//     调理五脏等任何疗效宣称。第一版完全不接 HealthKit。
//

import SwiftUI
import CoreHaptics
import AVFoundation
import WebKit
import UIKit

// MARK: - 柔软度：Watch 上不存在的旋钮，在 iOS 上是真的

struct SoftnessProfile: Equatable, Hashable {
    var name: String
    var intensity: Float
    var sharpness: Float
    var attack: Float
    var decay: Float
    var duration: Double

    static let presets: [SoftnessProfile] = [
        .init(name: "云朵", intensity: 0.22, sharpness: 0.05, attack: 0.42, decay: 0.85, duration: 1.30),
        .init(name: "水面", intensity: 0.32, sharpness: 0.14, attack: 0.28, decay: 0.70, duration: 1.05),
        .init(name: "软木", intensity: 0.40, sharpness: 0.20, attack: 0.16, decay: 0.55, duration: 0.80),
        .init(name: "绒布", intensity: 0.26, sharpness: 0.02, attack: 0.55, decay: 0.95, duration: 1.50)
    ]
}

// MARK: - Core Haptics：一次「叩」= 极轻瞬态 + 一段缓慢消散的连续余韵

@MainActor
final class SoftHaptics: ObservableObject {
    @Published var softness: SoftnessProfile = .presets[1]
    @Published private(set) var available = false

    private var engine: CHHapticEngine?
    private var running = false
    private var holdPlayer: CHHapticAdvancedPatternPlayer?
    /// 引擎启动得太早（App 还没激活）会失败；做成惰性的，每次叩击前兜底重试。
    private let fallbackImpact = UIImpactFeedbackGenerator(style: .soft)
    private var lastKnock: TimeInterval = 0

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let e = try? CHHapticEngine()
        guard let e else { return }
        e.playsHapticsOnly = true
        e.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.running = false }
        }
        e.resetHandler = { [weak self] in
            Task { @MainActor in self?.running = false }
        }
        engine = e
        available = true
        startEngine()
        fallbackImpact.prepare()
        // 回到前台时引擎大概率已被系统停掉：主动拉起，第一声就不会丢
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.startEngine() }
        }
    }

    private func startEngine() {
        guard available, let engine, !running else { return }
        do { try engine.start(); running = true } catch { running = false }
    }

    /// 用模式真正发声；失败抛给调用方决定重试 / 退系统轻拍。
    private func playPattern(_ pattern: CHHapticPattern) throws {
        guard let engine else { return }
        try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }

    func knock(degree: Int, echo: Bool = false, strength: Float = 1.0, long: Bool = false) {
        let now = Date().timeIntervalSince1970
        let rapid = now - lastKnock < 0.28
        lastKnock = now
        guard available, let engine else {
            // Core Haptics 不可用时也不断反馈：退到系统轻拍，保证「触感跟随」
            guard !echo else { return }
            fallbackImpact.impactOccurred(intensity: min(1, max(0.3, CGFloat(strength))))
            fallbackImpact.prepare()
            return
        }
        startEngine()
        let s = softness
        let k = Float(degree) / 9.0
        // 网页原型把力度(0…1)一起传过来：重叩更实、轻叩更虚；回想再压低一层。
        let force = min(max(strength, 0.25), 1.25)
        let scale: Float = (echo ? 0.42 : 1.0) * (long ? 0.8 : 1.0) * force
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity,
                                               value: s.intensity * (0.85 + k * 0.25) * scale)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness,
                                               value: s.sharpness * (0.8 + k * 0.4))
        let transient = CHHapticEvent(eventType: .hapticTransient,
                                      parameters: [intensity, sharpness], relativeTime: 0)
        var events: [CHHapticEvent] = [transient]
        // 余韵持续近 1 秒：连敲时多条长触觉叠在马达上，硬件会整条丢弃——
        // 这正是「有的叩击没有触感」的主因。快节奏时只留瞬态，余韵封顶 0.4 秒。
        let baseDur = s.duration * (1.15 - Double(k) * 0.3) * (long ? 1.6 : 1.0)
        if !rapid || long {
            // Core Haptics 的包络参数名是 attackTime / decayTime（不是 hapticAttackTime）
            let attack = CHHapticEventParameter(parameterID: .attackTime, value: s.attack)
            let decay = CHHapticEventParameter(parameterID: .decayTime, value: s.decay)
            let tailIntensity = CHHapticEventParameter(parameterID: .hapticIntensity,
                                                       value: s.intensity * 0.55 * scale)
            events.append(CHHapticEvent(eventType: .hapticContinuous,
                                        parameters: [tailIntensity, sharpness, attack, decay],
                                        relativeTime: 0.02, duration: min(baseDur, 0.4)))
        }
        do {
            try playPattern(try CHHapticPattern(events: events, parameters: []))
        } catch {
            // 最常见的失败是引擎被系统停了：重启重试一次，仍失败就退系统轻拍兜底
            do {
                try engine.start(); running = true
                try playPattern(try CHHapticPattern(events: events, parameters: []))
            } catch {
                if !echo {
                    fallbackImpact.impactOccurred(intensity: min(1, max(0.25, CGFloat(scale))))
                    fallbackImpact.prepare()
                }
            }
        }
    }

    /// 触感跟随：手指一落就垫上一层极轻的「贴着水面」的持续触感，
    /// 按住蓄长韵时它一直在，抬手即停。1.5 秒上限防消息丢失后常振。
    func beginHold() {
        guard available, let engine else { return }
        startEngine()
        if holdPlayer == nil {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity,
                                                   value: softness.intensity * 0.22)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness,
                                                   value: softness.sharpness * 0.5)
            let attack = CHHapticEventParameter(parameterID: .attackTime, value: 0.6)
            let decay = CHHapticEventParameter(parameterID: .decayTime, value: 0.9)
            let hold = CHHapticEvent(eventType: .hapticContinuous,
                                     parameters: [intensity, sharpness, attack, decay],
                                     relativeTime: 0, duration: 1.5)
            do {
                let pattern = try CHHapticPattern(events: [hold], parameters: [])
                holdPlayer = try engine.makeAdvancedPlayer(with: pattern)
            } catch { return }
        }
        try? holdPlayer?.start(atTime: CHHapticTimeImmediate)
    }

    func endHold() {
        try? holdPlayer?.stop(atTime: CHHapticTimeImmediate)
    }
}

// MARK: - 全屏水面：一整片连续高度切片，没有任何描边的圆

struct IOSWaterView: View {
    let pulses: [WaterPulse]
    let backdrop: Backdrop

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let t = CGFloat(now.timeIntervalSinceReferenceDate)
                let ink = backdrop.ink
                // 月影交给 SwiftUI 背景层（见 IOSRootView 的 .background），
                // 不在 Canvas 里 fill 全屏渐变：实测会覆盖整帧成不透明黑。
                let lines = 28
                let cols = 46
                for i in 0..<lines {
                    let baseY = size.height * CGFloat(i + 1) / CGFloat(lines + 1)
                    var path = Path()
                    for s in 0...cols {
                        let x = size.width * CGFloat(s) / CGFloat(cols)
                        var y = baseY
                        // 环境层：极缓的整片水在流，没有起点也没有边界
                        y += sin(x * 0.012 + t * 0.22 + CGFloat(i) * 0.28) * 1.6
                        for p in pulses {
                            let age = now.timeIntervalSince(p.birth)
                            guard age > 0, age < 2.8 else { continue }
                            let dx = x - p.x, dy = baseY - p.y
                            let r = sqrt(dx * dx + dy * dy)
                            let front = CGFloat(age) * (110 + CGFloat(p.degree) * 9)
                            let band = (r - front) / (70 + CGFloat(9 - p.degree) * 5)
                            let env = CGFloat(exp(-Double(band * band) * 1.7)
                                              * pow(1 - age / 2.8, 1.6)) * (p.echo ? 0.35 : 1)
                            y += sin((r - front) * 0.10) * env * 12
                        }
                        let pt = CGPoint(x: x, y: y)
                        if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    context.stroke(path, with: .color(ink.opacity(i % 4 == 0 ? 0.34 : 0.17)),
                                   lineWidth: 0.7)
                }
                for p in pulses {
                    let age = now.timeIntervalSince(p.birth)
                    guard age > 0, age < 2.8 else { continue }
                    let q = 1 - age / 2.8
                    let rr = CGFloat(24 + age * 46)
                    let rect = CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)
                    let shade = GraphicsContext.Shading.radialGradient(
                        Gradient(colors: [ink.opacity(0.14 * q), .clear]),
                        center: CGPoint(x: p.x, y: p.y), startRadius: 0, endRadius: rr)
                    context.fill(Path(ellipseIn: rect), with: shade)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct WaterPulse: Identifiable {
    let id = UUID()
    let x: CGFloat, y: CGFloat
    let degree: Int
    let birth: Date
    let echo: Bool
}

// MARK: - 引擎：与 Watch 同一套规则，加上 iOS 才有的自定义触觉与声音

@MainActor
final class IOSEngine: ObservableObject {
    @Published var pulses: [WaterPulse] = []
    @Published var count = 0
    @Published var degree = 5
    @Published var noteCounts: [Int] = Array(repeating: 0, count: 5)
    @Published var trace: [Int] = []
    @Published var hint = "轻 叩 水 面 · 连 敲 成 句"
    @Published var soundOn = false                 // 默认静音优先，与 Watch 一致
    @Published var backdrop: Backdrop = .mochi
    @Published var mood: Mood = .chengming {
        didSet { walk.profile = mood.profile; walk.reset() }
    }
    @Published var softness: SoftnessProfile = .presets[1]
    /// 设置页开关也放引擎里：Xcode 27 的 @State 是 external macro，
    /// 放进 @Published 后两端都不依赖宏插件，CI / 沙箱构建也能通过。
    @Published var showingSettings = false

    private var walk = MelodyWalk()
    private let tone = SoftTone()
    private let haptics = SoftHaptics()
    private var preset = SoftTapPreset()
    private var phrase: [(degree: Int, at: Date, x: CGFloat, y: CGFloat)] = []
    private var echoTask: Task<Void, Never>?

    init() { walk.profile = mood.profile }

    func knock(at point: CGPoint, in size: CGSize) {
        let d = walk.next()
        degree = d
        count += 1
        noteCounts[d % 5] += 1
        trace.append(d)
        if trace.count > 9 { trace.removeFirst() }

        haptics.knock(degree: d)
        if soundOn {
            let pan = Float((point.x / max(1, size.width) - 0.5) * 1.4)
            tone.render(preset: preset, degree: d, softening: 0.18, pan: pan,
                        echo: false, octave: false, long: false)
            tone.play()
        }
        pulses.append(WaterPulse(x: point.x, y: point.y, degree: d,
                                 birth: Date(), echo: false))
        if pulses.count > 12 { pulses.removeFirst() }
        phrase.append((d, Date(), point.x, point.y))
        scheduleEcho()
    }

    func cycleMood() {
        let all = Mood.allCases
        mood = all[((all.firstIndex(of: mood) ?? 0) + 1) % all.count]
    }

    func cycleBackdrop() {
        let all = Backdrop.allCases
        backdrop = all[((all.firstIndex(of: backdrop) ?? 0) + 1) % all.count]
    }

    private func scheduleEcho() {
        echoTask?.cancel()
        echoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            self.replay()
        }
    }

    /// 水有记忆：静默后把刚才那一句更淡、更慢地还回来一次，然后归于静。
    /// 回想不计数、不再生成新音，也不打断用户新敲的一句。
    private func replay() {
        guard phrase.count >= 2 else { return }
        let snapshot = phrase
        phrase = []
        let t0 = snapshot[0].at
        hint = "水 在 回 想"
        for n in snapshot {
            let delay = n.at.timeIntervalSince(t0) * 1.18
            Task { @MainActor in
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                self.pulses.append(WaterPulse(x: n.x, y: n.y, degree: n.degree,
                                              birth: Date(), echo: true))
                if self.pulses.count > 14 { self.pulses.removeFirst() }
                self.haptics.knock(degree: n.degree, echo: true)
                if self.soundOn {
                    self.tone.render(preset: self.preset, degree: n.degree, softening: 0.52,
                                     pan: 0, echo: true, octave: false, long: false)
                    self.tone.play()
                }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if Task.isCancelled { return }
            self.hint = "归 于 静"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            self.hint = "轻 叩 水 面 · 连 敲 成 句"
        }
    }
}

// MARK: - 主界面

struct IOSRootView: View {
    @StateObject private var engine = IOSEngine()

    var body: some View {
        GeometryReader { geo in
            let bd = engine.backdrop
            let fg: Color = bd.isPaper
                ? Color(red: 0.18, green: 0.22, blue: 0.18)
                : Color(red: 0.84, green: 0.89, blue: 0.86)
            ZStack {
                bd.base.ignoresSafeArea()
                IOSWaterView(pulses: engine.pulses, backdrop: bd)

                VStack(spacing: 14) {
                    Text(appDisplayName)
                        .font(.system(size: 15, weight: .light))
                        .kerning(10)
                        .foregroundStyle(fg.opacity(0.62))
                    Text("\(appName) · \(engine.count)")
                        .font(.system(size: 10, weight: .light).monospacedDigit())
                        .foregroundStyle(fg.opacity(0.40))
                    NoteBarsView(counts: engine.noteCounts, tint: fg)
                    MelodyTraceView(trace: engine.trace, tint: fg)
                    Spacer()
                    WuxingGlyph(index: engine.degree % 5, high: engine.degree >= 5, tint: fg)
                        .opacity(engine.count == 0 ? 0.32 : 0.95)
                    Spacer()
                    Text(engine.hint)
                        .font(.system(size: 11, weight: .light))
                        .kerning(3)
                        .foregroundStyle(fg.opacity(0.58))
                }
                .padding(.vertical, 40)
                .allowsHitTesting(false)

                VStack {
                    HStack {
                        Spacer()
                        Button { engine.showingSettings.toggle() } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(fg.opacity(0.62))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    HStack {
                        // 与网页「景 · 墨池」「调 · 澄明」同一套模式
                        Button("景 · " + bd.name) { engine.cycleBackdrop() }
                        Spacer()
                        Button("调 · " + engine.mood.profile.name) { engine.cycleMood() }
                    }
                    .font(.system(size: 10, weight: .light))
                    .buttonStyle(.plain)
                    .foregroundStyle(fg.opacity(0.52))
                }
                .padding(24)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                engine.knock(at: value.location, in: geo.size)
            })
        }
        .sheet(isPresented: $engine.showingSettings) {
            IOSSettingsView(engine: engine)
        }
    }
}

// MARK: - 设置：耳机提示只出现在这里，且是「增益」不是「前提」

struct IOSSettingsView: View {
    @ObservedObject var engine: IOSEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("触感 · 只有 iPhone 能真正调") {
                    Picker("材质", selection: $engine.softness) {
                        ForEach(SoftnessProfile.presets, id: \.name) { p in
                            Text(p.name).tag(p)
                        }
                    }
                    Text("强度与锐度来自 Core Haptics；Apple Watch 上只有固定的轻拍，\n那边改用敲击的疏密来表达音高。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("声音") {
                    Toggle("播放五音", isOn: $engine.soundOn)
                    Text(AudioHint.text)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("心境与景") {
                    Picker("心境", selection: $engine.mood) {
                        ForEach(Mood.allCases) { m in Text(m.profile.name).tag(m) }
                    }
                    Picker("景", selection: $engine.backdrop) {
                        ForEach(Backdrop.allCases) { b in Text(b.name).tag(b) }
                    }
                }
                Section("关于") {
                    Text("课虚无以责有，叩寂寞而求音 —— 晋 · 陆机《文赋》")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("这只是借五行之象做的视觉符号，与任何疗疾、养生主张无关。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("调")
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}

/// iOS 侧不 import WatchKit，所以把那句增益提示单独放这里，避免两端文案走样
enum AudioHint {
    static let text = "戴上耳机，回响会更远、更有空间感。不戴也完整：曲调在水面上，腕上则在触觉里。"
}

// MARK: - 网页原型的原生容器（2026-11-08 起为 iOS 端主界面）
//
// 设计决策：原生 SwiftUI 呈现层与最初设计的网页原型差距太大，因此改为把
// `soft-tap.html` **零改动**打包进 App，用 WKWebView 全屏承载。原生层只补两件
// 网页在 iOS 上做不到的事：
//   ① Core Haptics 真实触觉（iOS Safari / WKWebView 没有 Vibration API）
//   ② AVAudioSession 输出策略、后台与熄屏时的引擎生命周期
// 桥接不修改 HTML：注入 WKUserScript 包装全局 playNote，把音级 / 力度 / 回声
// 标记转发给原生。网页原型仍是单一事实来源，改设计只改那一个 HTML 文件。
//
// ⚠️ 上架提示：主要功能由 Web 内容承载，App Store 审核可能援引 4.2「最低功能」。
//    见 AppStore/02-审核与隐私.md；原生触觉、音频策略与配套 watchOS App 是
//    说明「这不是一个网页书签」的主要依据。后续若要彻底规避，可把呈现层原生化。

/// 与 soft-tap.html 的 body 背景一致，让状态栏区域与水面连成一片。
struct WebPrototypeRoot: View {
    var body: some View {
        ZStack {
            Color(red: 0.020, green: 0.027, blue: 0.035)
                .edgesIgnoringSafeArea(.all)
            // 铺满全屏（含刘海与底部横条区域），页面自己的 --sat/--sab 变量
            // 会由原生注入实际安全区值，把标题与底部文字让开系统遮挡。
            WebPrototypeView()
                .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear { AudioSessionPolicy.activate() }
    }
}

enum AudioSessionPolicy {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        // 原型默认开声，这里沿用；Watch 端仍默认静音、不弹「请戴耳机」。
        // mixWithOthers：不打断用户正在听的音乐。
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

private enum BridgeScript {
    /// 包装顶层 function playNote(...)。documentEnd 时若脚本尚未执行，
    /// DOMContentLoaded / load 再兜底一次，避免只拿到 undefined。
    /// 另外把「手指落下 / 抬起」也转发给原生：落指垫一层极轻的持续触感，
    /// 按住蓄长韵时持续跟随，抬手即停 —— 视觉里的指痕在触觉里也有了对应物。
    static let hook = #"""
    (function () {
      var H = window.webkit && window.webkit.messageHandlers &&
              window.webkit.messageHandlers.koushui;
      if (!H) return;
      function post(o) { try { H.postMessage(o); } catch (e) {} }
      function hook() {
        if (typeof window.playNote !== 'function' || window.playNote.__koushui) return false;
        var orig = window.playNote;
        // 原型里第 6 个参数实际传的是 long（长韵），不是八度：长韵要更绵长的余韵，
        // 原生按 long 处理，octave 字段名保留只作兼容。
        var wrapped = function (degree, strength, x, y, isEcho, octave, long) {
          post({ degree: Number(degree) || 0,
                 strength: Number(strength) || 0,
                 echo: !!isEcho, long: !!(octave || long) });
          return orig.apply(this, arguments);
        };
        wrapped.__koushui = true;
        window.playNote = wrapped;
        var stage = document.getElementById('stage');
        if (stage) {
          stage.addEventListener('pointerdown', function (e) {
            if (e.target.closest('.panel, #tuneBtn, #sceneSwitch')) return;
            post({ hold: 1 });
          });
        }
        window.addEventListener('pointerup', function () { post({ hold: 0 }); });
        window.addEventListener('pointercancel', function () { post({ hold: 0 }); });
        return true;
      }
      if (!hook()) {
        document.addEventListener('DOMContentLoaded', hook);
        window.addEventListener('load', hook);
      }
    })();
    """#
}

@MainActor
final class WebPrototypeCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let haptics = SoftHaptics()
    private var lastKnock: TimeInterval = 0
    private var insetsInjected = false

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                          didReceive message: WKScriptMessage) {
        // WKScriptMessage.body 在 Xcode 27 SDK 里是 main-actor 隔离的，
        // 解析必须放进 MainActor 任务，不能从 nonisolated 回调里直接读。
        Task { @MainActor [weak self] in
            guard let body = message.body as? [String: Any] else { return }
            if let hold = body["hold"] as? Int {
                hold == 1 ? self?.haptics.beginHold() : self?.haptics.endHold()
                return
            }
            let degree = body["degree"] as? Int ?? 0
            let strength = Float(body["strength"] as? Double ?? 1.0)
            let echo = body["echo"] as? Bool ?? false
            let long = body["long"] as? Bool ?? false
            self?.knock(degree: degree, strength: strength, echo: echo, long: long)
        }
    }

    /// 页面加载完成后，把真实安全区写进页面的 --sat / --sab 变量：
    /// 标题让开刘海，底部文字让开 Home 横条。WKWebView 的 CSS px 与 point 一致。
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard !self.insetsInjected else { return }
            self.insetsInjected = true
            let top = webView.safeAreaInsets.top
            let bottom = webView.safeAreaInsets.bottom
            let js = "document.documentElement.style.setProperty('--sat','\(top)px');" +
                     "document.documentElement.style.setProperty('--sab','\(bottom)px');"
            _ = try? await webView.evaluateJavaScript(js)
        }
    }

    private func knock(degree: Int, strength: Float, echo: Bool, long: Bool) {
        // 长按成句时 playNote 可能同帧连发；18ms 去抖，避免触觉糊成一团。
        let now = Date().timeIntervalSince1970
        guard now - lastKnock > 0.018 else { return }
        lastKnock = now
        haptics.knock(degree: degree, echo: echo, strength: strength, long: long)
    }
}

struct WebPrototypeView: UIViewRepresentable {
    func makeCoordinator() -> WebPrototypeCoordinator { WebPrototypeCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Web Audio 由首次敲击（真实用户手势）解锁，不要求额外的播放授权。
        config.mediaTypesRequiringUserActionForPlayback = []
        // 单文件离线资源、零网络请求；不落任何浏览数据，隐私最省。
        config.websiteDataStore = .nonPersistent()

        let content = WKUserContentController()
        content.add(context.coordinator, name: "koushui")
        content.addUserScript(WKUserScript(source: BridgeScript.hook,
                                          injectionTime: .atDocumentEnd,
                                          forMainFrameOnly: true))
        config.userContentController = content

        let webView = WKWebView(frame: .zero, configuration: config)
        let paper = UIColor(red: 0.020, green: 0.027, blue: 0.035, alpha: 1)
        webView.backgroundColor = paper
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.allowsBackForwardNavigationGestures = false
        // 页面加载完成后注入安全区值（见 WebPrototypeCoordinator.webView(_:didFinish:)）
        webView.navigationDelegate = context.coordinator

        guard let url = Bundle.main.url(forResource: "soft-tap", withExtension: "html") else {
            assertionFailure("soft-tap.html 未打包进 Copy Bundle Resources")
            return webView
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: WebPrototypeCoordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "koushui")
    }
}

@main
struct StillwaveApp: App {
    var body: some Scene {
        WindowGroup { WebPrototypeRoot() }
    }
}
