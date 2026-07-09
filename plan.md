# Sleepy — plano de projeto

App de menu bar para macOS que liga/desliga o sleep automático com um toggle,
para poder deixar o Claude Code (ou qualquer tarefa longa) a trabalhar com a
tampa fechada, e voltar ao comportamento normal quando o Mac deixa de estar a
ser usado. É basicamente uma "Amphetamine/Caffeine" simplificada, feita por
nós, sem anúncios nem lixo.

> Contexto: nasceu de uma conversa sobre gerir sleep manualmente com
> `caffeinate` no terminal — decidimos que um toggle na toolbar é muito mais
> prático. Este projeto é irmão do **Clippy** (`~/Documents/Clippy`), outra
> app de menu bar já publicada, e deve seguir exatamente o mesmo playbook de
> build/assinatura/release para poupar tempo.

---

## 1. Objetivo e conceito

- Ícone fixo na menu bar (sem ícone na Dock — `LSUIElement`).
- Clique no ícone → menu com um **toggle** "Impedir sleep".
- Quando **ligado**: o Mac não dorme — nem por idle, nem ao fechar a tampa —
  enquanto o toggle estiver ativo.
- Quando **desligado**: comportamento normal do macOS (incluindo sleep ao
  fechar a tampa).
- Ícone muda de estado visualmente (ex.: ☕ cheio vs vazio, ou lua/sol) para
  ver de relance se está ativo.

### Mecanismo — dois níveis, propositadamente diferentes

Há dois mecanismos distintos no macOS para impedir sleep, e só um dos dois
sobrevive a fechar a tampa:

1. **IOKit power assertion** (`kIOPMAssertionTypeNoIdleSleep`, o que o
   `caffeinate -i` usa por baixo) — impede *idle sleep*, mas **não** impede o
   sleep por fechar a tampa (clamshell). É por processo, não precisa de
   privilégios admin.
2. **`pmset -a disablesleep 1`** — mexe a um nível mais baixo do power
   management e **ignora mesmo o lid-close**. É o mecanismo que apps tipo
   Amphetamine usam para "keep system awake with display closed", **sem**
   precisar de ecrã externo nem de estar ligado à corrente. A pegadinha: é
   uma definição de sistema, por isso **exige privilégios de admin**
   (`sudo`), ao contrário da assertion do IOKit.

Para o caso de uso do Tiago (deixar o Claude Code a trabalhar de tampa
fechada), o mecanismo **2 é o que interessa**. O 1 sozinho não resolve —
serve só para impedir sleep com a tampa aberta (ex. enquanto vê algo sem
mexer no rato).

**Como lidar com os privilégios de admin — duas opções de implementação:**

- **v1 (mais simples, arrancar por aqui)**: cada toggle corre
  `osascript -e 'do shell script "pmset -a disablesleep 1" with administrator privileges'`
  (ou `2`→`0` para desligar). Isto mostra o prompt nativo de password/Touch ID
  do macOS de cada vez que se liga/desliga. Funciona logo, zero setup extra,
  mas é chato ter de autenticar sempre.
- **v1.1 (melhor UX, iterar depois)**: instalar um **helper tool
  privilegiado** uma única vez (via `SMAppService` no macOS 13+, ou o
  `SMJobBless` mais antigo), aprovado uma vez nas Definições do sistema.
  Depois disso, os toggles seguintes já não pedem password — é o que o
  Amphetamine faz. Mais trabalho de engenharia (assinar o helper, entry no
  `Info.plist`/`launchd.plist`, IPC entre a app e o helper via XPC), por isso
  fica para uma iteração depois do MVP funcionar com `osascript`.

## 2. Funcionalidades

### MVP
- [ ] Menu bar icon com `NSStatusItem`, sem Dock icon.
- [ ] Toggle on/off que cria/liberta uma **IOKit power assertion**
      (`IOPMAssertionCreateWithName` com
      `kIOPMAssertionTypeNoIdleSleep` — preferível a invocar `caffeinate` via
      `Process`, é a forma nativa e mais leve).
- [ ] Ícone muda consoante o estado (ativo/inativo).
- [ ] Menu simples: toggle, "Iniciar no login", "Definições…", "Sair".
- [ ] Ao sair da app ou ao desligar o Mac, a assertion é sempre libertada
      (nunca deixar o Mac "preso" em não-sleep por engano).
- [ ] Estado do toggle **não** persiste entre relançamentos por defeito —
      arranca sempre desligado (segurança: evitar bateria a esvaziar da
      próxima vez que abrir o Mac sem se lembrar que ficou ligado).

### Nice-to-have (v1.1+)
- [ ] Auto-desligar o toggle ao fim de N horas (proteção contra esquecimento
      — ex. default 8h, configurável nas Definições).
- [ ] Deteção de ecrã externo + corrente, e aviso quando o utilizador liga o
      toggle sem essas condições ("isto não vai evitar sleep com a tampa
      fechada, a não ser que ligues um ecrã externo").
- [ ] Atalho global para toggle rápido (reutilizar `HotKey.swift` do Clippy).
- [ ] Mostrar tempo restante / "ativo há Xh" no menu.
- [ ] Widget/indicador de bateria vs corrente no menu.

## 3. Arquitetura técnica

Estrutura de ficheiros (mirror do Clippy):

```
Sources/Sleepy/
  main.swift              — entry point (menu-bar app)
  AppDelegate.swift        — NSStatusItem, menu, lifecycle
  SleepController.swift    — wrapper da IOKit power assertion (core da app)
  SettingsWindow.swift     — definições (auto-desligar, launch at login)
  Updater.swift             — copiar do Clippy, adaptar repo/nome
  UpdateController.swift    — copiar do Clippy, adaptar repo/nome
```

`SleepController.swift` (núcleo) — v1 usando `pmset -a disablesleep`, que é
o mecanismo que realmente sobrevive à tampa fechada (ver secção 1):

```swift
import Foundation

final class SleepController {
    static let shared = SleepController()
    private(set) var isActive = false

    /// Corre `pmset -a disablesleep <0|1>` elevado, via AppleScript
    /// (prompt nativo de password/Touch ID). Ver plano v1.1 para trocar
    /// isto por um helper privilegiado sem prompt repetido.
    private func setDisableSleep(_ on: Bool) -> Bool {
        let value = on ? "1" : "0"
        let script = "do shell script \"pmset -a disablesleep \(value)\" with administrator privileges"
        var error: NSDictionary?
        let applescript = NSAppleScript(source: script)
        applescript?.executeAndReturnError(&error)
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
}
```

Notas importantes:
- Garantir `disable()` é chamado em `applicationWillTerminate` para nunca
  deixar o Mac preso em `disablesleep=1` se a app fechar/crashar sem o
  utilizador desligar o toggle primeiro.
- Também vale a pena correr `pmset -a disablesleep 0` no arranque da app
  (defensivo), caso tenha ficado ligado de uma sessão anterior que crashou.
- Cada chamada a `enable()`/`disable()` vai mostrar o prompt de admin do
  macOS (Touch ID ou password) — é esperado na v1, documentar isso no
  README/onboarding para o utilizador não estranhar.

## 4. Bundle & identidade

- Nome: **Sleepy**
- Bundle ID: `com.tiagof.sleepy`
- `Package.swift` — copiar o do Clippy e trocar `name: "Clippy"` →
  `"Sleepy"`, mesmo `.macOS(.v14)`.
- `Info.plist` — copiar o do Clippy, ajustar `CFBundleName`,
  `CFBundleDisplayName`, `CFBundleIdentifier`, `CFBundleExecutable`,
  `CFBundleIconFile`, manter `LSUIElement = true` (sem Dock icon) e
  `CFBundleShortVersionString` a começar em `1.0.0`.

## 5. Assinatura e build (copiar do Clippy, adaptar nomes)

O Clippy já resolveu isto — replicar tal e qual, só trocando "Clippy" por
"Sleepy" em todo o lado:

- **`setup-signing.sh`** — cria um certificado self-signed estável
  ("Sleepy Self Signed") numa keychain dedicada
  (`~/Library/Keychains/sleepy-signing.keychain-db`). Corre uma vez; garante
  que a assinatura (e por isso permissões do sistema, se vierem a ser
  precisas) sobrevive a recompilações.
- **`build.sh`** — compila release (`swift build -c release`), monta o
  `.app` bundle (`Contents/MacOS`, `Contents/Resources`), copia
  `Info.plist` + ícone, assina com a identidade estável, instala em
  `/Applications` e relança.
- **`make-dmg.sh`** — produz `Sleepy.dmg` (para download/instalação) e
  `Sleepy.zip` (para o auto-updater, preserva bundle+assinatura via `ditto`).

Estes três scripts do Clippy podem ser copiados quase 1:1 — só find/replace
de "Clippy" → "Sleepy" e dos nomes de keychain/identity.

## 6. Ícone

- Design simples: algo tipo ☕/lua a fechar-se, ou um switch estilizado.
  Pode reaproveitar o processo do Clippy: `make-icon.swift` gera o iconset
  programaticamente, depois `iconutil -c icns Sleepy.iconset -o Sleepy.icns`.

## 7. Auto-update (copiar do Clippy)

- **`Updater.swift`** — copiar do Clippy tal e qual, só mudar:
  - `repo = "itsjustiago/Sleepy"` (criar o repo GitHub primeiro)
  - nome do asset zip: `"Sleepy.zip"`
  - env var de debug: `SLEEPY_DEBUG_VERSION` em vez de `CLIPPY_DEBUG_VERSION`
- **`UpdateController.swift`** — copiar tal e qual, trocar strings em
  português ("A transferir a Sleepy…" etc.), caminho do log
  (`Sleepy/update.log`), nome do processo a verificar
  (`Sleepy.app/Contents/MacOS/Sleepy`), e a env var de debug a limpar no
  script de swap.
- Mecanismo: verifica a última release do GitHub via API
  (`api.github.com/repos/.../releases/latest`), compara versões, e se há
  update mais recente, descarrega o `.zip`, substitui o bundle em
  `/Applications` com um script bash que espera o processo antigo morrer,
  faz `ditto` do novo bundle, remove quarentena (`xattr -dr
  com.apple.quarantine`), regista no LaunchServices e reabre.
- Ativar por defeito (`autoCheckUpdates = true`), com toggle nas Definições
  para desligar.

## 8. README (seguir a estrutura do Clippy)

Secções a incluir, pela mesma ordem que funcionou bem no Clippy:

1. Título curto + tagline de uma linha + emoji do ícone.
2. **⬇️ Install** — link direto para o `.dmg` da última release no GitHub,
   passos: abrir dmg → arrastar para Applications → primeiro launch precisa
   de **System Settings → Privacy & Security → Open Anyway** (porque não é
   notarizado pela Apple, é self-signed). Explicar que só pede uma vez.
3. **Features** — lista curta em bullets.
4. Tabela de atalhos/menu (se aplicável).
5. **Updates** — como funciona o auto-update, o que aparece no menu quando
   há novidade.
6. **O aviso "unidentified developer"** — explicar porquê (self-signed, sem
   conta paga de developer Apple) e que não há nada de errado.
7. **Build from source** — `./build.sh` cobre tudo, requisitos (macOS 14+,
   Command Line Tools).
8. **Releasing a new version** — checklist (ver secção 10 abaixo).
9. **Project layout** — árvore de ficheiros com descrição de uma linha cada.
10. **Notes** — comportamentos a saber (ex. onde ficam os dados guardados).

## 9. Licença

O Clippy **não tem ficheiro LICENSE** — foi uma lacuna. Para o Sleepy,
adicionar um `LICENSE` logo no início (recomendo **MIT**, é o que faz
sentido para uma ferramenta open-source pequena tipo esta). Vale a pena
depois voltar ao Clippy e adicionar lá também.

## 10. Checklist de release (igual ao Clippy)

1. Bump `CFBundleShortVersionString` (e `CFBundleVersion`) no `Info.plist`.
2. `./build.sh && ./make-dmg.sh`
3. `gh release create vX.Y.Z Sleepy.dmg Sleepy.zip --title "Sleepy X.Y.Z" --notes "…"`
4. Confirmar que os dois assets (`.dmg` e `.zip`) estão na release — o dmg é
   para quem instala de novo, o zip é o que o auto-updater das cópias já
   instaladas vai buscar.

## 11. Ordem de trabalho sugerida para o próximo chat

1. `swift package init` / copiar `Package.swift` do Clippy ajustado.
2. Criar `Info.plist` ajustado.
3. Implementar `SleepController.swift` (core da lógica, secção 3).
4. Implementar `AppDelegate.swift` com `NSStatusItem` + menu + toggle a
   chamar `SleepController.shared.enable()/disable()`.
5. Testar manualmente: ligar toggle, `pmset -g assertions` no terminal para
   confirmar que a assertion `NoIdleSleep` está ativa; desligar e confirmar
   que desaparece.
6. Copiar `setup-signing.sh`, `build.sh`, `make-dmg.sh` do Clippy, find/replace
   de nomes.
7. Criar ícone.
8. `./build.sh` → testar a app instalada em `/Applications`.
9. Criar repo GitHub `itsjustiago/Sleepy`, adicionar `LICENSE` (MIT).
10. Copiar e adaptar `Updater.swift` + `UpdateController.swift`.
11. Escrever `README.md` seguindo a secção 8.
12. `./make-dmg.sh`, primeira `gh release create v1.0.0 …`.
13. (Opcional) Implementar nice-to-haves da secção 2.

---

## Referência rápida — o que já existe no Clippy para copiar

| Ficheiro | Caminho no Clippy | O que faz |
|---|---|---|
| `Package.swift` | `~/Documents/Clippy/Package.swift` | Manifest do executable target |
| `Info.plist` | `~/Documents/Clippy/Info.plist` | Bundle metadata, `LSUIElement` |
| `setup-signing.sh` | `~/Documents/Clippy/setup-signing.sh` | Cria certificado self-signed estável |
| `build.sh` | `~/Documents/Clippy/build.sh` | Compila, assina, instala, relança |
| `make-dmg.sh` | `~/Documents/Clippy/make-dmg.sh` | Gera `.dmg` + `.zip` de release |
| `make-icon.swift` | `~/Documents/Clippy/make-icon.swift` | Gera iconset programaticamente |
| `Sources/Clippy/Updater.swift` | idem | Check de release via GitHub API |
| `Sources/Clippy/UpdateController.swift` | idem | Download + swap + relaunch automático |
| `README.md` | `~/Documents/Clippy/README.md` | Estrutura de referência para o README novo |

Basta abrir estes ficheiros no próximo chat e dizer "usa isto como base,
troca Clippy por Sleepy" — não é preciso reexplicar o processo todo.
