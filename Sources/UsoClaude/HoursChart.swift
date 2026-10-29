import SwiftUI
import UsoClaudeCore

private let accountPalette: [Color] = [
    Color(red: 0x6a / 255, green: 0xa7 / 255, blue: 0xff / 255),
    Color(red: 0xc1 / 255, green: 0x8c / 255, blue: 0xff / 255),
    Color(red: 0xff / 255, green: 0xa6 / 255, blue: 0x5c / 255),
    Color(red: 0x4d / 255, green: 0xd0 / 255, blue: 0xc4 / 255),
    Color(red: 0xff / 255, green: 0x7a / 255, blue: 0xb6 / 255),
    Color(red: 0xe3 / 255, green: 0xc4 / 255, blue: 0x3b / 255),
]

/// Cor da conta pela ordem em `accounts.json`; nomes que não estão mais no arquivo (dados antigos) ficam cinza.
func accountColor(_ label: String) -> Color {
    guard let index = Account.all.firstIndex(where: { $0.label == label }) else { return Color(white: 0.6) }
    return accountPalette[index % accountPalette.count]
}

/// Barras empilhadas por conta (uma por hora no Dia, uma por dia nos demais), com tooltip no hover.
struct HoursChart: View {
    let buckets: [Bucket]
    let accounts: [String]
    let hourly: Bool
    /// Colunas selecionadas (destacadas; as demais ficam apagadas enquanto houver seleção).
    var selected: Set<Int> = []
    /// Clique numa coluna, pelo índice.
    var onTap: ((Int) -> Void)?

    @State private var hovered: Int?

    private var maxTotal: Double { max(buckets.map(\.total).max() ?? 0, 60) }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let slot = geo.size.width / CGFloat(max(buckets.count, 1))
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: min(2, slot * 0.2)) {
                        ForEach(buckets.indices, id: \.self) { i in
                            bar(buckets[i], height: geo.size.height)
                                .opacity(selected.isEmpty || selected.contains(i) ? 1 : 0.4)
                                .overlay(RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.white.opacity(selected.contains(i) ? 1 : hovered == i ? 0.6 : 0),
                                            lineWidth: selected.contains(i) ? 1.5 : 1))
                                // A coluna inteira é clicável, inclusive a parte vazia acima da barra.
                                .contentShape(Rectangle())
                                .onTapGesture { onTap?(i) }
                        }
                    }
                    if let i = hovered, buckets.indices.contains(i) {
                        tooltip(buckets[i])
                            .fixedSize()
                            .offset(x: min(max(0, CGFloat(i) * slot - 60), geo.size.width - 150), y: -4)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hovered = min(buckets.count - 1, max(0, Int(point.x / slot)))
                    case .ended: hovered = nil
                    }
                }
            }
            .frame(height: 70)
            axis
        }
    }

    private func bar(_ bucket: Bucket, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(accounts.reversed(), id: \.self) { account in
                let seconds = bucket.byAccount[account] ?? 0
                if seconds > 0 {
                    Rectangle().fill(accountColor(account))
                        .frame(height: max(1, height * CGFloat(seconds / maxTotal)))
                }
            }
            if bucket.total == 0 {
                Rectangle().fill(Color(white: 0.2)).frame(height: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .frame(maxWidth: .infinity)
    }

    private func tooltip(_ bucket: Bucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(bucketLabel(bucket)) · \(formatHours(bucket.total))").font(.system(size: 10, weight: .semibold))
            ForEach(accounts, id: \.self) { account in
                if let s = bucket.byAccount[account], s > 0 {
                    Text("\(account) \(formatHours(s))").font(.system(size: 10))
                }
            }
            ForEach(bucket.byProject.sorted { $0.value > $1.value }.prefix(4), id: \.key) { project, s in
                Text("\(project) \(formatHours(s))").font(.system(size: 10)).foregroundStyle(Color(white: 0.3))
            }
        }
        .foregroundStyle(Color(white: 0.07))
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.96)))
        .shadow(radius: 4)
    }

    private func bucketLabel(_ bucket: Bucket) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        if hourly {
            formatter.dateFormat = "HH:mm"
            let end = bucket.end.addingTimeInterval(-60)
            return "\(formatter.string(from: bucket.start))–\(formatter.string(from: end))"
        }
        formatter.dateFormat = "EEE dd/MM"
        return formatter.string(from: bucket.start).replacingOccurrences(of: ".", with: "")
    }

    private var axis: some View {
        HStack {
            ForEach(axisLabels, id: \.self) { label in
                Text(label)
                if label != axisLabels.last { Spacer() }
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(Color(white: 0.45))
    }

    private var axisLabels: [String] {
        if hourly { return ["00h", "06h", "12h", "18h", "23h"] }
        guard let first = buckets.first, let last = buckets.last else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        if buckets.count <= 2 { return [formatter.string(from: first.start), formatter.string(from: last.start)] }
        let mid = buckets[buckets.count / 2]
        return [formatter.string(from: first.start), formatter.string(from: mid.start), formatter.string(from: last.start)]
    }
}
