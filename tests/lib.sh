#!/usr/bin/env bash
# tests/lib.sh — die einzigen Zusicherungen der Suite. Testdateien laden diese
# Datei und definieren selbst keine Helfer. Bei einem Fehlschlag wird die
# Ausgabe des geprüften Befehls mitgedruckt, damit die Ursache ohne zweiten
# Lauf sichtbar ist.
#
# Verwendung:
#   . "$tests_dir/lib.sh"
#   begin_suite "verify-gate"
#   expect_success "grüner Task" run_verify
#   finish_suite

suite_name=unbenannt
suite_passed=0
suite_failed=0

begin_suite() {
  suite_name=$1
  suite_passed=0
  suite_failed=0
}

ok() { suite_passed=$((suite_passed + 1)); }

bad() {
  suite_failed=$((suite_failed + 1))
  echo "FAILED: $1" >&2
}

expect_success() {
  local name=$1 output status
  shift
  output=$("$@" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    ok
  else
    printf '%s\n' "$output" >&2
    bad "$name"
  fi
}

expect_failure() {
  local name=$1 output status
  shift
  output=$("$@" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    ok
  else
    printf '%s\n' "$output" >&2
    bad "$name"
  fi
}

expect_output() {
  local name=$1 expected=$2 actual
  shift 2
  if ! actual=$("$@" 2>&1); then
    printf '%s\n' "$actual" >&2
    bad "$name"
    return 0
  fi
  if [ "$actual" = "$expected" ]; then
    ok
  else
    bad "$name"
    echo "  erwartet: $expected" >&2
    echo "  erhalten: $actual" >&2
  fi
}

expect_contains() {
  local name=$1 needle=$2 output
  shift 2
  if ! output=$("$@" 2>&1); then
    printf '%s\n' "$output" >&2
    bad "$name"
    return 0
  fi
  case "$output" in
    *"$needle"*) ok ;;
    *) bad "$name"; echo "  fehlt in der Ausgabe: $needle" >&2 ;;
  esac
}

assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then ok; else bad "$name (erwartet '$expected', erhalten '$actual')"; fi
}

assert_file() {
  local name=$1 file=$2
  if [ -f "$file" ]; then ok; else bad "$name (Datei fehlt: $file)"; fi
}

assert_file_has() {
  local name=$1 file=$2 needle=$3
  if grep -Fq -- "$needle" "$file" 2>/dev/null; then ok; else bad "$name (fehlt in $file: $needle)"; fi
}

assert_file_lacks() {
  local name=$1 file=$2 needle=$3
  if grep -Fq -- "$needle" "$file" 2>/dev/null; then bad "$name (unerwartet in $file: $needle)"; else ok; fi
}

finish_suite() {
  if [ "$((suite_passed + suite_failed))" -eq 0 ]; then
    echo "$suite_name: RED (keine Zusicherung ausgeführt)" >&2
    exit 1
  fi
  if [ "$suite_failed" -ne 0 ]; then
    echo "$suite_name: RED ($suite_failed fehlgeschlagen, $suite_passed bestanden)" >&2
    exit 1
  fi
  echo "$suite_name: GREEN ($suite_passed bestanden)"
}
