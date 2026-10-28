#!/bin/bash
# Compila e monta "build/Uso Claude.app". Com --install, copia para /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Uso Claude.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/UsoClaude" "$APP/Contents/MacOS/UsoClaude"
cp "$BIN_DIR/UsoClaudeHook" "$APP/Contents/MacOS/uso-claude-hook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force -s - "$APP"
echo "App gerado em: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x UsoClaude 2>/dev/null || true
    # Troca por renomeação: o hook (uso-claude-hook) fica fora do ar só pelo instante entre os dois mv,
    # em vez de durante toda a cópia, o que evitaria erros de hook nas sessões abertas do Claude Code.
    DEST="/Applications/Uso Claude.app"
    rm -rf "$DEST.new" "$DEST.old"
    cp -R "$APP" "$DEST.new"
    [[ -d "$DEST" ]] && mv "$DEST" "$DEST.old"
    mv "$DEST.new" "$DEST"
    rm -rf "$DEST.old"
    echo "Instalado em: /Applications/Uso Claude.app"
fi
