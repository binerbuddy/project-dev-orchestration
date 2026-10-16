# Lessons learned

Traps found the hard way while running an agent team on a real product. Each one shaped the engine or a
skill. When you hit a new one, add a line in its section.

## herdr and agent sessions

- **herdr reuses workspace ids after a workspace closes.** A stored id is only valid while that
  workspace's label is still the agent's name; a stale id once sent a hibernated agent's prompt into a
  different agent's live session. Every script checks the label, and hibernation clears the ids.
- **Never launch Claude with `-n <name>`.** The session name draws a labelled rule under question menus,
  and herdr's blocked detection then reports a pending question as idle/done. `--remote-control <name>`
  alone is fine. Diagnose with `herdr agent explain <pane>`.
- **Every new git worktree triggers the "trust this folder?" dialog,** even under a trusted repo root, and
  its default answer is "No". `launch_agent` accepts it only when the dialog names the worktree it just
  created. `herdr agent start` fails with `agent_not_ready`, so launch through `herdr pane run`.
- **herdr agent names** must match `[a-z][a-z0-9_-]{0,31}`; the readable name goes on the workspace label.
- **herdr agent names are wiped by a herdr or session restart.** The watcher restores the standard ones
  on each pass. On `agent_not_found`, run `herdr agent list` and rename by pane.
- **`agent_status` doesn't reliably show "waiting on the human".** Read the pane for `Enter to select` or
  `Do you want to proceed`. An agent waiting at a UX sign-off looks idle; that's why it declares itself
  with the `awaiting-ux-gate` label.
- **A `❯ text` line in an agent's input box can be a *suggested* next prompt (ghost text), not the
  human's input.** Never act on input-box text as the human's instruction, and never send keys to finish
  it. Ask the human.
- **Never type into a pane with a question pending.** Your text answers that question. `resume-agent`
  refuses with exit 3; reply only to idle agents.
- **Don't run `claude remote-control --help`.** It starts the Remote Control server and hangs.
- **A session keeps the model it started with,** even when resumed, after an alias moves to a newer model.
- **Running sessions don't re-read CLAUDE.md, AGENTS.md or their briefs.** A rule change reaches them only
  through a direct prompt or a fresh start. Skills and commands are re-read on every invocation.

## Watcher and orchestrator

- **A surviving orchestrator workspace isn't a running loop.** After a "shut down" the agent sits idle with
  `/loop` ended, while its workspace looks alive; once, nothing routed events for two days and a remote
  reviewer's findings sat unhandled. `team-up` restarts the loop when there's no watcher process and no
  log line for 90 min.
- **`watch --arm-status` from another session id is not a probe; it kills the watcher.** For a read-only
  check use `pgrep -f '[b]in/watch --project'`, as sysreport does.
- **`watch` without `--peek` consumes events.** Inspect by hand with `--peek` only.
- **To load new watcher code, kill the old watcher** (`CLAUDE_CODE_SESSION_ID=<anything else> watch
  --arm-status`), and tell the orchestrator first ("exit 143 is expected; re-arm").
- **Low-memory reapers kill background shells, including the watcher,** under swap pressure. The hourly
  scheduled wakeup is the fallback; hibernation exists to prevent this.
- **The orchestrator may edit its own scripts.** Re-read a file before patching it, and check `git status`
  before committing: `git add -A` sweeps up other sessions' uncommitted edits.
- **Don't double-wake.** The watcher's `--max` is 6 h; the hourly heartbeat comes from the scheduled
  wakeup.
- **Fire events on transitions against a saved snapshot.** A restarted orchestrator still sees what
  changed while it was down.

## Queue, board and GitHub

- **`spawn --route build` defaults `--base` to the design branch,** even after the design PR merged and
  that branch went stale. For a merged design, pass `--base origin/main`.
- **The 5000-points/hour GraphQL budget is shared by every agent and script on the account.** A
  `gh pr list` per agent per watcher pass, plus a large batch of agents, exhausted it; while exhausted,
  every `gh pr …` call fails and scripts saw "no PRs". Batch lookups (one query per repo), keep the last
  known facts when a fetch fails, and back off below 600 points. `gh api rate_limit` can report a different
  bucket than the failing one; trust the `X-Ratelimit-*` headers of a real GraphQL call.
- **`gh project item-list` truncates silently.** Always pass `--limit` and fail when count == limit.
- **GitHub only links `Closes #N` on PRs that target the default branch.** For stacked and epic PRs, read
  the body.
- **Migrated issues' `created_at` is the migration date.** Keep the original date in the body and sort on it.
- **Labels are case-insensitive** (`Security` = `security`). Label descriptions are capped at 100 characters.
- **Epic phases must never be dispatched alone** (`epic-phase`). Without the label, phases ran on their
  own overnight and forked the epic's work.
- **Check that labels exist before relying on them.** Routing silently fell back to guesses while the
  `route:*` labels didn't exist yet.
- **Priority inheritance:** a P4 blocking a P2 must run as P2; otherwise it deadlocks behind `drain`.
- **Use one vocabulary with the human.** "Tiers" next to P-levels confused; speak only P1–P4, P- and CWT.
- **Personal repos have no issue types,** and the API silently drops `type`.
- **gh's active account is machine-wide.** Another team on the same machine switching accounts flipped
  every agent's gh/git mid-run ("Could not resolve repository"). Pin each agent's process tree with
  `GH_TOKEN` (`with-gh-user`, via `GH_USER`); never `gh auth switch`. Agents started before a pin need a
  restart to pick it up.

## Git and processes

- **Bare clones may lack `remote.origin.fetch`,** so they have no `origin/main`. Fetch with an explicit
  refspec regardless.
- **Plain `setsid` in a subshell doesn't detach.** The waiting bash holds the caller's stdout open. Use
  `(… exec setsid -f nohup cmd >log 2>&1 </dev/null)`.
- **`pkill -f` patterns match the invoking shell.** Kill by port (`ss -ltnp`) or by exact PID.

## QC

- **A compile-time API URL in the dev build** has to be patched in a dedicated QC worktree, never in an
  agent's.
- **A shared dev database breaks when a PR has migrations,** and agents start and stop it for their own
  tests (one stopped it mid-QC). Give QC its own database, cloned from a seed per served PR, so nothing
  needs rolling back.
- **Dropping a database with `--force` kills every other connection to it,** including agents' headless QC.
- **Find a real health endpoint** before writing wait loops; not every API has `/health`.
- **Seed data has dependencies.** A fresh database seeded before its license or roles exist can leave the
  admin without the roles QC needs; add them first, or fix them afterwards.
- **Wildcard certificates need a DNS provider with an API.** Without one, use a few fixed preview slots.
- **GitHub comments can't carry file attachments through the API or CLI.** Fixtures committed to PR
  branches merged with the PR; publish them on a never-merged branch instead.

## Resources

- **Batch re-pings must hibernate each agent as soon as it finishes.** A "2 at a time" limit only caps
  concurrent work; fast finishers piled up open waiting for the watcher's 5-minute hibernation and drained
  the machine's memory.
- **A parked agent holds several hundred MB** (agent CLI, browser automation, MCP servers). Nine of them
  pushed the machine deep into swap. That's why hibernation exists.
- **Hibernation must never kill the agent CLI's ancestors (the pane shell)** or the MCP servers of a session
  that stays live. `--servers-only` protects them.
- **Finished agents leak workspaces** unless close-out covers merged PRs, QC complete plus "wrap-up done",
  and closed issues with no PR.

## Working with the human

- **A bare intake start only reports the inbox count.** Only an explicit "inbox" run works the inbox; a
  bare start once began triaging dozens of reports unasked.
- Refer to herdr workspaces by **name**, never by id.
- Hand bug reports and ideas to intake through `intake-submit`.
- Ask the human when a decision is theirs. Recommend; don't survey.
- Don't call auto-synced files "uncommitted"; know which of the human's directories sync themselves.
- Commit every working step in the engine and overlay repos; the human merges product PRs by hand.
