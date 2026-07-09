import AppKit

/// Janela de definições: acesso sem password, iniciar no login, auto-update.
/// Auto-desligar por N horas e outros nice-to-haves ficam para v1.1.
final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 190),
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
        passwordless.frame = NSRect(x: 20, y: 140, width: 320, height: 24)

        let hint = NSTextField(labelWithString: "Instala uma regra sudoers restrita (só pmset disablesleep). Pede admin uma vez.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 40, y: 118, width: 300, height: 18)

        let login = NSButton(checkboxWithTitle: "Iniciar no login", target: self, action: #selector(toggleLogin(_:)))
        login.state = LoginItem.isEnabled ? .on : .off
        login.frame = NSRect(x: 20, y: 80, width: 320, height: 24)

        let autoUpdate = NSButton(checkboxWithTitle: "Verificar atualizações automaticamente", target: self, action: #selector(toggleAutoUpdate(_:)))
        autoUpdate.state = Updater.autoCheckEnabled ? .on : .off
        autoUpdate.frame = NSRect(x: 20, y: 50, width: 320, height: 24)

        let content = NSView(frame: win.contentRect(forFrameRect: win.frame))
        content.addSubview(passwordless)
        content.addSubview(hint)
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
