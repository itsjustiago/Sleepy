# Sleepy 🌙

Impede o Mac de dormir — mesmo com a tampa fechada — com um toggle na menu bar.
Uma "Amphetamine/Caffeine" simplificada, feita por nós, sem anúncios nem lixo.

## ⬇️ Install

**[⬇️ Descarregar Sleepy (.dmg)](https://github.com/itsjustiago/Sleepy/releases/latest/download/Sleepy.dmg)**

1. Abre o **Sleepy.dmg** descarregado e arrasta o **Sleepy.app** para **Applications**.
2. **Primeiro arranque** — uma vez só, porque não vem de uma conta paga de developer Apple:
   - Faz duplo-clique no Sleepy. O macOS diz que *"não foi possível verificar"* → clica **Concluído**.
   - Abre **Definições do Sistema → Privacidade e Segurança**, desce até **Segurança** e
     clica **Abrir Mesmo Assim** na linha do Sleepy. Confirma com Touch ID / password.
   - O Sleepy abre — e nunca mais pergunta nesse Mac.
3. Clica no ícone da lua na menu bar e liga o toggle **"Impedir sleep"** (pede
   password/Touch ID — é o mecanismo `pmset -a disablesleep`, que é o único que
   sobrevive a fechar a tampa).

## Features

- **Toggle "Impedir sleep"** na menu bar — impede o sleep do Mac mesmo com a
  tampa fechada, sem precisar de ecrã externo nem estar ligado à corrente.
  Trava os dois caminhos: o sleep por **inatividade** (IOKit power assertion)
  e o sleep por **fechar a tampa** (`pmset -a disablesleep`).
- **Ícone dinâmico** — sol quando ativo, lua quando o comportamento é o normal.
- Nunca fica "preso": ao sair da app ou reiniciá-la, o estado é sempre
  reposto para o normal.
- **Não persiste entre relançamentos** — arranca sempre desligado, para não
  esvaziar a bateria por esquecimento.
- **Iniciar no login** e **Definições…** no menu.
- **Update check** — o Sleepy verifica o GitHub por novas versões e oferece
  atualização com um clique no menu.
- Sem ícone na Dock.

## Updates

O Sleepy verifica o GitHub por uma release mais recente no arranque (toggle
nas Definições). Quando há uma disponível, a menu bar mostra **⤓ Atualizar
para vX.Y.Z…**. Clica e o Sleepy **descarrega, instala e reinicia-se** —
sem arrastar, sem Terminal.

## O aviso "unidentified developer"

O Sleepy é assinado com um certificado self-signed e não está notarizado pela
Apple (isso exige uma conta paga de developer). Por isso o **primeiro**
arranque precisa de **Abrir Mesmo Assim** nas Definições; depois disso abre
normalmente. Não há nada de errado.

## Build from source

```bash
./build.sh    # compila, assina, instala em /Applications e relança
```

O primeiro run cria um certificado self-signed (`./setup-signing.sh`) numa
keychain dedicada. Dá à app uma **identidade estável** entre recompilações.

Requisitos: macOS 14+ e as Command Line Tools (`swift`).

- Regenerar o ícone: `swift make-icon.swift && iconutil -c icns Sleepy.iconset -o Sleepy.icns`
- Empacotar o DMG: `./make-dmg.sh`

### Releasing a new version

1. Bump `CFBundleShortVersionString` (e `CFBundleVersion`) no `Info.plist`.
2. `./build.sh && ./make-dmg.sh`
3. `gh release create vX.Y.Z Sleepy.dmg Sleepy.zip --title "Sleepy X.Y.Z" --notes "…"`

Os dois assets importam: **Sleepy.dmg** para quem instala de novo,
**Sleepy.zip** para o auto-updater das cópias já instaladas.

## Project layout

```
Sources/Sleepy/
  main.swift              — entry point (menu-bar app)
  AppDelegate.swift        — NSStatusItem, menu, lifecycle
  SleepController.swift    — impede sleep via pmset -a disablesleep
  SettingsWindow.swift     — definições (login, auto-update)
  Updater.swift            — check de release via GitHub API
  UpdateController.swift   — download + swap + relaunch automático
```

## Não pedir password a cada toggle

Por defeito, cada toggle corre `pmset -a disablesleep` com privilégios de admin,
por isso o macOS pede Touch ID/password de cada vez. Para eliminar isso, ativa
**"Não pedir password a cada toggle"** nas Definições (ou *Ativar acesso sem
password…* no menu): pede admin **uma vez** e instala uma regra `sudoers`
mínima em `/etc/sudoers.d/sleepy` que permite ao teu utilizador correr **apenas**
`pmset -a disablesleep 0|1` sem password. Sem wildcards, mais nada — não é
superfície de escalada de privilégios, e é validada com `visudo` antes de ser
instalada. Desmarca a opção para a remover.

Optámos por isto em vez de um helper privilegiado (SMAppService/SMJobBless):
é muito menos código e funciona bem com a assinatura self-signed, que dá
problemas com o matching de code-signing exigido pelo SMJobBless.

## Como funciona

São precisos **dois** mecanismos, porque cobrem coisas diferentes:

| Mecanismo | Trava | Precisa de admin? |
|---|---|---|
| IOKit `PreventUserIdleSystemSleep` | Sleep por inatividade (o timer `sleep` do `pmset -g`) | Não |
| `pmset -a disablesleep 1` | Sleep ao fechar a tampa | Sim |

O `disablesleep` sozinho **não** trava o idle sleep, por isso o Sleepy segura
os dois enquanto o toggle está ligado. Para confirmar, com o toggle ligado:

```bash
pmset -g assertions | grep Sleepy   # deve listar PreventUserIdleSystemSleep
pmset -g | grep SleepDisabled       # deve mostrar 1
```

## Como sobrevive a relaunches

O Sleepy usa **três** mecanismos ao mesmo tempo, porque cobrem coisas diferentes:

| Mecanismo | Trava | Bateria? | Precisa de admin |
|---|---|---|---|
| `pmset -a disablesleep 1` | sleep ao fechar a tampa | sim | sim |
| IOKit `PreventUserIdleSystemSleep` (`caffeinate -i`) | sleep por inatividade | sim | não |
| IOKit `PreventSystemSleep` (`caffeinate -s`) | maintenance / dark-wake sleep | só na corrente | não |

As duas assertions IOKit em conjunto são o equivalente a `caffeinate -s -i`. A
`PreventSystemSleep` (a que apps como o NoSleep usam) é a mais forte, mas num
portátil só é respeitada na corrente — por isso seguramos também a
`PreventUserIdleSystemSleep`, que funciona em bateria.

O estado **persiste**: se a app crashar, for recompilada, ou se o auto-updater
a reiniciar, ela volta a armar os dois no arranque. Sem isso a proteção caía em
silêncio a meio de uma tarefa longa — exatamente o cenário para que existe.

Como contrapeso, há **auto-desligar** ao fim de N horas (default 8h,
configurável nas Definições, ou "Nunca"). Sair da app pelo menu desliga sempre.

## Notes

- Enquanto o acesso sem password não estiver instalado, cada toggle mostra o
  prompt de admin do macOS — é esperado.
- No arranque o Sleepy nunca mostra prompts: só usa o caminho sem password. O
  ícone reflete o `SleepDisabled` real do sistema, não o que a app julga ter
  feito.
- O sleep do **display** é deixado em paz de propósito: de tampa fechada,
  manter o ecrã aceso só gastaria bateria.
- Debug: `SLEEPY_DEBUG_ENABLE=1` liga o toggle no arranque, sem clicar no menu.
