//
//  Overlays.swift — 双端共享：五音计数柱与旋律线
//
import SwiftUI

// MARK: - 五音计数柱：每敲一次，对应那根水位涨一格

struct NoteBarsView: View {
    let counts: [Int]
    let tint: Color

    var body: some View {
        let peak = max(1, counts.max() ?? 1)
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(0..<5, id: \.self) { i in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(tint.opacity(0.72))
                        .frame(width: 3, height: max(2, CGFloat(counts[i]) / CGFloat(peak) * 14))
                    Text(noteNames[i])
                        .font(.system(size: 8, weight: .light))
                        .foregroundStyle(tint.opacity(0.5))
                }
            }
        }
        .animation(.easeOut(duration: 0.5), value: counts)
        .allowsHitTesting(false)
    }
}

// 一句话的音高走向，极淡地画在音名上方（圆滑曲线 + 每音一颗小点，与设计稿一致）
struct MelodyTraceView: View {
    let trace: [Int]
    var tint: Color = Color(red: 0.72, green: 0.84, blue: 0.78)
    var body: some View {
        Canvas { context, size in
            guard trace.count > 1 else { return }
            let pts: [CGPoint] = trace.enumerated().map { i, d in
                CGPoint(x: size.width * CGFloat(i) / CGFloat(trace.count - 1),
                        y: size.height - 2 - CGFloat(d) / 9 * (size.height - 4))
            }
            var path = Path()
            path.move(to: pts[0])
            for i in 1..<pts.count {
                let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2,
                                  y: (pts[i - 1].y + pts[i].y) / 2)
                path.addQuadCurve(to: mid, control: pts[i - 1])
            }
            path.addLine(to: pts[pts.count - 1])
            context.stroke(path, with: .color(tint.opacity(0.40)), lineWidth: 1)
            for pt in pts.dropLast() {   // 末音是「正在响」的那个，交给中央墨符
                let r: CGFloat = 1.3
                context.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(tint.opacity(0.55)))
            }
        }
        .frame(width: 92, height: 14)
    }
}

