#!/usr/bin/env bash
# live_state.sh — re-measure everything a handoff doc could have stale-ified. Never trust the doc for these.
#
#   live_state.sh                          inventory cwd + nested repos, remote heads, dirty state, env
#   live_state.sh --since b231291          also: what happened AFTER that commit (commits, files, mtimes)
#   live_state.sh --gate 'label|command'   run a project-specific probe (repeatable)
#   live_state.sh --gates FILE             read gates from a file, one 'label|command' per line (# = comment)
#   live_state.sh --depth 5                how deep to hunt for nested repos (default 4)
#   live_state.sh --dir PATH               run from this directory instead of cwd
#
# Why: a handoff records status at minute zero. Jobs moved, tokens died, someone else pushed, the tree
# changed. Every one of those is measurable in seconds and none of them is measurable from the doc.
#
# Exit: 0 = nothing diverged; 1 = something moved/failed/diverged (read the output, do not proceed blind).
set -uo pipefail

SINCE=""
DEPTH=4
GATES=""
ROOT=$(pwd -P)

while [ $# -gt 0 ]; do
  case "$1" in
    --since)  SINCE="${2:-}"; shift 2 ;;
    --gate)   GATES="${GATES}${GATES:+
}${2:-}"; shift 2 ;;
    --gates)  GATES="${GATES}${GATES:+
}$(grep -v '^[[:space:]]*#' "${2:-/dev/null}" 2>/dev/null)"; shift 2 ;;
    --depth)  DEPTH="${2:-4}"; shift 2 ;;
    --dir)    ROOT=$(cd "${2:-.}" && pwd -P); shift 2 ;;
    -h|--help) sed -n '1,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

FAIL=0
mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
when_of()  { date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?'; }

command -v git >/dev/null 2>&1 || { echo "git not found" >&2; exit 2; }
in_git=$(git rev-parse --is-inside-work-tree 2>/dev/null || true)
since_epoch=""
if [ -n "$SINCE" ]; then
  since_epoch=$(git log -1 --format=%ct "$SINCE" 2>/dev/null)
  [ -n "$since_epoch" ] || echo "note: --since '$SINCE' is not a resolvable revision here (may live in another repo)"
fi

echo "=== LOCAL CLOCK (untrusted: record it, do not let it overwrite a declared date) ==="
echo "   $(date -u '+%Y-%m-%d %H:%M:%SZ' 2>/dev/null)  local=$(date '+%Y-%m-%d %H:%M:%S%z')"

# ---------------------------------------------------------------- repos
repos="$ROOT"
nested=$(find "$ROOT" -maxdepth "$DEPTH" -name .git \
           -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv*' 2>/dev/null \
         | sed 's#/.git$##' | grep -vxF "$ROOT" | sort)
[ -n "$nested" ] && repos="$repos
$nested"

echo
echo "=== REPOS ($ROOT, depth $DEPTH) ==="
printf '%s\n' "$repos" | while IFS= read -r r; do
  cd "$r" 2>/dev/null || continue
  rel="${r#"$ROOT"}"; case "$rel" in "") rel="." ;; /*) rel="${rel#/}" ;; esac
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
  echo "-- $rel  [$branch]"
  if [ -z "$up" ]; then
    echo "   upstream: NONE"
  else
    set -- $(git rev-list --left-right --count "$up...HEAD" 2>/dev/null)
    echo "   upstream: $up behind=${1:-?} ahead=${2:-?}"
  fi
  echo "   head:     $(git --no-pager log -1 --format='%h %ci %s' 2>/dev/null | cut -c1-90)"

  # The doc may say 'pushed'. The only proof is the remote's own head.
  lh=$(git rev-parse HEAD 2>/dev/null)
  rh=$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true git ls-remote origin "refs/heads/$branch" 2>/dev/null | awk '{print $1}')
  if [ -z "$rh" ]; then
    rh=$(git rev-parse --quiet --verify "origin/$branch" 2>/dev/null) && echo "   remote:    origin/$branch = $(git rev-parse --short "$rh") (fetched ref, remote NOT contacted)" \
         || echo "   remote:    CANNOT READ origin/$branch — do not describe this repo as pushed"
  elif [ "$lh" = "$rh" ]; then
    echo "   remote:    origin/$branch = $(git rev-parse --short "$rh")  [matches HEAD]"
  else
    echo "   remote:    origin/$branch = $(git rev-parse --short "$rh")  [DIFFERS from HEAD $(git rev-parse --short HEAD)]"
    echo "            -> someone pushed since the handoff, or this box has unpushed work. Inspect BOTH before touching anything."
  fi

  # Work that landed after the handoff point changes the plan.
  if [ -n "$since_epoch" ] && [ -n "$lh" ]; then
    if git cat-file -e "$SINCE^{commit}" 2>/dev/null; then
      n=$(git rev-list --count "$SINCE..HEAD" 2>/dev/null || echo 0)
      echo "   since $SINCE: $n commit(s) on HEAD"
      [ "${n:-0}" -gt 0 ] 2>/dev/null && git --no-pager log --oneline "$SINCE..HEAD" | sed 's/^/       /' | head -10
    fi
  fi

  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    git status --porcelain | while IFS= read -r line; do
      p=$(printf '%s' "$line" | cut -c4- | sed 's/.* -> //')
      mt=$(mtime_of "$p"); how="untracked/unreadable"
      [ "$mt" != 0 ] && how=$(when_of "$mt")
      if [ -n "$since_epoch" ] && [ "$mt" != 0 ] && [ "$mt" -gt "$since_epoch" ]; then
        echo "   dirty: $line   ($how — AFTER the handoff point: new work, or a previous half-done pickup)"
      else
        echo "   dirty: $line   ($how)"
      fi
    done
    # Deliberate: never print 'clean' when something is dirty; unmentioned dirt is evidence, not noise.
  else
    echo "   worktree: clean"
  fi
  for f in AGENTS.md CLAUDE.md; do
    [ -L "$f" ] && echo "   note:     $f -> $(readlink "$f") (symlink: stage the target, not the link)"
  done
done

# Anything dirty at all -> non-zero, because the caller must reconcile it, not 'continue'.
cd "$ROOT" || exit 1
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo
  echo "   ! working tree is dirty — read the diff before assuming it is yours or trash"
  FAIL=1
fi
printf '%s\n' "$repos" | while IFS= read -r r; do
  cd "$r" 2>/dev/null || continue
  lh=$(git rev-parse HEAD 2>/dev/null); branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
  rh=$(GIT_TERMINAL_PROMPT=0 git ls-remote origin "refs/heads/$branch" 2>/dev/null | awk '{print $1}')
  [ -n "$rh" ] && [ "$lh" != "$rh" ] && { echo "DIVERGE"; exit 0; }
  [ -n "$(git status --porcelain 2>/dev/null)" ] && { echo "DIVERGE"; exit 0; }
done | grep -q DIVERGE && { echo "   ! a repo is dirty, or its remote head differs from HEAD"; FAIL=1; }

# ---------------------------------------------------------------- env drift
echo
echo "=== ENV / ARTIFACT DRIFT ==="
env_fail=0
[ -d .venv ] || [ -d venv ] || echo "   no .venv in cwd (if the project declares one, a bare 'python' will use the wrong interpreter)"
n_dangle=$(find "$ROOT" -maxdepth 3 -type l ! -exec test -e {} \; -print 2>/dev/null | head -10)
if [ -n "$n_dangle" ]; then
  echo "   DANGLING SYMLINKS (generated output moved or was never built):"
  printf '%s\n' "$n_dangle" | sed 's/^/     /'
  env_fail=1
fi
lock_old=""
for lf in package-lock.json yarn.lock pnpm-lock.yaml uv.lock poetry.lock requirements.txt; do
  [ -f "$lf" ] || continue
  inst=".venv/.stamp"; [ -d node_modules ] && inst="node_modules"
  [ -e "$inst" ] && [ "$(mtime_of "$lf")" -gt "$(mtime_of "$inst")" ] && lock_old="$lock_old $lf"
done
[ -n "$lock_old" ] && { echo "   lockfile(s) newer than the install marker:$lock_old — deps may be stale"; env_fail=1; }
[ "$env_fail" -eq 0 ] && echo "   no dangling links or obvious dep drift detected"

# Instructions that reference paths: catch docs that drifted from the tree.
# Deliberately narrow, or it drowns in noise: the token must be a slash-path ending in a file extension,
# whose first segment is a real directory here. That excludes directory shorthands (`wdl/`, `figures/`),
# GitHub slugs (`mwalker174/clarum-utils`), MIME types (`text/x-vcard`) and globs.
if [ "$in_git" = true ]; then
  tracked=$(git ls-files 2>/dev/null | awk -F/ '{print $NF}' | sort -u)
else
  tracked=""
fi
for ins in AGENTS.md CLAUDE.md README.md; do
  [ -f "$ins" ] || continue
  target=$ins
  [ -L "$ins" ] && target=$(readlink "$ins")
  miss=""; nmiss=0
  for tok in $(grep -oE '`[A-Za-z0-9_][A-Za-z0-9_./+-]{2,}`' "$target" 2>/dev/null | tr -d '`' | sort -u); do
    case "$tok" in *://*|*\'*|*\"*|*\**|*\{*|*\$*|*\\\\*) continue ;; esac   # urls, quotes, globs, templates
    case "$tok" in */*) : ;; *) continue ;; esac                            # must be path-like
    case "$tok" in */) continue ;; esac                                     # directory shorthand
    last=${tok##*/}
    printf '%s' "$last" | grep -qE '\.[A-Za-z][A-Za-z0-9]{0,5}$' || continue # must end in an extension
    first=${tok%%/*}
    [ -d "$first" ] || continue                                             # first segment must be real
    [ -e "$tok" ] && continue
    b=$(basename "$tok")
    [ -n "$tracked" ] && printf '%s\n' "$tracked" | grep -qx "$b" && continue  # shorthand for a deeper path
    miss="$miss $tok"; nmiss=$((nmiss+1))
    [ "$nmiss" -ge 8 ] && break
  done
  [ -n "$miss" ] && echo "   $ins names files absent from this checkout:$miss  (drift, or written on another box)"
done

# ---------------------------------------------------------------- project gates
if [ -n "$GATES" ]; then
  echo
  echo "=== PROJECT GATES (the cheap checks that otherwise fail loudly an hour later) ==="
  gtmp=$(mktemp 2>/dev/null || echo /tmp/live_state_gates.$$.tmp)
  printf '%s\n' "$GATES" | grep -v '^[[:space:]]*$' > "$gtmp"
  # Read from a file, not a pipe: a piped while-loop is a subshell and would lose FAIL.
  while IFS= read -r g; do
    label=${g%%|*}; cmd=${g#*|}
    if [ -z "$cmd" ] || [ "$cmd" = "$g" ]; then echo "   SKIP  [$label] (no command given)"; continue; fi
    otmp=$(mktemp 2>/dev/null || echo /tmp/live_state_out.$$.tmp)
    eval "$cmd" >"$otmp" 2>&1; st=$?
    if [ "$st" -eq 0 ]; then
      echo "   PASS  [$label]"
    else
      echo "   FAIL  [$label] (exit $st)"; tail -3 "$otmp" | sed 's/^/          /'; FAIL=1
    fi
    rm -f "$otmp"
  done < "$gtmp"
  rm -f "$gtmp"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "VERDICT: live state matches what a handoff would claim — nothing diverged, gates pass."
else
  echo "VERDICT: state moved or something failed. Reconcile BEFORE choosing the next action;"
  echo "         the highest-value next step may no longer be the one the handoff doc proposed."
fi
exit "$FAIL"
