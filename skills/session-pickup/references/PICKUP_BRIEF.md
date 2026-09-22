# Pickup brief

Fill this in **before** substantive work, paste it to the user, then keep the ledger alive. It exists so a
wrong inference surfaces in the first minute instead of an hour deep into a wrong plan.

```markdown
**Picking up from:** `<path to the doc that won>` — chosen because <highest number AND newest commit AND
newest mtime | it is uncommitted but newer, so it supersedes the numbered doc>.
Numbering/clock note: <"all three agree" | "the highest number is not the newest commit: <details>">.

**Re-verified (measured just now, not recalled):**
- <claim from the doc> → <actual measured value> via `<command>` — <matches / moved>
- <live job / submission / deploy> → <status + id> via `<command>`, observed <HH:MM>
- <git/remote> → `<repo>` HEAD `<sha>` = `origin/<branch>` `<sha>`
- <auth/credential> → <alive / re-minted> via `<command>`

**Divergences from the handoff (these reorder the plan):**
| doc expected | actual now | consequence |
|---|---|---|
|  |  |  |

**Expectations ledger** (the handoff's "what good looks like", closed):

| check | doc's expected | actual | stamp |
|---|---|---|---|
|  |  |  | CONFIRMED / DIVERGED / STILL PENDING / UNCHECKABLE |

**Duplicate-work guard:** <"the submission the doc left pending is already `Succeeded` — reading the
result, not relaunching"> / <"confirmed absent, launching once, new id recorded: …">.

**First action:** <one verb + target + how I will know it worked> — chosen because <why it now beats the
doc's first checkbox>.

**Not re-checked, and why:** <cheap durable claims taken on trust — gotchas, decisions, error texts>.
**Cannot be verified any more:** <what is gone: temp dir, expired run, revoked access>.
**Inherited labels I am keeping:** <"not measured", "inferred", "not exercised" — still not measured>.
```

## Rules this template encodes

- **Measured, not recalled.** Every line in "Re-verified" came from a command run in this session. If you
  cannot name the command, the line does not belong there.
- **Divergences are stated, not smoothed.** A mismatch you quietly resolve is a defect you delete.
- **The doc's first checkbox is a proposal, not a queue.** Justify your first action against re-verified
  state; if the doc's item is still right, say so in one clause.
- **Unverifiable is an answer.** `UNCHECKABLE` with what was lost beats a hopeful `CONFIRMED`.
- **Nothing here is a claim that work is done.** Ticks belong in the doc, and only after evidence.

## Ledger maintenance (through the session)

Append to the same structure as you go:

```
| time | what I ran | expected | actual | stamp |
|---|---|---|---|---|
```

Mutations get their own ledger row: *identifier · created by · how to verify · how to undo · reversible?*
Both ledgers are what `session-handoff` will consume at the end of the session — the closer you keep them,
the less the next session has to invent.
