//
//  SoftTapWatch.swift — watchOS target 专属：引擎、连续波场、主界面、App 入口
//  触觉乐谱 / 输出策略 / 熄屏会话见 HapticScore.swift。
//
import SwiftUI
import WatchKit
import AVFoundation

// MARK: - 引擎：句子 + 回想 + 波场

struct WaveFieldSource: Identifiable {
    let id: Int
    let x: CGFloat, y: CGFloat
    let degree: Int
    let strength: Double
    let birth: Date
    let echo: Bool
    let wavelength: CGFloat
    let speed: CGFloat
    let life: TimeInterval
}

@MainActor
final class SoftTapEngine: ObservableObject {
    struct Note {
        let x: CGFloat, y: CGFloat
        let degree: Int
        let strength: Double
        let at: Date
    }

    @Published var pulse = 0
    @Published var count = 0
    @Published var noteName = "宫"
    @Published var degree = 5
    @Published var scale: CGFloat = 1
    @Published var echoing = false
    @Published var hint = "轻触水面"
    @Published var waves: [WaveFieldSource] = []
    @Published var melodyTrace: [Int] = []
    @Published var preset = SoftTapPreset()
    @Published var noteCounts: [Int] = Array(repeating: 0, count: 5)
    /// 供水面的「让位」计算使用：最后一次真实敲击的时间
    @Published var lastTapAt = Date.distantPast
    /// 表冠值放在引擎里：Xcode 27 的 SwiftUI @State 是 external macro，
    /// 受限构建环境（CI / 沙箱）可能无法启动 swift-plugin-server。放进 @Published
    /// 后 Watch 端完全不依赖 @State 宏，真机行为一致。
    @Published var crownValue: Double = 0
    var pressStart: Date?

    /// 输出状态：默认 .silent（主动静音）。系统静音 / 勿扰没有公开 API 可读，
    /// 所以不检测，只由用户显式开关与屏幕状态决定 —— 详见 AudioPolicy。
    @Published var outputMode: OutputMode = .silent
    /// 用户显式打开声音才为 true；iPhone 端设置页同步过来（WatchConnectivity）
    @Published var soundEnabled = false
    /// 用户自己标注「我开着勿扰」；系统连触觉一起关时 App 不绕过、不弹窗
    @Published var userMarkedFocus = false

    /// 由 WKApplicationDelegate 的 active / inactive 或 scenePhase 调用
    func refreshOutput(screenOn: Bool) {
        outputMode = AudioPolicy.resolve(soundEnabled: soundEnabled,
                                         screenOn: screenOn,
                                         userMarkedFocus: userMarkedFocus)
    }

    private let tone = SoftTone()
    private var lastTap = Date.distantPast
    private var walk = MelodyWalk()
    private var chain = 0, lastDegree = 5
    private var phrase: [Note] = []
    private var echoDone = false
    private var echoTask: Task<Void, Never>?
    private var waveID = 0

    /// 切换心境：同步覆盖标量参数并另起一句，让曲线的变化立刻听得出来
    func setMood(_ mood: Mood) {
        let m = mood.profile
        preset.mood = mood
        preset.melodyWander = m.wander
        preset.melodyBias = m.bias
        preset.melodyAnchor = m.anchor
        preset.melodySpan = m.span
        preset.phraseMin = m.lenMin
        preset.phraseMax = m.lenMax
        walk.profile = preset.resolvedMood
        walk.reset()
        melodyTrace = []
        hint = m.name
    }

    func setBackdrop(_ backdrop: Backdrop) {
        preset.backdrop = backdrop
    }

    func tap(at point: CGPoint, in size: CGSize) {
        let now = Date()
        let gap = now.timeIntervalSince(lastTap)
        guard gap >= preset.minInterval else { return }
        // 第一次落指就签下运行时契约：不发声的练习用 mindfulness，
        // 熄屏后 HapticScore 仍能继续敲。session 幂等，delegate 挂在 app 作用域。
        WristSession.shared.start()
        walk.profile = preset.resolvedMood
        lastTapAt = now
        echoTask?.cancel(); echoTask = nil
        if echoing { echoing = false; echoDone = true }
        if gap > 2.2 { walk.reset(); melodyTrace = [] }

        let degree = walk.next()
        lastDegree = degree
        melodyTrace.append(degree)
        if melodyTrace.count > 9 { melodyTrace.removeFirst() }
        noteCounts[degree % 5] += 1   // 高八度计入同一个音，回想不重复计数
        chain = gap < 0.46 ? min(chain + 1, 4) : 0
        let strength = max(0.46, 1 - Double(chain) * 0.13)
        lastTap = now; count += 1; echoDone = false
        noteName = noteNames[degree % 5]
        self.degree = degree
        hint = "连敲成句"

        phrase.append(Note(x: point.x, y: point.y, degree: degree, strength: strength, at: now))
        if phrase.count > 12 { phrase.removeFirst() }
        emit(point: point, size: size, degree: degree, strength: strength,
             echo: false, octave: false, long: false)
        scheduleEcho(size: size)
    }

    // 按住超过约 0.45 秒再松开：同一个音的高八度长韵，不计入句子
    func hold(at point: CGPoint, in size: CGSize) {
        guard preset.octaveOnHold else { return }
        emit(point: point, size: size, degree: lastDegree, strength: 0.8,
             echo: false, octave: true, long: true)
    }

    private func emit(point: CGPoint, size: CGSize, degree: Int, strength: Double,
                      echo: Bool, octave: Bool, long: Bool) {
        // 触觉永远先发，且在任何状态下都是完整通道。音高由敲击疏密编码，
        // 回想自动走更疏更淡的节奏；勿扰态静默跳过，不弹窗。
        HapticScore.play(degree: degree, echo: echo, mode: outputMode)

        // 声音只是可选的一层：默认关闭，用户显式打开且当前态允许才合成。
        // 静音模式并不保证挡住 App 的媒体音频，所以必须由 App 自己关掉。
        if outputMode.soundOn && soundEnabled {
            let pan: Float = preset.spatialAudio && size.width > 0
                ? Float((point.x / size.width - 0.5) * 1.6) : 0
            let far = 1 - min(1, max(0, Double(point.y / max(1, size.height))))
            tone.render(preset: preset, degree: degree,
                        softening: Double(chain) * 0.13 + far * 0.22,
                        pan: pan, echo: echo, octave: octave, long: long)
            tone.play()
        }

        // 音高同一个数，同时决定水波的长短与快慢：低音长而缓，高音短而快
        let tonePos = min(1.0, Double(degree + (long ? 5 : 0)) / 9.0)
        waveID += 1
        waves.append(WaveFieldSource(
            id: waveID, x: point.x, y: point.y, degree: degree,
            strength: strength, birth: Date(), echo: echo,
            wavelength: preset.waveWavelength * CGFloat(1 + (1 - tonePos) * 0.55)
                        * (echo ? 1.18 : 1) * (long ? 1.35 : 1),
            speed: preset.waveSpeed * CGFloat(0.78 + tonePos * 0.5)
                   * (echo ? 0.62 : 1) * (long ? 0.58 : 1),
            life: 1.5 + preset.audioDecay * 0.7
        ))
        if waves.count > 8 { waves.removeFirst() }

        pulse += 1
        withAnimation(.easeOut(duration: preset.easeOut * 0.3)) { scale = echo ? 1.02 : 1.04 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(preset.easeOut * 0.3 * 1_000_000_000))
            withAnimation(.easeOut(duration: preset.easeOut)) { scale = 1 }
        }
    }

    private func scheduleEcho(size: CGSize) {
        let delay = preset.echoDelay + 0.8
        echoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard !echoDone, phrase.count >= 2,
                  Date().timeIntervalSince(lastTap) >= preset.echoDelay else { return }
            await playEcho(size: size)
        }
    }

    private func playEcho(size: CGSize) async {
        echoing = true
        hint = "水在回想"
        let snapshot = phrase
        let t0 = snapshot.first?.at ?? Date()
        var previous = 0.0
        for n in snapshot {
            if Task.isCancelled { echoing = false; return }
            let target = n.at.timeIntervalSince(t0) * 1.18
            let delta = target - previous
            if delta > 0 { try? await Task.sleep(nanoseconds: UInt64(delta * 1_000_000_000)) }
            previous = target
            // 回想时中央墨符也跟着那一句依次变化
            degree = n.degree
            emit(point: CGPoint(x: n.x, y: n.y), size: size, degree: n.degree,
                 strength: n.strength * 0.45, echo: true, octave: false, long: false)
        }
        try? await Task.sleep(nanoseconds: 1_700_000_000)
        guard !Task.isCancelled else { echoing = false; return }
        echoing = false; echoDone = true; phrase = []
        hint = "归于静"
    }

    func crownTick() {
        let now = Date()
        guard now.timeIntervalSince(lastTap) >= max(0.12, preset.minInterval) else { return }
        lastTap = now
        lastTapAt = now
        WKInterfaceDevice.current().play(.click)
    }
}

// MARK: - 连续波场：一组横向高度切片，没有一根描边的圆

/// 小数部分，供程序化雨点的哈希相位使用
func fract(_ x: Double) -> Double { x - floor(x) }

struct WaterField: View {
    let waves: [WaveFieldSource]
    let lines: Int
    let backdrop: Backdrop
    let ambient: Double
    let lastTap: Date
    let duckOn: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let t: Double = now.timeIntervalSinceReferenceDate
                // 点击后 1.2 秒内环境层主动压低，再慢慢回来
                let sinceTap: Double = now.timeIntervalSince(lastTap)
                let duck: Double = duckOn ? max(0, exp(-sinceTap / 0.55)) : 0
                let e: Double = ambient * (1 - duck * 0.62)
                let live: CGFloat = CGFloat(0.55 + e * 0.45)
                let cols = 30

                // 环境层 ①：极缓漂移的雾光，无起点、无边界、无离散事件
                let driftX: Double = 10 + e * 22
                let driftY: Double = 8 + e * 16
                let fx: CGFloat = size.width * 0.5 + CGFloat(sin(t * 0.11)) * CGFloat(driftX)
                let fy: CGFloat = size.height * 0.45 + CGFloat(cos(t * 0.085)) * CGFloat(driftY)
                let fogR: CGFloat = min(size.width, size.height) * 0.75
                let fogA: Double = backdrop.isPaper ? 0.012 : 0.045 * e
                let fog = GraphicsContext.Shading.radialGradient(
                    Gradient(colors: [backdrop.light.opacity(fogA), Color.clear]),
                    center: CGPoint(x: fx, y: fy), startRadius: 0, endRadius: fogR)
                context.fill(Path(ellipseIn: CGRect(x: fx - fogR, y: fy - fogR,
                                                    width: fogR * 2, height: fogR * 2)), with: fog)

                // 环境层 ②：月光——设计稿里画面中央那团柔和的光，随呼吸明灭
                let moonR: CGFloat = min(size.width, size.height) * 0.52
                let moonA: Double = backdrop.isPaper ? 0.02 : 0.11 * (0.55 + e * 0.45) * (1 - duck * 0.30)
                let moon = GraphicsContext.Shading.radialGradient(
                    Gradient(colors: [backdrop.light.opacity(moonA), Color.clear]),
                    center: CGPoint(x: fx, y: fy * 0.92), startRadius: 0, endRadius: moonR)
                context.fill(Path(ellipseIn: CGRect(x: fx - moonR, y: fy * 0.92 - moonR,
                                                    width: moonR * 2, height: moonR * 2)), with: moon)

                // 雨夜 · 夜雨落池（与 soft-tap.html 同一语言）：
                // 天也在叩水——雨点敲在暗夜水面绽开小涟漪，灯光倒影拉成竖直光带。
                if backdrop == .yuyue {
                    Self.drawRainNight(context: context, size: size,
                                        t: t, e: e, duck: duck, fx: fx, fy: fy)
                }

                // 水流肌理：与设计稿一致，横线只是几乎看不见的底纹（alpha≈0.02–0.03）
                for i in 0..<lines {
                    let baseY = size.height * CGFloat(i + 1) / CGFloat(lines + 1)
                    var path = Path()
                    for s in 0...cols {
                        let x = size.width * CGFloat(s) / CGFloat(cols)
                        // 整片水一直在极缓地流，让位时收敛
                        var y = baseY + CGFloat(sin(Double(x) * 0.012 + t * 0.24
                                                    + Double(i) * 0.7)) * 3.4 * live
                        for w in waves {
                            let age = now.timeIntervalSince(w.birth)
                            guard age > 0, age < w.life else { continue }
                            let dx = x - w.x, dy = baseY - w.y
                            let r = sqrt(dx * dx + dy * dy)
                            let front = CGFloat(age) * w.speed
                            let band = (r - front) / (42 + w.wavelength * 3)
                            let env = exp(-band * band * 1.6)
                                    * pow(1 - age / w.life, 1.5) * w.strength
                            y += sin((r - front) * 6.283 / w.wavelength) * CGFloat(env) * 8
                        }
                        let pt = CGPoint(x: x, y: y)
                        if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    let lineA: Double = 0.020 * Double(live) + 0.010
                    context.stroke(path, with: .color(backdrop.ink.opacity(lineA)),
                                   lineWidth: 0.6)
                }
                // 叩击涟漪：扩散的亮环（主环 + 后随环）+ 落点光晕——设计稿的主角语言
                let pxs: Double = Double(size.width) / 390
                for w in waves {
                    let age = now.timeIntervalSince(w.birth)
                    guard age > 0, age < w.life else { continue }
                    let q = age / w.life
                    let fade: Double = pow(1 - q, 1.5) * Double(w.strength)
                    let ringColor = backdrop.light.opacity(0.16 * fade * (0.5 + e * 0.5))
                    // 主环：波前所在处
                    let r1: CGFloat = CGFloat(age) * w.speed
                    if r1 > 2 {
                        let rect1 = CGRect(x: w.x - r1, y: w.y - r1, width: r1 * 2, height: r1 * 2)
                        context.stroke(Path(ellipseIn: rect1), with: .color(ringColor),
                                       lineWidth: 1.2)
                    }
                    // 后随环：落后一个波长，更淡
                    let r2: CGFloat = CGFloat(age) * w.speed - w.wavelength
                    if r2 > 2 {
                        let rect2 = CGRect(x: w.x - r2, y: w.y - r2, width: r2 * 2, height: r2 * 2)
                        context.stroke(Path(ellipseIn: rect2),
                                       with: .color(backdrop.light.opacity(0.09 * fade)),
                                       lineWidth: 1)
                    }
                    // 落点光晕：缓缓扩散后熄灭（设计稿 2D 同参数：rr = 26 + age*60）
                    let rr: CGFloat = CGFloat(26 + age * 60) * CGFloat(pxs)
                    let glow = GraphicsContext.Shading.radialGradient(
                        Gradient(colors: [backdrop.light.opacity(0.09 * (1 - q) * Double(w.strength)),
                                          Color.clear]),
                        center: CGPoint(x: w.x, y: w.y), startRadius: 0, endRadius: rr)
                    context.fill(Path(ellipseIn: CGRect(x: w.x - rr, y: w.y - rr,
                                                        width: rr * 2, height: rr * 2)), with: glow)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 雨夜专属环境层：灯光倒影竖直光带 + 稀落雨丝 + 雨点落水的小涟漪。
    /// 参数全部由调用处的 Canvas 环境算好传入，方法内不再碰闭包捕获。
    private static func drawRainNight(context: GraphicsContext, size: CGSize,
                                      t: Double, e: Double, duck: Double,
                                      fx: CGFloat, fy: CGFloat) {
        let pxs: Double = Double(size.width) / 390
        let light = Backdrop.yuyue.light
        let ink = Backdrop.yuyue.ink

        // 灯的倒影：在雾光处拉成竖直光带，随水纹轻轻颤动。
        // GraphicsContext 是值类型：画在变换过的副本上，底层画布相同，原 context 不受影响。
        let shimmer: Double = 0.66 + 0.34 * sin(t * 1.1)
        let bandA: Double = 0.10 * shimmer * (1 - duck * 0.22)
        let bandR: CGFloat = min(size.width, size.height) * 0.30
        var ctx = context
        ctx.translateBy(x: fx, y: fy + size.height * 0.06)
        ctx.scaleBy(x: 1, y: 3.2)
        let band = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [light.opacity(bandA), Color.clear]),
            center: .zero, startRadius: 0, endRadius: bandR)
        let bandRect = CGRect(x: -bandR, y: -bandR, width: bandR * 2, height: bandR * 2)
        ctx.fill(Path(ellipseIn: bandRect), with: band)

        // 稀落的雨丝：极淡的竖直短划
        let streakA: Double = 0.030 + 0.020 * e
        let streakColor = ink.opacity(streakA)
        for i in 0..<7 {
            let rxF: Double = fract(0.13 + Double(i) * 0.213)
            let rx: CGFloat = size.width * CGFloat(rxF)
            let sp: Double = 520 + Double((i * 7) % 10) * 30
            let span: Double = Double(size.height) + 300
            let yF: Double = fract((t * sp + Double(i) * 231) / span)
            let y0: CGFloat = CGFloat(yF * span - 150)
            var streak = Path()
            streak.move(to: CGPoint(x: rx, y: y0))
            streak.addLine(to: CGPoint(x: rx, y: y0 + CGFloat(34 * pxs)))
            context.stroke(streak, with: .color(streakColor), lineWidth: 1)
        }

        // 雨点落水：约 1.4 秒一滴，落点绽开小涟漪（与叩击同一语言，更小更淡）
        let Pr: Double = 1.4
        let slot0: Double = floor(t / Pr)
        for j in 0..<5 {
            let s1: Double = slot0 - Double(j)
            let sdx: Double = fract(s1 * 0.6180339887 + 0.13)
            let sdy: Double = fract(s1 * 0.3819660113 + 0.31)
            let t0: Double = (s1 + 0.15 + sdy * 0.7) * Pr
            let age: Double = t - t0
            guard age > 0, age < 2.2 else { continue }
            let rp = CGPoint(x: CGFloat(sdx) * size.width,
                             y: CGFloat(0.12 + sdy * 0.76) * size.height)
            let rr: CGFloat = CGFloat(age * 90 * pxs)
            let amp: Double = exp(-age * 2.0) * (1 - Double(j) * 0.15)
            let ringA: Double = 0.10 * amp * (0.4 + e * 0.6)
            let ringRect = CGRect(x: rp.x - rr, y: rp.y - rr, width: rr * 2, height: rr * 2)
            context.stroke(Path(ellipseIn: ringRect),
                           with: .color(ink.opacity(ringA)), lineWidth: 1)
            if age < 0.3 {   // 落点初绽的微光
                let gr: CGFloat = CGFloat(8 * pxs)
                let glowA: Double = 0.6 * (0.3 - age) * (0.4 + e * 0.6)
                let glow = GraphicsContext.Shading.radialGradient(
                    Gradient(colors: [ink.opacity(glowA), Color.clear]),
                    center: rp, startRadius: 0, endRadius: gr)
                let glowRect = CGRect(x: rp.x - gr, y: rp.y - gr, width: gr * 2, height: gr * 2)
                context.fill(Path(ellipseIn: glowRect), with: glow)
            }
        }
    }
}


// MARK: - 界面：位置即乐器

struct SoftTapView: View {
    @StateObject private var engine = SoftTapEngine()

    var body: some View {
        GeometryReader { geo in
            let bd = engine.preset.backdrop
            let fg: Color = bd.isPaper
                ? Color(red: 0.18, green: 0.22, blue: 0.18)
                : Color(red: 0.84, green: 0.89, blue: 0.86)
            ZStack {
                bd.base.ignoresSafeArea()
                WaterField(waves: engine.waves, lines: engine.preset.fieldLines,
                           backdrop: bd, ambient: engine.preset.ambientMotion,
                           lastTap: engine.lastTapAt, duckOn: engine.preset.duckOnTap)
                VStack(spacing: 3) {
                    Text(engine.hint)
                        .font(.system(size: 10))
                        .foregroundStyle(fg.opacity(0.55))
                    MelodyTraceView(trace: engine.melodyTrace, tint: fg)
                    if engine.preset.glyphStyle == .wuxing {
                        WuxingGlyph(index: engine.degree % 5, high: engine.degree >= 5, tint: fg)
                    } else {
                        Text(engine.noteName)
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(fg)
                    }
                    Text(engine.noteName + " · " + wuxingNames[engine.degree % 5])
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(fg.opacity(0.5))
                    NoteBarsView(counts: engine.noteCounts, tint: fg)
                }
                .scaleEffect(engine.scale)

                VStack {
                    // 总敲击次数跟着「叩音」标题，与网页一致：只统计主动落指
                    // 末尾标出当前输出态（静 / 熄屏 / 有声），让用户知道声音为什么没响
                    Text("\(appName) · \(engine.count) · \(engine.outputMode.label)")
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(fg.opacity(0.36))
                        .monospacedDigit()
                        .padding(.top, 2)
                    HStack(spacing: 6) {
                        // 与网页右下角「调 · 心境」同一模式：标签 + 当前值，点击循环切换
                        Button("调 " + engine.preset.mood.profile.name) {
                            let all = Mood.allCases
                            let i = all.firstIndex(of: engine.preset.mood) ?? 0
                            engine.setMood(all[(i + 1) % all.count])
                        }
                        Spacer()
                        Button("景 " + bd.name) {
                            let all = Backdrop.allCases
                            let i = all.firstIndex(of: bd) ?? 0
                            engine.setBackdrop(all[(i + 1) % all.count])
                        }
                    }
                    .font(.system(size: 9))
                    .buttonStyle(.plain)
                    .foregroundStyle(fg.opacity(0.45))
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    // 真机上这两个入口建议移到 iPhone 端设置页，表上只留当前值
                    Spacer()
                    Button("轻触") {
                        engine.tap(at: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2), in: geo.size)
                    }
                    .handGestureShortcut(.primaryAction)
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(fg.opacity(0.7))
                    .padding(.bottom, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // 一个手势同时拿到落点与按住时长，避免与互点手势冲突
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if engine.pressStart == nil { engine.pressStart = Date() } }
                    .onEnded { value in
                        let held = Date().timeIntervalSince(engine.pressStart ?? Date())
                        engine.pressStart = nil
                        engine.tap(at: value.location, in: geo.size)
                        if held > 0.45 { engine.hold(at: value.location, in: geo.size) }
                    }
            )
            .onAppear {
                // 预览钩子：`-demo` 启动参数自动落两叩，供模拟器截图验证涟漪观感
                if ProcessInfo.processInfo.arguments.contains("-demo") {
                    let c = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.42)
                    engine.tap(at: c, in: geo.size)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        engine.tap(at: CGPoint(x: c.x * 0.72, y: c.y * 1.18), in: geo.size)
                    }
                }
            }
        }
        .focusable()
        .onAppear {
            engine.refreshOutput(screenOn: true)
        }
        // 真机应在 WKApplicationDelegate 的 didBecomeActive / willResignActive
        // 里再调 refreshOutput(screenOn:)，让熄屏态切到 .wristDown
        .digitalCrownRotation($engine.crownValue, from: 0, through: 3, by: 1, sensitivity: .low)
        .onChange(of: engine.crownValue) { _, _ in engine.crownTick() }
    }
}

// MARK: - 熄屏继续
//
// 已经落在 HapticScore.swift 的 WristSession 里。Watch target 的
// WKBackgroundModes **只勾 mindfulness**（不要勾 background audio）：
// Apple 明确写着，全程播音频的练习才用 background audio；不发声的练习用
// extended runtime，它同样能在熄屏后播触觉，且审核语义贴合正念练习。
// 每个 App 只能声明一种 extended runtime 类型。
//
// 审核备注建议写明：「30–60 秒的正念 / 自我关怀练习，放下手腕后仍需播放
// 触觉节奏，不用于常驻后台」——避免被判滥用后台模式。
//
// WaterField 已把 TimelineView 限到 24fps；若实测仍耗电，可在 waves 全部
// 过期后暂停时间线（只保留极慢的雾光），抬腕或下次敲击再恢复。

@main
struct SoftTapApp: App {
    var body: some Scene {
        WindowGroup { SoftTapView() }
    }
}
