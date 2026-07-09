import Foundation
import IOKit.pwr_mgt

/// Núcleo do Sleepy: impede o Mac de dormir, incluindo com a tampa fechada.
///
/// São precisos **dois** mecanismos, e cobrem coisas diferentes:
///
/// 1. `pmset -a disablesleep` — sobrevive ao lid-close sem precisar de ecrã
///    externo nem corrente, mas exige admin (prompt, ou a regra sudoers de
///    [[PrivilegedAccess]]).
/// 2. IOKit power assertion `PreventUserIdleSystemSleep` — impede o sleep por
///    inatividade (o timer `sleep` do `pmset -g`). Não precisa de privilégios.
///
/// O estado é persistido: um crash, um rebuild ou o auto-updater relançam a
/// app, e sem isso a proteção caía em silêncio a meio de uma tarefa longa.
/// Para não deixar o Mac acordado por esquecimento, há auto-desligar ao fim de
/// `autoOffHours` (default 8h).
final class SleepController {
    static let shared = SleepController()

    private(set) var isActive = false

    /// Chamado quando o estado muda sem ser por clique (restore, auto-off).
    var onStateChange: (() -> Void)?

    /// O auto-updater relança a app de propósito — nesse caso não desarmamos.
    var isRelaunching = false

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var autoOffTimer: Timer?

    private let activeKey = "sleepActive"
    private let activeSinceKey = "activeSince"
    private static let autoOffKey = "autoOffHours"

    /// Horas até desligar sozinho. 0 = nunca.
    static var autoOffHours: Int {
        get { UserDefaults.standard.object(forKey: autoOffKey) as? Int ?? 8 }
        set {
            UserDefaults.standard.set(newValue, forKey: autoOffKey)
            shared.scheduleAutoOff()
        }
    }

    private init() {}

    // MARK: - Estado real do sistema

    /// Lê o `SleepDisabled` do `pmset -g`. Não precisa de privilégios, e é a
    /// única fonte de verdade — o que julgamos ter feito pode não ter pegado.
    static func systemSleepDisabled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return false }
        for line in out.split(separator: "\n") where line.contains("SleepDisabled") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return fields.last == "1"
        }
        return false
    }

    // MARK: - IOKit power assertion (idle sleep)

    /// Segura uma assertion que impede o sleep por inatividade. Sem privilégios.
    /// O display continua livre para adormecer (queremos isso de tampa fechada).
    @discardableResult
    private func createAssertion() -> Bool {
        guard !hasAssertion else { return true }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Sleepy: impedir sleep por inatividade" as CFString,
            &id)
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        hasAssertion = true
        return true
    }

    private func releaseAssertion() {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        hasAssertion = false
        assertionID = 0
    }

    // MARK: - pmset disablesleep (lid-close)

    /// Elevado via prompt AppleScript (Touch ID/password). Usado como fallback
    /// quando o acesso sem password ([[PrivilegedAccess]]) não está instalado.
    @discardableResult
    private func setDisableSleepPrompting(_ on: Bool) -> Bool {
        let value = on ? "1" : "0"
        let script = "do shell script \"pmset -a disablesleep \(value)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            NSLog("Sleepy: pmset disablesleep=\(value) falhou: \(error)")
        }
        return error == nil
    }

    /// Sem password primeiro (sem prompt); só cai no prompt de admin se a regra
    /// sudoers não estiver instalada.
    private func setDisableSleep(_ on: Bool) -> Bool {
        if PrivilegedAccess.setDisableSleep(on) { return true }
        return setDisableSleepPrompting(on)
    }

    // MARK: - Toggle

    func enable() {
        guard !isActive else { return }
        // Sem o disablesleep não há proteção de lid-close — se o utilizador
        // cancelar o prompt de admin, não fingimos que ficou ligado.
        guard setDisableSleep(true) else { return }
        if !createAssertion() {
            NSLog("Sleepy: falha a criar a power assertion — o idle sleep pode ocorrer")
        }
        isActive = true
        activeSince = Date()
        UserDefaults.standard.set(true, forKey: activeKey)
        scheduleAutoOff()
        onStateChange?()
    }

    func disable() {
        guard isActive else { return }
        guard setDisableSleep(false) else { return }
        releaseAssertion()
        isActive = false
        clearPersisted()
        autoOffTimer?.invalidate()
        autoOffTimer = nil
        onStateChange?()
    }

    // MARK: - Arranque

    /// Re-arma se a app foi relançada (crash, rebuild, auto-update) enquanto
    /// estava ligada; caso contrário faz o reset defensivo. Nunca mostra prompt
    /// no arranque — só usa o caminho sem password.
    func restoreOnLaunch() {
        let shouldBeActive = UserDefaults.standard.bool(forKey: activeKey) && !autoOffExpired()

        if shouldBeActive {
            _ = PrivilegedAccess.setDisableSleep(true)
        } else {
            _ = PrivilegedAccess.setDisableSleep(false)
            clearPersisted()
        }

        // O ícone segue o que o sistema diz, não o que julgamos ter feito. Sem
        // acesso sem password não conseguimos mexer no disablesleep em silêncio,
        // e mentir sobre o estado seria pior do que mostrá-lo.
        isActive = Self.systemSleepDisabled()
        if isActive {
            createAssertion()
            UserDefaults.standard.set(true, forKey: activeKey)
            if activeSince == nil { activeSince = Date() }
            scheduleAutoOff()
        } else {
            releaseAssertion()
        }
        onStateChange?()
    }

    // MARK: - Auto-desligar

    private var activeSince: Date? {
        get { UserDefaults.standard.object(forKey: activeSinceKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: activeSinceKey) }
    }

    /// Momento em que o auto-off vai disparar, para mostrar no menu.
    var autoOffDate: Date? {
        guard isActive, Self.autoOffHours > 0, let since = activeSince else { return nil }
        return since.addingTimeInterval(TimeInterval(Self.autoOffHours) * 3600)
    }

    private func autoOffExpired() -> Bool {
        guard Self.autoOffHours > 0, let since = activeSince else { return false }
        return Date().timeIntervalSince(since) >= TimeInterval(Self.autoOffHours) * 3600
    }

    private func clearPersisted() {
        UserDefaults.standard.set(false, forKey: activeKey)
        UserDefaults.standard.removeObject(forKey: activeSinceKey)
    }

    private func scheduleAutoOff() {
        autoOffTimer?.invalidate()
        autoOffTimer = nil
        guard isActive, let deadline = autoOffDate else { return }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { autoOff(); return }
        autoOffTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            self?.autoOff()
        }
    }

    private func autoOff() {
        guard isActive else { return }
        NSLog("Sleepy: auto-desligar ao fim de \(Self.autoOffHours)h")
        disable()
    }
}
