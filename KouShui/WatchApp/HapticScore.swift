//
//  HapticScore.swift
//  叩音 · Stillwave — 腕上「不能出声」时的完整策略层
//
//  这个文件回答一个问题：Apple Watch 在静音 / 熄屏 / 没戴耳机时，App 怎么办？
//  结论：**不提示戴耳机**。声音是可选的一层，触觉乐谱才是骨架。
//
//  ── 已核实的系统事实（决定架构，不要凭直觉改） ──────────────────────────
//  1. Apple 官方：静音模式 / 剧院模式下「声音关闭、触觉开启（若允许）」；
//     只有勿扰 / 专注才把声音与触觉一起关掉。
//  2. 静音模式只静音提示音与系统音效，**不保证挡住 App 用 .playback 播的媒体音频**。
//     所以「系统静音了，我尽管播」是错的 —— 开会时可能突然外放。由 App 自己关。
//  3. watchOS 没有公开 API 能可靠读取静音开关 / 勿扰状态。因此**不做检测、不做判断、不弹窗**，
//     改成「默认静音优先」：soundEnabled 默认 false，用户显式打开才发声。
//  4. Apple《Using extended runtime sessions》明确写着：若整个练习都在播音频，
//     就用 background audio mode，没必要用 WKExtendedRuntimeSession；
//     **不发声的练习才用 WKExtendedRuntimeSession(.mindfulness)**，
//     它能在熄屏后继续播触觉（frontmost 类型，1 小时上限）。
//     本 App 默认不发声 → 走 mindfulness，审核语义也贴合。
//
//  ── 触觉只有 9 个语义预设，没有 Core Haptics / 没有强度 / 没有自定义波形 ──
//  所以「曲调」不能靠波形，只能靠**节奏**：每个音 1–2 下最轻的 .click，
//  音越高两下靠得越近（108→234ms），一句旋律于是变成腕上可摸到的疏密。
//  回想时更疏、更淡，把刚才那句轻轻敲回来。
//
//  ⚠️ 合规：文案只写「片刻安静 / 放松 / 专注呼吸」，绝不写治疗焦虑、改善睡眠、
//     降低血压、调理五脏或任何疗效宣称。第一版建议完全不接 HealthKit。
//

import Foundation
import WatchKit
import AVFoundation

// MARK: - 四种输出状态

enum OutputMode: String, CaseIterable, Identifiable {
    /// 有外部音频输出，且用户显式打开了声音
    case full
    /// 默认态：主动静音，屏幕可见（开会、通勤）
    case silent
    /// 熄屏 / 腕放下，触觉是唯一通道
    case wristDown
    /// 勿扰 / 专注：系统连触觉一起关，App 不绕过、不弹窗
    case focus

    var id: String { rawValue }
    var soundOn: Bool { self == .full }
    var screenOn: Bool { self == .full || self == .silent }
    var hapticsOn: Bool { self != .focus }

    var label: String {
        switch self {
        case .full: return "有声"
        case .silent: return "静音"
        case .wristDown: return "熄屏"
        case .focus: return "勿扰"
        }
    }
}

// MARK: - 触觉乐谱：音高 → 敲击密度

struct HapticBeat {
    let type: WKHapticType
    /// 相对本音起点的秒数；系统要求两次触觉至少约 100ms，这里最小 108ms
    let delay: TimeInterval
}

enum HapticScore {

    /// 一次「音」的敲击包。只用 .click —— 避开 .notification / .success / .failure
    /// 这些又重又带语义的预设，也避开 .directionUp/Down 的导航感。
    static func beats(degree: Int, echo: Bool = false) -> [HapticBeat] {
        let d = min(9, max(0, degree))
        // 高音密、低音疏：跨感官把「频率」翻译成「敲击间距」
        let gapMS = (echo ? 150.0 : 108.0) + Double(9 - d) * (echo ? 20.0 : 14.0)
        var out: [HapticBeat] = [HapticBeat(type: .click, delay: 0)]
        if (!echo && d >= 4) || (echo && d >= 7) {
            out.append(HapticBeat(type: .click, delay: gapMS / 1000.0))
        }
        return out
    }

    /// 异步播放，不阻塞 UI。勿扰态直接静默跳过 —— 不弹「请关闭勿扰」。
    static func play(degree: Int, echo: Bool = false, mode: OutputMode) {
        guard mode.hapticsOn else { return }
        let beats = beats(degree: degree, echo: echo)
        Task { @MainActor in
            for beat in beats {
                if beat.delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(beat.delay * 1_000_000_000))
                }
                WKInterfaceDevice.current().play(beat.type)
            }
        }
    }

    /// 回想：按原句节奏，把每个音以更疏更淡的节奏敲回来。
    /// 由 Engine 的 echo Task 调用，不要重复计数、不要再触发一次落指。
    static func replay(phrase: [(degree: Int, at: TimeInterval)], mode: OutputMode) {
        guard mode.hapticsOn, phrase.count >= 2 else { return }
        let t0 = phrase[0].at
        for note in phrase {
            let delay = (note.at - t0) * 1.18
            Task { @MainActor in
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                play(degree: note.degree, echo: true, mode: mode)
            }
        }
    }
}

// MARK: - 音频策略：不读静音开关，默认静音优先

enum AudioPolicy {

    /// 是否接着耳机 / 蓝牙 / AirPlay。仅用于「要不要给一句增益提示」，
    /// **不用于决定体验是否成立**。腕上永不因这个结果弹窗。
    static var hasExternalOutput: Bool {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outs.contains { port in
            switch port.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .airPlay:
                return true
            default:
                return false
            }
        }
    }

    /// 唯一的决策入口。注意：系统静音 / 勿扰没有公开 API 可读，
    /// 所以这里不做「检测」——只看用户显式开关与屏幕状态。
    /// - soundEnabled: 默认 false（静音优先），只在 iOS 端设置页可打开
    /// - screenOn: 由 WKExtensionDelegate / scenePhase 提供
    /// - userMarkedFocus: 用户自己在设置里标注「我现在开着勿扰」；不自动推断
    static func resolve(soundEnabled: Bool, screenOn: Bool,
                        userMarkedFocus: Bool = false) -> OutputMode {
        if userMarkedFocus { return .focus }
        if !screenOn { return .wristDown }
        return soundEnabled && hasExternalOutput ? .full : .silent
    }

    /// 用户开了声音但没接外部输出时：**不禁用、不弹窗**，
    /// 只收窄音量与混响（交给 SoftTone），触觉乐谱照常。
    /// 耳机提示只出现在 iPhone 端设置页：「戴上耳机，回响会更远」——增益语气。
    static var headphoneHint: String {
        "戴上耳机，回响会更远、更有空间感。不戴也完整：曲调在腕上。"
    }
}

// MARK: - 熄屏后仍可播触觉：mindfulness extended runtime

/// 生命周期要点（Apple 文档）：
/// - 只能在 app 处于 .active 时 start()
/// - 每个 App 只能声明一种 session 类型；Info.plist 里 WKBackgroundModes: mindfulness
/// - frontmost 类型上限 1 小时，系统可因温度 / 电量提前结束
/// - delegate 必须挂在 **app 作用域**（不能是 View 里的 @StateObject），
///   否则页面切换把 delegate 释放掉，session 会静默失效
/// - 审核备注写明：这是 30–60 秒的正念 / 自我关怀练习，不是借后台模式常驻
final class WristSession: NSObject, WKExtendedRuntimeSessionDelegate {

    static let shared = WristSession()
    private var session: WKExtendedRuntimeSession?

    func start() {
        guard session == nil else { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()                       // 必须在 app active 时调用
        session = s
    }

    func stop() {
        session?.invalidate()
        session = nil
    }

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        // 屏幕熄灭后，HapticScore 仍然可用；这里不要启动任何音频会话
    }

    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        // 收尾：把还在排队的回想 Task 取消，避免会话结束后继续敲
        stop()
    }

    func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        self.session = nil
    }
}
