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

# --- Manifeste und Snapshot -------------------------------------------------
# Ein Manifest ist eine sortierte Liste "<feld>  <pfad>". Git liefert Namen und
# Hashes in je einer Prozessgruppe; .gitignore gilt. Feldwerte:
#   <hash>            Blob-Hash einer normalen Datei. Der Inhalt liegt damit als
#                     Snapshot im Git-Objektspeicher und laesst sich
#                     zurueckschreiben.
#   exec:<hash>       dasselbe mit gesetztem Ausfuehrungsbit
#   symlink:<hash>    Hash des Linkziels, nie des Inhalts dahinter
#   missing           im Index, aber nicht im Arbeitsbaum (geloescht)
#   ignored           von .gitignore erfasst: nur der Name. Ein neu angelegter
#                     ignorierter Pfad wie .env wird dadurch sichtbar, sein
#                     Inhalt aber nie gelesen.

agent_manifest_include_repo() {
  case "$1" in
    .agent-runs|.agent-runs/*) return 1 ;;
  esac
  return 0
}

agent_manifest_include_product() {
  agent_manifest_include_repo "$1" || return 1
  case "$1" in
    .git/*|.agent|.agent/*|.claude|.claude/*) return 1 ;;
    docs/state|docs/state/*|docs/tasks|docs/tasks/*) return 1 ;;
    docs/verification|docs/verification/*|docs/templates|docs/templates/*) return 1 ;;
    scripts/agent|scripts/agent/*) return 1 ;;
    scripts/orchestrate.sh|scripts/validate-ledger.sh) return 1 ;;
    scripts/next-tasks.sh|scripts/state-summary.sh|scripts/bash-guard.sh|scripts/commit-gate.sh) return 1 ;;
  esac
  return 0
}

# Das Produkt aus Sicht eines Tasks: alles ausser Ledger, Laufstand und den
# Git-Steuerdateien. Kit-Skripte und Vorlagen zaehlen mit, weil ein Task sie
# aendern koennen soll.
agent_manifest_include_candidate() {
  case "$1" in
    .git/*|.agent-runs|.agent-runs/*) return 1 ;;
    docs/state|docs/state/*|docs/tasks|docs/tasks/*|docs/verification|docs/verification/*) return 1 ;;
  esac
  return 0
}

# Sammelt alle Manifestzeilen eines Projekts auf der Standardausgabe. Laeuft in
# einer Subshell, damit das Arbeitsverzeichnis des Aufrufers unberuehrt bleibt.
agent_manifest_collect() (
  project_dir=$1
  filter=$2
  work=$3
  cd "$project_dir" || return 1
  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "agent-common: kein Git-Repository: $project_dir" >&2
    return 1
  }
  : > "$work/paths"
  : > "$work/labels"
  : > "$work/modes"
  : > "$work/plain"

  # Ein Eintrag: <name im Manifest> <tatsaechlicher Pfad>. Beide unterscheiden
  # sich nur bei den Git-Steuerdateien, die ausserhalb des Arbeitsbaums liegen.
  record() {
    entry=$1
    target=$2
    case "$entry" in *$'\n'*|*$'\r'*)
      echo "agent-common: Dateiname mit Zeilenumbruch ist unzulaessig" >&2
      return 1 ;;
    esac
    "$filter" "${entry%/}" || return 0
    if [ -L "$target" ]; then
      printf 'symlink:%s  %s\n' "$(readlink "$target" | git hash-object -w --stdin)" "$entry" >> "$work/plain"
    elif [ -f "$target" ]; then
      if [ -x "$target" ]; then printf 'exec\n' >> "$work/modes"; else printf 'plain\n' >> "$work/modes"; fi
      printf '%s\n' "$target" >> "$work/paths"
      printf '%s\n' "$entry" >> "$work/labels"
    elif [ -e "$target" ]; then
      return 0
    else
      printf 'missing  %s\n' "$entry" >> "$work/plain"
    fi
  }

  while IFS= read -r -d '' entry; do
    record "$entry" "$entry" || return 1
  done < <(git ls-files -z -co --exclude-per-directory=.gitignore)

  # Ignorierte Pfade nur mit Namen; ein vollstaendig ignorierter Ordner zaehlt
  # als ein Eintrag, damit node_modules weder gelesen noch aufgezaehlt wird.
  while IFS= read -r -d '' entry; do
    case "$entry" in *$'\n'*|*$'\r'*) echo "agent-common: Dateiname mit Zeilenumbruch ist unzulaessig" >&2; return 1 ;; esac
    "$filter" "${entry%/}" || continue
    printf 'ignored  %s\n' "$entry" >> "$work/plain"
  done < <(git ls-files -z -oi --directory --exclude-per-directory=.gitignore)

  # Steuerdateien von Git selbst: sie liegen ausserhalb des Arbeitsbaums, aendern
  # aber das Verhalten des Projekts und gehoeren deshalb ins Manifest.
  if "$filter" .git/config; then
    for control in config info/exclude; do
      resolved=$(git rev-parse --git-path "$control") || return 1
      [ -f "$resolved" ] || continue
      record ".git/$control" "$resolved" || return 1
    done
    hooks_dir=$(git rev-parse --git-path hooks) || return 1
    if [ -d "$hooks_dir" ]; then
      for hook in "$hooks_dir"/*; do
        [ -f "$hook" ] || continue
        record ".git/hooks/$(basename -- "$hook")" "$hook" || return 1
      done
    fi
  fi

  if [ -s "$work/paths" ]; then
    git hash-object -w --stdin-paths < "$work/paths" > "$work/hashes" || return 1
    awk '
      FILENAME == hashes_file { hash[FNR]=$0; count_hashes=FNR; next }
      FILENAME == modes_file { mode[FNR]=$0; count_modes=FNR; next }
      { print (mode[FNR] == "exec" ? "exec:" : "") hash[FNR] "  " $0; count_labels=FNR }
      END { if (count_hashes != count_labels || count_modes != count_labels) exit 1 }
    ' hashes_file="$work/hashes" modes_file="$work/modes" \
      "$work/hashes" "$work/modes" "$work/labels" >> "$work/plain" || {
      echo "agent-common: Manifest konnte Hashes und Pfade nicht paaren" >&2
      return 1
    }
  fi
  LC_ALL=C sort "$work/plain"
)

agent_manifest_build() {
  local project_dir=$1 destination=$2 filter=$3 work result
  work=$(mktemp -d "${TMPDIR:-/tmp}/agent-manifest.XXXXXX") || return 1
  agent_manifest_collect "$project_dir" "$filter" "$work" > "$destination"
  result=$?
  rm -rf "$work"
  return "$result"
}

agent_repo_manifest() {
  agent_manifest_build "$1" "$2" agent_manifest_include_repo
}

agent_product_manifest() {
  agent_manifest_build "$1" "$2" agent_manifest_include_product
}

# Liefert das Feld eines Pfades aus einem Manifest; Exit 1, wenn es ihn nicht kennt.
agent_manifest_field() {
  awk -v want="$2" '
    { separator=index($0, "  "); if (separator == 0) next }
    substr($0, separator + 2) == want { print substr($0, 1, separator - 1); found=1; exit }
    END { if (!found) exit 1 }
  ' "$1"
}

# Setzt Pfade auf den Stand des Manifests zurueck. Bekannte Inhalte kommen aus
# dem Git-Objektspeicher; Pfade, die das Manifest nicht kennt, sind nach dem
# Snapshot entstanden und wandern in die Quarantaene statt geloescht zu werden.
agent_snapshot_restore() {
  local project_dir=$1 manifest=$2 quarantine=$3 path field target result=0
  shift 3
  [ -f "$manifest" ] || { echo "agent-common: Manifest fehlt: $manifest" >&2; return 1; }
  project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || return 1
  for path in "$@"; do
    case "$path" in ''|/*|..|../*|*/../*|*/..) echo "agent-common: unzulaessiger Pfad: $path" >&2; result=1; continue ;; esac
    target="$project_dir/$path"
    field=$(agent_manifest_field "$manifest" "$path") || field=''
    case "$field" in
      '')
        mkdir -p "$quarantine/$(dirname -- "$path")" || { result=1; continue; }
        if [ -e "$target" ] || [ -L "$target" ]; then
          mv -f "$target" "$quarantine/$path" || result=1
        fi ;;
      ignored)
        : ;;
      missing)
        rm -f "$target" || result=1 ;;
      symlink:*)
        mkdir -p "$(dirname -- "$target")" || { result=1; continue; }
        rm -f "$target"
        ln -s "$(git -C "$project_dir" cat-file blob "${field#symlink:}")" "$target" || result=1 ;;
      *)
        mkdir -p "$(dirname -- "$target")" || { result=1; continue; }
        rm -f "$target"
        case "$field" in
          exec:*) git -C "$project_dir" cat-file blob "${field#exec:}" > "$target" && chmod +x "$target" || result=1 ;;
          *) git -C "$project_dir" cat-file blob "$field" > "$target" || result=1 ;;
        esac ;;
    esac
  done
  return "$result"
}

agent_manifest_changes() {
  local before after
  before=$1
  after=$2
  awk '
    function path(line) { return substr(line, index(line, "  ") + 2) }
    function field(line) { return substr(line, 1, index(line, "  ") - 1) }
    NR == FNR { old[path($0)]=field($0); next }
    { name=path($0); current[name]=field($0); if (!(name in old) || old[name] != current[name]) print name }
    END { for (name in old) if (!(name in current)) print name }
  ' "$before" "$after" | LC_ALL=C sort -u
}
