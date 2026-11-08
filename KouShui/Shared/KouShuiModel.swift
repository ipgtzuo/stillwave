//
//  KouShuiModel.swift
//  叩音 · Stillwave — iOS / watchOS 共享模型
//
//  品牌名、三分损益律、四种心境、五套景、可调参数、加权旋律游走。
//  两个 target 都必须勾选此文件；再改产品名要同时改 appName / appDisplayName、
//  两个 Info.plist 的 CFBundleDisplayName、metadata.json 与 ASC 名称。
//
import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// 产品名：与网页 APP_NAME 保持一致，只改这一行
let appName = "叩音"
/// 顶部大字用的带字距版本
let appDisplayName = "叩 音"

/// 触点浮起的是五行墨符，还是音名文字
enum GlyphSet: Equatable { case wuxing, noteNames }

// MARK: - 心境：一整套旋律生成规则（与网页 MOODS 一一对应）

struct MoodProfile {
    let name: String
    let wander: Double, bias: Double, anchor: Double, span: Double
    let lenMin: Int, lenMax: Int
    let arch: Double, drift: Double, ripple: Double
    let link: Double, endPull: Double, homePull: Double, octave: Double
}

enum Mood: String, CaseIterable, Identifiable {
    case chengming, youyuan, qingyang, yousi
    var id: String { rawValue }

    var profile: MoodProfile {
        switch self {
        case .chengming:  // 级进为主，中音区，句句收得住
            return MoodProfile(name: "澄明", wander: 0.28, bias: 0.00,
                anchor: 5.0, span: 2.0, lenMin: 5, lenMax: 7,
                arch: 0.55, drift: 0.30, ripple: 0.15,
                link: 0.35, endPull: 1.25, homePull: 0.55, octave: 0.18)
        case .youyuan:    // 长句单向，音区开阔
            return MoodProfile(name: "悠远", wander: 0.56, bias: -0.15,
                anchor: 5.2, span: 3.4, lenMin: 7, lenMax: 9,
                arch: 0.15, drift: 0.62, ripple: 0.23,
                link: 0.28, endPull: 0.85, homePull: 0.35, octave: 0.30)
        case .qingyang:   // 上行短句，明亮，偶尔小跳
            return MoodProfile(name: "轻扬", wander: 0.46, bias: 0.62,
                anchor: 6.0, span: 2.5, lenMin: 4, lenMax: 6,
                arch: 0.35, drift: 0.45, ripple: 0.20,
                link: 0.30, endPull: 1.00, homePull: 0.60, octave: 0.48)
        case .yousi:      // 下行低回，浅波起伏，落宫收尾
            return MoodProfile(name: "幽思", wander: 0.22, bias: -0.60,
                anchor: 4.0, span: 2.2, lenMin: 6, lenMax: 8,
                arch: 0.20, drift: 0.30, ripple: 0.50,
                link: 0.42, endPull: 1.55, homePull: 0.70, octave: 0.10)
        }
    }
}

// MARK: - 景：色板与池底纹理

enum Backdrop: String, CaseIterable, Identifiable {
    case mochi, xingtan, xuanzhi, yuyue, songwu
    var id: String { rawValue }

    var name: String {
        switch self {
        case .mochi: return "墨池"
        case .xingtan: return "星潭"
        case .xuanzhi: return "宣纸"
        case .yuyue: return "雨夜"
        case .songwu: return "松雾"
        }
    }
    var isPaper: Bool { self == .xuanzhi }
    var base: Color {
        switch self {
        case .mochi: return Color(red: 0.020, green: 0.027, blue: 0.035)
        case .xingtan: return Color(red: 0.016, green: 0.024, blue: 0.055)
        case .xuanzhi: return Color(red: 0.86, green: 0.85, blue: 0.80)
        case .yuyue: return Color(red: 0.020, green: 0.047, blue: 0.055)
        case .songwu: return Color(red: 0.039, green: 0.055, blue: 0.043)
        }
    }
    var ink: Color {
        switch self {
        case .mochi: return Color(red: 0.55, green: 0.72, blue: 0.68)
        case .xingtan: return Color(red: 0.42, green: 0.56, blue: 0.88)
        case .xuanzhi: return Color(red: 0.27, green: 0.31, blue: 0.27)
        case .yuyue: return Color(red: 0.40, green: 0.66, blue: 0.68)
        case .songwu: return Color(red: 0.56, green: 0.66, blue: 0.48)
        }
    }
    var light: Color {
        switch self {
        case .mochi: return Color(red: 0.36, green: 0.52, blue: 0.47)
        case .xingtan: return Color(red: 0.34, green: 0.42, blue: 0.72)
        case .xuanzhi: return Color(red: 0.30, green: 0.33, blue: 0.29)
        case .yuyue: return Color(red: 0.30, green: 0.50, blue: 0.52)
        case .songwu: return Color(red: 0.50, green: 0.54, blue: 0.40)
        }
    }
}

// MARK: - 可调参数（与网页导出字段一致）

struct SoftTapPreset {
    #if os(watchOS)
    var haptic: WKHapticType = .click
    #endif
    /// 两次落指的最小间隔。系统要求两次触觉至少约 100ms，这里取 0.12：
    /// 既守住触觉不被系统吞掉的下限，又保证「每次点击都有震感」——
    /// 旧值 0.22 会把快速连敲直接静默丢弃，正是「有的敲没感觉」的成因。
    var minInterval: TimeInterval = 0.12
    var rootHz: Double = 140
    /// 三分损益律，degree 0...9：两个八度的宫商角徵羽
    var pentatonic: [Double] = [1, 1.125, 1.265625, 1.5, 1.6875, 2, 2.25, 2.53125, 3, 3.375]
    /// 0 = 规整（几乎全级进），1 = 自由（更多跳进）
    var melodyWander: Double = 0.28
    /// 心境走向：>0 偏上行明亮，<0 偏下行低回
    var melodyBias: Double = 0.00
    var melodyAnchor: Double = 5.0
    var melodySpan: Double = 2.0
    var phraseMin: Int = 5
    var phraseMax: Int = 7
    /// 心境给轮廓/顶针/收束，网页导出的标量覆盖音区与漫游
    var mood: Mood = .chengming
    /// 预览/调试钩子：启动参数 `-backdrop yuyue` 可直接指定初始景；
    /// 正常安装包不带该参数，仍走默认墨池。
    var backdrop: Backdrop = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-backdrop"), i + 1 < args.count,
              let bd = Backdrop(rawValue: args[i + 1]) else { return .mochi }
        return bd
    }()
    /// 背景持续动画强度：0 静 → 1 活
    var ambientMotion: Double = 0.55
    /// 点击瞬间背景主动让位，避免与点击反馈抢注意力
    var duckOnTap: Bool = true
    var glyphStyle: GlyphSet = .wuxing
    var audioDecay: Double = 2.90
    var lowpassHz: Double = 1700
    var reverbMix: Double = 0.78
    var gain: Double = 0.72
    var jitter: Double = 0.02
    var easeOut: Double = 1.50
    var waveWavelength: CGFloat = 46
    var waveSpeed: CGFloat = 118
    var fieldLines: Int = 22
    var echoDelay: TimeInterval = 3.2
    var spatialAudio: Bool = true
    var octaveOnHold: Bool = true
}

let noteNames = ["宫", "商", "角", "徵", "羽"]
let wuxingNames = ["土", "金", "木", "火", "水"]

extension SoftTapPreset {
    /// 网页导出的标量覆盖心境预设的对应项，其余（轮廓/顶针/收束）由心境给
    var resolvedMood: MoodProfile {
        let m = mood.profile
        return MoodProfile(name: m.name, wander: melodyWander, bias: melodyBias,
                           anchor: melodyAnchor, span: melodySpan,
                           lenMin: phraseMin, lenMax: phraseMax,
                           arch: m.arch, drift: m.drift, ripple: m.ripple,
                           link: m.link, endPull: m.endPull,
                           homePull: m.homePull, octave: m.octave)
    }
}

// MARK: - 有曲调的随机：加权旋律游走

struct MelodyWalk {
    /// 同一套随机规则，心境不同则性格不同
    var profile: MoodProfile = Mood.chengming.profile

    private var degree = 5
    private var pos = 0
    private var len = 6
    private var contour: [Double] = []
    private var lastStep = 0
    private var repeatRun = 0
    private var lastEnd = 5

    /// 切换心境或长时间停顿时另起一句
    mutating func reset() { pos = len }

    private mutating func newPhrase() {
        // 顶针：偶尔接着上一句末音起句；高八度起句概率随心境
        let high = Double.random(in: 0..<1) < profile.octave
        degree = Double.random(in: 0..<1) < profile.link
            ? lastEnd : (high ? Int.random(in: 5...7) : Int.random(in: 2...5))
        len = Int.random(in: profile.lenMin...profile.lenMax)
        pos = 0
        lastStep = 0
        repeatRun = 0
        let dir = Bool.random() ? 1.0 : -1.0
        let total = profile.arch + profile.drift + profile.ripple
        let kind = Double.random(in: 0..<total)
        contour = (0..<len).map { i in
            let u = Double(i) / Double(len - 1)
            if kind < profile.arch { return sin(u * .pi) * dir }                    // 拱形
            if kind < profile.arch + profile.drift { return (1 - 2 * u) * dir }    // 单向
            return 0.35 * sin(u * .pi * 1.5) * dir                                 // 浅波
        }
    }

    mutating func next() -> Int {
        if pos == 0 || pos >= len {
            if pos >= len { lastEnd = degree }
            newPhrase()
        }
        let anchor = profile.anchor
        let target = anchor + contour[pos] * profile.span + profile.bias * 1.2
        let steps = [-3, -2, -1, 0, 1, 2, 3]
        var weights: [Double] = []
        for s in steps {
            let nx = degree + s
            if nx < 0 || nx > 9 { weights.append(0); continue }
            let a = abs(s)
            var w: Double = a == 0 ? 0.14
                : a == 1 ? 1.0
                : a == 2 ? (0.18 + profile.wander * 0.30)
                : (0.02 + profile.wander * 0.12)
            // 朝这一句的轮廓走
            if s != 0 && (target - Double(nx)) * Double(s) > 0 { w *= 1.55 }
            if pos == len - 1 {
                // 句尾落在宫或徵，收束强度随心境
                let pc = nx % 5
                w *= pc == 0 ? 2.6 * profile.endPull : pc == 3 ? 1.8 * profile.endPull : 0.28
                if abs(Double(nx) - anchor) > 3 { w *= 0.25 }
            } else if abs(Double(nx) - anchor) > abs(Double(degree) - anchor)
                        && abs(Double(degree) - anchor) >= 2 {
                w *= profile.homePull  // 离家太远就往回收
            }
            if a >= 2 && abs(lastStep) >= 2 { w *= 0.18 }  // 不连续大跳
            if s == 0 { w *= repeatRun > 0 ? 0.15 : 0.5 } // 不连续重复
            weights.append(w)
        }
        let total = weights.reduce(0, +)
        var step = Double(degree) > anchor ? -1 : 1
        if total > 0 {
            var r = Double.random(in: 0..<total)
            for (i, w) in weights.enumerated() {
                r -= w
                if r <= 0 { step = steps[i]; break }
            }
        }
        degree = min(9, max(0, degree + step))
        lastStep = step
        repeatRun = step == 0 ? repeatRun + 1 : 0
        pos += 1
        lastEnd = degree
        return degree
    }
}
