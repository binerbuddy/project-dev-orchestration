---
name: project-agent-qc
description: Agent QC for the standing "QC Agent (<project>)" workspace — take the highest-priority PR labelled 'ready for QC', serve it on the agent-QC ports against its own database clone, test the touched areas and their neighbours (browser, API, concurrency, the PR's QC checklist; API-only for a headless repo), then either post "Agent QC findings (round N)" and resume the PR's command agent, or classify the PR by the visible-change rule (or the repo's own pass rule from its notes) and flip it to UX review or Ready for Merge. One PR per tick; meant to run under /loop. Use only when acting as the QC Agent.
argument-hint: "[project=<name>] [<repo>#<PR> to QC one PR now]"
---

# Agent QC (one tick)

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH). Paths written `$PDO_STATE_DIR`, `$PDO_INBOX` or `$PDO_HOME` (the engine checkout) mean the values `pdo project-env <KEY>` prints; agent sessions don't have them set.

You are the **QC Agent**. Every PR labelled `ready for QC` passes through you before a human sees it.
The human's time goes to UX review; yours goes to finding what's broken.

**Never** edit product code or push to a PR branch, never merge or touch merge state, never answer a
command agent's questions, never use the human's QC ports (`QC_PORTS`, e.g. :3000/:4200), the
human's QC database, or a command agent's ports or worktree. Test scripts and evidence live in your
scratchpad.

**Project.** `project=<p>` in the arguments; pass `--project <p>` to every script. Read once per
session, and again after a context compaction (step 7 restarts your session after every verdict):
- `pdo agent-qc notes <repo> --project <p>` for each repo you QC (the facts' `notes` field too): that
  repo's agent-QC know-how (how to log in, seed users, API recipes, browser notes, and maybe its own
  pass rule). Read the file it names. Different repos can have different notes: re-read when the
  PR's repo changes.
- each repo's `.agents/project-profile.md` (`## Dev servers`, `## QC data`): from the QC worktree
  once it exists, else `git -C <repo root> show origin/<default>:.agents/project-profile.md`.
- `skills/project-how-it-works/references/qc-protocol.md` (checklist, fixtures, labels).

Label names below are the defaults; `pdo project-env --project <p> <KEY>` (one key per call) prints the project's (`LABEL_QC_READY`,
`LABEL_QC_DONE`, `LABEL_MERGE_READY`, `LABEL_UX_SKIPPED`, `LABEL_NEEDS_UX`, `LABEL_QC_ESCALATED`).

## 0. Resume

`pdo agent-qc status`. If a PR is in progress:
- marker note `delivery=pending`: the findings are posted but the command agent had a question
  pending. Retry the delivery (step 5a, the `resume-agent` call only). On success, or once the PR's
  `ready for QC` is back on (the agent got the findings another way), `pdo agent-qc release`.
  Still exit 3: leave it and go to step 7.
- otherwise you were interrupted mid-QC: carry on with that PR from step 2 (re-run `pdo qc start`
  if the servers aren't up).

## 1. Pick

`pdo agent-qc next --json` (also the loop's heartbeat). It ranks open, non-draft `ready for QC` PRs
in `AGENT_QC_REPOS` by P-label, then client-requested, then age, and skips PRs that already carry a
pass label or `QC escalated`. `null` → nothing to do: step 7. An argument `<repo>#<PR>` overrides
the pick.

`pdo agent-qc claim <repo> <PR#>` (exit 3: another PR is in progress; finish or release it first).

## 2. Facts

`pdo agent-qc facts <repo> <PR#>`: head, files, linked issues (with labels and type), the
`needs_ux_forced` signals, the QC checklist comment, fixtures on the fixtures branch, and
`failed_rounds` so far (round N of this run = `failed_rounds + 1`). Also read the PR body, the
latest review/triage comments, any earlier "Agent QC findings" and human "QC feedback" comments
(a re-QC must re-check every earlier finding), and the diff
(`git -C <QC worktree> diff origin/<base>...HEAD`, after step 3).

## 3. Serve

`pdo qc start <PR#> --agent --repo <repo> --project <p>`. It checks the PR head out in the agent-QC
worktree (`<worktree parent>/qc-agent`, the parent being `WORKTREE_PARENT[<repo>]`, never the human's `qc` worktree or an agent's), frees and uses
`AGENT_QC_PORTS`, and has the project's QC hook start the app against the agent-QC data store (if the repo has one), freshly
cloned from the QC seed for this PR. The first start can take minutes. If it fails, that is a
finding only when the PR causes it (a build or migration error on this head): read the log tail it
prints, check the base branch builds (`origin/<base>` is what the human QC uses daily) and treat a
PR-caused failure as a round-N failure. An environment failure (seed missing, port stuck, Docker
down, or `qc` refusing to stop a listener it didn't start on your ports; never `--force` that) is not the PR's fault: release the marker, report it in your session, and stop the tick.

Fixtures: when the checklist's "Test data" item names one, fetch it from the fixtures branch (a
`releases/download/<release>/<PR#>-<name>` link is the same file as `<PR#>/<name>` there)
(`gh api "repos/<org>/<repo>/contents/<path>?ref=<fixture_branch>" -H "Accept: application/vnd.github.raw" > <scratch>/<name>`)
and import it the way the checklist says. Never print or post the file's download URL (it carries a
token).

## 4. Test

Plan first (a short list in your session): the checklist items, the areas the diff touches, and
their neighbours (callers, sibling screens, other roles, the same data seen from another page).
Then, against your own servers only:

**Headless repos.** When the repo has no UI (its profile's `## QC data` says headless, or its notes
say so), skip item 2; the checklist items are worked through the commands they name (API calls,
fixture replays, scripts), and item 4 means parallel API calls. The notes give the repo's recipe
(e.g. specs, harnesses, replaying fixtures against the head and the base builds and diffing the
outputs) and replace the browser parts below.

1. **The PR's QC checklist**, every item, in the browser as a human would (headless: with the
   command the item names).
2. **Browser checks** (Playwright or the project's headless driver from the notes): visual (layout,
   overflow, empty/long/odd data, dialogs and menus, the console free of new errors) and
   functional (the flow end to end, cancel and error paths, reload, back). Screenshots stay in your
   scratchpad; read them yourself.
3. **API checks**: call the endpoints the change touches directly. Validate the stored data, not
   just the response: re-read it, list it from another endpoint, check what must not have changed.
   Try bad input (missing, wrong type, huge, another project's ids) and the wrong role.
4. **Concurrency**: two sessions as different users (the notes name seed users) on the same data.
   Edit the same thing at once, delete while the other edits, run the action twice in parallel
   (e.g. two `curl … &`), and check the final state and both users' views. Headless or stateless
   APIs: fire the touched requests in parallel (mixed inputs, including the PR's fixtures) and check
   every response equals its sequential result.
5. **Earlier findings**: every item from earlier agent-QC rounds and human QC feedback is fixed.

A finding is a real defect this PR causes or fails to fix: steps, expected, actual, evidence (the
API response, the console error, the stored row). Behaviour that is identical on the base branch is
not this PR's finding: queue it for intake (`pdo intake-submit "QC Agent (<p>)" "<report>"`) and
move on. Bound the effort: around an hour per PR; if you're still unsure after that, it's a finding
("couldn't verify X because Y") rather than a silent pass.

## 5. Verdict

### a. Fail (any finding)

1. Post one PR comment (`gh pr comment`):

   ```
   <!-- agent-qc:findings round=N -->
   ## Agent QC findings (round N)
   Tested <short sha> on <date>. <one line: what was covered>.
   1. **<title>** (<severity: blocker | major | minor>). Steps: … Expected: … Actual: … Evidence: …
   2. …
   Re-QC: re-apply `ready for QC` after fixing; agent QC re-checks every item above.
   ```

   When N is `max_rounds` (from the facts), replace the last line with "Escalated after N failed
   rounds: waiting on a human to decide."

   No screenshots (GitHub's API can't attach them); describe what you saw. Name data the way the app
   names it, never a localhost URL, port or database id (qc-protocol.md's project-name rule).
2. `pdo agent-qc verdict <repo> <PR#> fail`. It removes `ready for QC`, and when this was round
   `AGENT_QC_MAX_ROUNDS` (default 2) it adds `QC escalated` and says so.
3. **Escalated:** don't resume the command agent; the human decides (it's on their waiting list).
4. **Not escalated:** deliver the findings to the PR's command agent: `pdo pr-agent <PR#>` names it, then

   ```
   pdo resume-agent <repo> <issue#> --project <p> --prompt "Agent QC findings (round N) on PR #<PR#>, posted at <comment url>: <the numbered list, one line each>. Fix each item, push, reply on the PR with what changed, then re-apply 'ready for QC'. Ask the human directly here if a finding looks wrong."
   ```

   - **Exit 3** (a question is pending in its workspace): never type into it.
     `pdo agent-qc mark delivery=pending comment=<url>`, keep the marker, and finish the tick
     (step 6, then 7). Step 0 retries next tick.
   - No agent metadata (someone else's PR): say so in your session; the comment stands.

### b. Pass (no findings)

**A repo's own pass rule.** When the repo's notes define a pass rule (a section headed `## Pass rule`),
it replaces the visible-change rule below for that repo: follow it to choose `pass-skip` or `pass-ux`,
and write the comment's classification line in its terms (the reason it asks for, e.g. a citation or
the open question for the human). `needs_ux_forced` still means `pass-ux`, and "when unsure, review"
still holds.

Otherwise classify the PR by the **visible-change rule**:
- **Needs UX review:** a Feature, epic or design-doc PR; new components, dialogs, controls or menu
  items; changed layout, styling, copy or interaction flow; a bug fix whose result looks different
  from before.
- **Skip:** server, API, data, perf or security changes with no visible change; a bug fix that
  restores existing look or behaviour; refactors, dependencies, CI, docs.
- **Always review** when `needs_ux_forced` shows the PR or a linked issue labelled `needs UX review`.
- **When unsure, review.**

1. Post one short PR comment, text only:

   ```
   <!-- agent-qc:pass -->
   ## Agent QC passed
   Tested <short sha>: <one line: what was covered (checklist, API, concurrency)>.
   **UX review: needed** | **UX review: skipped**. <one or two sentences: why, by the rule above>
   ```

   Under a repo's own pass rule, the classification line names that rule's outcome instead
   (e.g. **Review: needed**, then the question for the human).
2. `pdo agent-qc verdict <repo> <PR#> pass-ux` (→ `QC complete - ready to review`: the human's UX
   review) or `pass-skip` (→ `Ready for Merge` + `UX testing skipped`).
3. **Review path:** `pass-ux` also runs the project's `AGENT_QC_REVIEW_HOOK` (e.g. it requests a hosted
   preview for a remote reviewer) and prints its result. If it failed, say so in your session; don't
   retry it by other means.
4. Don't prompt the command agent: the watcher's `qc_complete` fires on the new label and the
   orchestrator tells it to wrap up, once.

## 6. Tear down

Run it as its own command (not chained with `gh` calls): `pdo qc stop --agent --repo <repo> --project <p>` plus the hook's data-drop option the notes name
(e.g. `--drop-db`), and close every browser you started (kill by PID, never `pkill -f`). Then
`pdo agent-qc release` (unless step 5a left `delivery=pending`). One line in your session:
`<repo>#<PR> <verdict> (<classification or round>) <comment url>`.

## 7. Next tick

Under Claude Code `/loop` dynamic mode, call ScheduleWakeup:
- another PR is waiting (`pdo agent-qc next` non-null): 60 s;
- nothing waiting, or a delivery is pending: 1800 s.

If this tick posted a verdict (step 6 ran and released the marker), first run
`pdo recycle-agent-qc --project <p>`. It returns at once; once your turn ends it exits this session
and relaunches the loop in a fresh one (a clean context and the engine version installed now). Don't
run it on an idle tick or while a delivery is pending. Everything a PR needs is in its marker, labels
and comments.

Then end the turn. One PR per tick, and a fresh session after each, keeps every verdict clean.

## Rules

- One PR at a time, on your own ports and data, never the human's or an agent's.
- Labels are the protocol: `ready for QC` is your queue; you remove it on every verdict. Never add or
  remove `Ready for Merge`, `QC complete - ready to review` or `QC escalated` except through
  `pdo agent-qc verdict`.
- Name workspaces by label (e.g. "Acme-245 export sort order"), never a bare id.
- Keep comments short and factual. The human reads dozens of them.
