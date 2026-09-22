# No handoff doc — reconstruct a baseline, and do not destroy anything

Absence of a handoff is common and is **not** permission to start clean. The tree, the reflog, the
filesystem, and the job queue all remember what nobody wrote down. Reconstruct, quarantine, then write the
baseline you owe.

## 1. Prove the absence before acting on it

The handoff often exists somewhere other than where you looked:

```bash
scripts/handoff_scan.sh --dir docs ; scripts/handoff_scan.sh --dir .     # wider net
git log --oneline -20 -- docs                                          # did the doc land in a later commit?
git log --all --oneline --diff-filter=A -- '*handoff*' 'docs/progress/*' # on another branch
git stash list ; git worktree list ; git branch -a --no-merged           # parked elsewhere
git log --oneline -10                                                  # "checkpoint: session handoff" as a commit message
```

Also: another machine, another agent's session log, a ticket/PM thread, or a deleted-file history
(`git log --all --oneline --diff-filter=D -- docs/`). If a handoff turns up **after** you started, say so —
it may contradict your reconstruction.

## 2. Reconstruction ladder — cheapest and highest-signal first

| # | Source | Command | What it proves |
|---|---|---|---|
| 1 | Live jobs | project's status command (see standing instructions) | The only state that is *currently* true. Query first. |
| 2 | Git log, all refs | `git --no-pager log --oneline --all -30 --date=iso --pretty='%h %ad %d %s'` | What was intended last, and on which branch |
| 3 | Reflog | `git --no-pager reflog -25` | Checkouts, resets, rebases, and the head from *before* a wipe — invisible to `log` |
| 4 | Dirty tree | `git status --porcelain -uall` then `git --no-pager diff --stat` and the real diff | Half-finished work in progress, with paths |
| 5 | Stashes / worktrees | `git stash list --date=iso`; `git worktree list` | Deliberately parked work (someone meant to come back) |
| 6 | Remote | `git ls-remote origin`; `git fetch --dry-run` | A collaborator or another box already moved things |
| 7 | Filesystem | `find src docs -type f -mtime -3 -print`; `ls -lt` on generated-output and scratch dirs | Edits that never got committed — often the actual last act |
| 8 | Logs | newest files in `artifacts/logs`, CI output, test output | The last thing that ran, and how it ended |
| 9 | Shell history | `tail -40 ~/.zsh_history` / `~/.bash_history` (`fc -l` for the live shell) | The single best "what was I doing 20 minutes ago" signal |
| 10 | Standing instructions + TODOs | `AGENTS.md`/`CLAUDE.md`, `docs/*TODO*`, open checklist items | Declared intent, which is not the same as state — check which |

Read the project's standing instructions early. They name the live-state command, the credential
mechanism, and the gotchas; those are the parts of a handoff that outlive the doc even when nobody wrote one.

**Label everything reconstructed:** *measured now* vs *reconstructed from `<evidence>`*. Never let a
reconstruction quietly become a recorded fact — that is exactly the fabrication the next session cannot detect.

## 3. Quarantine, never discard

The ways a pickup destroys someone's work all look like tidying:

```
git checkout -- .      git restore .       git clean -fd      git reset --hard
git stash drop         rm -rf <dir>         re-running a script that overwrites output
```

If the changes are not yours, or you cannot yet tell, **snapshot before you touch**:

```bash
d="scratch/pickup-$(date -u +%Y%m%d-%H%M)"        # or the project's scratch/ convention
mkdir -p "$d"
git status --porcelain -uall              > "$d/status.txt"
git --no-pager diff --binary              > "$d/tracked.patch"       # restorable with git apply
git --no-pager log --oneline -5 --all     > "$d/gitlog.txt"
git --no-pager reflog -25                 > "$d/reflog.txt"
git ls-files --others --exclude-standard  > "$d/untracked.txt"
# copy (do not move) small untracked files; list — do not copy — anything large
```

That directory is now a reversible record, and you may work around the changes, or move them to a
`wip/pickup-<date>` branch. Deleting them needs the user to confirm **naming the paths** — and keep the
patch anyway. If a script's default output path would overwrite something found dirty, change the output
path rather than "regenerating" it.

## 4. Write the baseline you owe

Once reconstructed, open the project's next numbered doc (or `session-handoff`'s template if there is no
convention) titled something like `NNN-pickup-no-handoff-reconstructed-baseline.md`, containing: what you
measured, what you reconstructed and from which evidence, what you quarantined and where the patch lives,
and the open items you can defend. This is the handoff that should have existed — and it stops two
consecutive sessions from running blind.

## 5. Special cases

- **Handoff exists but is old** (days/weeks): every decayable claim is stale by definition; live jobs have
  aged out of retention (`UNCHECKABLE`), and the *decisions* may have been overtaken by an answer you have
  to go find. Trust gotchas, re-measure everything else.
- **Handoff on another branch / machine:** re-verify its shas exist here (`git cat-file -e <sha>^{commit}`);
  if they do not, the doc describes work you do not have — pull or fetch before planning against it.
- **Doc contradicts the tree** (says `clean`, `pushed`, `done`): the tree wins. Record the contradiction
  loudly — per `session-handoff` §3.3 a wrong claim in a doc is a defect, and the next session needs to
  know this one lied.
- **Handoff by a different person/agent with a different convention:** read it as evidence, not as a
  contract — its expectations ledger may not exist, so build one from open items.
- **Two handoffs claim to be last:** both are evidence; usually one covers science and one covers
  operations. Merge their open items, keep both labelled, and note which one you based the plan on.

## 6. Done-reconstructing gate

Begin substantive work only when you can state, in one breath: **what last changed and who did it** ·
**what is live right now** · **what is dirty, and whether it is mine** · **the first action and how I will
know it worked**. Missing any of those, you are still reconstructing — and that is a legitimate thing to
tell the user rather than guess through.
