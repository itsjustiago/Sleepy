import AppKit

/// Janela de definições mínima do MVP — apenas "Iniciar no login".
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
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Definições — Sleepy"
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        let login = NSButton(checkboxWithTitle: "Iniciar no login", target: self, action: #selector(toggleLogin(_:)))
        login.state = LoginItem.isEnabled ? .on : .off
        login.frame = NSRect(x: 20, y: 90, width: 280, height: 24)

        let autoUpdate = NSButton(checkboxWithTitle: "Verificar atualizações automaticamente", target: self, action: #selector(toggleAutoUpdate(_:)))
        autoUpdate.state = Updater.autoCheckEnabled ? .on : .off
        autoUpdate.frame = NSRect(x: 20, y: 60, width: 280, height: 24)

        let content = NSView(frame: win.contentRect(forFrameRect: win.frame))
        content.addSubview(login)
        content.addSubview(autoUpdate)
        win.contentView = content

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
