# project-dev-orchestration: design

How the engine works, and why. Living document. The day-to-day guide is [user-guide.md](user-guide.md).

Script names below are written `bin/<name>` (paths in this repo). Run them as `pdo <name> …` once
`bin/install --bin` has put the `pdo` dispatcher on PATH, or by absolute path from an engine checkout.

## Roles

- **System Manager.** The lead session that builds and maintains an install: the engine, its config dirs,
  hooks and skills. Reload it after a context clear with the `project-system-manager` skill; it reads
  [lessons-learned.md](lessons-learned.md) and runs `bin/sysreport`. Its workspace name is the project's
  `SYSTEM_MANAGER_WORKSPACE`.
- **Repo Manager.** Each project's lead, `Repo Manager (<project>)` (the project's `MANAGER`): tab 1 of
  the project's home (see "herdr layout"), opened by `pdo start-manager`, running the
  `project-repo-manager` skill. It runs that project's team on the human's and the CEO's direction:
  status, start and stop of its orchestrator, QC, QC Agent and intake (`pdo start-*`, `pdo team-up`),
  the floor, "work #N now", QC, agent QC, screenshots, and `pdo shutdown --project`. It hands engine
  changes to the System Manager. Hierarchy: CEO → Repo Manager → orchestrator, QC, QC Agent, command
  agents. A self-managed repo has its own (`REPO_MANAGER[<repo>]`, `start-manager --repo`). Without a
  Repo Manager (the default `MANAGER`), the orchestrator is the manager and tab 1.
- **Orchestrator.** One long-lived agent session, `Orchestrator (<project>)`: a tab in the project's
  home, started by its Repo Manager when told, running `/loop` over the `project-orchestrate` skill. It ranks the queue, claims issues, spawns command
  agents, routes events and moves board cards. It never edits product code.
- **Command agent.** One per issue or epic, in its own herdr tab of its home (`<Repo>-<issue#> <2-3 word brief>`)
  and its own git worktree. It runs a lifecycle skill and orchestrates its own sub-agents.
- **QC agent.** The standing `QC (<project>)` workspace (`project-qc-review`). It serves a PR on the
  project's QC servers for the human's hands-on QC, and relays feedback to the PR's command agent.
- **Intake agent.** The standing `intake` workspace (`project-intake`). It turns reports into typed,
  prioritised issues. Other agents queue reports with `bin/intake-submit`; the human drains the queue.
- **CEO.** The first session the human opens, one level above the per-project managers (`ceo`
  skill). It turns the human's direction ("work acme", "pause ti4") into team operations
  (`team-up`, `floor`), observes every project and the machine they share, gives the human one ranked
  "waiting on you" list, brokers cross-project requests and dependencies, and advises how resources
  are split. It never does project work. See [CEO](#ceo).
- **Human.** Answers questions directly in a command agent's workspace, does UX and QC review, and merges
  by hand.

## herdr layout (engine 0.12+)

One herdr workspace per manager, one tab per agent (`AGENT_LAYOUT=tabs`, the default):

- **Homes.** An orchestrated project's home is labelled with the project's name (`acme`): tab 1 its
  manager (`MANAGER`: `Repo Manager (acme)`, or `Orchestrator (acme)` in a project without one), then
  the orchestrator, `QC (acme)`, `QC Agent (acme)` and one tab per command agent
  (`<Repo>-<n> <brief>`) for every repo the orchestrator manages. A self-managed repo's home is labelled
  with the repo's name (`dnd3yond`): tab 1 `Repo Manager (dnd3yond)`, then its agents. When every repo of a
  project is self-managed, its standing QC tabs live in the primary repo's home (`pdo_team_home`;
  `TEAM_HOME` overrides). The CEO, `System Manager` and `intake` keep their own workspaces.
- **Names are labels.** The tab label is the agent's name everywhere the engine used a workspace label
  before. `bin/pdo_herdr.py` (`pdo herdr-agent`) is the one place that maps names to herdr places: it
  matches a tab label first, then a workspace label, so agents of the old layout (one workspace per
  agent, labelled with its name) keep working during the switch. watch, queue, fleet, sysreport,
  agent-meta, pr-agent, hibernate, resume-agent, spawn and the start-* scripts all go through it.
- **Placing.** `pdo_place <home> <name> <cwd>` (lib.sh) opens a tab in the home. Only the home's manager
  (`pdo_home_manager`) may create a missing home, so it is always tab 1; anyone else is refused with
  the command to run first (`pdo start-manager`, or `pdo start-orchestrator` when the orchestrator is the
  manager). team-up never starts a Repo Manager and refuses while it isn't running; when the
  orchestrator is the manager, team-up starts it first. A resumed old-layout agent reopens as a tab in
  its home.
- **Shutdown.** `pdo shutdown (--project P | --all) [--apply]` (a dry run by default) stops a team in
  order: orchestrators and their watchers, command agents (side processes stopped, tab closed,
  `hibernated_at` with `hibernate_reason: shutdown`; session id and claims kept, so `resume-agent`
  brings each back), served QC stacks, QC Agent and QC, intake (`--all` only), Repo Managers last. It
  never touches the CEO, the System Manager or any tab outside the fleet, and refuses (and lists) a tab
  with a question or menu pending.
- **Closing.** Always `herdr tab close`, never `herdr workspace close`: herdr closes a workspace with its
  last tab, so an old-layout agent's own workspace still goes, and a home with other agents never does.
  hibernate, spawn's rollback, the qc-review wrap-up and the orchestrator's `design_ready` step close tabs.
- **Status.** herdr reports `agent_status` per tab, and a blocked tab marks its whole home blocked in the
  sidebar. fleet and sysreport list status per tab, so a question in tab N reaches the CEO's list.
- **Migration.** `pdo relayout` (dry run unless `--apply`) renames each idle manager's old workspace to
  its home and its tab 1 to the manager's name, and restarts idle standing QC sessions as tabs there
  (nothing served, no agent-QC PR in progress). Live command agents are never moved; each moves into its
  home the next time it is hibernated and resumed. `AGENT_LAYOUT=workspaces` restores the old layout.

## Spawning

- `bin/spawn <repo> <n>` re-reads the issue live, picks the route, creates a worktree and branch (the worktree in
  `WORKTREE_PARENT[<repo>]`: the bare root, or `<clone>-worktrees/` next to a plain clone), writes
  the dispatch brief, opens a herdr workspace and launches the agent there with Remote Control on and the
  route's lifecycle skill as its first prompt. Then it claims the issue (`bin/claim`: the `managed-by:`
  label, a claim comment and the board status; see [Coordination between managers](#coordination-between-managers))
  and records metadata in `$PDO_STATE_DIR/agents/<Repo>-<n>.json`.
- It refuses duplicates (an open workspace, an existing worktree or branch), closed issues, pull requests,
  issues with an assignee (the human lock; with `CLAIM_ASSIGNS=1` the gh login's own assignment is a legacy
  claim and doesn't count), and issues carrying another manager's `managed-by:` label. It rolls back on failure. Every
  failure except `--dry-run` is logged, and `bin/queue` skips that issue for 24 h.
- Launching goes through `launch_agent` in `bin/lib.sh`, the one seam for other agent CLIs (`AGENT_CLI`;
  only `claude` today). It runs the CLI through `herdr pane run`, accepts the "trust this folder?" dialog
  only when it names the worktree it just created, and returns 2 when the agent is blocked on anything else.
- Every launch is prefixed by `identity_wrapper`: `bin/with-gh-user --user $GH_USER` when the project sets
  `GH_USER` (gh's active account is machine-wide and other sessions switch it), plus whatever words the
  project's `IDENTITY_HOOK` prints for that checkout (e.g. a bot identity for one repo).
- The engine's own scripts pin themselves the same way: `pdo_finalize` (bash) and `pdo_config.load` (python) set
  `GH_TOKEN` and the git helper for `GH_USER` (`pdo_gh_pin`, `bin/gh-pin.sh`), so `pdo spawn` can read a private
  repo the machine's active account can't see. A token a person set (`GH_TOKEN` or `GITHUB_TOKEN`) wins; one an
  engine pin set for another login (`PDO_GH_PIN`, e.g. another project's script calling this one) is replaced.
- `with-gh-user` pins both gh (`GH_TOKEN`) and git over HTTPS: it appends two `GIT_CONFIG_KEY_<i>`/`VALUE_<i>`
  entries after the existing `GIT_CONFIG_COUNT` (reset the github.com credential helpers, then
  `!gh auth git-credential`, which answers with `GH_TOKEN`), so `git push` and `fetch` use the same login and no
  config file changes. If entries already in the environment set a github.com helper, it adds none and the outer
  chain stays in charge. An `IDENTITY_HOOK` wrapper runs inside it, so it should append the same way rather than
  set `GIT_CONFIG_COUNT` outright. A person-started session pins one call with
  `pdo with-gh-user --user <login> git push …`.
- Every launch also sets `PDO_DISPATCHED=1` in the agent's environment (`agent_command` in `bin/lib.sh`),
  so the agent knows it was started by the engine and skips the collaborator's one-time guide check.
- The dispatch brief is `BRIEF_TEMPLATE`, else the first `prompts/dispatch-brief.md` in the config dirs,
  else the engine's `prompts/dispatch-brief.md`. Its placeholders (upper-case names in double braces) are
  filled in: REF, URL, NAME, WORKTREE, BRANCH, BASE, ROUTE, SKILL, TITLE, TYPE, LABELS, BODY, DIRECTIVES, NUMBER, ENGINE.
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

- **Board-less mode** (no `PROJECT_NUMBER`): the queue is the open issues labelled `QUEUE_LABEL` (default
  `queue:work`, matched without case), ranked as above with no CWT and no board-status exclusions (the
  `managed-by:` claim label marks work in progress). The usual exclusions and priority inheritance apply, and a
  blocker of queued work joins the queue even without the label. `claim` still applies the label and the claim
  comment and skips only the board move.
- **Auto-spawn:** CWT and P1–P3. P4 and unprioritised wait for `drain`.
- **Spawn floor:** `bin/floor P2` (persisted per project) stops anything below it from auto-spawning,
  CWT included.
- **Urgent bypass:** P1 AND on CWT starts even with no free slot and over the usage ceiling.
- **Fleet advice (opt-in):** with `FLEET_ADVICE=honour` and a fresh `fleet-advice.json`, a `hold`
  makes everything but the urgent bypass `auto_spawn: false`, and `suggested_max_active` caps
  `max_active` (see [CEO](#ceo)).
- **Priority inheritance:** an issue that blocks others runs at the best P-level (and CWT) among the
  issues it transitively holds up, when being blocked is their only exclusion. A P4 blocking a P2 runs
  as P2; otherwise it would deadlock behind `drain`.
- **Excluded** (listed with `--all`): assigned, another manager's `managed-by:<slug>` label (reason
  `managed-by:<slug>`; this project's own label shows as `claimed`), `on-hold`, `likely-fixed`, `epic-phase`,
  a spawn failure in the last 24 h, `needs-triage` (unless on CWT), GitHub's native "blocked by" an open issue
  (reason `blocked-by:<ref>[,<ref>]`; see below), already In Progress / In
  Review / Done, an open workspace, Epics without a `route:*` label, and `orchestrator-system` work (the
  System Manager owns it).
- **Native blockers.** The REST issue list carries `issue_dependencies_summary.blocked_by` (open blockers
  only). For the issues where it is non-zero, one GraphQL query per repo (aliases, 50 issues each, about one
  point) reads `blockedBy` to name them. If that read fails the reason falls back to the count
  (`blocked-by:2`). GitHub updates the summary a few seconds after a dependency is added, so a brand-new
  link can take one queue refresh to show.
- The board fetch passes an explicit `--limit` and fails when the count equals it (silent truncation).

## Concurrency and the usage budget

- At most `MAX_ACTIVE` (default 3) **active** command agents. Parked agents (PR at `ready for QC` or QC
  complete, `likely-fixed`, `on-hold`, a design handed to build, idle at `awaiting-ux-gate`) don't count.
- Spawning stops at `WEEKLY_CEILING` % of the weekly usage budget (default 90, keeping 10% for manual and
  hot work), and pauses at `FIVE_HOUR_CEILING` % of the 5-hour window (default 90). Usage comes from a
  cache file (`USAGE_CACHE`; the oh-my-claudecode HUD's cache by default). Missing data never blocks
  silently: it is reported as unknown.
- **PR cap (per repo):** when `<project>-pr-cap` (default 10) open PRs in one repo are waiting on the human,
  that repo's issues stop spawning, so each repo's pace follows the human's merge rate there. Other repos
  carry on; one repo's QC backlog doesn't hold up another (Matt, 2026-10-22).

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
  `hibernate_failed`, `event_hook_failed`, `tmp_swept`, and hook events marked `"quiet": true`) ride along with the
  next wake.
- **Project events.** `WATCH_EVENT_HOOK` adds project-specific events to each snapshot (contract under
  Hooks, "Watcher event hook").
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

- `bin/hibernate <repo> <n>` requires idle, no question pending, `ready for QC` or `QC escalated` on the
  PR (or `awaiting-ux-gate` with `--ux-gate`) and a resumable session on disk. It stops the processes whose cwd or
  command line lies in the agent's worktree or session scratchpad (plus descendants), closes the workspace
  and records `hibernated_at`. It never touches the agent CLI's ancestors (the pane shell), the QC worktree
  or anything on `QC_PORTS` / `AGENT_QC_PORTS`. `--servers-only` keeps the session and stops just the dev stack and browser.
- **Automatic.** The watcher (not under `--peek`) hibernates agents idle at `ready for QC` for 5+ min,
  and closes out finished ones (`--closed-out`): PR merged, or `QC complete` / `Ready for Merge` plus
  "wrap-up done" on screen,
  or the issue closed with no open PR.
- Hibernated agents stay in the snapshot with status `hibernated`, so `qc_complete` and `pr_merged` still
  fire. `bin/resume-agent` brings one back with the same session (`--resume <id>`), recreating the
  worktree from the branch if needed; it prompts a live agent in place, and refuses (exit 3) while a
  question is pending on its screen.
- herdr reuses workspace ids after a close, so a stored id is trusted only while that workspace still
  carries the agent's name, and hibernation clears the ids.
- **/tmp cleanup (2026-10-25).** /tmp is often a RAM-backed tmpfs, and agents failed on a full one. Most
  of it was headless browser profiles (200-300 MB each) left in agents' Claude scratchpads
  (`/tmp/claude-<uid>/<slug>/<session>/`). `bin/tmp-sweep` removes what nothing uses (no process has
  its cwd there or names it on its command line):
  - browser profiles older than 30 min;
  - the whole scratchpad of a finished agent (`done_tracking`);
  - scratchpads untouched for 7 days;
  - files older than a day in shared tool caches (jest, node/v8 compile caches, tsx, playwright).

  Hibernation removes the stopped session's profiles at once; the watcher runs the full sweep at most
  hourly. Sessions started in the home directory (a personal assistant, not an agent) are skipped.
  A closed-out agent keeps the rest of its scratchpad, since a UX review may resume it.
  Owner decision (same day): an agent with an open PR (or still running) never loses its scratchpad,
  not even to the 7-day rule, since it may be resumed; only its idle browser profiles go, because they
  are what filled /tmp and the browser makes a fresh one. A gh failure keeps all of that repo's
  agents. The QC Agent is never resumed: `recycle-agent-qc` removes the ended session's whole
  scratchpad (`tmp-sweep --session ID --whole`).

## QC

- **Local QC.** `bin/qc start <pr#>` (or `--ref <branch>`) checks out the PR in one shared, reused
  worktree (`<worktree parent>/$QC_WORKTREE`, detached at the head), so dependency installs and builds stay
  incremental and agents' worktrees are never touched. The project's `QC_HOOK` owns the servers.
- **Port ownership.** Before the hook's `stop` (on `start` and `stop`), `bin/qc` checks the instance's ports. A
  listener it didn't start (not recorded in `$PDO_QC_STATE/listeners` at its last start, not a descendant of one,
  not running in the QC worktree) is probably the human's own dev server: `qc` exits 1 and names it, unless
  `--force` or `QC_PORTS_SHARED=1` (QC uses the human's dev ports on purpose and may stop whatever is there).
- **Feedback** is posted on the PR as "QC feedback (round N)" and delivered to the agent with
  `bin/resume-agent`; `ready for QC` comes off, and the agent re-applies it after fixing.
- **Pass** flips the label to `Ready for Merge` (`LABEL_MERGE_READY`); the agent wraps up and says
  "wrap-up done", and the watcher closes it out.
- **The handoff is labels and reviews.** `ready for QC` (`LABEL_QC_READY`) means the PR waits for QC.
  A pass label is `QC complete - ready to review` (`LABEL_QC_DONE`: agent QC passed, a human UX review
  follows) or `Ready for Merge` (`LABEL_MERGE_READY`). The watcher's `qc_complete` fires once per pass, on
  whichever appears first, whoever added it; the UX pass (QC complete → Ready for Merge) fires nothing,
  so the agent is told to wrap up exactly once, at the first pass. Feedback on a PR at QC complete
  removes that label, so the next pass fires again. A PR carrying `ready for QC` and a pass label
  counts as passed.
- **Agent QC** (on when `AGENT_QC_PORTS` is set). A standing "QC Agent (<project>)" workspace
  (`bin/start-agent-qc`, started by `team-up`, `/loop` over the `project-agent-qc` skill) QCs every
  `ready for QC` PR in `AGENT_QC_REPOS` before a human sees it, one at a time, highest P-label first
  (`bin/agent-qc next`), with an in-progress marker under `$PDO_STATE_DIR/agent-qc`. It doesn't use a
  command-agent slot.
  - After each verdict the skill runs `bin/recycle-agent-qc` (detached). Once the turn ends, with no PR
    in progress and no question on screen, it sends `/exit` (choosing "Exit and stop tasks", which ends
    the pending `/loop` wakeup) and `start-agent-qc` relaunches the loop in the same workspace. A
    restart, not `/clear`: a running session keeps the plugin version it started with, and `/clear`
    doesn't restart the process (the /exit + relaunch was tested 2026-10-22; a /loop wakeup survives
    `/clear`, so `/clear` alone would also have worked for the context). A long-lived QC Agent had filled its context in ~2 days.
    `AGENT_QC_RECYCLE=0` turns it off.
  - `bin/qc --agent` is a second QC instance: worktree `<worktree parent>/$AGENT_QC_WORKTREE` (default
    `qc-agent`), state `$PDO_STATE_DIR/agent-qc`, ports `AGENT_QC_PORTS`; the hook sees
    `PDO_QC_INSTANCE=agent` and must use its own data store, never the human's.
  - It tests the checklist, the touched areas and their neighbours (browser, direct API calls,
    two-user concurrency). A fail posts "Agent QC findings (round N)" (marker
    `<!-- agent-qc:findings round=N -->`), removes `ready for QC` and resumes the agent; round
    `AGENT_QC_MAX_ROUNDS` (default 2) adds `QC escalated` instead and stops. A pass posts a short
    classification (`<!-- agent-qc:pass -->`) by the visible-change rule, then `bin/agent-qc verdict`
    flips the labels: `QC complete - ready to review` (UX review) or `Ready for Merge` +
    `UX testing skipped`. A PR or linked issue labelled `needs UX review` (`LABEL_NEEDS_UX`; intake sets
    it, `CARRY_LABELS` copies it onto PRs) always gets UX review; when unsure, review.
  - Project know-how (login, seed users, browser notes) lives in the file `AGENT_QC_NOTES` names, or per
    repo in `AGENT_QC_NOTES_BY_REPO[<repo>]` (`bin/agent-qc notes <repo>`). A repo's notes may define its
    own `## Pass rule`, which replaces the visible-change rule for that repo. A headless repo (no UI) skips
    the browser checks; its checklist runs through commands, and concurrency means parallel API calls. A
    review-path extra (e.g. requesting a hosted preview) is `AGENT_QC_REVIEW_HOOK <repo> <pr#>`, run by
    `bin/agent-qc verdict … pass-ux` itself, so the agent never posts trigger comments.
- **Awaiting the human** (the PR cap, parking, the waiting lists): `ready for QC`, `QC complete - ready to
  review`, `Ready for Merge` and `QC escalated`. The snapshot's `human_queue` lists open PRs by stage
  (`agent_qc`, `ux_review`, `ready_for_merge`, `qc_escalated`); where agent QC runs, `ready for QC` PRs
  leave `waiting_on_you`.
- **Remote QC feedback** is a standard GitHub PR review with state *Request changes* (`CHANGES_REQUESTED`)
  from a trusted author (association OWNER, MEMBER or COLLABORATOR). The watcher reads the newest reviews
  of each open PR in its existing PR query (no extra call), and raises each new one once as `qc_feedback`
  (`source: "review"`), which the orchestrator routes to the PR's agent. A reviewer who only uses a browser
  can therefore drive the whole loop. Agents answer remote reviewers on the PR, never only in their
  session. GitHub doesn't let a PR's author request changes on it, so the author gives feedback in the
  agent's session (or with local QC) instead.
- **Project conventions on top** (PR-comment triggers, a hosted preview service, chat commands) belong to
  the project: its `WATCH_EVENT_HOOK` turns them into the same events, and the profile's
  `## Project extras` tells humans and agents how to use them.
- **Headless repos** (no UI): QC cases are fixture inputs with expected outputs and the command that checks them
  (profile "QC data"); the same checklist, fixture branch and handoff apply.
- **Fixtures.** GitHub's API can't attach files to comments. `bin/qc-fixture-push <pr#> <file>` stores test
  data on a never-merged branch (`FIXTURE_BRANCH`, default `qc-fixtures`) with git plumbing (no checkout),
  and prints the link for the checklist. Fixtures never go on the PR branch, or they merge with it.
- **Screenshots.** `bin/shots <pr#>` opens the PR's newest screenshot folder under
  `<worktree>/$SCREENSHOT_DIR`.
- **Ports.** Command agents never bind `QC_PORTS` or `AGENT_QC_PORTS`; their own headless QC uses
  per-issue ports from the profile.

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
  `bin/project-env [--project P] [KEY]` prints it for skills and humans. `project-env --board` looks up the
  board's node id, Status field id and column option ids live, so the profiles of several repos sharing one
  board cite it instead of copying ids.

### Project env keys

| Key | Default | Meaning |
|---|---|---|
| `ORG` | (required) | GitHub owner of the repos and the board |
| `PROJECT_NUMBER` | (none) | org project board number; without one the queue is board-less (`QUEUE_LABEL`) and claim skips the board move |
| `QUEUE_LABEL` | `queue:work` | board-less projects only: the issue label that puts an issue in the queue; empty = no queue |
| `REPO_ROOT` | (required) | `declare -A`: repo name → local clone root |
| `SELF_MANAGED_REPOS` | `()` | repos another manager owns; queue and watch skip them |
| `AGENT_LAYOUT` | `tabs` | `tabs`: one herdr workspace per manager, one tab per agent; `workspaces`: one workspace per agent (pre-0.12) |
| `REPO_MANAGER_SKILL` | `${PDO_SKILL_PREFIX}project-repo-manager` | the skill `start-manager` runs |
| `TEAM_HOME` | | the standing agents' home workspace (default: the project's name, or the primary repo's when every repo is self-managed) |
| `REPO_MANAGER` | `()` | `declare -A`: self-managed repo → its manager's workspace/session name (`fleet`) |
| `MANAGER` | `Orchestrator (<p>)` with a board, else empty | the project manager's workspace/session name; empty = the human |
| `MANAGER_SLUG` | a slug of `MANAGER` (else of the project name), e.g. `orchestrator-acme` | the claim label is `managed-by:<slug>`; cut to 39 characters |
| `CLAIM_ASSIGNS` | `0` | `1` = `claim` also assigns the gh login (the pre-0.6 lock); `0` leaves assignees to humans |
| `PORTFOLIO_PRIORITY` | `3` | rank across projects, 1 = highest (`fleet` advice) |
| `RESOURCE_PROFILE` | `medium` | `light` / `medium` / `heavy`: MB and usage weight per active agent |
| `AGENT_MB` / `AGENT_USAGE_WEIGHT` | from the profile | override the profile's per-agent MB / usage weight |
| `FLEET_ADVICE` | `ignore` | `honour`: queue and watch apply fresh `fleet-advice.json` |
| `ROUTE_SKILL` | (required for spawn) | `declare -A`: route → first-prompt skill |
| `DEFAULT_MODEL` | `opus` | model alias for launched agents |
| `BRIEF_TEMPLATE` | see Spawning | dispatch brief template |
| `PRIMARY_REPO` | (none) | bare `#n` means this repo; default `--repo` for qc, shots, pr-agent, fixtures |
| `GH_USER` | (none) | pin gh and git to this login: launched agents (`with-gh-user`) and every engine script (`pdo_finalize`, `pdo_config.load`), unless `GH_TOKEN`/`GITHUB_TOKEN` is already set; unset = no pin |
| `IDENTITY_HOOK` | (none) | `hook <dir>` prints extra wrapper words for an agent in that checkout |
| `TEAM_UP_HOOK` | (none) | extra `team-up` steps; gets team-up's unknown options |
| `SYSREPORT_HOOK` | (none) | extra `sysreport` lines |
| `QC_HOOK` | (none) | the QC servers (contract below) |
| `BRANCH_PREFIX` | `bug=fix default=feat` | `spawn`'s small-route branch prefix, `<key>=<prefix>` pairs matched without case against the issue type, or for an issue without a type (user-owned repos) its labels in order, else `default`; e.g. `bug=fix task=chore docs=docs default=feat` |
| `QC_REPO` | `PRIMARY_REPO` | repo `bin/qc` serves |
| `WORKTREE_PARENT` | bare root, or `<clone>-worktrees` | `declare -A`: repo → the dir that holds its agent, QC and agent-QC worktrees (`spawn`, `qc`, `resume-agent`); the default keeps worktrees out of a plain clone's checkout. Upgrading from 0.7: a plain clone's existing `qc` worktree stays registered inside the clone (remove it with `git worktree remove`), or set the entry to the clone to keep the old place |
| `QC_WORKTREE` | `qc` | QC worktree dir name under the worktree parent |
| `QC_PORTS` | (none) | ports hibernation never stops |
| `QC_PORTS_SHARED` | `0` | `1`: `QC_PORTS` are the human's dev ports on purpose, so `qc` may stop a listener it didn't start (otherwise it refuses without `--force`) |
| `FIXTURE_EXT` | (none) | the project's fixture extension (a mismatch warns) |
| `FIXTURE_EXT_BY_REPO` | `()` | `declare -A`: repo → its fixture extension, for repos whose format differs; `qc-fixture-push --repo` uses it before `FIXTURE_EXT` |
| `WATCH_EVENT_HOOK` | (none) | executable the watcher runs each snapshot for project-specific events (contract below) |
| `WATCH_EVENT_HOOK_TIMEOUT` | `120` | seconds before the watcher abandons a hook run |
| `FIXTURE_BRANCH` | `qc-fixtures` | never-merged fixture branch |
| `SCREENSHOT_DIR` | `.omc/qa` | screenshot root inside a worktree |
| `CARRY_LABELS` | `client-requested` | issue labels copied onto PRs (comma-separated when a name has spaces) |
| `CWT_STATUS` | `Claude Work This` | board status that jumps the queue |
| `P_LABELS` | `P1-urgent P2-high P3-medium P4-low` | priority labels, best first |
| `LABEL_QC_READY` / `LABEL_QC_DONE` | `ready for QC` / `QC complete - ready to review` | QC state labels (QC done = agent QC passed, UX review next) |
| `LABEL_MERGE_READY` / `LABEL_UX_SKIPPED` | `Ready for Merge` / `UX testing skipped` | all QC passed; agent QC judged no visible change |
| `LABEL_NEEDS_UX` / `LABEL_QC_ESCALATED` | `needs UX review` / `QC escalated` | force a UX review; agent QC failed `AGENT_QC_MAX_ROUNDS` times |
| `AGENT_QC_PORTS` | (none: agent QC off) | the QC Agent's reserved ports; hibernation never stops them |
| `AGENT_QC_REPOS` / `AGENT_QC_WORKTREE` | `QC_REPO` / `qc-agent` | repos agent QC takes; its worktree under each worktree parent |
| `AGENT_QC_REVIEW_HOOK` | (none) | run with `<repo> <pr#>` after a UX-review pass |
| `AGENT_QC_MAX_ROUNDS` / `AGENT_QC_NOTES` / `AGENT_QC_SKILL` | `2` / (none) / `<prefix>project-agent-qc` | failed rounds before escalation; the project's agent-QC know-how file; the skill |
| `AGENT_QC_NOTES_BY_REPO` | `()` | `declare -A`: repo → its own agent-QC notes file (recipe, optional `## Pass rule`); repos without an entry use `AGENT_QC_NOTES` |
| `SYSTEM_MANAGER_WORKSPACE` | `System Manager` | named in the queue's `orchestrator-system` reason |
| `CONTROL_DIR` | the env's config dir | cwd of the standing orchestrator, QC and intake agents |
| `ORCHESTRATE_SKILL` / `QC_SKILL` / `INTAKE_SKILL` | `${PDO_SKILL_PREFIX}project-orchestrate` / `…project-qc-review` / `…project-intake` | standing agents' skills |
| `AGENT_CLI` | `claude` | agent CLI (only `claude` today) |
| `MAX_ACTIVE`, `WEEKLY_CEILING`, `FIVE_HOUR_CEILING` | 3, 90, 90 | concurrency and usage limits |

`PDO_SKILL_PREFIX` (environment or `config.env`) defaults to `/pdo:`, the Claude
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

**Watcher event hook (`WATCH_EVENT_HOOK`).** The extension point for project-specific signals (PR-comment
commands, another service's state). `bin/watch` runs it once per snapshot, after the PR index is read,
with no arguments and a JSON context on stdin:

```json
{"version": 1, "project": "acme", "org": "acme", "repos": ["widget"],
 "since": "2026-10-16T18:00:00Z", "now": "2026-10-16T18:05:00Z", "peek": false,
 "trusted_associations": ["COLLABORATOR", "MEMBER", "OWNER"], "state_dir": "/home/u/.local/state/pdo",
 "labels": {"qc_ready": "ready for QC", "qc_done": "QC complete - ready to review", "merge_ready": "Ready for Merge",
            "qc_escalated": "QC escalated", "ux_skipped": "UX testing skipped", "needs_ux": "needs UX review"},
 "prs": [{"repo": "widget", "number": 5, "url": "https://github.com/acme/widget/pull/5", "head": "feat/5",
          "head_sha": "abc123", "base": "main", "labels": ["ready for QC"], "draft": false,
          "mergeable": "MERGEABLE"}]}
```

- `repos` are the managed repos (`REPO_ROOT` minus `SELF_MANAGED_REPOS`); `prs` are their open PRs.
- `since` is where the previous successful run's `now` left off (10 minutes ago on a first run, never more
  than 7 days back). It advances only after a clean run, so a failed run is retried over the same window:
  the hook must dedupe by its own ids (kept under `state_dir`, in a file named after the hook).
- `peek: true` (also `PDO_WATCH_PEEK=1`) is `watch --peek`: report what you find, but change nothing (no
  labels, comments or state writes).
- Only `trusted_associations` authors should count, the same rule the watcher applies to reviews.
- The usual hook environment applies (`PDO_STATE_DIR`, `PDO_PROJECT`, …) and the watcher's `gh` login.

It prints a JSON array of events on stdout, in the watcher's own shapes, e.g.
`{"type": "qc_feedback", "repo": "widget", "number": 5, "id": 901, "author": "boss", "url": "…", "body": "…"}`.
The watcher merges them as if it had found them: a wake event ends `--until-event`, and an event with
`"quiet": true` (or a quiet type) rides along with the next wake. Hook events skip the snapshot diff,
so each must be emitted once. Items that aren't objects with a string `type` are dropped with a warning;
at most 200 are taken per run.

Robustness: a run is killed after `WATCH_EVENT_HOOK_TIMEOUT` seconds (default 120). A timeout, a non-zero
exit, output that isn't a JSON array, a missing file, or a GitHub outage (the hook is skipped when the PR
index can't be read) prints a warning on stderr and adds the quiet event `event_hook_failed`; the watcher
carries on. The hook's last few stderr lines are echoed with a `watch: hook:` prefix.

## The project profile

The engine env above is for scripts. What agents need to know about a product repo lives in that repo,
in **`.agents/project-profile.md`** on the default branch; the skills cite its sections as `§<Section>`.

- **Location.** The worktree's top level (`git rev-parse --show-toplevel`); for a bare-root layout, the
  default branch's copy (`git show origin/HEAD:.agents/project-profile.md` against
  `git rev-parse --git-common-dir`). With no profile, a skill detects the obvious build tooling
  (package.json scripts, `*.sln`, pyproject, Cargo, go.mod), carries on with that, and offers to write one
  from [`templates/project-profile.md`](https://github.com/binerbuddy/project-dev-orchestration/blob/main/templates/project-profile.md).
- **Sections** (exact `##` headings): `Identity`, `Layout`, `Build & checks`, `Tests`, `Dev servers`,
  `QC data`, `Changelog`, `Review roles`, `Docs`, `Conventions`, `Project extras` (optional), `Do not`. What each holds is
  in [profile.md](profile.md) and the template.
- The repo's `AGENTS.md` gets a short "How work flows here" section from
  [`templates/AGENTS-workflow-section.md`](https://github.com/binerbuddy/project-dev-orchestration/blob/main/templates/AGENTS-workflow-section.md); `CLAUDE.md` can be
  `@AGENTS.md` plus any Claude-only notes.

## CEO

One level above the per-project managers, and the first session the human opens. "Observe and
coordinate, observe the system's constraints, and prioritise the managers' allocations; not a strict
slot queue, since projects need different amounts of resources." The human's current direction
decides which teams run: the CEO starts them (`team-up`) and pauses the rest (`floor P1`); the advice
below is the safety rail, not the plan. It never does project work.

Standing sessions are named `<Role> (<scope>)`: `CEO`, `System Manager`, `intake`,
`Orchestrator (<project>)` (the project's `MANAGER`), `QC (<project>)`, `QC Agent (<project>)`,
`Repo Manager (<repo>)` (a self-managed repo's `REPO_MANAGER`); command agents are `<Repo>-<n> <slug>`.

- **`bin/fleet`** (read-only) enumerates every project env along `PDO_CONFIG_DIRS` and reports, per
  project: its manager (`MANAGER`; `REPO_MANAGER` for `SELF_MANAGED_REPOS`) and how to reach it
  (peer messaging, else the herdr agent, else the human); active, parked, hibernated (split by
  whether an open PR remains), stalled and standing agents (agents in a `SELF_MANAGED_REPOS` repo on a
  separate "self-managed (owner: <REPO_MANAGER>)" line: out of active/MAX and the advice, in the memory
  estimate), from the agent metadata, herdr's
  workspace/agent lists and the watcher's last saved snapshot; what waits on the human (QC-passed
  PRs, `awaiting-ux-gate` issues, pending questions, `ready for QC` PRs, the intake inbox); the
  queue's eligible and auto-spawn counts; open PRs awaiting the human against the PR cap. System
  constraints: weekly and 5-hour usage (`USAGE_CACHE`), free memory and swap, disk free on the
  state dir and repo roots (one line per filesystem), GraphQL and core rate limits per distinct
  `GH_USER` (a token from `gh auth token -u`, never a switch), and the herdr agent count.
- **Allocation advice:** per project `go`, `slow` or `hold`, a reason and a soft
  `suggested_max_active`. Hard limits first (disk under 5 GB, weekly usage over the ceiling = only
  `PORTFOLIO_PRIORITY` 1, 5-hour ceiling, memory under 3 GB available = hold heavy projects, swap
  half full, fewer than 600 GraphQL points); then the spare memory (available minus a 2 GB reserve)
  is shared out in priority order, each new agent costing its `RESOURCE_PROFILE` MB (light 400,
  medium 900, heavy 1800; usage weights 0.5 / 1 / 2). The full rules and thresholds are in
  `skills/ceo/references/allocation.md`.
- **Advice file.** Only `fleet --write-advice` writes `fleet-advice.json` (into each project's state
  dir). A project with `FLEET_ADVICE=honour` and advice under 2 h old: `queue` makes `hold` rows
  `auto_spawn: false` (`fleet_hold`) except the urgent bypass, and bounds `max_active` by
  `suggested_max_active`; `watch` computes `free_slots` with that bound. The default, `ignore`,
  changes nothing; `queue` shows the advice in its summary line either way. Stale advice is ignored.
- **Cross-project dependencies:** `fleet deps add|list|done "<org/repo#n>" blocks "<org/repo#m>"`
  in `$PDO_STATE_DIR/fleet-deps.json`, mirrored as GitHub's native dependency (below). `fleet` lists
  the open ones, flags any whose blocker has closed or merged, and also lists native cross-repo
  dependencies that exist only on GitHub.
- **Claims:** per manager, the open issues carrying its `managed-by:<slug>` label, and **stale
  claims**: an issue labelled by one of this install's managers with no live workspace and no
  hibernated agent still in progress (needs herdr; without it, stale claims are unknown).
- **Degrades gracefully.** No herdr (metadata only), no board (queue depth unknown), a gh failure
  or no usage data: each is a warning in the report, never a crash and never "fine".
- **Escalation.** The other-repos rule escalates through it: an agent asks its manager; when another
  project's manager owns the repo, that manager asks the CEO, which brokers with the
  owner. Peers never grant approvals; holding a project needs the human's yes, and it asks a
  project's manager rather than hibernating that project's agents itself.

## Coordination between managers

Several managers (project orchestrators, leads that self-manage a repo, people's own agents) can work
the same repos. Three GitHub-side mechanisms keep them from colliding; anyone's agent can read them
without the engine.

- **Claim labels.** `bin/claim` adds `managed-by:<MANAGER_SLUG>` (it creates the label, colour `c5def5`,
  description "Worked by agents of <MANAGER>", when the repo lacks it: the one label it may create), posts
  one comment ("Claimed by <agent> (manager: <MANAGER>). Coordinate through that manager before working on
  this issue.") and records the label and the comment id in the agent metadata (`claim_label`,
  `claim_comment_id`). It refuses an issue with another manager's label, and one with an assignee.
- **The assignee is a human lock again.** With `CLAIM_ASSIGNS=0` (the default) claim never assigns, and any
  assignee blocks claim, spawn and the queue. `CLAIM_ASSIGNS=1` keeps the pre-0.6 behaviour (claim assigns
  the gh login, whose own assignment then doesn't block) for installs whose live issues are still assigned
  that way; switch it off after relabelling them.
- **Release.** `bin/hibernate --closed-out` (merged, QC passed and wrapped up, or closed) removes the label;
  plain hibernation keeps it (still in progress). The watcher (not under `--peek`) also releases finished
  agents whose metadata still records the label: merged or closed after they hibernated, or a release that
  failed. `pdo claim --release <repo> <n> [--unassign]` releases by hand.
- **Native dependencies.** `pdo fleet deps add A blocks B` adds GitHub's "B is blocked by A":
  `POST /repos/{o}/{r}/issues/{B}/dependencies/blocked_by` with `issue_id` = A's numeric issue id (the REST
  `id`, not its number); an existing link (HTTP 422 "already been taken") counts as added. `deps done`
  calls `DELETE …/dependencies/blocked_by/{A's id}`. GitHub refuses a pull request as blocker ("Target issue
  may only be an issue"), and a repo or blocker the login can't read is a 404: then the pair stays local, a
  coordination comment on B says so, and `deps add` warns; `deps done` posts the matching "no longer
  blocked" comment. The queue holds natively blocked issues (`blocked-by:<ref>`).
- **Coordination log.** `pdo fleet note <org/repo#n> "<text>" [--as NAME]` posts a comment headed
  `**Coordination (<NAME>):**` (NAME defaults to `$PDO_COORDINATOR`, else `CEO`) and appends it to
  `$PDO_STATE_DIR/coordination-log.jsonl`. The CEO logs every cross-manager agreement
  (ordering, hand-off, ownership) this way on each issue involved.

gh calls for another org run as the `GH_USER` of a project whose `ORG` owns the repo (`gh auth token -u`;
never a switch).

## Overlays

A private overlay is a config dir that sits first on `PDO_CONFIG_DIRS`: its project envs, prompts, hooks,
`config.env` and any project-only scripts. An overlay can keep old script paths working with a shim per
name that sets `PDO_CONFIG_DIRS` (and, if it wants the old default, `PDO_PROJECT`) and `exec`s the engine's
script, so prompts, briefs and memories that name the old paths still work.

## Lifecycle end state

A command agent runs until its PR is labelled `ready for QC`, then idles. After QC it wraps the PR up:
fixes, final push and comment. Merging stays manual.

## Borrowed ideas

- An atomic claim that rechecks the issue live, self-heals a stale card and sets the claim marker and
  the board status.
- A stop-guard hook that blocks "done" while the branch has no PR, or a PR that is neither `ready for QC`
  nor merged (fails open; gives up after 3 blocks).
- Lean dispatch briefs with pre-digested context.
- Board helpers that pass an explicit `--limit` and fail when the result count equals it.
