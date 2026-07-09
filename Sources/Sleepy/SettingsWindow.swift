import AppKit

/// Janela de definições: acesso sem password, iniciar no login, auto-update.
/// Auto-desligar por N horas e outros nice-to-haves ficam para v1.1.
final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    private static let autoOffValues = [8, 1, 2, 4, 12, 0]
    private static let autoOffTitles = ["8 horas", "1 hora", "2 horas", "4 horas", "12 horas", "Nunca"]

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Definições — Sleepy"
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        let passwordless = NSButton(checkboxWithTitle: "Não pedir password a cada toggle", target: self, action: #selector(togglePasswordless(_:)))
        passwordless.state = PrivilegedAccess.isInstalled ? .on : .off
        passwordless.frame = NSRect(x: 20, y: 180, width: 320, height: 24)

        let hint = NSTextField(labelWithString: "Instala uma regra sudoers restrita (só pmset disablesleep). Pede admin uma vez.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 40, y: 158, width: 300, height: 18)

        let autoOffLabel = NSTextField(labelWithString: "Desligar sozinho ao fim de:")
        autoOffLabel.frame = NSRect(x: 20, y: 120, width: 175, height: 24)

        let autoOff = NSPopUpButton(frame: NSRect(x: 198, y: 116, width: 142, height: 26), pullsDown: false)
        autoOff.addItems(withTitles: Self.autoOffTitles)
        autoOff.target = self
        autoOff.action = #selector(changeAutoOff(_:))
        let current = SleepController.autoOffHours
        autoOff.selectItem(at: Self.autoOffValues.firstIndex(of: current) ?? 0)

        let login = NSButton(checkboxWithTitle: "Iniciar no login", target: self, action: #selector(toggleLogin(_:)))
        login.state = LoginItem.isEnabled ? .on : .off
        login.frame = NSRect(x: 20, y: 80, width: 320, height: 24)

        let autoUpdate = NSButton(checkboxWithTitle: "Verificar atualizações automaticamente", target: self, action: #selector(toggleAutoUpdate(_:)))
        autoUpdate.state = Updater.autoCheckEnabled ? .on : .off
        autoUpdate.frame = NSRect(x: 20, y: 50, width: 320, height: 24)

        let content = NSView(frame: win.contentRect(forFrameRect: win.frame))
        content.addSubview(passwordless)
        content.addSubview(hint)
        content.addSubview(autoOffLabel)
        content.addSubview(autoOff)
        content.addSubview(login)
        content.addSubview(autoUpdate)
        win.contentView = content

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePasswordless(_ sender: NSButton) {
        let ok = sender.state == .on ? PrivilegedAccess.install() : PrivilegedAccess.uninstall()
        // Reverte o visual se o utilizador cancelar o prompt de admin.
        if !ok { sender.state = PrivilegedAccess.isInstalled ? .on : .off }
    }

    @objc private func changeAutoOff(_ sender: NSPopUpButton) {
        SleepController.autoOffHours = Self.autoOffValues[sender.indexOfSelectedItem]
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        LoginItem.setEnabled(sender.state == .on)
    }

    @objc private func toggleAutoUpdate(_ sender: NSButton) {
        Updater.autoCheckEnabled = sender.state == .on
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
