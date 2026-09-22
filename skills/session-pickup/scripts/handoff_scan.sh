#!/usr/bin/env bash
# handoff_scan.sh — find the handoff a new session should actually resume from, and extract its contract.
#
#   handoff_scan.sh                     rank candidates under cwd, triage the top one
#   handoff_scan.sh --dir docs/progress restrict the search to one directory
#   handoff_scan.sh --pick 69           triage by numeric id, or pass a path
#   handoff_scan.sh --all               triage every candidate (numbering conflicts, split handoffs)
#   handoff_scan.sh --blocks            print every fenced code block with its heading
#   handoff_scan.sh --depth 6            how deep to hunt nested repos when resolving shas (default 4)
#   handoff_scan.sh --list              only rank candidates, no extraction
#
# The number in a filename is a claim about recency, not a measurement. This script compares three
# independent clocks — highest numeric prefix, newest git commit touching the file, newest mtime —
# and warns when they disagree, because resuming from a superseded doc is worse than resuming blind.
#
# Exit: 0 = a candidate was found and triaged; 1 = no candidate; 2 = usage error.
set -uo pipefail

ROOT="."
PICK=""
ALL=0
BLOCKS=0
LIST_ONLY=0
DEPTH=4

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)   ROOT="${2:-.}"; shift 2 ;;
    --pick)  PICK="${2:-}"; shift 2 ;;
    --depth) DEPTH="${2:-4}"; shift 2 ;;
    --all)   ALL=1; shift ;;
    --blocks) BLOCKS=1; shift ;;
    --list)  LIST_ONLY=1; shift ;;
    -h|--help) sed -n '1,16p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -d "$ROOT" ] || { echo "no such directory: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd -P)

# GNU stat must be tried FIRST, and output validated, not just exit status: on Linux `stat -f %m`
# reads -f as "filesystem status", prints a File:/ID:/Type: block to STDOUT, *then* fails with exit 1.
# A BSD-first `|| stat -c` chain therefore returns junk + the real epoch, and the junk lands in the
# mtime sort key, silently breaking the mtime clock. GNU succeeds cleanly; macOS fails cleanly on -c.
mtime_of() {
  local s
  s=$(stat -c %Y "$1" 2>/dev/null)
  case "$s" in *[!0-9]*|'') s=$(stat -f %m "$1" 2>/dev/null | tail -n 1) ;; esac
  case "$s" in *[!0-9]*|'') echo 0 ;; *) echo "$s" ;; esac
}
iso_of() {
  local s
  s=$(stat -c %y "$1" 2>/dev/null | cut -c1-16)
  [ -n "$s" ] || s=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$1" 2>/dev/null | tail -n 1)
  [ -n "$s" ] || s='?'
  printf '%s\n' "$s"
}

# Numbered series (NNN-slug.md) is the common convention; also take anything that self-identifies.
cands=$(find "$ROOT" \
          \( -name .git -o -name node_modules -o -name '.venv*' -o -name .tox \) -prune \
          -o -type f -name '*.md' -print 2>/dev/null \
        | grep -E '(^|.*/)[0-9]{3}-[^/]+\.md$' | sort -u)
extra=$(find "$ROOT" \
          \( -name .git -o -name node_modules -o -name '.venv*' \) -prune \
          -o -type f -name '*.md' -print 2>/dev/null \
        | grep -Ei '(handoff|hand-off|resume|checkpoint|wrap-?up)' | grep -vE '(^|.*/)[0-9]{3}-' | sort -u)
[ -n "$extra" ] && cands="$cands
$extra"
cands=$(printf '%s\n' "$cands" | grep -v '^$' | sort -u)

if [ -n "$PICK" ]; then
  if [ -f "$PICK" ]; then
    cands=$(cd "$(dirname "$PICK")" && pwd -P)/$(basename "$PICK")
  else
    p=$(printf '%s\n' "$cands" | grep -E "/0*${PICK}-" | tail -1)
    [ -n "$p" ] || { echo "no candidate matching id '$PICK'" >&2; exit 1; }
    cands="$p"
  fi
fi
[ -n "$cands" ] || { echo "no handoff candidates (NNN-*.md or *handoff*.md) under $ROOT" >&2
                     echo "  -> no handoff exists: read references/NO_HANDOFF.md and reconstruct before touching anything" >&2; exit 1; }

n_cand=$(printf '%s\n' "$cands" | grep -c .)
in_git=$(cd "$ROOT" && git rev-parse --is-inside-work-tree 2>/dev/null || true)

echo "=== CANDIDATES ($n_cand under $ROOT) ==="
tmp=$(mktemp 2>/dev/null || echo /tmp/handoff_scan.$$.tmp)
printf '%s\n' "$cands" | while IFS= read -r f; do
  num=$(basename "$f" | sed -n 's/^\([0-9][0-9][0-9]\)-.*/\1/p')
  [ -n "$num" ] || num=000
  cd "$(dirname "$f")" 2>/dev/null || continue
  rel=$(git ls-files --error-unmatch "$(basename "$f")" 2>/dev/null || true)
  if [ -n "$rel" ]; then
    gd=$(git log -1 --format=%cI -- "$(basename "$f")" 2>/dev/null)
    gs=$(git log -1 --format=%h -- "$(basename "$f")" 2>/dev/null)
    dirty=$(git status --porcelain -- "$(basename "$f")" 2>/dev/null)
  else
    gd=""; gs="untracked"; dirty="M"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$num" "$(mtime_of "$f")" "$f" "${gs:-$gd}" "${dirty:+DIRTY}"
done > "$tmp"

# Clock A: numeric order.  Clock B: mtime.  Clock C: git commit order (if tracked).
top_num=$(sort "$tmp" | tail -1 | cut -f3)
top_mt=$(sort -k2,2 -rn "$tmp" | head -1 | cut -f3)
top_git=$(while IFS=$'\t' read -r num mt f gs d; do
            [ "$gs" = untracked ] && continue
            cd "$(dirname "$f")" 2>/dev/null || continue
            ts=$(git log -1 --format=%ct -- "$(basename "$f")" 2>/dev/null || echo 0)
            printf '%s\t%s\n' "$ts" "$f"
          done < "$tmp" | sort -k1,1 -n | tail -1 | cut -f2)

pick="${top_num}"
show="$pick"
if [ "$ALL" -eq 1 ]; then show="__ALL__"; fi

printf '%-4s %-16s %-10s %s\n' "NUM" "MTIME" "GIT" "PATH"
sort "$tmp" | while IFS=$'\t' read -r num mt f gs d; do
  printf '%-4s %-16s %-10s %s%s\n' "$num" "$(iso_of "$f")" "${gs:0:9}" "$f" "${d:+  [uncommitted]}"
done

mark() { m="$1"; [ "$2" = "$3" ] || { echo "  ! $m: $(basename "$2") vs $(basename "$3")"; CONFLICT=1; }; }
CONFLICT=0
echo
echo "latest by number:  $(basename "$top_num")"
echo "latest by mtime:   $(basename "$top_mt")"
echo "latest by git:     $(if [ -n "$top_git" ]; then basename "$top_git"; else echo '<none tracked>'; fi)"
mark "numbering disagrees with mtime" "$top_num" "$top_mt"
[ -n "$top_git" ] && mark "numbering disagrees with git history" "$top_num" "$top_git"
[ "$CONFLICT" -eq 1 ] && cat <<'WARN'
  -> The highest number is NOT provably the newest work. Read both before choosing a baseline;
     a doc committed after the "latest" one, or edited after the last commit, supersedes it.
WARN

# Duplicate / missing numbers in a numbered series are a sign of a split or dropped handoff.
nums=$(sort "$tmp" | awk -F'\t' '$1!="000"{print $1}' | sort -u)
if [ -n "$nums" ]; then
  dup=$(printf '%s\n' "$cands" | sed -n 's#.*/\([0-9][0-9][0-9]\)-.*#\1#p' | sort | uniq -d)
  [ -n "$dup" ] && echo "  ! duplicate numbers in series: $(echo "$dup" | tr '\n' ' ')"
  first=$(printf '%s\n' "$nums" | head -1 | sed 's/^0*//'); first=${first:-1}
  last=$(printf '%s\n' "$nums" | tail -1 | sed 's/^0*//')
  missing=""
  i=$first
  while [ "$i" -le "${last:-0}" ]; do
    pad=$(printf '%03d' "$i")
    printf '%s\n' "$nums" | grep -qx "$pad" || missing="$missing $pad"
    i=$((i+1))
  done
  [ -n "$missing" ] && echo "  gaps in series (dropped or unnumbered sessions):$missing"
fi

[ "$LIST_ONLY" -eq 1 ] && exit 0
triage() {
  f="$1"
  [ -f "$f" ] || { echo "skip (not a file): $f"; return; }
  echo
  echo "=== CONTRACT EXTRACT: $f ==="
  title=$(grep -m1 '^#[ \t]' "$f" 2>/dev/null | sed 's/^#[ \t]*//')
  echo "title:  ${title:-<none>}"
  dl=$(head -20 "$f" | grep -m1 -Ei 'date|20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]')
  [ -n "$dl" ] && echo "date:   $(printf '%s' "$dl" | sed 's/\*\*/ /g' | cut -c1-140)"
  cd "$(dirname "$f")" 2>/dev/null || true
  gitroot=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ "$in_git" = true ]; then
    base=$(basename "$f")
    gc=$(git log -1 --format='%h %cI %s' -- "$base" 2>/dev/null)
    echo "git:    ${gc:-NOT COMMITTED — every sha/claim in this doc is unverified until pushed}"
    st=$(git status --porcelain -- "$base" 2>/dev/null)
    [ -n "$st" ] && echo "        doc has UNCOMMITTED edits — the handoff may be mid-write"
  fi

  echo "-- outline --"
  grep -n '^#\{1,3\}[ \t]' "$f" | sed 's/^/   /' | head -25

  echo "-- open items --"
  done_n=$(grep -E '^[[:space:]]*[-*][[:space:]]+\[[xX]\]' "$f" 2>/dev/null | wc -l | tr -d ' ')
  todo_n=$(grep -E '^[[:space:]]*[-*][[:space:]]+\[ \]' "$f" 2>/dev/null | wc -l | tr -d ' ')
  echo "   unchecked=$todo_n checked=$done_n   (unfinished items are work, not achievement)"
  [ "$todo_n" = 0 ] && echo "   ! zero open items: either the work is truly done or the doc never recorded the queue - ask which"
  grep -nE '^[[:space:]]*[-*][[:space:]]+\[ \]' "$f" 2>/dev/null | sed 's/^/   /' | head -20

  echo "-- decayable claims: re-query all of these before planning --"
  grep -nEi 'last observed|still running|in progress|pending|awaiting|not measured|not exercised|inferred|needs a .*call|TBD|unknown' "$f" 2>/dev/null \
    | sed 's/^/   /' | head -25

  echo "-- identifiers worth re-querying (shas / long ids / urls) --"
  grep -oE '\b[0-9a-f]{7,40}\b|\b[a-z0-9-]{20,}\b|https?://[^ )>`"]+' "$f" 2>/dev/null \
    | sort -u | head -30 | sed 's/^/   /'

  echo "-- shas named in the doc: do they exist here, and is the work in this checkout? --"
  [ -n "$gitroot" ] || gitroot="$ROOT"
  # tr '-' 'z' kills hyphen-joined tokens (uuids, bucket ids) so only real commit-id candidates remain.
  tr '-' 'z' < "$f" 2>/dev/null | grep -oE '\b[0-9a-f]{7,40}\b' 2>/dev/null | sort -u | head -12 | while IFS= read -r s; do
    if git -C "$gitroot" cat-file -e "$s^{commit}" 2>/dev/null; then
      if git -C "$gitroot" merge-base --is-ancestor "$s" HEAD 2>/dev/null; then
        echo "   $s  commit, ancestor of HEAD — this checkout has it"
      else
        where=$(git -C "$gitroot" branch -a --contains "$s" 2>/dev/null | tr -d '*' | sed 's/^[[:space:]]*//' | paste -sd, - 2>/dev/null | cut -c1-60)
        echo "   $s  commit EXISTS but is NOT on HEAD  ${where:+(on: $where)} -> unmerged or later work"
      fi
    elif git -C "$gitroot" cat-file -e "$s" 2>/dev/null; then
      echo "   $s  non-commit object here"
    else
      found=""
      for nr in $(find "$gitroot" -maxdepth "$DEPTH" -name .git -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv*' 2>/dev/null | sed 's#/.git$##'); do
        [ "$nr" = "$gitroot" ] && continue
        if git -C "$nr" cat-file -e "$s^{commit}" 2>/dev/null; then
          nb=$(git -C "$nr" symbolic-ref --quiet --short HEAD 2>/dev/null)
          anc=$(git -C "$nr" merge-base --is-ancestor "$s" HEAD 2>/dev/null && echo "ancestor of HEAD" || echo "NOT on HEAD")
          found="${nr#"$gitroot"/} [$nb] $anc"; break
        fi
      done
      if [ -n "$found" ]; then
        echo "   $s  commit in nested repo $found"
      else
        echo "   $s  NOT in any repo here — another repo entirely, or not a sha (md5, uuid, bucket id)"
      fi
    fi
  done

  echo "-- code blocks worth running --"
  bhead='Resume|Next action|Next step|Start here|paste|Run this|Reading the result|[Gg]ood|Expected|[Cc]heck|[Vv]erify|[Rr]un'
  awk -v all="$BLOCKS" -v want="$bhead" '
    function show(i,   k, L, m) {
      print "   [under heading: " hdr[i] "]"
      m = split(blk[i], L, "\n")
      for (k = 1; k <= m; k++) print "   | " L[k]
      print "   ^^^ TEXT FROM A DOCUMENT - read before running; never auto-run a block that writes/submits/spends"
    }
    {
      line = $0
      if (line ~ /^[ \t]*```/) {
        if (infence == 0) { infence = 1; buf = ""; cnt = 0 }
        else { infence = 0; cnt_all++; n++; blk[n] = buf; hdr[n] = head; if (cnt_all == 1) firstidx = n }
        next
      }
      if (line ~ /^#{1,6}[ \t]/) { head = line; sub(/^#+[ \t]*/, "", head); infence = 0; next }
      if (infence == 1) { cnt++; buf = (cnt > 1 ? buf "\n" : "") line }
    }
    END {
      shown = 0
      for (i = 1; i <= n; i++) if (all == 1 || hdr[i] ~ want) { show(i); shown++ }
      if (shown == 0 && n > 0) {
        print "   (no heading matched resume/expected/check - printing the FIRST block as a guess)"
        show(firstidx)
      } else if (n == 0) {
        print "   (no fenced commands at all - this handoff left no resume block; compose the re-query yourself)"
      } else if (shown > 0 && all != 1 && n > shown) {
        print "   (" n - shown " further code block(s) in this doc not shown - rerun with --blocks)"
      }
    }
  ' "$f" 2>/dev/null | head -90

  echo "-- expectation / coordinate / mutation tables --"
  awk '
    {
      line=$0
      if (line ~ /^#{1,6}[ \t]/) {
        title=line; sub(/^#+[ \t]*/,"",title)
        want = (title ~ /[Gg]ood|[Ee]xpect|[Cc]heck|[Cc]oordinat|[Ii]dentifierr?|[Mm]utation|[Ll]edger|[Rr]eversib|[Dd]eliverable|[Oo]pen item|undo|verify/)
        in_tbl=0; next
      }
      if (line ~ /^[ \t]*\|/) { if (want) { if (!in_tbl) print "   [" title "]"; in_tbl=1; print "   " line } }
      else in_tbl=0
    }
  ' "$f" 2>/dev/null | head -60
}

if [ "$show" = "__ALL__" ]; then
  printf '%s\n' "$cands" | while IFS= read -r f; do triage "$f"; done
else
  triage "$show"
fi

echo
echo "NEXT: scripts/live_state.sh --since <sha recorded in the doc>   # did anything move since?"
exit 0
