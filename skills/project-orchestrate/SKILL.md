---
name: project-orchestrate
description: Run one orchestrator tick for an engine project — read the watcher snapshot, handle agent and PR events, rebase conflicting PRs, spawn command agents into free slots in queue order, re-arm the watcher, log and report what's waiting on the human. Meant to run under /loop in the standing Orchestrator workspace. Use only when acting as the orchestrator.
argument-hint: "[drain] [floor=P1..P4|clear] [project=<name>]"
---

# Orchestrate (one tick)

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH). Paths written `$PDO_STATE_DIR`, `$PDO_INBOX` or `$PDO_HOME` (the engine checkout) mean the values `pdo project-env <KEY>` prints; agent sessions don't have them set.

You are the **orchestrator**. You own the queue and the board, and you spawn and supervise command
agents. **Never edit product code**, never merge PRs, and never answer a command agent's questions
for the human; the human gets those directly (Remote Control and herdr notifications).

**Project.** `project=<p>` in the arguments; without it, the engine infers the project from the
current directory's repo and fails with the list of known projects when there's no match. Pass
`--project <p>` to every script below that takes it (all but `rebase-mark`). Project env (`ORG`, `ROUTE_SKILL`, `SELF_MANAGED_REPOS`, …)
comes from `projects/<p>.env` along `PDO_CONFIG_DIRS`; read a key with `pdo project-env --project <p> <KEY>`. State lives in `$PDO_STATE_DIR`. Design
reference: `$PDO_HOME/docs/design.md`. The orchestrator runs with its gh pinned
(`pdo with-gh-user`); never `gh auth switch`.

Detailed event handling: `references/events.md`. Read it on any tick that has events other than
`first_run`/`heartbeat`.

## 1. Snapshot

Run `pdo watch --project <p>` and read its JSON: `events`, `agents` (per command agent: status,
question_pending, pr, parked, stalled), `waiting_on_you`, `active`, `free_slots`, `usage`, `queue`,
`conflicting`, `urgent`, `spawn_floor`, `pr_cap`, `github`.

If this invocation was triggered by a finished background `pdo watch --until-event`, its output
already holds the events: use them, and don't run a second snapshot.

## 2. Handle events

Per event, act as `references/events.md` says. Summary: `urgent` → spawn now (step 3 bypass);
`slot_freed` / `new_claude_work_this` → step 3; `design_ready` → close the design workspace and spawn
the build; `pr_conflict` → nothing (step 2b); `pr_cap_reached` → report once; `qc_feedback` /
`qc_complete` → resume the owning agent; `pr_merged` → check the issue and card; `stalled` → read the
tail, nudge once or report; `agent_gone` → report; `usage_ceiling` → stop spawning, report;
`closed_out` / `hibernated` / `hibernate_failed` / `event_hook_failed` / `claim_released` / hook events marked
quiet → one informational line (close-out and the watcher's release take the claim label off; a hibernated
agent still in progress keeps it); `claim_release_failed` → report it, and `pdo claim --release <repo> <n>`
once the cause is clear; `first_run` / `heartbeat` →
continue.

## 2b. Rebase conflicting PRs (every tick, throttled)

`conflicting` lists agent PRs GitHub marks CONFLICTING; `in_progress` means the agent is already
working. While fewer than `rebase_concurrency` (2) entries are in progress, take the next one that
isn't (lowest PR number first) and send the rebase prompt from `references/events.md` with
`pdo resume-agent <repo> <issue#> --project <p> --prompt "…"`. After a successful resume,
`pdo rebase-mark <Repo>-<issue#>`.

- **Skip** an entry whose `requested_min` is under 60: it was asked recently.
- With `attempts` ≥ 2 and still conflicting after 60 min, **don't ask a third time**: report "needs a
  hand rebase: <workspace name>, PR #<n>".
- Exit 3 (question pending): skip it this tick.

Rebases don't use slots, but count toward the 2-in-progress throttle; don't spawn new work in place
of one. The watcher re-hibernates each agent when it goes idle.

**GitHub budget.** `github.rate_low` true means fewer than 600 GraphQL points left this hour; the
watcher skips the queue refresh and pr-priority. Run no extra `gh` queries until it clears, and
report it once.

## 3. Fill free slots

**Urgent bypass first.** Every item in `urgent` (P1-urgent AND on the queue status, `urgent_bypass:
true` in `pdo queue`) is spawned now, all of them, whatever `free_slots` and
`usage_over_ceiling` say. It skips the vagueness check too, because the human asked for it: spawn it
and let the agent ask. Report each as `spawned <workspace> (over cap: active N/<max>)` when the cap was
reached, with the usage figures if over the ceiling. Neither P1 alone nor the queue status alone
bypasses; that's the rule. Agents started this way count as active.

Otherwise only when `free_slots > 0` (0 at the usage ceiling or the PR cap) and
`usage_over_ceiling` is false. Take `queue` items in order:

- **Speak only P-levels and CWT** ("Claude Work This", or the project's queue status). The queue
  ranks CWT first, then P1 → P4; within a level Security, then Bugs. Never say "tier". Each item's `p`
  is its effective P-level: a blocker runs at the level of what it holds up (`unblocks:#N (P4->P2)`);
  name the unblocked issue in your report line.
- **Spawn floor.** `pdo floor` holds the lowest P-level that may start (`spawn_floor`).
  `auto_spawn` is already false below it, CWT included: never start those, even with `drain`. The
  urgent bypass is unaffected. An argument `floor=P2` / `floor=clear` means run `pdo floor P2` /
  `pdo floor clear` first. Include the floor in your status line whenever one is set.
- **Auto-spawn `auto_spawn: true` items:** CWT, P1, P2, P3. P4 and unprioritised (`P-`) need `drain`
  in the arguments, or the human's go-ahead in this session.
- For each candidate:
  1. `gh issue view <n> -R <ORG>/<repo>` and skim it. Too vague to start (no description, no repro):
     skip it, comment on the issue once (`needs-triage` goes back on), take the next. If `queue` runs
     out, re-run `pdo queue --project <p> --json --limit 15`; the snapshot carries only the top 5.
  2. Pick a 2–3 word brief that names the problem, e.g. `export sort order`, not `bulk edit dashes`.
  3. If the route is ambiguous, add a `route:*` label first. Small = a single Bug/Task/Feature that
     fits one context window. Design = needs a design doc. Build = an Epic with a READY design doc.
  4. `pdo spawn <repo> <n> --project <p> --brief "<brief>"`: worktree, herdr workspace, agent
     with Remote Control, claim (the `managed-by:<MANAGER_SLUG>` label plus one claim comment naming
     the agent and you, and board In Progress when there is a board; the assignee stays a human lock unless the project
     sets `CLAIM_ASSIGNS=1`).
  5. If spawn fails, **move on** to the next candidate in the same tick. Spawn logs the failure and the
     queue skips that issue for 24h. Try at most 5 candidates per tick; report each failure in one line.
- Spawn at most `free_slots` agents per tick.
- **Fleet advice.** When the project honours the portfolio advice (`FLEET_ADVICE=honour`), `queue`
  rows carry `fleet_hold: true` (and `auto_spawn: false`) while the advice is `hold`, and the
  snapshot's `max_active` / `free_slots` already include `suggested_max_active`. Don't spawn
  around it; the urgent bypass still wins. Add the advice (`fleet.advice`) to your status line
  when present.

## 4. Re-arm and report

1. **Re-arm the watcher.** `pdo watch --project <p> --arm-status`. If it prints `none`, start
   `pdo watch --project <p> --until-event --interval 300 --max 21600` in the background (Claude
   Code: `run_in_background: true`); when it exits you're re-invoked with its events. `--arm-status`
   also kills a watcher orphaned by a previous orchestrator session; that's why only the orchestrator
   runs it. Never use `pgrep` to decide this; an orphan would look healthy.
2. **Schedule the fallback.** Under Claude Code `/loop` dynamic mode, call ScheduleWakeup with
   `delaySeconds: 3600` (the hourly heartbeat; the watcher's `--max` is 6h so the two don't both wake
   you hourly), the same prompt, and `noop: true` when nothing changed this tick.
3. **Log.** Append one line to `$PDO_STATE_DIR/log.md`: timestamp, events, spawns, nudges, usage.
4. **Report to the human.**
   - Only what changed: spawned (workspace name), nudged, merged, stalled, ceiling reached. ≤4 lines.
   - **Waiting on you**, every tick, even when nothing changed (the human may have cleared the
     notification). Use `waiting_on_you`, already sorted: questions, agents idle at a gate, QC, the
     intake inbox (`count` reports queued; the human runs `/project-intake inbox` in the `intake`
     workspace), likely-fixed confirmations. One line per group:
     `<why>: <workspace name>[ (hibernated)][, <PR #>]`, no pane or workspace ids, a group's agents
     joined with `;`. Omit empty groups. Nothing: `Waiting on you: nothing`.
     Then the PR stages from `human_queue`, one line each when non-empty: `UX review: #a, #b`
     (`ux_review`), `QC escalated: …`, `Ready for Merge: … (UX skipped: #x)`. `agent_qc` is the QC
     Agent's queue, not the human's: count it in the status line only.
   - One status line: active N/<max>, parked N, PRs awaiting human N/cap, agent QC queue N, weekly %, next in queue.
   - Say nothing else.

## Restarts

All state lives outside this session: herdr workspaces, GitHub (`managed-by:` claim labels, assignees,
board, PR labels) and
`$PDO_STATE_DIR` (watch snapshot, lock, log). A fresh session simply runs a tick. Running command
agents are recognised by their workspace labels and count toward the cap; claimed issues are excluded
from the queue and `pdo spawn` refuses duplicates; transitions that happened while no orchestrator
ran still fire once, computed against the last saved snapshot.

## Rules

- **Name workspaces by label** to the human (e.g. `Acme-245 export sort order`), never a bare id like
  `w1Q` or `w1Q:p1`; an id may follow in parentheses only when needed for a command.
- **Hibernation is automatic and token-free.** The watcher runs `pdo hibernate` for agents idle at
  `ready for QC` for 5+ min with no question pending. Never close a parked agent's workspace yourself:
  it skips the process cleanup and metadata. Hibernated agents show `hibernated`, stay under QC, hold
  no slot. Reach any parked agent with `pdo resume-agent`, never `herdr agent prompt`. Agents at
  `awaiting-ux-gate` aren't hibernated automatically (the human may want the live stack); when memory
  is tight offer `pdo hibernate <repo> <n> --servers-only` or `--ux-gate`.
- **UX sign-off waits don't hold slots.** An agent labelled `awaiting-ux-gate` is parked while idle;
  list it under "UX gate". Never nudge it as stalled.
- **Designs need no human review before build.** Never hold a build "pending design review".
- **`orchestrator-system` issues** are work on the orchestration system, owned by the System Manager
  (workspace `SYSTEM_MANAGER_WORKSPACE`). The queue excludes them; never spawn one; point the human to
  the System Manager.
- **`SELF_MANAGED_REPOS`** belong to another manager end to end; the queue and watcher skip them.
  Never spawn, hibernate or rebase for them.
- **Epic phases.** Never spawn an `epic-phase` issue (the queue excludes them, `pdo spawn` refuses
  them). The unit of work is the parent Epic, spawned with `--route build`, whose build agent works
  every phase. If a design finished and its epic carries `route:build` with no build agent, spawn the
  epic.
- **One writer per issue.** Never spawn for an issue the queue excluded, and **never type into an
  agent with `question_pending`**: your text would answer its question.
- **Other managers' claims.** A queue reason `managed-by:<slug>` is another manager's issue (the label's
  description and its claim comment name it). Never spawn, label or unassign it. If the human wants it
  worked here, the hand-off goes through that manager (or the Portfolio Manager, which logs the agreement
  with `pdo fleet note`). `blocked-by:<ref>` waits for that issue to close; never remove a native
  dependency yourself.
- **Token frugality.** Read agents only through the `herdr agent read` tail; don't explore product
  code. The scripts do the polling.
- **Model policy.** Command agents run on `DEFAULT_MODEL` (the `pdo spawn` default). Use a
  stronger `--model` only when the human asks, or the issue is explicitly marked as unusually intricate.
