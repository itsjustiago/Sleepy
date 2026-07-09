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

## Notes

- Cada toggle liga/desliga `pmset -a disablesleep`, que exige privilégios de
  admin — por isso o prompt do macOS aparece a cada mudança de estado. Um
  helper privilegiado sem prompt repetido está planeado para uma v1.1 (ver
  `plan.md`).
- O estado é sempre reposto a "sleep normal" ao sair da app ou no arranque,
  para nunca deixar o Mac preso em não-sleep.
