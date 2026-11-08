//
//  WuxingGlyph.swift — 双端共享：五行象形墨符，Path 手绘，不依赖字体
//  宫土 / 商金 / 角木 / 徵火 / 羽水。只借五行之象作视觉符号，
//  文案绝不引申为五音疗疾、养生或调理脏腑。
//
import SwiftUI

// MARK: - 五音墨符：五行象形，Path 手绘，不依赖字体

struct WuxingGlyph: View {
    let index: Int
    let high: Bool
    var tint: Color = Color(red: 0.84, green: 0.89, blue: 0.86)

    private func shape(_ s: CGFloat) -> Path {
        var p = Path()
        switch index {
        case 0:  // 宫 · 土：方厚居中，右下留口，中有一横
            p.move(to: CGPoint(x: -0.72*s, y: -0.72*s))
            p.addLine(to: CGPoint(x:  0.72*s, y: -0.72*s))
            p.addLine(to: CGPoint(x:  0.72*s, y:  0.40*s))
            p.move(to: CGPoint(x: -0.72*s, y:  0.72*s))
            p.addLine(to: CGPoint(x: -0.72*s, y: -0.72*s))
            p.addLine(to: CGPoint(x:  0.34*s, y:  0.72*s))
            p.move(to: CGPoint(x: -0.34*s, y:  0.02*s))
            p.addLine(to: CGPoint(x:  0.34*s, y:  0.02*s))
        case 1:  // 商 · 金：圆璧收敛，右侧留口，中含一点
            p.addArc(center: .zero, radius: 0.70*s,
                     startAngle: .degrees(27), endAngle: .degrees(333), clockwise: false)
            p.move(to: CGPoint(x: 0.11*s, y: 0))
            p.addArc(center: .zero, radius: 0.11*s,
                     startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        case 2:  // 角 · 木：一直两歧，向上生发
            p.move(to: CGPoint(x: 0, y:  0.80*s)); p.addLine(to: CGPoint(x: 0, y: -0.80*s))
            p.move(to: CGPoint(x: 0, y: -0.06*s))
            p.addQuadCurve(to: CGPoint(x: -0.70*s, y: -0.76*s),
                           control: CGPoint(x: -0.44*s, y: -0.34*s))
            p.move(to: CGPoint(x: 0, y: 0.22*s))
            p.addQuadCurve(to: CGPoint(x: 0.70*s, y: -0.48*s),
                           control: CGPoint(x: 0.46*s, y: -0.02*s))
        case 3:  // 徵 · 火：外焰上升，内焰一撇
            p.move(to: CGPoint(x: -0.54*s, y: 0.68*s))
            p.addQuadCurve(to: CGPoint(x: 0, y: -0.84*s),
                           control: CGPoint(x: -0.30*s, y: -0.14*s))
            p.addQuadCurve(to: CGPoint(x: 0.54*s, y: 0.68*s),
                           control: CGPoint(x: 0.30*s, y: -0.14*s))
            p.move(to: CGPoint(x: -0.16*s, y: 0.52*s))
            p.addQuadCurve(to: CGPoint(x: 0.14*s, y: 0.52*s),
                           control: CGPoint(x: 0, y: 0.06*s))
        default:  // 羽 · 水：三道润下之水纹
            for k in -1...1 {
                let y = CGFloat(k) * 0.42 * s
                p.move(to: CGPoint(x: -0.78*s, y: y))
                p.addCurve(to: CGPoint(x: 0.78*s, y: y),
                           control1: CGPoint(x: -0.26*s, y: y - 0.26*s),
                           control2: CGPoint(x:  0.26*s, y: y + 0.26*s))
            }
        }
        return p
    }

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 2 * 0.78
            let t = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            let glyph = shape(s).applying(t)
            let round = StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            context.stroke(glyph, with: .color(tint.opacity(0.22)), style: round)
            context.stroke(glyph, with: .color(tint.opacity(0.90)),
                           style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
            if high {
                let r = max(1.0, s * 0.09)
                let dot = CGRect(x: -r, y: -1.10*s - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: dot).applying(t), with: .color(tint.opacity(0.8)))
            }
        }
        .frame(width: 34, height: 34)
        .allowsHitTesting(false)
    }
}
