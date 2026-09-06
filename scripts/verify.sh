#!/usr/bin/env bash
# verify.sh — DIE einzige Prüfung dieses Repositoriums.
# Vertrag: exit 0 <=> alles bestanden. Letzte Zeile IMMER "verify: GREEN"
# oder "verify: RED".
# --quick = tests/run.sh --fast (ohne e2e); ohne Option läuft die ganze Suite.
#
# Ein Projekt, das aus diesem Kit entsteht, ersetzt dieses Skript durch seine
# eigene Prüfung; dann prüft es das Produkt statt das Kit.
set -uo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1

suite_args=''
case "${1:-}" in
  -h|--help)
    echo "Verwendung: $0 [--quick | --deep]"
    echo "Einzige globale Projektprüfung; letzte Zeile ist verify: GREEN oder verify: RED."
    echo "--quick lässt die e2e-Stufe der Testsuite weg."
    exit 0 ;;
  --quick) suite_args=--fast ;;
  ''|--deep) ;;
  *) echo "Verwendung: $0 [--quick | --deep]" >&2; exit 2 ;;
esac

# Rekursionsbremse: tests/run.sh setzt AGENT_TEST_SUITE, und die Suite prüft
# unter anderem den Commit-Hook, der wiederum verify.sh --quick startet.
if [ "${AGENT_TEST_SUITE:-}" = 1 ]; then
  echo "ok: (Suite läuft bereits — keine zweite Runde)"
  echo "verify: GREEN"
  exit 0
fi

if [ -n "$suite_args" ]; then
  "$root/tests/run.sh" "$suite_args"
else
  "$root/tests/run.sh"
fi
status=$?

if [ "$status" -ne 0 ]; then
  echo 'FAILED: tests'
  echo 'verify: RED'
  exit 1
fi
echo 'ok: tests'
echo 'verify: GREEN'
