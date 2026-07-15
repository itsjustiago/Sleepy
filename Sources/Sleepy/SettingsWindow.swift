import SwiftUI
import AppKit

/// Estado observável das definições, espelhado do sistema em cada `show()`.
final class SettingsModel: ObservableObject {
    @Published var passwordless = PrivilegedAccess.isInstalled
    @Published var autoOffHours = SleepController.autoOffHours
    @Published var login = LoginItem.isEnabled
    @Published var autoCheck = Updater.autoCheckEnabled
    @Published var updateStatus = ""
    @Published var foundUpdate: UpdateInfo?
    let version = Updater.currentVersion
}

/// Janela de definições: acesso sem password, auto-desligar, iniciar no login e
/// atualizações. Reescrita em SwiftUI para partilhar a linguagem visual do Facet.
final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = SettingsModel()

    /// Ligado pelo `AppDelegate` para instalar uma atualização encontrada.
    var onStartUpdate: ((UpdateInfo) -> Void)?

    func show() {
        if window == nil { build() }
        // Espelha o estado real antes de aparecer.
        model.passwordless = PrivilegedAccess.isInstalled
        model.login = LoginItem.isEnabled
        model.autoOffHours = SleepController.autoOffHours
        model.autoCheck = Updater.autoCheckEnabled
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.center()
            self?.window?.makeKeyAndOrderFront(nil)
            self?.window?.orderFrontRegardless()
        }
    }

    private func build() {
        let view = SettingsView(model: model,
                                startUpdate: { [weak self] in self?.onStartUpdate?($0) })
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.title = "Definições — Sleepy"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: view)
        window = w
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var startUpdate: (UpdateInfo) -> Void

    /// (horas, título) — 0 = nunca desligar sozinho.
    private let autoOffOptions: [(Int, String)] = [
        (1, "1 hora"), (2, "2 horas"), (4, "4 horas"),
        (8, "8 horas"), (12, "12 horas"), (0, "Nunca"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                SettingsSection(title: "Impedir sleep") {
                    ToggleRow(
                        title: "Não pedir password",
                        subtitle: "Instala uma regra restrita (só pmset disablesleep). Pede admin uma vez.",
                        isOn: Binding(
                            get: { model.passwordless },
                            set: { on in
                                _ = on ? PrivilegedAccess.install() : PrivilegedAccess.uninstall()
                                model.passwordless = PrivilegedAccess.isInstalled
                            }))
                    RowDivider()
                    SettingsRow(
                        title: "Desligar sozinho",
                        subtitle: "Volta ao sleep normal ao fim deste tempo."
                    ) {
                        Picker("", selection: Binding(
                            get: { model.autoOffHours },
                            set: { model.autoOffHours = $0; SleepController.autoOffHours = $0 })) {
                            ForEach(autoOffOptions, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }

                SettingsSection(title: "Arranque") {
                    ToggleRow(
                        title: "Iniciar no login",
                        subtitle: "Abre o Sleepy quando entras na sessão.",
                        isOn: Binding(
                            get: { model.login },
                            set: { LoginItem.setEnabled($0); model.login = LoginItem.isEnabled }))
                }

                SettingsSection(title: "Atualizações") {
                    ToggleRow(
                        title: "Procurar automaticamente",
                        isOn: Binding(
                            get: { model.autoCheck },
                            set: { model.autoCheck = $0; Updater.autoCheckEnabled = $0 }))
                    RowDivider()
                    SettingsRow(
                        title: "Versão \(model.version)",
                        subtitle: model.updateStatus.isEmpty ? nil : model.updateStatus
                    ) {
                        if let update = model.foundUpdate {
                            Button("Atualizar para \(update.version)") { startUpdate(update) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        } else {
                            Button("Procurar agora", action: checkNow)
                                .controlSize(.small)
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 440, height: 470)
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIcon(systemName: "moon.zzz.fill", size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sleepy").font(.title2.weight(.bold))
                Text("Impede o Mac de dormir, mesmo de tampa fechada.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func checkNow() {
        model.updateStatus = "A procurar…"
        model.foundUpdate = nil
        Updater.check { info in
            model.foundUpdate = info
            if let info {
                model.updateStatus = "Atualização disponível: \(info.version)."
            } else {
                model.updateStatus = "Estás na versão mais recente (\(model.version))."
            }
        }
    }
}
