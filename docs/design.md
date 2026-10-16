# project-dev-orchestration: design

How the engine works, and why. Living document. The day-to-day guide is [user-guide.md](user-guide.md).

Script names below are written `bin/<name>` (paths in this repo). Run them as `pdo <name> …` once
`bin/install --bin` has put the `pdo` dispatcher on PATH, or by absolute path from an engine checkout.

## Roles

- **System Manager.** The lead session that builds and maintains an install: the engine, its config dirs,
  hooks and skills. Reload it after a context clear with the `project-system-manager` skill; it reads
  [lessons-learned.md](lessons-learned.md) and runs `bin/sysreport`. Its workspace name is the project's
  `SYSTEM_MANAGER_WORKSPACE`.
- **Orchestrator.** One long-lived agent session in its own herdr workspace, `Orchestrator (<project>)`,
  running `/loop` over the `project-orchestrate` skill. It ranks the queue, claims issues, spawns command
  agents, routes events and moves board cards. It never edits product code.
- **Command agent.** One per issue or epic, in its own herdr workspace (`<Repo>-<issue#> <2-3 word brief>`)
  and its own git worktree. It runs a lifecycle skill and orchestrates its own sub-agents.
- **QC agent.** The standing `QC (<project>)` workspace (`project-qc-review`). It serves a PR on the
  project's QC servers for the human's hands-on QC, and relays feedback to the PR's command agent.
- **Intake agent.** The standing `intake` workspace (`project-intake`). It turns reports into typed,
  prioritised issues. Other agents queue reports with `bin/intake-submit`; the human drains the queue.
- **Human.** Answers questions directly in a command agent's workspace, does UX and QC review, and merges
  by hand.

## Spawning

- `bin/spawn <repo> <n>` re-reads the issue live, picks the route, creates a worktree and branch, writes
  the dispatch brief, opens a herdr workspace and launches the agent there with Remote Control on and the
  route's lifecycle skill as its first prompt. Then it claims the issue (`bin/claim`: assignee plus board
  status) and records metadata in `$PDO_STATE_DIR/agents/<Repo>-<n>.json`.
- It refuses duplicates (an open workspace, an existing worktree or branch), closed issues, pull requests,
  and issues assigned to someone else (the human/interactive lock). It rolls back on failure. Every
  failure except `--dry-run` is logged, and `bin/queue` skips that issue for 24 h.
- Launching goes through `launch_agent` in `bin/lib.sh`, the one seam for other agent CLIs (`AGENT_CLI`;
  only `claude` today). It runs the CLI through `herdr pane run`, accepts the "trust this folder?" dialog
  only when it names the worktree it just created, and returns 2 when the agent is blocked on anything else.
- Every launch is prefixed by `identity_wrapper`: `bin/with-gh-user --user $GH_USER` when the project sets
  `GH_USER` (gh's active account is machine-wide and other sessions switch it), plus whatever words the
  project's `IDENTITY_HOOK` prints for that checkout (e.g. a bot identity for one repo).
- The dispatch brief is `BRIEF_TEMPLATE`, else the first `prompts/dispatch-brief.md` in the config dirs,
  else the engine's `prompts/dispatch-brief.md`. `{{UPPERCASE}}` placeholders are filled in: REF, URL,
  NAME, WORKTREE, BRANCH, BASE, ROUTE, SKILL, TITLE, TYPE, LABELS, BODY, DIRECTIVES, NUMBER, ENGINE.
- **Human directives.** Issue comments that start with "Claude" or "@claude", from OWNER, MEMBER or
  COLLABORATOR authors only, go into the brief with the same authority as the issue body.

## Routing

| Signal | Route |
|---|---|
| `route:small` / `route:design` / `route:build` label | that route |
| `needs-design` label | design |
| Epic whose body links a READY `docs/design/*.md` | build (base: the epic's `docs/*-design` branch) |
| Other Epic | design |
| Bug, Task, single Feature | small |

`ROUTE_SKILL` maps a route to its skill. A command agent may push back: a "small" issue that turns out to
need a migration or a cross-cutting UX decision stops and asks to be re-routed.

**Epic phases.** Phase sub-issues carry `epic-phase`. The queue excludes them and `spawn` refuses them
without `--allow-phase`: the epic's build agent works every phase. Independent follow-ups carry no
`epic-phase` label and dispatch normally.

## Queue (deterministic, no model judgement)

`bin/queue` ranks open issues in the managed repos (`REPO_ROOT` minus `SELF_MANAGED_REPOS`):

1. Board Status = Claude Work This (`CWT_STATUS`) first, then P-level (`P_LABELS`, best first;
   unlabelled sorts last as `P-`).
2. Within a level: `Security`-labelled, then Bugs, then issues whose parent epic is In Progress, then
   oldest first (a "created YYYY-MM-DD by" footer in the body wins over `created_at`, for migrated issues).

- **Auto-spawn:** CWT and P1–P3. P4 and unprioritised wait for `drain`.
- **Spawn floor:** `bin/floor P2` (persisted per project) stops anything below it from auto-spawning,
  CWT included.
- **Urgent bypass:** P1 AND on CWT starts even with no free slot and over the usage ceiling.
- **Priority inheritance:** an issue that blocks others runs at the best P-level (and CWT) among the
  issues it transitively holds up, when being blocked is their only exclusion. A P4 blocking a P2 runs
  as P2; otherwise it would deadlock behind `drain`.
- **Excluded** (listed with `--all`): assigned, `on-hold`, `likely-fixed`, `epic-phase`, a spawn failure
  in the last 24 h, `needs-triage` (unless on CWT), blocked by an open issue, already In Progress / In
  Review / Done, an open workspace, Epics without a `route:*` label, and `orchestrator-system` work (the
  System Manager owns it).
- The board fetch passes an explicit `--limit` and fails when the count equals it (silent truncation).

## Concurrency and the usage budget

- At most `MAX_ACTIVE` (default 3) **active** command agents. Parked agents (PR at `ready for QC` or QC
  complete, `likely-fixed`, `on-hold`, a design handed to build, idle at `awaiting-ux-gate`) don't count.
- Spawning stops at `WEEKLY_CEILING` % of the weekly usage budget (default 80, keeping 20% for manual and
  hot work), and pauses at `FIVE_HOUR_CEILING` % of the 5-hour window (default 90). Usage comes from a
  cache file (`USAGE_CACHE`; the oh-my-claudecode HUD's cache by default). Missing data never blocks
  silently: it is reported as unknown.
- **PR cap:** when `<project>-pr-cap` (default 10) open PRs are waiting on the human, nothing new spawns,
  so the team's pace follows the human's merge rate.

## The watcher

Claude only acts when a turn is triggered, so the orchestrator isn't self-sustaining. `bin/watch` is a
token-free probe; the model only reads what changed.

- One snapshot covers every command-agent workspace: herdr status, whether a question or menu is on
  screen, the branch and its PR (one GraphQL query per repo for all open and recently closed PRs), parked
  and stalled state, plus `waiting_on_you`, usage, the PR cap, conflicting PRs, the queue top (refreshed
  every 5 min) and the intake inbox count.
- Events are transitions against the saved snapshot, so each fires once and a restarted orchestrator
  still sees what changed while it was down: `slot_freed`, `urgent`, `qc_feedback`, `pr_conflict`,
  `pr_cap_reached`, `design_ready`, `qc_complete`, `pr_merged`, `agent_gone`, `stalled`,
  `new_claude_work_this`, `usage_ceiling`, `heartbeat`. Quiet events (`hibernated`, `closed_out`,
  `hibernate_failed`) ride along with the next wake.
- `--until-event` polls (default every 300 s) until an event, or emits `heartbeat` at `--max`. The
  orchestrator runs it in the background with `--max 21600`, and an hourly scheduled wakeup is the
  fallback heartbeat, so the two don't both wake it every hour.
- **Ownership.** A watcher belongs to the session that started it (a lock file with the session id).
  `--arm-status` reports whether this session owns a live watcher and kills every other one, so a
  restarted orchestrator replaces an orphan instead of trusting it. For a read-only check use
  `pgrep -f '[b]in/watch --project'`; `--peek` takes a snapshot without saving it.
- **GitHub budget.** Below 600 GraphQL points left, the queue refresh and pr-priority are skipped. When a
  fetch fails, the last known PR facts are kept rather than concluding every PR vanished.
- **Agent names.** herdr agent names don't survive a restart, so every pass restores the standard ones:
  `intake`, `orchestrator-<project>`, `qc-<project>`, `<repo>-<n>`.

## Hibernation and close-out

A parked agent holds several hundred MB (the agent CLI, browser automation, MCP servers), and enough of
them push the machine into swap, where low-memory reapers start killing background shells (including the
watcher).

- `bin/hibernate <repo> <n>` requires idle, no question pending, `ready for QC` on the PR (or
  `awaiting-ux-gate` with `--ux-gate`) and a resumable session on disk. It stops the processes whose cwd or
  command line lies in the agent's worktree or session scratchpad (plus descendants), closes the workspace
  and records `hibernated_at`. It never touches the agent CLI's ancestors (the pane shell), the QC worktree
  or anything on `QC_PORTS`. `--servers-only` keeps the session and stops just the dev stack and browser.
- **Automatic.** The watcher (not under `--peek`) hibernates agents idle at `ready for QC` for 5+ min,
  and closes out finished ones (`--closed-out`): PR merged, or QC complete plus "wrap-up done" on screen,
  or the issue closed with no open PR.
- Hibernated agents stay in the snapshot with status `hibernated`, so `qc_complete` and `pr_merged` still
  fire. `bin/resume-agent` brings one back with the same session (`--resume <id>`), recreating the
  worktree from the branch if needed; it prompts a live agent in place, and refuses (exit 3) while a
  question is pending on its screen.
- herdr reuses workspace ids after a close, so a stored id is trusted only while that workspace still
  carries the agent's name, and hibernation clears the ids.

## QC

- **Local QC.** `bin/qc start <pr#>` (or `--ref <branch>`) checks out the PR in one shared, reused
  worktree (`<repo root>/$QC_WORKTREE`, detached at the head), so dependency installs and builds stay
  incremental and agents' worktrees are never touched. The project's `QC_HOOK` owns the servers.
- **Feedback** is posted on the PR as "QC feedback (round N)" and delivered to the agent with
  `bin/resume-agent`; `ready for QC` comes off, and the agent re-applies it after fixing.
- **Pass** flips the label to `QC complete - ready to review` (`LABEL_QC_DONE`); the agent wraps up and
  says "wrap-up done", and the watcher closes it out.
- **Remote QC.** Trusted PR comments starting `QC:` become `qc_feedback` events, so a reviewer who only
  uses a browser (e.g. against a hosted preview service, the profile's "QC preview" section) can drive the
  same loop. Agents answer remote reviewers on the PR, never only in their session.
- **Fixtures.** GitHub's API can't attach files to comments. `bin/qc-fixture-push <pr#> <file>` stores test
  data on a never-merged branch (`FIXTURE_BRANCH`, default `qc-fixtures`) with git plumbing (no checkout),
  and prints the link for the checklist. Fixtures never go on the PR branch, or they merge with it.
- **Screenshots.** `bin/shots <pr#>` opens the PR's newest screenshot folder under
  `<worktree>/$SCREENSHOT_DIR`.
- **Ports.** Command agents never bind `QC_PORTS`; their own headless QC uses per-issue ports from the
  profile.

## PR priority labels

`bin/pr-priority` gives each open PR the best P-label among the issues it closes
(`closingIssuesReferences`, or the body's `Closes/Fixes/Resolves/Part of #N` for stacked and epic PRs,
which GitHub doesn't link). It also copies `CARRY_LABELS` (default `client-requested`), add-only. It never
downgrades: a higher P-label already on the PR stays. It runs after `gh pr create` and on every queue
refresh.

## Intake

The intake skill classifies each report, runs one bounded, fact-only look (duplicates, related docs and
memories, candidate files and entry points) into a "Starting points (unverified)" section with no
root-cause guesses, asks at most one clarification round, and files through `bin/file-issue` (typed,
labels validated, parent sub-issue attached, board status set). Agents never prompt it directly; they
queue reports with `bin/intake-submit`, and only an explicit "inbox" run triages the queue.

## Configuration

### Resolution (one place: `bin/lib.sh`)

- `PDO_CONFIG_DIRS`: colon-separated config dirs, default `${XDG_CONFIG_HOME:-~/.config}/project-dev-orchestration`.
  Each may hold `projects/<name>.env`, `prompts/`, `hooks/` and `config.env`. The first match wins.
- `config.env` files are sourced when `lib.sh` loads (the first dir wins); write `: "${KEY:=value}"` so a
  real environment variable still wins. A project env, sourced later, overrides plain assignments.
- `PDO_STATE_DIR`: default `${XDG_STATE_HOME:-~/.local/state}/project-dev-orchestration`.
- `PDO_INBOX`: the intake inbox, default `$PDO_STATE_DIR/intake-inbox`; `INTAKE_INBOX` is still honoured.
- Project: `--project`, else `$PDO_PROJECT`, else the project whose `REPO_ROOT` holds the cwd's repo
  (matched on the git common dir, so every worktree of a bare root matches; else by path prefix). No match
  fails with the list of known projects. There is no built-in default.
- While an env file is sourced, `$HERE` is the config dir that holds it. Relative hook, template and
  `CONTROL_DIR` paths resolve against that dir.
- Python scripts read the same resolution through `bin/pdo-config --json` (`bin/pdo_config.py`), and
  `bin/project-env [--project P] [KEY]` prints it for skills and humans.

### Project env keys

| Key | Default | Meaning |
|---|---|---|
| `ORG` | (required) | GitHub owner of the repos and the board |
| `PROJECT_NUMBER` | (none) | org project board number; the queue and claim need it |
| `REPO_ROOT` | (required) | `declare -A`: repo name → local clone root |
| `SELF_MANAGED_REPOS` | `()` | repos another manager owns; queue and watch skip them |
| `ROUTE_SKILL` | (required for spawn) | `declare -A`: route → first-prompt skill |
| `DEFAULT_MODEL` | `opus` | model alias for launched agents |
| `BRIEF_TEMPLATE` | see Spawning | dispatch brief template |
| `PRIMARY_REPO` | (none) | bare `#n` means this repo; default `--repo` for qc, shots, pr-agent, fixtures |
| `GH_USER` | (none) | pin agents' gh to this login; unset = no pin |
| `IDENTITY_HOOK` | (none) | `hook <dir>` prints extra wrapper words for an agent in that checkout |
| `TEAM_UP_HOOK` | (none) | extra `team-up` steps; gets team-up's unknown options |
| `SYSREPORT_HOOK` | (none) | extra `sysreport` lines |
| `QC_HOOK` | (none) | the QC servers (contract below) |
| `QC_REPO` | `PRIMARY_REPO` | repo `bin/qc` serves |
| `QC_WORKTREE` | `qc` | QC worktree dir name under the repo root |
| `QC_PORTS` | (none) | ports hibernation never stops |
| `FIXTURE_EXT` | (none) | the project's fixture extension (a mismatch warns) |
| `FIXTURE_BRANCH` | `qc-fixtures` | never-merged fixture branch |
| `SCREENSHOT_DIR` | `.omc/qa` | screenshot root inside a worktree |
| `CARRY_LABELS` | `client-requested` | issue labels copied onto PRs |
| `CWT_STATUS` | `Claude Work This` | board status that jumps the queue |
| `P_LABELS` | `P1-urgent P2-high P3-medium P4-low` | priority labels, best first |
| `LABEL_QC_READY` / `LABEL_QC_DONE` | `ready for QC` / `QC complete - ready to review` | QC state labels |
| `SYSTEM_MANAGER_WORKSPACE` | `System Manager` | named in the queue's `orchestrator-system` reason |
| `CONTROL_DIR` | the env's config dir | cwd of the standing orchestrator, QC and intake agents |
| `ORCHESTRATE_SKILL` / `QC_SKILL` / `INTAKE_SKILL` | `${PDO_SKILL_PREFIX}project-orchestrate` / `…project-qc-review` / `…project-intake` | standing agents' skills |
| `AGENT_CLI` | `claude` | agent CLI (only `claude` today) |
| `MAX_ACTIVE`, `WEEKLY_CEILING`, `FIVE_HOUR_CEILING` | 3, 80, 90 | concurrency and usage limits |

`PDO_SKILL_PREFIX` (environment or `config.env`) defaults to `/project-dev-orchestration:`, the Claude
Code plugin namespace. Set it to `/` when the skills are linked un-namespaced (`bin/install --link`).

Example project env (`<config dir>/projects/acme.env`, plain bash):

```bash
ORG=acme-co
PROJECT_NUMBER=3
declare -A REPO_ROOT=([acme-app]="$HOME/src/acme-app.git" [acme-engine]="$HOME/src/acme-engine")
PRIMARY_REPO=acme-app
declare -A ROUTE_SKILL=(
  [small]="${PDO_SKILL_PREFIX}project-small-feature-or-bug-fix"
  [design]="${PDO_SKILL_PREFIX}project-feature-design"
  [build]="${PDO_SKILL_PREFIX}project-feature-build"
)
QC_HOOK=hooks/acme-qc-hook        # relative: resolved against this config dir
QC_PORTS="3000 8080"
```

### Hooks

Hooks are executables. They get `PDO_HOME`, `PDO_PROJECT`, `PDO_ENV_DIR`, `PDO_STATE_DIR`, `ORG` and
`PRIMARY_REPO` in the environment, and may `source "$PDO_HOME/bin/lib.sh"` for helpers such as
`pdo_free_port`.

**`QC_HOOK <stop|start|wait|status> [options]`.** `bin/qc start` runs: `stop`, then fetch + checkout +
clean, then `start`, then writes `$PDO_QC_STATE/current.json` (merging `$PDO_QC_STATE/hook-current.json`
if `start` wrote one), then `wait`. Options `bin/qc` doesn't know (e.g. `--fresh-db`) are passed through.
Environment: `PDO_QC_STATE`, `PDO_QC_REPO`, `PDO_QC_ROOT`, `PDO_QC_WORKTREE`, `PDO_QC_PR`, `PDO_QC_REF`,
`PDO_QC_SHA`, `PDO_QC_BASE`, `PDO_QC_PREV_SHA` (the worktree's previous head, to skip an unchanged
dependency install) and `PDO_QC_KEY` (`pr:<n>` or `ref:<branch>`, e.g. to decide when to reseed a QC
database). The hook should never use a database that command agents start and stop, and should clone a
seed per served PR rather than roll migrations back.

## The project profile

The engine env above is for scripts. What agents need to know about a product repo lives in that repo,
in **`.agents/project-profile.md`** on the default branch; the skills cite its sections as `§<Section>`.

- **Location.** The worktree's top level (`git rev-parse --show-toplevel`); for a bare-root layout, the
  default branch's copy (`git show origin/HEAD:.agents/project-profile.md` against
  `git rev-parse --git-common-dir`). With no profile, a skill detects the obvious build tooling
  (package.json scripts, `*.sln`, pyproject, Cargo, go.mod), carries on with that, and offers to write one
  from [`templates/project-profile.md`](../templates/project-profile.md).
- **Sections** (exact `##` headings): `Identity`, `Layout`, `Build & checks`, `Tests`, `Dev servers`,
  `QC data`, `QC preview`, `Changelog`, `Review roles`, `Docs`, `Conventions`, `Do not`. What each holds is
  in [profile.md](profile.md) and the template.
- The repo's `AGENTS.md` gets a short "How work flows here" section from
  [`templates/AGENTS-workflow-section.md`](../templates/AGENTS-workflow-section.md); `CLAUDE.md` can be
  `@AGENTS.md` plus any Claude-only notes.

## Overlays

A private overlay is a config dir that sits first on `PDO_CONFIG_DIRS`: its project envs, prompts, hooks,
`config.env` and any project-only scripts. An overlay can keep old script paths working with a shim per
name that sets `PDO_CONFIG_DIRS` (and, if it wants the old default, `PDO_PROJECT`) and `exec`s the engine's
script, so prompts, briefs and memories that name the old paths still work.

## Lifecycle end state

A command agent runs until its PR is labelled `ready for QC`, then idles. After QC it wraps the PR up:
fixes, final push and comment. Merging stays manual.

## Borrowed ideas

- An atomic claim that rechecks the issue live, self-heals a stale card and sets both the assignee and
  the board status.
- A stop-guard hook that blocks "done" while the branch has no PR, or a PR that is neither `ready for QC`
  nor merged (fails open; gives up after 3 blocks).
- Lean dispatch briefs with pre-digested context.
- Board helpers that pass an explicit `--limit` and fail when the result count equals it.
