import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let settings = SettingsWindow()
    private let updater = UpdateController()
    private var availableUpdate: UpdateInfo?

    private static let activeSymbol = "sun.max.fill"
    private static let inactiveSymbol = "moon.zzz"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        SleepController.shared.onStateChange = { [weak self] in self?.updateIcon() }
        SleepController.shared.restoreOnLaunch()

        if Updater.autoCheckEnabled {
            Updater.check { [weak self] info in self?.availableUpdate = info }
        }

        // Debug hook: liga o toggle sem clicar no menu (usado para verificar o
        // re-arm no relaunch). Só funciona com o acesso sem password instalado.
        if ProcessInfo.processInfo.environment["SLEEPY_DEBUG_ENABLE"] == "1" {
            SleepController.shared.enable()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // O auto-updater relança-nos de propósito: manter a proteção e deixar o
        // restoreOnLaunch re-armar do outro lado.
        guard !SleepController.shared.isRelaunching else { return }
        SleepController.shared.disable()
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateIcon()
    }

    private func updateIcon() {
        let active = SleepController.shared.isActive
        let symbol = active ? Self.activeSymbol : Self.inactiveSymbol
        let description = active ? "Sleepy — sleep impedido" : "Sleepy — sleep normal"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true  // monocromático: branco na menu bar escura, adapta-se
        statusItem?.button?.image = image
    }

    // Rebuild the menu each time it opens so the toggle state stays fresh.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Banner when a newer release is available on GitHub.
        if let update = availableUpdate {
            let item = addItem(to: menu, "⤓ Atualizar para \(update.version)…", #selector(openUpdate))
            item.attributedTitle = NSAttributedString(
                string: item.title,
                attributes: [.foregroundColor: NSColor.systemGreen])
            menu.addItem(.separator())
        }

        let active = SleepController.shared.isActive
        let toggle = addItem(to: menu, active ? "Impedir sleep (ligado)" : "Impedir sleep", #selector(toggleSleep))
        toggle.state = active ? .on : .off

        if let off = SleepController.shared.autoOffDate {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            let info = NSMenuItem(title: "Desliga sozinho às \(fmt.string(from: off))", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }

        // Nudge to set up passwordless toggling while it isn't installed yet.
        if !PrivilegedAccess.isInstalled {
            let hint = addItem(to: menu, "Ativar acesso sem password…", #selector(enablePasswordless))
            hint.attributedTitle = NSAttributedString(
                string: hint.title,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        }
        menu.addItem(.separator())

        let login = addItem(to: menu, "Iniciar no login", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off

        addItem(to: menu, "Definições…", #selector(showSettings))
        menu.addItem(.separator())

        let quit = addItem(to: menu, "Sair do Sleepy", #selector(quit))
        quit.keyEquivalent = "q"
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func toggleSleep() {
        if SleepController.shared.isActive {
            SleepController.shared.disable()
        } else {
            SleepController.shared.enable()
        }
        updateIcon()
    }

    @objc private func enablePasswordless() { _ = PrivilegedAccess.install() }

    @objc private func toggleLoginItem() { LoginItem.toggle() }

    @objc private func showSettings() { settings.show() }

    @objc private func openUpdate() {
        if let update = availableUpdate { updater.start(update) }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Launch at login

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static func toggle() { setEnabled(!isEnabled) }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Sleepy: login item error: \(error.localizedDescription)")
        }
    }
}
