#!/usr/bin/env bash
# next-tasks.sh — listet Tasks, deren depends_on alle status: done sind.
# PLATZHALTER: Der Initializer liefert die echte Frontmatter-Auswertung.
set -uo pipefail
ls docs/tasks/*.md >/dev/null 2>&1 || { echo "keine Tasks (Initialisierung noch nicht ausgeführt)"; exit 0; }
ls docs/tasks/*.md
