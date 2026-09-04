#!/usr/bin/env bash
# autoformat.sh — PostToolUse-Hook (Edit|Write). Formatiert die bearbeitete
# Datei. Still bei Erfolg. Liest den Dateipfad aus dem Hook-JSON auf stdin
# (.tool_input.file_path); alternativ als Argument.
# Der Initializer ergänzt die Formatter (prettier etc.), sobald der Stack feststeht.
# Bewusst KEIN npx: npx lädt einen fehlenden Formatter ungefragt aus dem Netz —
# bei jeder Dateiänderung, unsichtbar und langsam. Das lokale Binary aufrufen;
# fehlt es, wird eben nicht formatiert.
set -uo pipefail
# Hooks laufen im aktuellen Verzeichnis (ändert sich mit `cd`); der Formatter
# liegt aber unter der Projektwurzel — also zuerst dorthin.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}" || exit 0
f="${1:-}"
if [ -z "$f" ] && [ ! -t 0 ]; then
  f=$(sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
fi
[ -n "$f" ] || exit 0
case "$f" in
  *.ts|*.tsx|*.js|*.mjs|*.astro|*.css|*.json)
    [ -x node_modules/.bin/prettier ] \
      && node_modules/.bin/prettier --write "$f" >/dev/null 2>&1 || true ;;
esac
exit 0
