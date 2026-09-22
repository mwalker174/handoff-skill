#!/usr/bin/env bash
# repo_state.sh — inventory every git repo under the current directory before writing a handoff.
#
#   repo_state.sh                 # inventory: branch, upstream, ahead/behind, dirty, last commit
#   repo_state.sh --push [branch] # additionally compare each repo's HEAD to its remote head
#   repo_state.sh --depth 5       # how deep to look for nested repos / submodules (default 4)
#
# Exit status is non-zero if any repo is dirty, ahead of its upstream, or (with --push) whose
# remote head does not match HEAD. "clean" for one repo is not a handoff-ready tree.
set -uo pipefail

MODE="status"
BRANCH=""
DEPTH=4
while [ $# -gt 0 ]; do
  case "$1" in
    --push)  MODE="push"; BRANCH="${2:-}"; case "${2:-}" in --*|"") shift ;; *) shift 2 ;; esac ;;
    --depth) DEPTH="${2:-4}"; shift 2 ;;
    -h|--help) sed -n '1,12p' "$0"; exit 0 ;;
    *) shift ;;
  esac
done

command -v git >/dev/null 2>&1 || { echo "git not found" >&2; exit 2; }
ROOT=$(pwd -P)
FAIL=0

# Repos: cwd plus any nested .git (dir or worktree/submodule file) under it.
repos="$ROOT"
nested=$(find "$ROOT" -maxdepth "$DEPTH" -name .git \
           -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null \
         | sed 's#/\.git$##' | grep -vxF "$ROOT" | sort)
[ -n "$nested" ] && repos="$repos
$nested"

report() {
  r="$1"
  cd "$r" 2>/dev/null || return 0
  rel="${r#$ROOT}"
  case "$rel" in ""|"/$ROOT") rel="." ;; /*) rel="${rel#/}" ;; esac
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD)
  up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)

  echo "── $rel   [$branch]"

  if [ -z "$up" ]; then
    echo "   upstream: NONE (branch was never pushed — 'clean' here means nothing)"
    FAIL=1
  else
    # rev-list --count prints "behind<TAB>ahead"; let the shell split on the tab.
    set -- $(git rev-list --left-right --count "$up...HEAD" 2>/dev/null)
    behind=${1:-?}; ahead=${2:-?}
    echo "   upstream: $up  behind=$behind ahead=$ahead"
    [ "${ahead:-0}" -gt 0 ] 2>/dev/null && { echo "   ! $ahead commit(s) not pushed"; FAIL=1; }
  fi

  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "   worktree: DIRTY"
    git status --porcelain | sed 's#^#     #' | head -15
    n=$(git status --porcelain | wc -l | tr -d ' ')
    [ "$n" -gt 15 ] && echo "     … $((n-15)) more"
    FAIL=1
  else
    echo "   worktree: clean"
  fi

  echo "   head:     $(git --no-pager log --oneline -1 2>/dev/null)"

  # Standing-instruction files that are symlinks: 'git add' on the link stages nothing.
  for f in AGENTS.md CLAUDE.md; do
    if [ -L "$f" ]; then
      tgt=$(readlink "$f")
      staged=$(git diff --cached --name-only 2>/dev/null | grep -xF "$tgt" || true)
      dirt=$(git status --porcelain -- "$f" "$tgt" 2>/dev/null | grep -v "^?? " || true)
      [ -n "$dirt" ] && echo "   note:     $f -> $tgt is a symlink; stage '$tgt' (staged=$([ -n "$staged" ] && echo yes || echo no))"
    fi
  done

  [ "$MODE" = "push" ] && verify_push "$r" "$branch"
}

verify_push() {
  r="$1"; branch="$2"
  cd "$r" || return 0
  lh=$(git rev-parse HEAD 2>/dev/null)
  rh=""; note=""
  if [ -n "$BRANCH" ] && [ "$BRANCH" != "$branch" ]; then branch="$BRANCH"; fi
  rh=$(GIT_TERMINAL_PROMPT=0 git ls-remote origin "refs/heads/$branch" 2>/dev/null | awk '{print $1}')
  if [ -z "$rh" ]; then
    rh=$(git rev-parse --quiet --verify "origin/$branch" 2>/dev/null) && note=" (fetched ref; remote not queried)"
  fi
  if [ -z "$rh" ]; then
    echo "   push:     CANNOT READ origin/$branch — do not report this repo as pushed"
    FAIL=1
  elif [ "$lh" = "$rh" ]; then
    echo "   push:     OK — origin/$branch = $(git rev-parse --short "$rh")$note"
  else
    echo "   push:     MISMATCH — local $(git rev-parse --short HEAD) != origin/$branch $(git rev-parse --short "$rh" 2>/dev/null)$note"
    FAIL=1
  fi
}

echo "repo inventory under $ROOT (depth $DEPTH)"
printf '%s\n' "$repos" | while IFS= read -r r; do report "$r"; echo; done

# The subshell above cannot set FAIL, so re-check independently.
cd "$ROOT" || exit 1
[ -n "$(git status --porcelain 2>/dev/null)" ] && FAIL=1
printf '%s\n' "$repos" | while IFS= read -r r; do
  cd "$r" 2>/dev/null || continue
  up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || up=""
  if [ -z "$up" ]; then echo "NEEDS"; exit 0; fi
  ahead=$(git rev-list --count "${up}..HEAD" 2>/dev/null || echo 0)
  [ "${ahead:-0}" -gt 0 ] 2>/dev/null && { echo "NEEDS"; exit 0; }
done | grep -q NEEDS && FAIL=1

if [ "$FAIL" -eq 0 ]; then
  echo "VERDICT: every repo inventoried above is clean and in sync with its upstream."
else
  echo "VERDICT: at least one repo is dirty, ahead, or unverified — not handoff-ready."
fi
exit "$FAIL"
