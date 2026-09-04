#!/usr/bin/env bash
# Gemeinsame, deterministische Hilfen fuer Kontext- und Output-Dateien.
set -uo pipefail

agent_sha256_file() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

agent_redact() {
  awk '
    BEGIN { in_key=0 }
    /-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----/ {
      if (!in_key) print "[REDACTED: private key]"
      in_key=1
      next
    }
    in_key && /-----END ([A-Z ]+ )?PRIVATE KEY-----/ { in_key=0; next }
    in_key { next }
    {
      lower=tolower($0)
      if (lower ~ /\.agent-runs([\/`[:space:]]|$)/ || lower ~ /\.env([.\/`[:space:]:]|$)/) {
        print "[REDACTED: excluded path]"
        next
      }
      if (lower ~ /(password|passwd|access[_-]?token|refresh[_-]?token|api[_-]?key|client[_-]?secret|private[_-]?key|authorization)[[:space:]]*[:=]/ ||
          $0 ~ /AKIA[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z]/ ||
          $0 ~ /(ghp_|github_pat_|sk_live_|sk_test_)[A-Za-z0-9_-]+/ ||
          $0 ~ /:\/\/[^[:space:]\/:]+:[^[:space:]@]+@/) {
        print "[REDACTED: secret-like line]"
        next
      }
      print
    }
  '
}

agent_truncate_blocks() {
  input=$1
  limit=$2
  label=$3
  case "$limit" in ''|*[!0-9]*) return 1 ;; esac
  [ "$limit" -gt 0 ] || return 0
  LC_ALL=C awk -v max="$limit" -v label="$label" '
    function emit_block() {
      if (block == "" || stopped) { block=""; return }
      if (used + length(block) + length(marker) <= max) {
        printf "%s", block
        used += length(block)
      } else stopped=1
      block=""
    }
    BEGIN {
      marker="\n[GEKUERZT: Abschnitt " label " ueberschreitet sein Zeichenlimit]\n"
      used=0; stopped=0; in_frontmatter=0; frontmatter_done=0
    }
    NR == 1 && $0 == "---" { in_frontmatter=1; frontmatter=$0 "\n"; next }
    in_frontmatter {
      frontmatter=frontmatter $0 "\n"
      if ($0 == "---") {
        in_frontmatter=0; frontmatter_done=1
        if (length(frontmatter) + length(marker) <= max) {
          printf "%s", frontmatter
          used=length(frontmatter)
        } else stopped=1
      }
      next
    }
    stopped { next }
    {
      block=block $0 "\n"
      if ($0 == "") emit_block()
    }
    END {
      emit_block()
      if (stopped && used + length(marker) <= max) printf "%s", marker
    }
  ' "$input"
}

agent_copy_mode() {
  source_file=$1
  target_file=$2
  mode=$(stat -f '%Lp' "$source_file" 2>/dev/null || stat -c '%a' "$source_file" 2>/dev/null) || return 0
  chmod "$mode" "$target_file"
}

agent_atomic_append_line() (
  file=$1
  line=$2
  dir=$(dirname -- "$file")
  base=$(basename -- "$file")
  lock="$dir/.${base}.lock"
  mkdir "$lock" 2>/dev/null || { echo "agent-common: $base wird bereits geschrieben" >&2; return 1; }
  tmp=$(mktemp "$dir/.${base}.tmp.XXXXXX") || { rmdir "$lock"; return 1; }
  cleanup_append() { rm -f "$tmp"; rmdir "$lock" 2>/dev/null || true; }
  trap cleanup_append EXIT HUP INT TERM
  cp "$file" "$tmp" || return 1
  printf '%s\n' "$line" >> "$tmp" || return 1
  agent_copy_mode "$file" "$tmp" || return 1
  mv -f "$tmp" "$file" || return 1
  trap - EXIT HUP INT TERM
  rmdir "$lock" 2>/dev/null || true
)
