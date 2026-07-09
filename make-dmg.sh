#!/bin/bash
# Empacota a app: Sleepy.dmg (instalação a arrastar) + Sleepy.zip (para o auto-update).
set -euo pipefail
cd "$(dirname "$0")"

[ -d "Sleepy.app" ] || { echo "Sleepy.app não existe — corre ./build.sh primeiro."; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "Sleepy.app" "$STAGING/Sleepy.app"
ln -s /Applications "$STAGING/Applications"

rm -f Sleepy.dmg
hdiutil create -volname "Sleepy" -srcfolder "$STAGING" -ov -format UDZO -quiet Sleepy.dmg

# Zip usado pelo atualizador embutido (ditto preserva o bundle + assinatura).
rm -f Sleepy.zip
ditto -c -k --keepParent "Sleepy.app" Sleepy.zip

echo "✓ Sleepy.dmg + Sleepy.zip criados"
