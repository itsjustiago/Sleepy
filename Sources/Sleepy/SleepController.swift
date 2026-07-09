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
/// O `disablesleep` sozinho não trava o idle sleep, por isso mantemos os dois
/// enquanto o toggle está ligado.
final class SleepController {
    static let shared = SleepController()

    private(set) var isActive = false

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false

    private init() {}

    // MARK: - IOKit power assertion (idle sleep)

    /// Segura uma assertion que impede o sleep por inatividade. Sem privilégios.
    /// O display continua livre para adormecer (queremos isso de tampa fechada).
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

    func enable() {
        guard !isActive else { return }
        // Sem o disablesleep não há proteção de lid-close — se o utilizador
        // cancelar o prompt de admin, não fingimos que ficou ligado.
        guard setDisableSleep(true) else { return }
        if !createAssertion() {
            NSLog("Sleepy: falha a criar a power assertion — o idle sleep pode ocorrer")
        }
        isActive = true
    }

    func disable() {
        guard isActive else { return }
        guard setDisableSleep(false) else { return }
        releaseAssertion()
        isActive = false
    }

    /// Reset defensivo silencioso no arranque — só quando o acesso sem password
    /// existe, para nunca atirar um prompt de admin no startup. (Sem ele, um
    /// valor preso de uma sessão que crashou limpa-se no próximo toggle manual.)
    func resetOnLaunch() {
        if PrivilegedAccess.setDisableSleep(false) { isActive = false }
    }
}
