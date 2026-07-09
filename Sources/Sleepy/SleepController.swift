import Foundation

/// Núcleo do Sleepy: impede o Mac de dormir, incluindo com a tampa fechada.
///
/// Usa `pmset -a disablesleep` (não a IOKit power assertion) porque é o
/// único mecanismo que sobrevive ao lid-close sem precisar de ecrã externo
/// nem estar ligado à corrente — ver plan.md secção 1 para a comparação.
/// A contrapartida é que exige privilégios de admin a cada chamada (prompt
/// nativo via AppleScript); um helper privilegiado sem prompt fica para v1.1.
final class SleepController {
    static let shared = SleepController()

    private(set) var isActive = false

    private init() {}

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
        isActive = setDisableSleep(true)
    }

    func disable() {
        guard isActive else { return }
        if setDisableSleep(false) { isActive = false }
    }

    /// Reset defensivo silencioso no arranque — só quando o acesso sem password
    /// existe, para nunca atirar um prompt de admin no startup. (Sem ele, um
    /// valor preso de uma sessão que crashou limpa-se no próximo toggle manual.)
    func resetOnLaunch() {
        if PrivilegedAccess.setDisableSleep(false) { isActive = false }
    }
}
