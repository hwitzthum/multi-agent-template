#!/usr/bin/env bash
# verify.sh — DIE einzige Prüfung. Stufen gemäss docs/profil/technik.md.
# Vertrag: exit 0 <=> alles bestanden. Letzte Zeile IMMER "verify: GREEN"
# oder "verify: RED". Pro Stufe "ok: <stufe>" bzw. "FAILED: <stufe>" + tail.
# --quick = nur schnelle Stufen (Commit-Hook).
#
# PLATZHALTER: Der Initializer ersetzt dieses Skript durch die echte
# Prüfung, sobald Stack und Skelett existieren. Bis dahin keine Stufen.
set -uo pipefail
echo "ok: (keine Stufen — Initialisierung ausstehend)"
echo "verify: GREEN"
exit 0
