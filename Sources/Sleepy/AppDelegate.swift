import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var lastPopoverClose = Date.distantPast
    private let menuModel = SleepMenuModel()
    private let settings = SettingsWindow()
    private let updater = UpdateController()
    private var availableUpdate: UpdateInfo? { didSet { menuModel.availableUpdate = availableUpdate } }

    private static let activeSymbol = "sun.max.fill"
    private static let inactiveSymbol = "moon.zzz"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        settings.onStartUpdate = { [weak self] info in self?.updater.start(info) }
        SleepController.shared.onStateChange = { [weak self] in
            self?.updateIcon()
            self?.refreshMenuModel()
        }
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
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        updateIcon()
        buildPopover()
    }

    private func updateIcon() {
        let active = SleepController.shared.isActive
        let symbol = active ? Self.activeSymbol : Self.inactiveSymbol
        let description = active ? "Sleepy — sleep impedido" : "Sleepy — sleep normal"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true  // monocromático: branco na menu bar escura, adapta-se
        statusItem?.button?.image = image
    }

    // MARK: - Menu popover

    /// The menu-bar dropdown is a SwiftUI panel in an `NSPopover`, matching Facet.
    private func buildPopover() {
        let panel = MenuPanel(
            model: menuModel,
            onToggleSleep: { [weak self] in self?.toggleSleep() },
            onEnablePasswordless: { [weak self] in
                _ = PrivilegedAccess.install()
                self?.refreshMenuModel()
            },
            onToggleLogin: { [weak self] on in
                LoginItem.setEnabled(on)
                self?.menuModel.loginAtStartup = LoginItem.isEnabled
            },
            onSettings: { [weak self] in self?.dismissPopover(); self?.settings.show() },
            onUpdate: { [weak self] in
                self?.dismissPopover()
                if let update = self?.availableUpdate { self?.updater.start(update) }
            },
            onQuit: { NSApp.terminate(nil) })

        let hosting = NSHostingController(rootView: panel)
        hosting.sizingOptions = .preferredContentSize

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.delegate = self
        pop.contentViewController = hosting
        popover = pop
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Clicking the icon while the popover is open dismisses it via the
            // transient behaviour first; don't let the same click reopen it.
            if Date().timeIntervalSince(lastPopoverClose) < 0.2 { return }
            refreshMenuModel()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverClose = Date()
    }

    private func dismissPopover() { popover?.performClose(nil) }

    /// Mirror the live system state into the panel's model before it shows.
    private func refreshMenuModel() {
        menuModel.isActive = SleepController.shared.isActive
        menuModel.autoOffText = autoOffText()
        menuModel.passwordlessInstalled = PrivilegedAccess.isInstalled
        menuModel.loginAtStartup = LoginItem.isEnabled
        menuModel.availableUpdate = availableUpdate
    }

    private func autoOffText() -> String? {
        guard let off = SleepController.shared.autoOffDate else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "Desliga sozinho às \(fmt.string(from: off))"
    }

    // MARK: - Actions

    private func toggleSleep() {
        if SleepController.shared.isActive {
            SleepController.shared.disable()
        } else {
            SleepController.shared.enable()
        }
        updateIcon()
        refreshMenuModel()
    }
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
