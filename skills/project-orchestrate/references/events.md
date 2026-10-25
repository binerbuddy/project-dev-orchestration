# Orchestrator events and prompts

> `pdo <name>` is an engine command (else `<engine checkout>/bin/<name>`). Paths written `$PDO_STATE_DIR`, `$PDO_INBOX` or `$PDO_HOME` (the engine checkout) mean the values `pdo project-env <KEY>` prints; agent sessions don't have them set.

`<p>` is the project; pass `--project <p>` to every script that takes it (all but `rebase-mark`). State paths are under `$PDO_STATE_DIR`.
Label and status names are the engine defaults ("Claude Work This", `ready for QC`,
`QC complete - ready to review`, `Ready for Merge`, `QC escalated`); a project may rename them in its
env (`CWT_STATUS`, `LABEL_QC_READY`, `LABEL_QC_DONE`, `LABEL_MERGE_READY`, `LABEL_QC_ESCALATED`;
`pdo project-env <KEY>` prints the value in use). Agent QC (the standing "QC Agent (<p>)" workspace)
handles `ready for QC` PRs itself and resumes their agents with its findings; the orchestrator
doesn't act on that.

## Event table

| Event | Action |
|---|---|
| `urgent` | A queue item is P1-urgent AND on the queue status. Spawn it now (step 3, urgent bypass) even when `free_slots` is 0 or usage is over the ceiling. |
| `slot_freed` | Go to step 3. |
| `new_claude_work_this` | Go to step 3. This item outranks everything. |
| `design_ready` | A design run finished and labelled its epic `route:build`. Don't wait for any human design review. Close the design workspace you spawned (`herdr workspace close <workspace_id>`), then immediately `pdo spawn <repo> <n> --route build --brief "<2-3 words> build"`. It doesn't count against the tick's slot budget: it replaces the design run. If spawn refuses because a workspace still exists, report it. If the design PR already merged and its branch is stale, pass `--base origin/<base branch>` (spawn defaults `--base` to the design branch). |
| `pr_conflict` | An agent's PR became CONFLICTING. Don't act on the event; step 2b handles every entry in `conflicting`. |
| `pr_cap_reached` | Repo `repo` has `open_awaiting_human` PRs ≥ `cap` (default 10 **per repo**, file `$PDO_STATE_DIR/<p>-pr-cap`). Its issues stop spawning (`pr_capped: true`, `auto_spawn: false` in `queue`; urgent bypass excepted); other repos carry on. `free_slots` drops to 0 only when every repo is capped (`pr_cap.reached`). Report it once with the repo and count, and say that merging or closing that repo's PRs resumes its work. A repo dropping back under raises `slot_freed` (with `pr_cap_lifted`). |
| `qc_feedback` | Remote QC feedback on a PR: a trusted PR review with *Request changes* (`source: "review"`), or a project's own feedback convention raised by its `WATCH_EVENT_HOOK` (profile `## Project extras`). Find the agent with `pdo pr-agent <number>`, then send the **remote QC feedback prompt** (below) with `pdo resume-agent <repo> <issue#> --prompt "…"`. Then `gh pr edit <n> --remove-label "ready for QC" --remove-label "QC complete - ready to review"` (whichever are on). Exit 3 (question pending): leave the label, report it, retry next tick. No agent metadata (someone else's PR): report it. |
| `qc_complete` | QC passed: `label` is `QC complete - ready to review` (agent QC passed; `awaiting_ux_review` true: a human UX review follows) or `Ready for Merge`. Fires once per pass. If `$PDO_STATE_DIR/qc/handled/<Repo>-<pr#>` exists, `/project-qc-review` already told the agent: do nothing. Otherwise send the **QC approved prompt** with `pdo resume-agent`. It works whether the agent is open or hibernated. Exit 3: leave it for the human. |
| `pr_merged` | Check the issue closed (`gh issue view`). If its board card isn't Done, set it (`pdo claim` refuses a closed issue and self-heals its card to Done). Report that the workspace can be closed and `/project-cleanup-worktrees` run. Don't close workspaces yourself. |
| `stalled` | Read the last ~60 lines with `herdr agent read <pane_id>`. If it's clearly waiting on something that has finished (a background agent, CI), or ended a turn mid-phase with no question, nudge it once with the **check-in prompt** (`herdr agent prompt <pane_id> "…"`). If it looks confused or errored, don't nudge: report it. |
| `agent_gone` | A workspace closed. If its issue is open and it has no merged PR, report it. Leave the claim alone; the human decides. |
| `usage_ceiling` | Stop spawning. Report the weekly and 5-hour figures. The weekly reserve is for manual or hot work. |
| `closed_out` | Informational. The watcher released a finished agent: PR merged, QC passed (`QC complete` or `Ready for Merge`) and it printed "wrap-up done" (or "rebase done" after a later rebase), or its issue closed with no open PR (likely-fixed confirmed, won't-fix). Session kept. One line. |
| `hibernated` / `hibernate_failed` | Informational; they ride along with other events. The watcher released an agent parked at `ready for QC` or `QC escalated` (side processes stopped, workspace closed, session kept for `pdo resume-agent`). One line; for a failure include the reason and don't retry by hand. |
| `tmp_swept` | Informational; rides along. The watcher's hourly `pdo tmp-sweep` freed 100 MB or more of /tmp (stale browser profiles, finished agents' scratchpads, old tool caches). One line. |
| `event_hook_failed` | Informational; rides along. The project's `WATCH_EVENT_HOOK` failed or timed out (`detail`); the watcher retries next poll over the same window. One line; if it repeats, report it for the System Manager. |
| other hook events marked `"quiet": true` | Informational; they ride along. A project's `WATCH_EVENT_HOOK` reported something it did (e.g. applied a label for a project command). One line each, with any `why`, so the human can act by hand when it was ignored. |
| `first_run` / `heartbeat` | Nothing special. Continue to step 3. |

## Prompts

**Remote QC feedback** (`qc_feedback`):

```
Remote QC feedback from @<author> on PR #<n> (<url>):
<body>
The reporter reads GitHub, not this session: reply ON THE PR. If anything is unclear, ask there with an @<author> mention, then wait for their next review or reply. Fix, push, reply on the PR with what changed, then re-apply 'ready for QC'.
```

**QC approved** (`qc_complete`):

```
QC approved: the '<label>' label is on <pr url>. Read any QC feedback in the PR comments and in this session, finish the PR per your dispatch brief (fixes, final push, final comment). Do not merge. If '<label>' is 'QC complete - ready to review', a human UX review still follows: if it brings feedback you'll be resumed with it. Say 'wrap-up done' as your last line.
```

**Check-in** (`stalled`):

```
Orchestrator check-in: you've been idle for <n> min without a pending question. Continue your current phase, or state plainly what you're waiting on.
```

**Rebase** (step 2b):

```
Your PR #<n> now conflicts with its base (<base>), after other PRs merged. Rebase it: git fetch origin && git rebase origin/<base> (if <base> was merged or deleted, retarget the PR to the default branch with gh pr edit --base <default> and rebase onto origin/<default>). Resolve every conflict keeping both sides' intent, following any rebase notes in your project profile's Conventions section (e.g. generated files to regenerate rather than merge). Run the profile's Build & checks commands, then git push --force-with-lease. Keep all labels. Post one PR comment: 'Rebased onto <base> @ <sha>; conflicts resolved in: <files>' (say if behaviour may have changed and needs re-QC). Stop any dev server you started. Say 'rebase done' as your last line.
```
