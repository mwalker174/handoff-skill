---
name: session-handoff
license: MIT
description: >-
  Writes an auditable end-of-session handoff — freeze live state, verify git/remote across every repo, write the project's numbered progress doc, fold durable facts into standing instructions, push and re-read the remote. Use when the user says "document and commit this session", "so I can clear it / start fresh", "fresh checkpoint", "hand off", or before a context clear. Counterpart skill is session-pickup, which resumes from what this writes.
---

# Session Handoff

A handoff is **evidence, not narrative**. The next session starts with zero context and no way to tell a claim you measured from a claim you guessed. Optimize for: every number reproducible, every open item actionable, every unverified thing labelled.

Follow the project's own convention when it exists (`AGENTS.md` / `CLAUDE.md` / a numbered `docs/progress/` series). This skill only adds the discipline around it.

The contract this doc writes is *consumed* by `session-pickup` — its scripts parse the headings below ("Resume here", "Open items / next steps", expectations/coordinate tables, fenced commands). Keeping those names intact is what makes the next session's pickup cheap.

## 1. Freeze live state first — before writing anything

Anything that outlives the session must be re-queried, or the doc records a state that already moved.

- Jobs / submissions / CI / background runs / VMs / deployed services → query them, record status **and** the identifier needed to re-query.
- Re-read the live counter for anything the doc will call "in progress". Never carry a status forward from memory.
- A job still running is a legitimate handoff state. Say "last observed `Running` at handoff" with the resume command; do not wait, guess, or write the expected outcome as the outcome.

Run `scripts/repo_state.sh` (from this skill dir) to inventory reality: branch, upstream, ahead/behind, dirty paths, last commit for the repo plus any nested git repos. Nested repos and submodules get missed constantly, and "clean" here is a lie if a nested repo is 10 commits ahead.

## 2. Write the handoff doc

Use `references/HANDOFF_TEMPLATE.md` if the repo has no convention. Required sections, in order:

1. **Date line** — see §3.1.
2. **What changed, per workstream**, with the evidence for each claim (command, file, id, line).
3. **Coordinates table** for anything external created or touched.
4. **How to resume** — a literal, paste-able command block, not prose.
5. **What "good" looks like** — expected values for the next check, so the next session can judge a result instead of just reading it.
6. **Gotchas found** — only ones actually hit, each with the error text that produced it.
7. **Deliverables** — file → what changed, as a table.
8. **Open items** — checklist, carrying every unfinished item forward. Unfinished ≠ deleted.

## Parser trap that silently kills your resume block

`handoff_scan.sh` tracks headings with `/^#{1,6}[ \t]/` **without tracking fence state**, so a
shell comment starting at column 0 inside your fenced resume block (`# re-verify the standing
claims`) is read as a heading: the block is abandoned mid-write, the closing fence re-opens a
new one, and the scan reports *"no fenced commands at all"* on a doc that plainly has one.
Indent in-fence comment lines by one space (renders identically). For the same reason, keep
the heading words the scanner greps for — `Resume`, `good`/`Expected`, `Coordinat`,
`Mutation`/`Ledger`, `Open items`, `verify` — or your coordinate/expectation tables never
surface. Prove it before declaring the handoff done:
`handoff_scan.sh --dir <docs> --pick <NNN>` must print your block and your tables.

## 3. The no-invention rules (the whole point)

### 3.1 Dates
System clocks are frequently wrong and sandbox clocks are unreliable. If the repo declares where dates come from (PM, ticket, server), use that source. When the repo's date **disagrees** with an external system's timestamp, record both and flag the disagreement — do not silently pick one. Billing/audit systems follow their own clock, not yours.

### 3.2 Numbers and status
- **Unmeasured ≠ estimated.** If the API/tool returned no figure, write "not measured" plus where to get it. A plausible estimate in a handoff doc becomes tomorrow's fabricated fact.
- Label each material claim: *verified by <command>* / *inferred* / *not exercised*. Untested-but-documented is a valid state; untested-documented-as-done is a defect.
- Prefer re-running the check over reusing a number from earlier in the session, if it is cheap.

### 3.3 Corrections get shouted
If this session proved an earlier doc/comment/config claim **wrong**, fix the old text *and* name the correction in the new doc. Buried corrections propagate; the wrong claim usually already shaped a decision or an entire workstream.

### 3.4 Mutations ledger
List external mutations actually made (rows written, jobs submitted, methods/configs registered, records created, branches pushed), each with how to undo or verify. Separate the reversible from the irreversible. Probes created during debugging get deleted and reported as deleted.

### 3.5 Failure modes that are still wins
Where a gate can fail *after* the real work succeeded, say so, and say what survives. Otherwise the next session reads `Failed` and throws away good output.

## 4. Fold durable facts into standing instructions

Anything that cost more than one turn to discover belongs in the project's standing instructions (`CLAUDE.md`/`AGENTS.md`) — not only in the dated progress doc, which nobody re-reads at the right moment.

Rules: only facts **verified this session**; include the failure text that proves it; keep it imperative and short; link the progress doc for the narrative.

**Trap:** `AGENTS.md` is often a symlink to `CLAUDE.md`. `git add AGENTS.md` then stages the unchanged link and commits nothing while reporting success. Check `ls -l`, stage the real file, and confirm the commit's diff contains the lines.

## 5. Commit, push, then re-read the remote

Never report "pushed" from the push command's exit status. Re-verify per repo:

```bash
git status -sb                          # branch vs upstream, no dirty paths
git --no-pager log --oneline -1         # local head
git --no-pager log --oneline origin/<branch> -1   # remote head — must equal local
```

Also confirm the commit actually holds the content: `git show --stat --oneline HEAD` (a file that silently failed to stage shows up as missing lines, not an error).

## 6. The handoff message

Short. Must contain: what was written and **where**, the resume command, state-at-handoff for anything still live, the highest-value next action, and what is deliberately left unmeasured. Do not restate the doc's body.

## Anti-patterns seen in the wild

- Status carried forward from earlier in the session instead of re-queried.
- "Pushed" without reading the remote head; committed-but-unstaged content reported as shipped.
- Nested repos / submodules / worktrees omitted from the inventory.
- A correction phrased as new information, so the wrong claim stays load-bearing.
- Open items rewritten as achievements; the next session inherits a list that looks finished.
- Secrets or tokens copied into the doc because a command line was convenient to paste.
- Standing-instruction edits written into the dated doc only — invisible exactly when needed.

## References

- `references/HANDOFF_TEMPLATE.md` — section skeleton when the repo has no convention.
- `scripts/repo_state.sh` — multi-repo state inventory; `--push <branch>` compares local vs remote heads.
