import SwiftUI
import UsoClaudeCore

/// Gaveta das horas de IA, abaixo dos anéis.
struct HoursDrawer: View {
    @ObservedObject var hours: HoursStore
    let onActivateHooks: () -> Void

    @AppStorage("hoursPeriodKind") private var kindRaw = HoursStore.PeriodKind.day.rawValue
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var customTo = Date()
    @State private var expanded: Set<String> = []
    /// Colunas da visão Dia selecionadas para somar.
    @State private var selectedHours: Set<Int> = []

    private var kind: HoursStore.PeriodKind { HoursStore.PeriodKind(rawValue: kindRaw) ?? .day }
    private var labels: [String] { hours.accounts.map(\.label) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: Binding(get: { kind }, set: { select($0) })) {
                Text("Dia").tag(HoursStore.PeriodKind.day)
                Text("Semana").tag(HoursStore.PeriodKind.week)
                Text("Mês").tag(HoursStore.PeriodKind.month)
                Text("Período…").tag(HoursStore.PeriodKind.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            if kind == .custom {
                HStack(spacing: 4) {
                    Text("de").foregroundStyle(Color(white: 0.6))
                    DatePicker("", selection: $customFrom, displayedComponents: .date).labelsHidden()
                    Text("até").foregroundStyle(Color(white: 0.6))
                    DatePicker("", selection: $customTo, displayedComponents: .date).labelsHidden()
                }
                .font(.system(size: 11))
                .controlSize(.small)
                .onChange(of: customFrom) { hours.period = .custom(customFrom, customTo) }
                .onChange(of: customTo) { hours.period = .custom(customFrom, customTo) }
            } else {
                HStack {
                    navButton("chevron.left") { hours.period = hours.period.previous(calendar: hours.calendar) }
                    Spacer()
                    Text(hours.period.title(calendar: hours.calendar)).font(.system(size: 11, weight: .semibold))
                    Spacer()
                    navButton("chevron.right") { hours.period = hours.period.next(calendar: hours.calendar) }
                }
            }

            filterRow

            if let report = hours.report {
                VStack(alignment: .leading, spacing: 0) {
                    Text(formatHours(report.total)).font(.system(size: 20, weight: .semibold))
                    Text(subtitle(report)).font(.system(size: 10)).foregroundStyle(Color(white: 0.55))
                }
                HoursChart(buckets: report.buckets, accounts: labels, hourly: kind == .day,
                           selected: kind == .day ? selectedHours : []) { index in
                    if kind == .day {
                        // No Dia, cada clique soma (ou tira) a coluna da seleção.
                        if selectedHours.remove(index) == nil { selectedHours.insert(index) }
                    } else if report.buckets.indices.contains(index) {
                        // Nos demais, o clique abre aquele dia.
                        kindRaw = HoursStore.PeriodKind.day.rawValue
                        hours.period = .day(report.buckets[index].start)
                    }
                }
                if kind == .day, !selectedHours.isEmpty {
                    selectionLine(report)
                }
                legend
                projectList(hours.listProjects)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }

            if hours.importing {
                Text("importando histórico…").font(.system(size: 10)).foregroundStyle(Color(white: 0.55))
            }
            if !hours.allHooksActive {
                VStack(alignment: .leading, spacing: 4) {
                    Text("O registro de horas pelos hooks está desligado. Só o histórico importado aparece.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Ativar registro de horas", action: onActivateHooks).controlSize(.small)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .onAppear { select(kind) }
        .onChange(of: hours.period) { selectedHours = [] }
    }

    private func select(_ newKind: HoursStore.PeriodKind) {
        kindRaw = newKind.rawValue
        let now = Date()
        switch newKind {
        case .day: hours.period = .day(now)
        case .week: hours.period = .week(now)
        case .month: hours.period = .month(now)
        case .custom: hours.period = .custom(customFrom, customTo)
        }
    }

    private func subtitle(_ report: HoursReport) -> String {
        switch kind {
        case .day: "de IA executando · 00:00–23:59"
        case .custom: "de IA executando · média \(formatHours(report.averagePerDay))/dia"
        default: "de IA executando"
        }
    }

    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 18)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.18)))
    }

    /// "Selecionado: 2h 10min · 13h–15h (3 colunas) · claude 1h 40min · proteo 30min ✕"
    private func selectionLine(_ report: HoursReport) -> some View {
        let sum = selectionSummary(report.buckets, selected: selectedHours)
        let hoursText = selectedHours.sorted().map { String(format: "%02dh", $0) }
        let range = hoursText.count <= 3 ? hoursText.joined(separator: ", ") : "\(hoursText.first!)…\(hoursText.last!)"
        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Selecionado: \(formatHours(sum.total))").font(.system(size: 11, weight: .semibold))
                Text("\(range) · \(selectedHours.count) \(selectedHours.count == 1 ? "coluna" : "colunas")")
                    .font(.system(size: 10)).foregroundStyle(Color(white: 0.6))
                HStack(spacing: 8) {
                    ForEach(labels, id: \.self) { label in
                        if let s = sum.byAccount[label], s > 0 {
                            HStack(spacing: 3) {
                                Circle().fill(accountColor(label)).frame(width: 6, height: 6)
                                Text("\(label) \(formatHours(s))")
                            }
                        }
                    }
                }
                .font(.system(size: 10))
            }
            Spacer(minLength: 0)
            Button { selectedHours = [] } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Limpar seleção")
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.17)))
    }

    /// Menu de projetos com caixas de marcar e, se houver filtro, o resumo com ✕ para limpar.
    private var filterRow: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(hours.listProjects) { project in
                    Toggle(project.project, isOn: Binding(
                        get: { hours.filter.projects.contains(project.project) },
                        set: { _ in hours.filter.toggleProject(project.project) }))
                }
                if !hours.filter.projects.isEmpty {
                    Divider()
                    Button("Todos os projetos") { hours.filter.projects = [] }
                }
            } label: {
                Text("Projetos").font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if !hours.filter.isEmpty {
                Text("filtrando: " + (hours.filter.projects.sorted() + hours.filter.accounts.sorted()).joined(separator: ", "))
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button { hours.filter = ReportFilter() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Limpar filtro")
            }
            Spacer(minLength: 0)
        }
    }

    /// Clicar numa conta da legenda filtra por ela (clicar de novo tira).
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(labels, id: \.self) { label in
                Button { hours.filter.toggleAccount(label) } label: {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(accountColor(label)).frame(width: 8, height: 8)
                        Text(label)
                    }
                    .opacity(hours.filter.accounts.isEmpty || hours.filter.accounts.contains(label) ? 1 : 0.35)
                }
                .buttonStyle(.plain)
                .help("Filtrar por \(label)")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Color(white: 0.6))
    }

    /// Lista de projetos: a seta abre as sessões; clicar no nome ou na barra filtra pelo projeto.
    /// Com filtro ativo, os projetos de fora continuam visíveis, apagados, para poder incluí-los.
    private func projectList(_ projects: [ProjectRow]) -> some View {
        let rowHeight: CGFloat = 22
        let rows = projects.reduce(0) { $0 + 1 + (expanded.contains($1.project) ? $1.sessions.count : 0) }
        let maxProject = projects.map(\.total).max() ?? 1
        let selected = hours.filter.projects
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(projects) { project in
                    HStack(spacing: 6) {
                        Button {
                            if expanded.contains(project.project) { expanded.remove(project.project) } else { expanded.insert(project.project) }
                        } label: {
                            Image(systemName: expanded.contains(project.project) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8)).frame(width: 12, height: rowHeight).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { hours.filter.toggleProject(project.project) } label: {
                            HStack(spacing: 6) {
                                Text(project.project).lineLimit(1).truncationMode(.tail).frame(width: 92, alignment: .leading)
                                stackedBar(project.byAccount, scale: project.total / max(maxProject, 1))
                                Text(formatHours(project.total)).frame(width: 62, alignment: .trailing)
                            }
                            .frame(height: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(selected.contains(project.project) ? "Tirar do filtro" : "Filtrar por \(project.project)")
                    }
                    .font(.system(size: 11))
                    .opacity(selected.isEmpty || selected.contains(project.project) ? 1 : 0.35)
                    if expanded.contains(project.project) {
                        ForEach(project.sessions) { session in
                            sessionRow(session).frame(height: rowHeight)
                        }
                    }
                }
                if projects.isEmpty {
                    Text("Nenhuma hora de IA neste período.").font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                        .frame(height: rowHeight)
                }
            }
        }
        .frame(height: min(CGFloat(max(rows, 1)) * rowHeight, 220))
    }

    private func stackedBar(_ byAccount: [String: TimeInterval], scale: Double) -> some View {
        GeometryReader { geo in
            let total = max(byAccount.values.reduce(0, +), 1)
            HStack(spacing: 0) {
                ForEach(labels, id: \.self) { label in
                    if let s = byAccount[label], s > 0 {
                        Rectangle().fill(accountColor(label)).frame(width: geo.size.width * scale * s / total)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 8)
            .background(Color(white: 0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(maxHeight: .infinity)
        }
    }

    private func sessionRow(_ session: SessionRow) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm dd/MM"
        return HStack(spacing: 6) {
            Circle().fill(accountColor(session.account)).frame(width: 6, height: 6)
            Text(hours.sessionTitles[session.sessionId] ?? "sem título").lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text(formatter.string(from: session.start)).foregroundStyle(Color(white: 0.5))
            Text(formatHours(session.seconds)).frame(width: 56, alignment: .trailing)
        }
        .font(.system(size: 10))
        .padding(.leading, 14)
    }
}
