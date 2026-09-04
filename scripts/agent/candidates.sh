#!/usr/bin/env bash
# Verwaltet zwei isolierte, vom selben Commit abgeleitete Kandidaten.
set -uo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$script_dir/common.sh"
. "$script_dir/ledger.sh"

usage() {
  echo "Verwendung: $0 init|capture|check-main|apply|rollback|cleanup --project-dir PFAD --run-dir PFAD [--candidate candidate-a|candidate-b] [--task-id ID]" >&2
  exit 2
}

command_name=${1:-}
[ -n "$command_name" ] || usage
shift
project_dir=''
run_dir=''
candidate=''
task_id=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) [ "$#" -ge 2 ] || usage; project_dir=$2; shift 2 ;;
    --run-dir) [ "$#" -ge 2 ] || usage; run_dir=$2; shift 2 ;;
    --candidate) [ "$#" -ge 2 ] || usage; candidate=$2; shift 2 ;;
    --task-id) [ "$#" -ge 2 ] || usage; task_id=$2; shift 2 ;;
    *) usage ;;
  esac
done

project_dir=$(CDPATH= cd -- "$project_dir" 2>/dev/null && pwd -P) || { echo "candidates: Projektpfad fehlt" >&2; exit 1; }
[ -d "$run_dir" ] || { echo "candidates: Laufpfad fehlt" >&2; exit 1; }
run_dir=$(CDPATH= cd -- "$run_dir" && pwd -P) || exit 1
case "$run_dir/" in "$project_dir/.agent-runs/"*) ;; *) echo "candidates: Laufpfad verlaesst .agent-runs" >&2; exit 1 ;; esac
candidates_dir="$run_dir/candidates"
base_file="$candidates_dir/base.commit"
main_manifest="$candidates_dir/main.manifest"

candidate_path() {
  case "$candidate" in candidate-a|candidate-b) ;; *) echo "candidates: unbekannter Kandidat '$candidate'" >&2; return 1 ;; esac
  printf '%s/%s/worktree\n' "$candidates_dir" "$candidate"
}

check_base() {
  [ -f "$base_file" ] || { echo "candidates: Basis-Commit fehlt" >&2; return 1; }
  base=$(sed -n '1p' "$base_file")
  case "$base" in *[!0-9a-f]*|'') echo "candidates: ungueltiger Basis-Commit" >&2; return 1 ;; esac
  git -C "$project_dir" cat-file -e "$base^{commit}" 2>/dev/null || { echo "candidates: Basis-Commit existiert nicht mehr" >&2; return 1; }
}

check_main() {
  check_base || return 1
  current="$candidates_dir/.main-current.manifest"
  agent_repo_manifest "$project_dir" "$current" || return 1
  if ! cmp -s "$main_manifest" "$current"; then
    rm -f "$current"
    echo "candidates: Hauptstand wurde seit Kandidatenstart extern veraendert" >&2
    return 1
  fi
  rm -f "$current"
  [ "$(git -C "$project_dir" rev-parse HEAD 2>/dev/null)" = "$base" ] || { echo "candidates: HEAD weicht vom Basis-Commit ab" >&2; return 1; }
}

case "$command_name" in
  init)
    git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1 || { echo "candidates: managed-fresh benoetigt ein Git-Repository" >&2; exit 1; }
    [ ! -e "$candidates_dir" ] || { echo "candidates: Kandidatenverzeichnis existiert bereits" >&2; exit 1; }
    mkdir -p "$candidates_dir/candidate-a" "$candidates_dir/candidate-b" || exit 1
    base=$(git -C "$project_dir" rev-parse HEAD 2>/dev/null) || { echo "candidates: managed-fresh benoetigt einen Basis-Commit" >&2; exit 1; }
    printf '%s\n' "$base" > "$base_file"
    agent_repo_manifest "$project_dir" "$main_manifest" || exit 1
    for name in candidate-a candidate-b; do
      path="$candidates_dir/$name/worktree"
      if ! git -C "$project_dir" worktree add --quiet --detach "$path" "$base"; then
        "$0" cleanup --project-dir "$project_dir" --run-dir "$run_dir" >/dev/null 2>&1 || true
        exit 1
      fi
    done
    # Der Fresh Worker erhaelt technisch keine kuratierten historischen Notes.
    printf '%s\n' '# Notizen' > "$candidates_dir/candidate-b/worktree/docs/state/notes.md"
    printf 'BASE_COMMIT=%s\nCANDIDATE_A=%s\nCANDIDATE_B=%s\n' "$base" \
      "$candidates_dir/candidate-a/worktree" "$candidates_dir/candidate-b/worktree"
    ;;
  capture)
    [ -n "$task_id" ] || usage
    case "$task_id" in *[!0-9]*|'') usage ;; esac
    check_base || exit 1
    worktree=$(candidate_path) || exit 1
    [ -d "$worktree" ] || { echo "candidates: Worktree fehlt" >&2; exit 1; }
    [ "$(git -C "$worktree" rev-parse HEAD 2>/dev/null)" = "$base" ] || { echo "candidates: Kandidat startet nicht vom Basis-Commit" >&2; exit 1; }
    task_file=$(ledger_task_path_by_id "$worktree/docs/tasks" "$task_id") || exit 1
    git -C "$worktree" add -N -- . >/dev/null 2>&1 || true
    changed_file="$candidates_dir/$candidate/changed-paths.txt"
    : > "$changed_file"
    while IFS= read -r -d '' changed; do
      case "$changed" in docs/state/notes.md) [ "$candidate" = candidate-b ] && continue ;; esac
      case "$changed" in .agent-runs/*|docs/state/*|docs/tasks/*|docs/verification/*) continue ;; esac
      "$script_dir/policy.sh" role-write worker-fresh "$changed" >/dev/null 2>&1 || { echo "candidates: verbotener Kandidatenpfad $changed" >&2; exit 1; }
      allowed=false
      while IFS= read -r permitted; do
        [ -n "$permitted" ] || continue
        permitted=${permitted%/}
        case "$changed" in "$permitted"|"$permitted"/*) allowed=true ;; esac
      done <<EOF
$(ledger_list "$task_file" touches 2>/dev/null || true)
EOF
      [ "$allowed" = true ] || { echo "candidates: Kandidatenpfad $changed liegt ausserhalb von touches" >&2; exit 1; }
      printf '%s\n' "$changed" >> "$changed_file"
    done < <(git -C "$worktree" diff --name-only -z HEAD --)
    LC_ALL=C sort -u "$changed_file" -o "$changed_file"
    patch="$candidates_dir/$candidate/candidate.patch"
    if [ -s "$changed_file" ]; then
      paths=()
      while IFS= read -r changed; do [ -n "$changed" ] && paths+=("$changed"); done < "$changed_file"
      git -C "$worktree" diff --binary --no-ext-diff HEAD -- "${paths[@]}" > "$patch" || exit 1
    else
      : > "$patch"
    fi
    shasum -a 256 "$patch" | awk '{print $1}' > "$candidates_dir/$candidate/patch.sha256"
    ;;
  check-main)
    check_main
    ;;
  apply|rollback)
    case "$candidate" in candidate-a|candidate-b) ;; *) echo "candidates: unbekannter Kandidat '$candidate'" >&2; exit 1 ;; esac
    check_base || exit 1
    patch="$candidates_dir/$candidate/candidate.patch"
    [ -f "$patch" ] || { echo "candidates: Kandidatenpatch fehlt" >&2; exit 1; }
    expected=$(sed -n '1p' "$candidates_dir/$candidate/patch.sha256" 2>/dev/null || true)
    actual=$(shasum -a 256 "$patch" | awk '{print $1}')
    [ -n "$expected" ] && [ "$expected" = "$actual" ] || { echo "candidates: Kandidatenpatch wurde veraendert" >&2; exit 1; }
    if [ "$command_name" = apply ]; then check_main || exit 1; fi
    if [ -s "$patch" ]; then
      if [ "$command_name" = apply ]; then
        git -C "$project_dir" apply --check "$patch" || exit 1
        git -C "$project_dir" apply "$patch" || exit 1
      else
        git -C "$project_dir" apply -R --check "$patch" || exit 1
        git -C "$project_dir" apply -R "$patch" || exit 1
      fi
    fi
    ;;
  cleanup)
    for name in candidate-a candidate-b; do
      path="$candidates_dir/$name/worktree"
      [ ! -d "$path" ] || git -C "$project_dir" worktree remove --force "$path" >/dev/null 2>&1 || true
    done
    git -C "$project_dir" worktree prune >/dev/null 2>&1 || true
    ;;
  *) usage ;;
esac
