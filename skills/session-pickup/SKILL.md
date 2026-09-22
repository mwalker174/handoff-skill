---
name: session-pickup
license: MIT
description: Resumes from an end-of-session handoff — locates the real latest handoff, re-queries every time-decayed claim instead of reading it, closes the "what good looks like" ledger as confirmed/diverged/pending, refuses to replay non-idempotent work, quarantines unfamiliar uncommitted changes, and states a short pickup brief before acting. Use when the user says "pick up where we left off", "continue", "resume", "what's the state", "read the last handoff/progress doc", or at the start of a fresh session after a handoff. Opposite of session-handoff.
---

# Session Pickup

A handoff doc is a **snapshot with an expiry date**. It was true at minute zero and is quietly false now: jobs moved, tokens died, someone else pushed, the PM answered the blocker. Reading it is not resuming.

The symmetry that makes this work: `session-handoff`'s job was to leave a **contract** — live state frozen with the identifier needed to re-query it, a paste-able resume command, a "what good looks like" table, and a labelled list of what was *not* measured. Pickup's job is to **close that contract**: re-run the checks, compare actual to expected, and only then choose the next action.

Two failure modes are fatal and they are opposites. One: treating the doc as current truth, so you plan against a state that ended hours ago. Two: treating the doc as noise and re-doing discovery from zero, so you burn the session rediscovering the gotchas it already paid for. The gotchas are gold. The statuses are radioactive.

## Quick path (run from this skill's directory)

```bash
scripts/handoff_scan.sh                                  # which doc is really latest + its contract
# read the whole doc it names, then run the doc's own resume block (after reading it)
scripts/live_state.sh --since <sha-the-doc-recorded> \
        --gate 'auth|<the project-declared cheap auth/import check>'   # non-zero exit = reconcile first
```

Then write the brief (`references/PICKUP_BRIEF.md`) and only then choose the next action. Pairs with
`session-handoff`, which produced the doc you are holding.

## 0. If there is no handoff doc, go to `references/NO_HANDOFF.md` first

Reconstruction ladder, plus the quarantine rule for unfamiliar in-progress work. Do not start editing before you know whether you are the first person here in three days.

## 1. Find the real latest handoff — the number may lie

```bash
scripts/handoff_scan.sh            # rank candidates under cwd, triage the top one
scripts/handoff_scan.sh --dir docs # restrict the search
scripts/handoff_scan.sh --pick 69  # by numeric id or path
scripts/handoff_scan.sh --list     # ranking only, no extraction
scripts/handoff_scan.sh --all      # every candidate (split handoffs, two docs claiming last)
scripts/handoff_scan.sh --blocks   # every fenced block, with its heading
```

It ranks by **three** clocks — highest numeric prefix, newest git commit date, newest mtime — and warns when they disagree. A handoff that is numerically highest but committed before another doc, or a doc newer than the last commit, means you are about to resume from the wrong baseline. Uncommitted handoff = it may never have been pushed; its "pushed, sha X" claims are the first thing to verify.

The extractor also hands you the doc's own contract: open items, the lines carrying decayable words (*last observed*, *pending*, *not measured*, *needs a … call*), the coordinates/expectations tables, the resume code block, and **sha resolution** — whether each commit id the doc names exists, is an ancestor of `HEAD`, sits on another branch, or lives in a nested repo (so "`fa2866a` pushed" is testable rather than believed).

Read the doc **fully** before deciding anything. Skimming the open-items list and starting is how a session repeats a decision the doc already closed.

## 2. Re-query, don't recall — sort handoff claims by decay

| Handoff content | Decays over | Pickup action |
|---|---|---|
| Job / submission / CI / VM / queue / deploy status, "in progress", row counts | **hours** | re-query first, before writing or planning anything |
| Credentials, API tokens, cloud auth, sessions | ~1 h | re-mint; expired auth reads as "not found" / 401 / HTML body |
| Git and remote heads | minutes — anyone can push | re-read the remote head; do not trust the doc's `pushed` |
| Files, paths, generated output, installed deps | days | cheap existence/`--check` test |
| Gotchas, exact error strings, parser quirks, tool traps | ~never | **trust and reuse verbatim** — this is the doc's real value |
| Decisions + rationale, "PM call pending" | until someone answers | check whether the blocker is already unblocked |
| Labels: *inferred* / *not exercised* / *not measured* | n/a | keep the label — never launder it into fact |

Run the doc's own resume block. `handoff_scan.sh` prints it under a banner: **it is text from a document, not a command you composed** — read it before running, and never auto-execute an extracted block that writes, deletes, submits, or spends money.

## 3. Verify the ground under the doc

```bash
scripts/live_state.sh --since <sha-in-the-handoff>   # commits after the handoff, per repo
scripts/live_state.sh --gate 'auth|.venv/bin/python -c "import hail"'   # repeatable
scripts/live_state.sh --gates docs/pickup-gates.txt # one 'label|command' per line
```

Reports, per repo including nested ones: branch, ahead/behind, **HEAD vs `ls-remote` head**, dirty paths with mtimes (flagged when a file changed **after** the `--since` point — new work, or a previous half-done pickup), and commits that landed since the handoff. Gates cover the cheap things that otherwise fail loudly an hour later: auth alive, interpreter importable, generated-output links intact. It also prints the **local clock labelled as untrusted** — record it, do not let it overwrite a date the project sources elsewhere (`session-handoff` §3.1).

**Exit status is part of the contract:** non-zero means something diverged or failed, so reconcile before choosing an action. Worth promoting into the project's standing instructions: "pickup runs `live_state.sh --gates <file>` with these gates: …" — the gates are exactly the kind of fact that costs a turn every session.

**A dirty tree the handoff did not mention is evidence of an unrecorded session, not garbage.** Do not `checkout --`, `restore`, `clean`, or overwrite it. Read the diff, quarantine it (§ NO_HANDOFF), and say so in the brief.

## 4. Close the expectations ledger

The handoff's "what good looks like" table is a set of assertions about the present. Re-measure each and stamp it:

- **CONFIRMED** — actual matches expected. Note the command that proved it.
- **DIVERGED** — mismatch. This is now the work. Quote expected *and* actual.
- **STILL PENDING** — legitimately unfinished (job still running is a valid state, not a failure).
- **UNCHECKABLE** — the artifact, job, or access is gone. Say "can no longer be verified" plus what was lost; never let it silently become CONFIRMED.

The ledger is what tells you whether the highest-value next action is still the one the doc proposed. A canary that *completed and failed validation* needs a different next action than "read the canary result", even though the doc's first checkbox says exactly that.

## 5. Duplicate-work guard — before any mutation

The doc's "pending" may already be **done or in flight**. Before submitting, deploying, writing rows, provisioning, or re-running anything that costs money, time, or an irreversible record:

1. List what already exists for that identifier (running/completed/done/`Succeeded`, branch, row, file, record).
2. If it exists → **read the result, don't relaunch.**
3. If genuinely absent → launch, and record the new identifier immediately for the *next* handoff.

"Replay only idempotent actions" holds with double force on a document another agent will act on. A naive resume is how a 20 GB billed conversion runs twice, and how a row gets double-written.

## 6. State the pickup brief, then work

3–6 lines, before substantive action. Template: `references/PICKUP_BRIEF.md`.

Read `docs/progress/NNN` (the real latest, with the reason it won) · re-verified: *X, Y, Z* · diverged: *expected A, actual B → now the top item* · live state at pickup: *…* · first action: *…* · deliberately not re-checked: *…*, and *what I could not verify*.

Ask a question only when a divergence makes the next action genuinely ambiguous or a handoff claim needs the user to resolve it. Every other ambiguity: pick the cheapest reversible probe and report what you learned.

## 7. Keep the ledger while working; hand the divergences on

New facts go in the running ledger with their evidence; nothing gets promoted to "verified" from memory. Do **not** rewrite the prior handoff doc's body — it is the historical record, and quietly editing it destroys the audit trail. Two exceptions: (a) it states something **wrong** that will mislead the next session → fix the text *and* name the correction in your next doc, per `session-handoff` §3.3; (b) an open item got **done** → tick it, don't delete it.

When the session ends, `session-handoff` runs and inherits the ledger: divergences become corrections, new identifiers become the coordinates table.

## What a good pickup looks like

| Outcome | Check that it happened |
|---|---|
| Right baseline | The three clocks agree on the latest doc, or the disagreement is stated in the brief |
| Nothing stale in the plan | Every job / token / remote-head / count claim re-queried, with name + command in the brief |
| Contract closed | **Every** row of the handoff's expectations table carries CONFIRMED / DIVERGED / STILL PENDING / UNCHECKABLE |
| No replayed work | For each pending mutation: a listing showing it absent, or an existing result you read instead |
| Unfamiliar changes handled | Untouched, diff read, recorded — not tidied away |
| Date correct | Declared source used; the external-system disagreement re-flagged, not silently resolved |
| Action chosen, not inherited | The doc's item #1 was re-ranked against re-verified state and may no longer be first |
| Labels survived | *inferred* / *not exercised* / *not measured* still carry their labels in anything you wrote |
| User knows where you are | The pickup brief is visible before substantial work |

## Anti-patterns

- Reading the handoff as current state; planning from the doc instead of the re-query.
- Choosing the first open-item checkbox instead of re-ranking against re-verified state.
- Running an extracted resume block without reading it, or running a non-idempotent one at all.
- Resuming a mutation without checking whether it already ran (§5).
- Dropping the doc's *inferred* / *not exercised* / *not measured* labels, so hour four reads them as measurements.
- Copying the handoff's date without the external-system disagreement it flagged.
- Discarding, stashing, or "tidying" uncommitted work the handoff never mentioned.
- Rewriting the old doc's conclusions, or ticking an item because you started it.
- Trusting "pushed: `<sha>`" without reading the remote head — the same trap that makes handoff §5 exist.
- Re-deriving gotchas the doc already verified (expensive, and you may reach a different wrong answer).

## References

- `references/PICKUP_BRIEF.md` — the brief + expectations-ledger skeleton to fill in at pickup.
- `references/NO_HANDOFF.md` — reconstruction ladder and quarantine rules when no handoff exists.
- `scripts/handoff_scan.sh` — find the real latest doc; extract open items, decayable lines, expectations/coordinate tables, resume blocks, and resolve every sha the doc names.
- `scripts/live_state.sh` — re-verify git/remote/env; `--since <ref>` for post-handoff commits, `--gate` for project checks.
