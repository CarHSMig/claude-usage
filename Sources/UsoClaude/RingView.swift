import SwiftUI
import UsoClaudeCore

struct RingView: View {
    let utilization: Double
    var size: CGFloat = 54
    var lineWidth: CGFloat = 6
    var fontSize: CGFloat = 12
    var showsPercentSign = true

    var body: some View {
        ZStack {
            Circle().stroke(Color(white: 0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(utilization, 100) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(displayPercent(utilization))\(showsPercentSign ? "%" : "")")
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var color: Color {
        switch level(for: utilization) {
        case .green: Color(red: 0.30, green: 0.76, blue: 0.48)
        case .yellow: Color(red: 0.89, green: 0.73, blue: 0.23)
        case .red: Color(red: 0.89, green: 0.34, blue: 0.30)
        }
    }
}
