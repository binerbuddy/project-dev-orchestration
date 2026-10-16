# System map (one engine install)

> `pdo <name>` is an engine command (else `<engine checkout>/bin/<name>`). Paths written `$PDO_STATE_DIR`, `$PDO_INBOX` or `$PDO_HOME` (the engine checkout) mean the values `pdo project-env <KEY>` prints; agent sessions don't have them set.

`<p>` is the engine project name (`--project`), `<Repo>-<n>` an issue's agent key. State paths are
under `$PDO_STATE_DIR` (default `${XDG_STATE_HOME:-~/.local/state}/project-dev-orchestration`).

| Piece | Where | What |
|---|---|---|
| Orchestrator | herdr workspace **"Orchestrator (<p>)"**, agent `orchestrator-<p>`, running `/loop <ORCHESTRATE_SKILL> project=<p>` (default `/project-orchestrate`, namespaced under the plugin) | Runs the queue, spawns command agents, routes events. Its log: `$PDO_STATE_DIR/log.md` |
| Watcher | `pdo watch` (in the background of the orchestrator) | Token-free probe and events. Hibernates and closes out agents, restores agent names, runs pr-priority, polls `QC:` comments |
| Queue | `pdo queue`, `pdo floor` | Deterministic ranking: CWT, then P1–P4. Exclusions, priority inheritance, urgent bypass, spawn floor |
| Command agents | workspaces `<Repo>-<n> <brief>`, started by `pdo spawn` with the brief template (`BRIEF_TEMPLATE`, from `prompts/` along `PDO_CONFIG_DIRS`) | Run the route's lifecycle skill (`ROUTE_SKILL`) and stop at `ready for QC` |
| Agent lifecycle | `pdo claim`, `hibernate`, `resume-agent`, `agent-meta`, `pr-agent` | Metadata in `$PDO_STATE_DIR/agents/<Repo>-<n>.json` |
| Local QC | workspace **"QC (<p>)"**, agent `qc-<p>`, `/project-qc-review`, `pdo qc` (dispatches to the project's `QC_HOOK`) | The human's hands-on QC on the reserved ports (profile `## Dev servers`) |
| Remote QC (optional) | whatever the profile's `## QC preview` describes; extra checks via `TEAM_UP_HOOK` / `SYSREPORT_HOOK` | Previews driven by PR comments (`Claude, spin up QC` …) |
| Intake | workspace and agent **`intake`**, `/project-intake`, `pdo intake-submit`, `pdo file-issue` | Bugs and ideas go to the inbox (`$PDO_INBOX`), then to filed issues |
| PR priority | `pdo pr-priority` | A PR gets the best P-label of its issues; never downgrades |
| Config | `PDO_CONFIG_DIRS` (first match wins): `projects/<p>.env`, `prompts/`, `hooks/` | Overlays prepend their own dir |
| Global agent rules | your tool's global instructions file | Name workspaces by label; hand-offs go through intake-submit |

**GitHub:** org `ORG`, board = Project `PROJECT_NUMBER` (its queue status, default "Claude Work
This", is the orchestrator's queue). Label families: P1–P4, `Security`, `route:*`, `epic-phase`,
`on-hold`, `likely-fixed`, `awaiting-ux-gate`, `orchestrator-system`, `ready for QC`,
`QC complete - ready to review`. Repos in `SELF_MANAGED_REPOS` are owned end to end by another
manager: the queue and watcher skip them. Humans merge product PRs by hand.

## Engine defaults (overridable per install)

These are engine behaviour, not one team's taste; an overlay can change them where the engine
allows, and records its own standing preferences in its own docs.

- `MAX_ACTIVE` 3 active command agents (project env; also `WEEKLY_CEILING`, `FIVE_HOUR_CEILING`); parked, hibernated and UX-gate agents don't hold a slot.
- Keep 20% of the weekly usage in reserve (spawning stops at 80% weekly, or 90% of the 5-hour window).
- The urgent bypass is P1-urgent AND on the queue status, nothing less.
- Spawn floor via `pdo floor` (persisted).
- No human review of design docs; prototypes get reviewed at UX gates.
- Agents stop at `ready for QC`; merging is manual.
- Agents answer remote QC on the PR.
- QC fixtures only when the data matters, and only on the never-merged `qc-fixtures` branch
  (`pdo qc-fixture-push`), never on PR branches.
- PR P-labels are never downgraded.
- Conflict rebases run continuously as merges land (2 at a time), so each PR is ready when the human
  gets to it. Don't suggest holding them.
- PR cap: with `open_awaiting_human` PRs ≥ the cap (default 10, `$PDO_STATE_DIR/<p>-pr-cap`), nothing
  new spawns.
