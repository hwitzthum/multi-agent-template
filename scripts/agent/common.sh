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

agent_project_root() {
  start=${1:-.}
  start=$(CDPATH= cd -- "$start" 2>/dev/null && pwd -P) || return 1
  while [ "$start" != / ]; do
    if [ -f "$start/.agent/config.env" ] && [ -x "$start/scripts/validate-ledger.sh" ]; then
      printf '%s\n' "$start"
      return 0
    fi
    start=$(dirname -- "$start")
  done
  echo "agent-common: Projektwurzel wurde nicht gefunden" >&2
  return 1
}

agent_atomic_write() (
  destination=$1
  source_file=$2
  [ -f "$source_file" ] || return 1
  directory=$(dirname -- "$destination")
  base=$(basename -- "$destination")
  mkdir -p "$directory" || return 1
  tmp=$(mktemp "$directory/.${base}.tmp.XXXXXX") || return 1
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  cp "$source_file" "$tmp" || return 1
  if [ -f "$destination" ]; then agent_copy_mode "$destination" "$tmp" || return 1; fi
  mv -f "$tmp" "$destination" || return 1
  trap - EXIT HUP INT TERM
)

agent_acquire_lock() {
  lock_dir=$1
  label=${2:-ein Orchestrator-Lauf}
  if ! mkdir "$lock_dir" 2>/dev/null; then
    # Eine Sperre mit toter PID stammt von einem abgestuerzten Lauf (kill -9,
    # Stromausfall) und wuerde sonst jeden weiteren Start dauerhaft blockieren.
    # Ohne PID-Datei gilt die Sperre als gehalten (Inhaber schreibt sie gerade).
    stale_pid=$(sed -n '1p' "$lock_dir/pid" 2>/dev/null || true)
    case "$stale_pid" in
      ''|*[!0-9]*) ;;
      *)
        if ! kill -0 "$stale_pid" 2>/dev/null; then
          echo "agent-common: verwaiste Sperre von PID $stale_pid wird entfernt" >&2
          rm -f "$lock_dir/pid"
          rmdir "$lock_dir" 2>/dev/null || true
          mkdir "$lock_dir" 2>/dev/null && { printf '%s\n' "$$" > "$lock_dir/pid"; return 0; }
        fi ;;
    esac
    echo "agent-common: $label ist bereits aktiv" >&2
    return 1
  fi
  printf '%s\n' "$$" > "$lock_dir/pid"
}

agent_release_lock() {
  lock_dir=$1
  [ -d "$lock_dir" ] || return 0
  rm -f "$lock_dir/pid"
  rmdir "$lock_dir" 2>/dev/null || true
}

agent_run_with_timeout() {
  timeout_seconds=$1
  shift
  case "$timeout_seconds" in ''|*[!0-9]*|0) return 2 ;; esac
  perl -e '
    use strict; use warnings;
    my $timeout = shift @ARGV;
    my $pid = fork();
    die "fork failed" unless defined $pid;
    if ($pid == 0) { exec @ARGV; exit 127; }
    $SIG{ALRM} = sub {
      kill "TERM", $pid;
      select undef, undef, undef, 0.2;
      kill "KILL", $pid;
      waitpid($pid, 0);
      exit 124;
    };
    alarm $timeout;
    waitpid($pid, 0);
    alarm 0;
    my $status = $?;
    exit(($status & 127) ? 128 + ($status & 127) : $status >> 8);
  ' "$timeout_seconds" "$@"
}

agent_repo_manifest() {
  local project_dir destination file
  project_dir=$1
  destination=$2
  (
    cd "$project_dir" || exit 1
    find . -type f \
      ! -path './.git/*' \
      ! -path './.agent-runs/*' \
      ! -path './docs/state/current-run.md' \
      ! -path './docs/state/metrics.csv' \
      -print | LC_ALL=C sort | while IFS= read -r file; do
        case "$file" in *$'\n'*|*$'\r'*) echo "agent-common: Dateiname mit Zeilenumbruch ist unzulässig" >&2; exit 1 ;; esac
        printf '%s  %s\n' "$(shasum -a 256 "$file" | awk '{print $1}')" "${file#./}"
      done
  ) > "$destination"
}

agent_product_manifest() {
  local project_dir destination file
  project_dir=$1
  destination=$2
  (
    cd "$project_dir" || exit 1
    find . -type f \
      ! -path './.git/*' \
      ! -path './.agent-runs/*' \
      ! -path './.agent/*' \
      ! -path './.claude/*' \
      ! -path './docs/state/*' \
      ! -path './docs/tasks/*' \
      ! -path './docs/verification/*' \
      ! -path './docs/templates/*' \
      ! -path './scripts/agent/*' \
      ! -path './scripts/orchestrate.sh' \
      ! -path './scripts/route-task.sh' \
      ! -path './scripts/validate-ledger.sh' \
      ! -path './scripts/next-tasks.sh' \
      ! -path './scripts/state-summary.sh' \
      ! -path './scripts/bash-guard.sh' \
      ! -path './scripts/commit-gate.sh' \
      -print | LC_ALL=C sort | while IFS= read -r file; do
        printf '%s  %s\n' "$(shasum -a 256 "$file" | awk '{print $1}')" "${file#./}"
      done
  ) > "$destination"
}

agent_manifest_changes() {
  local before after
  before=$1
  after=$2
  awk '
    function path(line) { return substr(line, 67) }
    NR == FNR { old[path($0)]=substr($0,1,64); next }
    { name=path($0); current[name]=substr($0,1,64); if (!(name in old) || old[name] != current[name]) print name }
    END { for (name in old) if (!(name in current)) print name }
  ' "$before" "$after" | LC_ALL=C sort -u
}
