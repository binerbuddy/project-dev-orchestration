# Running the dev team: user guide

The human's guide to an agent team run by project-dev-orchestration. You talk to one session, the
**System Manager**, and it runs everything else. Examples use a made-up project, `acme`, whose main repo is
`widget`.

## The 30-second version

0. First time on this machine: install the plugin, open your agent in the repo and run `/project-setup repo+team`.
   It installs the engine (`pdo`) from the plugin and registers the repo.
1. Open an agent session in herdr, anywhere, named CEO (`claude -n CEO`, workspace "CEO").
2. Type: `/ceo fire up acme`
3. It checks every project, starts anything of acme's team that isn't running (intake, QC, the
   orchestrator, and any extras your `TEAM_UP_HOOK` adds), then gives you one "waiting on you" list.

Use the same command after `/clear`, or in a brand-new session, to get the CEO back up to speed.
(With the Claude Code plugin the skill shows as `/pdo:ceo`.) The CEO runs the teams; the **System
Manager** (`/project-system-manager`, workspace "System Manager") changes and repairs the system
itself, and takes the CEO's hand-offs.

## Who's who

| Agent | herdr workspace | What it does | You talk to it when… |
|---|---|---|---|
| **CEO** | CEO | Runs the teams: starts and pauses them on your direction, one "waiting on you" list across projects, brokers between projects. | Always first: tell it what to work on. |
| **System Manager** | System Manager | Builds and maintains the system itself; fixes the machinery. Takes change requests from the CEO. | Something's broken, or you want to change how the system works. |
| **Orchestrator** | Orchestrator (acme) | Picks issues from the board in priority order, starts command agents, watches them, and closes them out. Runs by itself. | Rarely. Its status reports land in its workspace. |
| **Command agents** | `widget-<issue#> <brief>` | Each takes one issue from start to a PR labelled `ready for QC`, asks you its questions directly, then hibernates until QC. | They ask you something (Remote Control and herdr notify you). |
| **QC agent** | QC (acme) | Serves a PR on your local QC ports for hands-on QC, and relays your feedback. | You're QC'ing on your own machine. |
| **Intake** | intake | Turns bug reports and ideas into proper GitHub issues. Other agents queue reports in its inbox. | You have something to file, or the inbox needs a pass. |

## Everyday things to say to the CEO

| Say | What happens |
|---|---|
| `status` | Health, who's working or hibernated, what's waiting on you, queue top, spawn floor, usage. |
| `fire up acme` / `work acme issues` | Starts whatever of acme's team isn't running (safe to repeat), then gives the status. |
| `work acme and beta` | Starts those teams and pauses the others' new work (floor P1). |
| `what's waiting on me` | Questions, UX sign-offs, PRs ready for QC, and the intake inbox, by workspace name. |
| `pause acme` / `resume acme` | Sets acme's spawn floor to P1, or back. Running agents keep going. |
| `set the floor to P2` / `clear the floor` | Changes which priorities may start automatically. |
| `work #123 now` | Puts the issue on **Claude Work This**; the orchestrator starts it within about 5 minutes. |
| `QC PR #264` | Has the QC agent serve that PR locally. |
| `show me the screenshots for #374` | Opens that PR's screenshot folder (`pdo shots 374`). |

You can also type into any agent's workspace directly, or reach it through Remote Control.

## How work flows

1. **An issue is ranked** by P-level: Claude Work This first, then P1 → P4. Security items and bugs come
   first within a level.
   - **Spawn floor:** nothing below the floor starts, not even CWT.
   - **Urgent bypass:** P1 **and** on Claude Work This starts even when every slot is full.
2. **The orchestrator starts a command agent** in its own workspace and worktree, with up to 3 active at a
   time. Agents waiting on you at a UX sign-off, or parked at QC, don't count. New work stops when weekly
   usage reaches 90%, keeping 10% in reserve for you.
3. **The agent explores, plans, builds, gets a review, and opens a PR.** The PR gets the P-label of its
   issue. If the issue turns out to be already fixed, it says so, labels it `likely-fixed`, and stops.
4. **It labels the PR `ready for QC`** and posts a QC checklist, with test data when needed (published
   with `qc-fixture-push`) and how to give feedback and pass. About 5 minutes later the agent **hibernates**: its
   workspace closes, its memory is freed, and its session is saved.
5. **You (or a remote reviewer) QC it.** Feedback wakes the same agent with its full context; it fixes,
   pushes and re-labels.
6. **On a QC pass, the agent wraps the PR up.** You merge it by hand. Finished agents close on their own.

**Big features** go design → build: a design agent writes the design doc and asks you the key decisions,
then the orchestrator starts a build agent that works through every phase. You review working prototypes
at UX sign-offs, never design docs.

## QC

**On your machine:** in the **QC (acme)** workspace, run `/project-qc-review <PR#>`. It serves the PR from
the shared QC worktree through your project's `QC_HOOK`. Type your findings in plain words; they go to the
PR's agent and get posted on the PR. Say `pass` when it's good.

**From a browser:** a reviewer submits a PR review with **Request changes**. The watcher hands it to the
PR's agent, which replies on the PR. To pass, add the `Ready for Merge` label (and remove
`ready for QC` / `QC complete - ready to review`): the watcher sees the label and the agent wraps up (once per
pass: after agent QC already passed it, nobody is prompted again). GitHub won't let a PR's author request
changes on their own PR, so as the author give feedback in the agent's session or through `/project-qc-review`.

**Agent QC** (when the project env sets `AGENT_QC_PORTS`): `team-up` also starts the **QC Agent (acme)**
workspace (`pdo start-agent-qc`). It takes `ready for QC` PRs one at a time, highest priority first, and tests them
on its own ports and database clone: the checklist, the touched areas and their neighbours in a browser, the API
directly, and two users at once. A fail posts "Agent QC findings (round N)" and resumes the PR's agent; two failed
rounds add `QC escalated` for you. A pass posts a short UX call by the visible-change rule: `QC complete - ready to
review` means your UX review is next, `Ready for Merge` + `UX testing skipped` means no visible change. Add
`needs UX review` to an issue or PR to force the review. `pdo agent-qc queue` lists what it will take next.

**Your project's extras:** comment commands, a hosted preview service or other conventions of your own go in
the repo profile's "Project extras" section. A `WATCH_EVENT_HOOK` in the project env can turn them into
watcher events (see [design.md](design.md#hooks)).

**A repo with no UI** (an engine, a library): the checklist names fixture inputs and their expected outputs, with
the command that checks each; you QC by running them or by reading the evidence the agent put in the PR.

## Filing bugs and ideas

- **Yourself:** in the **intake** workspace, type `/project-intake <what you saw or want>`. It checks for
  duplicates, drafts, and files after one OK from you.
- **Agents** queue reports with `intake-submit`. Run `/project-intake inbox` in the intake workspace to
  triage the queue in one batch. Nothing else starts the triage: a bare `/project-intake` (including the
  one `team-up` launches) only reports how many are waiting.

## Labels you'll see

| Label | Meaning |
|---|---|
| `P1-urgent` … `P4-low` | Priority, on issues and PRs. A PR never gets downgraded. |
| `Security` | Ranks first within its P-level. |
| `ready for QC` | Waiting for QC (the QC Agent first, where it runs). |
| `QC complete - ready to review` | Agent QC passed; your UX review is next. |
| `Ready for Merge` / `UX testing skipped` | All QC done; awaiting code review and merge (UX skipped: no visible change). |
| `QC escalated` | Agent QC failed twice; you decide. |
| `needs UX review` | Always gets a human UX review. Intake sets it on issues; it's carried onto their PRs. |
| `awaiting-ux-gate` | On an issue and its PR: the agent is waiting for your prototype sign-off. |
| `likely-fixed` | The agent thinks it's already done; you confirm and close. |
| `on-hold` | Parked by you; never started. |
| `needs-triage` | Filed but not yet triaged; not started unless on Claude Work This. |
| `epic-phase` | Part of an epic; worked by the epic's build agent. |
| `route:small` / `route:design` / `route:build` | Which lifecycle the orchestrator uses. |
| `orchestrator-system` | Work on the system itself, for the System Manager. |
| `managed-by:<manager>` | Claimed by that manager's agents (set and removed by the engine). Another manager's label means: ask that manager first. |

The P-labels, the CWT status and the QC labels can be renamed per project (`P_LABELS`, `CWT_STATUS`,
`LABEL_QC_READY`, `LABEL_QC_DONE`, `LABEL_MERGE_READY`, `LABEL_UX_SKIPPED`, `LABEL_NEEDS_UX`, `LABEL_QC_ESCALATED`).

## The engine's commands

With `bin/install --bin`, every script runs as `pdo <script>`; from a checkout, as `bin/<script>`. A session you
start yourself (not dispatched) finds the engine through `pdo` on PATH, else through the engine path the repo's
`AGENTS.md` names in "How work flows here" (filled in by `/project-setup`).

| Command | Does |
|---|---|
| `team-up` | start intake, QC and the orchestrator if missing, then `sysreport` |
| `sysreport` | one-call live status (read-only) |
| `queue [--all]` | the ranked queue (and exclusions with reasons) |
| `floor [P1..P4\|clear]` | show or set the spawn floor |
| `spawn <repo> <n> [--dry-run]` | start a command agent for an issue |
| `resume-agent <repo> <n> --prompt …` | prompt an agent, bringing it back if hibernated |
| `hibernate <repo> <n>` | release a parked agent's memory |
| `watch --peek` | the watcher's snapshot, without consuming events |
| `qc start <pr#>` / `qc stop` / `qc status` | local QC servers |
| `qc-fixture-push <pr#> <file>` | publish QC test data |
| `intake-submit "<ws>" "<report>"` | queue a report for intake |
| `file-issue`, `claim`, `board-status` | board and issue helpers |
| `claim --release <repo> <n> [--unassign]` | take a claim's `managed-by:` label off by hand (finished agents release on their own) |
| `pr-agent <pr#>`, `pr-priority`, `shots <pr#>`, `agent-meta backfill` | PR helpers |
| `project-env [KEY]` / `project-env --board` | the current project's resolved settings / the board's ids (live) |
| `with-gh-user --user <login> <cmd>` | run one command (`gh …`, `git push …`) as that GitHub login, without switching the account |
| `install --gh-identities [--check\|--uninstall]` | one gh login per repo owner for every shell and agent (see [Multiple GitHub accounts](#multiple-github-accounts)) |
| `fleet [--json] [--write-advice]` | every project at once, the machine's constraints, allocation advice (read-only by default) |
| `fleet deps add\|list\|done …` | cross-project dependencies (also GitHub's native "blocked by") |
| `fleet note <org/repo#n> "<text>" [--as NAME]` | log a cross-manager agreement as an issue comment |

## CEO (several projects)

When one machine runs several projects, open the CEO first (`claude -n CEO`) and type `/ceo`.
Tell it what matters now ("work acme issues", "fire up acme to intake and work #412", "work
dnd3yond and ti4"): it starts those teams (`pdo team-up`) and pauses the others (`pdo floor P1`). It runs `pdo fleet` and gives you **one** "Waiting on you" list for
every project, ranked by impact (PRs ready to merge, questions, UX gates, then QC and the intake
inbox), plus the constraint that binds most right now (memory, usage, disk, GitHub calls).

| Say | What happens |
|---|---|
| `status` | The unified list, plus each project's manager, agents, queue and PRs. |
| `which project should get resources?` | It explains the go / slow / hold advice and the trade-off. |
| `apply the advice` | After your yes, `pdo fleet --write-advice`; projects with `FLEET_ADVICE=honour` follow it. |
| `team A needs a change in team B's repo` | It asks B's manager and brings the answer back. |
| `loop` | An hourly check that reports only changes and escalations. |

It never does project work and never stops another project's agents; it asks that project's
manager. Projects opt in to its advice with `FLEET_ADVICE=honour` in their env file, and set
`PORTFOLIO_PRIORITY` (1 = highest), `RESOURCE_PROFILE` (`light`, `medium`, `heavy`), `MANAGER`
(the manager's workspace name) and, for self-managed repos, `REPO_MANAGER`. Cross-project
dependencies: `pdo fleet deps add "<org/repo#n>" blocks "<org/repo#m>"`.

## Claims and coordination between managers

When your engine claims an issue it adds a label, `managed-by:<slug>`, and a short comment naming the
agent and its manager. Other managers' engines and people's agents skip issues with someone else's
label, so two teams never work the same issue. The **assignee** is yours: an assigned issue is a
human lock that the engine never touches or starts.

| Env key | Default | Meaning |
|---|---|---|
| `MANAGER_SLUG` | a slug of `MANAGER`, e.g. `orchestrator-acme` | the claim label is `managed-by:<slug>` |
| `CLAIM_ASSIGNS` | `0` | `1` = claim also assigns the gh login (the old lock); keep it only until older claims are relabelled |

- The label comes off when the agent finishes (merged, QC passed and wrapped up, or the issue closed).
  A hibernated agent that is still in progress keeps it. To release one by hand:
  `pdo claim --release <repo> <n>`.
- `pdo fleet` counts each manager's claims and flags **stale claims**: a label whose agent is gone.
- `pdo fleet deps add A blocks B` also sets GitHub's "blocked by" on B, and the queue holds B
  (`blocked-by:<ref>`) until A closes. `deps done` removes it.
- Agreements between managers (who goes first, a hand-off, who owns what) are logged on every issue
  involved with `pdo fleet note`, so a collaborator's agent sees them too.

## Multiple GitHub accounts

If you work a work org and your own repos from one machine, with agents in both, don't let anything
run `gh auth switch`: gh has one active account for the whole machine, so a switch breaks every
other session. Instead, list which login works which owner and install the gh identities shim:

```
$EDITOR ~/.config/project-dev-orchestration/gh-identities
#   acme-corp  alice-work  alice@acme-corp.example  Alice Example
#   alice      alice       alice@example.com
#   default    alice
pdo install --gh-identities
# add the printed `export PATH=...shims:$PATH` line to your shell profile, open a new shell
pdo install --gh-identities --check
```

From then on every `gh` call, from you or any agent, runs as the login that owns the repo it
touches, and git pushes and commits in a repo use that owner's login and email. The shim refuses
`gh auth switch` (set `PDO_GH_ALLOW_SWITCH=1` when you really mean it, such as adding an account).
A project's `GH_USER` pin still wins for the agents the engine launches. `sysreport` shows a
`gh identities:` line (shim active or not, and the owners). Details: the README's "Multiple
GitHub accounts"; undo with `pdo install --gh-identities --uninstall`.

## When something looks wrong

- Ask the System Manager: `status`, then describe what you see.
- If an agent shows "blocked", it's waiting on you: open its workspace, or use Remote Control.
- If an agent was closed by accident, resuming it is safe; ask the System Manager to bring #N back.
- Design: [design.md](design.md). Traps already found: [lessons-learned.md](lessons-learned.md).
