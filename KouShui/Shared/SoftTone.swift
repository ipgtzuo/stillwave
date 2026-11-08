//
//  SoftTone.swift — iOS / watchOS 共享：不依赖音频资源文件、不依赖音频节点的五音合成
//
//  真编译验证过的一点：AVAudioUnitDelay 在 watchOS 上不可用，
//  所以「空灵的余韵」改成在生成的 PCM 里离线叠多抽头混响，
//  两端跑的是同一份代码，也不需要打包任何 wav 资源。
//
import Foundation
import AVFoundation

// MARK: - 五音合成

final class SoftTone {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var pan: Float = 0

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        try? engine.start()
    }

    func render(preset: SoftTapPreset, degree: Int, softening: Double,
                pan: Float, echo: Bool, octave: Bool, long: Bool) {
        self.pan = pan
        let sr = 44100.0
        let jit = 1.0 + Double.random(in: -preset.jitter...preset.jitter)
        let decay = preset.audioDecay * (long ? 1.8 : 1) * jit
        let frames = AVAudioFrameCount(sr * (decay + 0.25))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buf.floatChannelData?[0] else { return }
        buf.frameLength = frames

        let d = min(9, max(0, degree))
        let f0 = preset.rootHz * preset.pentatonic[d] * (octave ? 2 : 1) * jit
        let peak = 0.20 * preset.gain * max(0.46, 1 - softening) * (echo ? 0.34 : 1)
        let alpha = 1 - exp(-2 * .pi * preset.lowpassHz * (echo ? 0.72 : 1) / sr)
        let attack = 0.04
        var phase = 0.0
        var filtered = 0.0

        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let f = f0 * (1 - 0.004 * min(1, t / decay))
            phase += 2 * .pi * f / sr
            let env: Double
            if t < attack { env = t / attack }
            else { env = exp(-3.0 * (t - attack) / max(0.01, decay - attack)) }
            var s = sin(phase) + 0.55 * sin(1.0026 * phase)   // 两条略失谐的基频，缓慢拍频
            s += 0.26 * sin(2 * phase) * exp(-t / (decay * 0.62))
            s += 0.09 * sin(3 * phase) * exp(-t / (decay * 0.40))
            if t > 0.11 { s += 0.10 * sin(4 * phase) * exp(-(t - 0.11) / (decay * 0.95)) }
            filtered += alpha * (s * env - filtered)
            channel[i] = Float(filtered * peak)
        }

        // 离线多抽头混响：三个越来越远、越来越淡的反射，回想时更湿。
        // 用干声快照叠加（不是就地反馈），避免增益累积把波形推爆。
        let wet = Float(max(0, min(1.4, preset.reverbMix * (echo ? 1.25 : 1.0))))
        if wet > 0.001 {
            let n = Int(frames)
            let dry = Array(UnsafeBufferPointer(start: channel, count: n))
            let taps: [(Int, Float)] = [(Int(0.11 * sr), 0.20),
                                        (Int(0.19 * sr), 0.13),
                                        (Int(0.31 * sr), 0.08)]
            for i in 0..<n {
                var v = dry[i]
                for (delay, gain) in taps where i >= delay {
                    v += dry[i - delay] * gain * wet
                }
                channel[i] = v
            }
        }
        buffer = buf
    }

    func play() {
        guard let buf = buffer else { return }
        player.pan = pan
        player.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
