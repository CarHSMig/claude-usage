import AppKit
import Combine
import SwiftUI
@preconcurrency import UserNotifications
import UsoClaudeCore
import os

private let notifyLog = Logger(subsystem: "com.carlosmigon.usoclaude", category: "notifications")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, UNUserNotificationCenterDelegate {
    private var alertsSubscription: AnyCancellable?
    private static let notifiedKey = "limitAlertsNotified"
    private let store = UsageStore(accounts: Account.all, source: LiveUsageSource())
    private let hours: HoursStore = {
        let db = (try? HoursDB(url: DataPaths.database))
            ?? (try! HoursDB(url: FileManager.default.temporaryDirectory.appendingPathComponent("usoclaude-fallback.sqlite")))
        return HoursStore(accounts: Account.all, db: db, eventsDir: DataPaths.eventsDir)
    }()
    private let notes = NotesStore(db: (try? NotesDB(url: DataPaths.database))
        ?? (try! NotesDB(url: FileManager.default.temporaryDirectory.appendingPathComponent("usoclaude-fallback.sqlite"))))
    private var panel: FloatingPanel!
    private var dockIcon: DockIcon!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel()
        let view = UsageView(store: store, pin: panel.pin, hours: hours, notes: notes,
                             onTogglePin: { [weak self] in self?.panel.isPinned.toggle() },
                             onActivateHooks: { [weak self] in self?.confirmHooks(active: true) })
        panel.setContent(view)
        panel.restoreOrigin()
        panel.orderFrontRegardless()
        dockIcon = DockIcon(store: store)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                           accessibilityDescription: "Uso Claude")
        let menu = NSMenu()
        menu.addItem(withTitle: "Mostrar/Ocultar janela", action: #selector(toggleWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Atualizar agora", action: #selector(refreshNow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Tamanho original", action: #selector(resetZoom), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ativar registro de horas…", action: #selector(activateHooks), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Desativar registro de horas…", action: #selector(deactivateHooks), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Enviar aviso de teste", action: #selector(sendTestAlert), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        // Menu principal mínimo, para o ⌘Q funcionar quando o app está em foco.
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Atualizar agora", action: #selector(refreshNow), keyEquivalent: "r").target = self
        appItem.submenu?.addItem(.separator())
        appItem.submenu?.addItem(withTitle: "Sair do Uso Claude", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu

        store.start()
        hours.start()
        notes.start()
        startLimitAlerts()
        if CommandLine.arguments.contains("--test-notification") { sendTestAlert() }
    }

    /// Notificação de exemplo, para conferir a aparência e a permissão de notificações.
    @objc private func sendTestAlert() {
        post(LimitAlert(title: "proteo: sessão em 96% (teste)",
                        body: "Renova em 2h40. Nenhuma outra conta com folga: claude renova qui 07:00."))
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .denied else { return }
            DispatchQueue.main.async { self?.explainNotificationsDenied() }
        }
    }

    /// Com a permissão negada o macOS aceita o aviso mas não mostra nada; explica e leva ao ajuste.
    private func explainNotificationsDenied() {
        let alert = NSAlert()
        alert.messageText = "Notificações desativadas para o Uso Claude"
        alert.informativeText = "O macOS está bloqueando os avisos deste app. Em Ajustes do Sistema › Notificações › "
            + "Uso Claude, ative \"Permitir notificações\" e escolha o estilo Faixas ou Alertas."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Agora não")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let id = Bundle.main.bundleIdentifier ?? "com.carlosmigon.usoclaude"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func post(_ alert: LimitAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        // Pede a permissão antes de postar: sem ela o aviso some sem erro visível.
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            notifyLog.notice("authorization granted=\(granted, privacy: .public) error=\(String(describing: error), privacy: .public)")
            center.getNotificationSettings { settings in
                notifyLog.notice("settings auth=\(settings.authorizationStatus.rawValue, privacy: .public) alert=\(settings.alertSetting.rawValue, privacy: .public) style=\(settings.alertStyle.rawValue, privacy: .public) nc=\(settings.notificationCenterSetting.rawValue, privacy: .public)")
            }
            center.add(request) { error in
                notifyLog.notice("add \(alert.title, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Avisa (notificação do macOS) quando uma conta passa de 80% na sessão ou na semana, e quando renova.
    private func startLimitAlerts() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            notifyLog.notice("startup authorization granted=\(granted, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
        alertsSubscription = store.$states.sink { [weak self] states in
            // O sink recebe os valores novos de `states` (emitidos no willSet).
            DispatchQueue.main.async { self?.checkLimits(states) }
        }
    }

    private func checkLimits(_ states: [String: AccountState]) {
        var usages: [String: Usage] = [:]
        for (label, state) in states {
            if case .ok(let usage, let stale) = state, !stale { usages[label] = usage }
        }
        guard !usages.isEmpty else { return }
        let defaults = UserDefaults.standard
        var notified = defaults.dictionary(forKey: Self.notifiedKey) as? [String: Double] ?? [:]
        let alerts = evaluateAlerts(usages, notified: &notified, now: Date(), calendar: .current)
        defaults.set(notified, forKey: Self.notifiedKey)
        alerts.forEach(post)
    }

    /// Mostra o aviso mesmo com o app em primeiro plano.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// "Ativar" só aparece habilitado se falta ativar em alguma conta; "Desativar", se há algo ativo.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(activateHooks): return !hours.allHooksActive
        case #selector(deactivateHooks): return hours.hooksActive.values.contains(true)
        default: return true
        }
    }

    @objc private func activateHooks() { confirmHooks(active: true) }
    @objc private func deactivateHooks() { confirmHooks(active: false) }

    /// Mostra o que vai mudar nos settings.json e só aplica se o usuário confirmar.
    private func confirmHooks(active: Bool) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = active ? "Ativar registro de horas" : "Desativar registro de horas"
        alert.informativeText = active
            ? hours.previewText()
            : "Os hooks do Uso Claude serão removidos dos settings.json das duas contas (com backup). Os outros hooks não são alterados."
        alert.addButton(withTitle: active ? "Ativar" : "Desativar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                try await hours.setHooks(active: active)
            } catch {
                let failure = NSAlert()
                failure.messageText = "Não foi possível alterar os settings.json"
                failure.informativeText = error.localizedDescription
                failure.runModal()
            }
        }
    }

    // Command-Tab ou clique no Dock: traz a janela para a frente.
    func applicationDidBecomeActive(_ notification: Notification) {
        panel.orderFrontRegardless()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.orderFrontRegardless()
        return true
    }

    /// Só esconde se a janela já estiver à vista; se estiver atrás de outra, traz para a frente.
    @objc private func toggleWindow() {
        if panel.isVisible, panel.occlusionState.contains(.visible), !isCoveredByOtherWindow() {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Alguma janela de outro app, no mesmo nível e acima da nossa, sobrepõe a janela?
    private func isCoveredByOtherWindow() -> Bool {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements],
                                                     CGWindowID(panel.windowNumber)) as? [[String: Any]],
              let screenHeight = NSScreen.screens.first?.frame.height else { return false }
        // CGWindowList usa origem no canto superior esquerdo da tela principal.
        let f = panel.frame
        let ours = CGRect(x: f.minX, y: screenHeight - f.maxY, width: f.width, height: f.height)
        let myPID = ProcessInfo.processInfo.processIdentifier
        return infos.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) != myPID,
                  (info[kCGWindowLayer as String] as? Int) == panel.level.rawValue,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return bounds.intersects(ours)
        }
    }

    @objc private func resetZoom() {
        panel.resetZoom()
    }

    @objc private func refreshNow() {
        Task { await store.refresh() }
    }
}
