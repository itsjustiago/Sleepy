#!/bin/bash
# Compila, assina (com identidade estável) e instala o Sleepy em /Applications.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Sleepy Self Signed"
KEYCHAIN="$HOME/Library/Keychains/sleepy-signing.keychain-db"

# Garante o certificado estável — sem ele a assinatura mudaria a cada build.
if ! security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "▸ Certificado em falta — a criar…"
  ./setup-signing.sh
fi

echo "▸ A compilar (release)…"
swift build -c release

APP="Sleepy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/Sleepy" "$APP/Contents/MacOS/Sleepy"
cp "Info.plist" "$APP/Contents/Info.plist"
[ -f "Sleepy.icns" ] && cp "Sleepy.icns" "$APP/Contents/Resources/Sleepy.icns"

sign() {
  security unlock-keychain -p "sleepy-signing" "$KEYCHAIN" 2>/dev/null || true
  codesign --force --deep --sign "$IDENTITY" --keychain "$KEYCHAIN" "$1"
}

echo "▸ A assinar com '$IDENTITY'…"
sign "$APP"

# Instalar em /Applications e reiniciar
DEST="/Applications/Sleepy.app"
pkill -f "Sleepy.app/Contents/MacOS/Sleepy" 2>/dev/null || true
sleep 1
if rm -rf "$DEST" 2>/dev/null && cp -R "$APP" "$DEST" 2>/dev/null; then
  sign "$DEST"
  open "$DEST"
  echo "✓ Instalado, assinado e reiniciado: $DEST"
else
  echo "✓ Pronto: $APP  (copia para /Applications manualmente)"
  DEST="$APP"
fi

echo "  Requisito:"
codesign -d --requirements - "$DEST" 2>&1 | grep -i designated | sed 's/^/    /'
