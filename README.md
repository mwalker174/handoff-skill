# handoff-skill

Two [pi](https://github.com/badlogic/pi-mono) skills that make context-clearing between agent sessions safe:
`session-handoff` writes an auditable end-of-session handoff, `session-pickup` resumes from one without
trusting it.

The idea: a handoff doc is a **contract**, not a narrative. The handoff session freezes live state (jobs,
git heads, coordinates) with the identifier needed to re-query each one, records a paste-able resume block,
a "what good looks like" expectations table, and labels every claim as *verified*, *inferred*, or *not
measured*. The pickup session **closes that contract**: re-queries everything that decays, stamps each
expectation CONFIRMED / DIVERGED / STILL PENDING / UNCHECKABLE, refuses to replay non-idempotent work, and
states a short pickup brief before acting.

## The skills

| Skill | Trigger phrases | What it does |
|---|---|---|
| `session-handoff` | "document and commit this session", "hand off", "so I can clear it" | Freeze live state → write the numbered progress doc → fold durable facts into standing instructions → commit, push, and re-read the remote to prove it |
| `session-pickup` | "pick up where we left off", "continue", "resume", "what's the state" | Find the real latest handoff (three clocks: number, git, mtime) → re-query every decayed claim → close the expectations ledger → brief, then work |

Both ship with helper scripts:

- `session-handoff/scripts/repo_state.sh` — inventory every git repo (incl. nested/submodules): branch,
  upstream, ahead/behind, dirty paths; `--push` compares local vs remote heads.
- `session-pickup/scripts/handoff_scan.sh` — rank handoff candidates by three independent clocks, warn when
  they disagree, and extract the doc's contract: open items, decayable claims, expectation tables, resume
  block, and resolution of every commit sha the doc names.
- `session-pickup/scripts/live_state.sh` — re-measure git/remote heads, post-handoff commits, dirty files
  (flagged by mtime vs the handoff), env drift, and repeatable project gates (`--gate 'label|command'`).

## Install

Skills are directories containing `SKILL.md` ([Agent Skills](https://agentskills.io/specification) format —
works in pi and other compatible agents). Place them where your agent looks for skills:

```bash
git clone https://github.com/mwalker174/handoff-skill.git ~/src/handoff-skill

# pi (user-level; discovered recursively)
ln -s ~/src/handoff-skill/skills/session-handoff ~/.pi/agent/skills/session-handoff
ln -s ~/src/handoff-skill/skills/session-pickup  ~/.pi/agent/skills/session-pickup

# or any Agent Skills location, e.g. ~/.agents/skills/
```

Symlinks keep `git pull` as your only upgrade step; copying works the same. Scripts must stay executable.

## Use

Nothing to configure. Say *"hand off"* (or *"document this session"*) at the end of a session; say
*"pick up where we left off"* at the start of the next one. The skills follow your project's own convention
(`AGENTS.md`/`CLAUDE.md`, a numbered `docs/progress/` series) when one exists and fall back to bundled
templates when not. If no handoff exists, `session-pickup` runs a reconstruction ladder and quarantines —
never discards — unfamiliar uncommitted work.

The rules the skills enforce, in one line each:

- Re-query anything that decays (jobs, tokens, remote heads); trust only gotchas and exact error strings.
- Unmeasured ≠ estimated; a plausible estimate in a handoff becomes tomorrow's fabricated fact.
- "Pushed" is only proven by reading the remote head, per repo, including nested ones.
- Never run an extracted resume block that writes, submits, or spends without reading it first.
- Before any mutation, check whether the pending work already ran — never bill the same job twice.
- A dirty tree the handoff didn't mention is evidence of an unrecorded session, not garbage.

## Layout

```
skills/
├── session-handoff/
│   ├── SKILL.md
│   ├── references/HANDOFF_TEMPLATE.md
│   └── scripts/repo_state.sh
└── session-pickup/
    ├── SKILL.md
    ├── references/{PICKUP_BRIEF,NO_HANDOFF}.md
    └── scripts/{handoff_scan,live_state}.sh
```

## License

MIT — see [LICENSE](LICENSE).
