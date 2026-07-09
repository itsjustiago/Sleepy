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

    /// Corre `pmset -a disablesleep <0|1>` elevado, via AppleScript
    /// (mostra o prompt nativo de password/Touch ID do macOS).
    @discardableResult
    private func setDisableSleep(_ on: Bool) -> Bool {
        let value = on ? "1" : "0"
        let script = "do shell script \"pmset -a disablesleep \(value)\" with administrator privileges"
        var error: NSDictionary?
        let applescript = NSAppleScript(source: script)
        applescript?.executeAndReturnError(&error)
        if let error {
            NSLog("Sleepy: pmset disablesleep=\(value) falhou: \(error)")
        }
        return error == nil
    }

    func enable() {
        guard !isActive else { return }
        isActive = setDisableSleep(true)
    }

    func disable() {
        guard isActive else { return }
        if setDisableSleep(false) { isActive = false }
    }

    /// Chamado no arranque da app: garante que não fica preso em
    /// disablesleep=1 de uma sessão anterior que tenha crashado.
    func resetOnLaunch() {
        setDisableSleep(false)
        isActive = false
    }
}
