<!-- guide-version: <version> -->
<!--
The per-repo human guide. /project-setup fills it from the repo's .agents/project-profile.md and, in full mode, the
engine's projects/<name>.env, and writes it to docs/agent-workflow.md (or where the profile's ## Docs says). Drop this
comment; keep the guide-version line above as the file's first line.
- <version>: an integer. 1 on first generation; /project-setup adds 1 whenever a re-run changes anything above
  "## Local notes". Agents compare it with their per-clone .agents/local/guide-ack to decide whether to re-ask.
- Every other <placeholder> comes from the profile or env (the source is named next to it). An answer the human
  gives goes into the profile first and is rendered from there, so a re-run reproduces it. Anything neither gives
  stays as `TODO(setup): <question>`.
- Optional blocks are marked [if ...]: keep the block (without the marker) when the condition holds, else delete it.
- Write for people, not agents: short sentences, no engine internals. LF line endings only.
-->

# Working on <org>/<repo> with agents

This repo is built by coding agents running the project-dev-orchestration skills, with humans deciding what gets
built, doing QC, and merging. This page is the house rules for **you**, the person whose agent works here. The
general guide, for any repo that uses the system, is at https://binerbuddy.github.io/project-dev-orchestration/.

- **Manager:** <manager> (<how to reach them>). They run the agent team, set priorities, and merge.
  <!-- profile §Identity "Manager"; the env's MANAGER, if set, names the managing agent, not this person -->
- **Ask questions:** <where to ask: an issue with the `question` label, a discussion category, a chat channel>.
  <!-- profile §Identity "Where to ask" -->
- **Board:** <org Project #<project#> "<board title>", or "none: the manager assigns work by hand">.
  <!-- profile §Identity -->

## Set up your agent (once)

1. Install the project-dev-orchestration plugin for your tool (Claude Code, Codex or Grok Build). The commands are
   in the general guide's "For collaborators" page.
2. Clone this repo. Your agent reads `AGENTS.md` and `.agents/project-profile.md`; you don't need to.
3. Start your agent in the clone. The first time, it asks whether you've read this page, then remembers your answer
   in `.agents/local/guide-ack` (per clone, never committed). It asks again only when this page changes.

## Requesting work

- **Open an issue** in `<org>/<repo>`. Say what you saw or want, where, and how to reproduce it. Add `needs-triage`
  and no priority label; the manager sets the priority.
- **Priority labels:** <P-labels, e.g. `P1-urgent` `P2-high` `P3-medium` `P4-low`>. <!-- env P_LABELS -->
  Higher goes first. A PR takes the highest priority of the issues it closes; nobody sets it by hand.
- **Route labels** choose how the work is done:

  | Label | Use it for | Your agent runs |
  |---|---|---|
  | `route:small` | a bug fix or small feature: one PR, no design decisions | `/project-small-feature-or-bug-fix` |
  | `route:design` | a big feature: a design doc and decisions first, then phased build | `/project-feature-design` |
  | `route:build` | a feature whose design doc is ready | `/project-feature-build` |

- **Getting it worked:** <one of: "The manager moves the issue to **<queue column>** on the board; the orchestrator
  starts an agent within minutes." / "The manager assigns it to you; then ask your agent to work it with the route's
  command."> An issue assigned to someone is theirs: leave it alone. <!-- env CWT_STATUS / PROJECT_NUMBER -->
- **Working an issue yourself:** in your clone, run the route's command with the issue, e.g.
  `/project-small-feature-or-bug-fix #<n>`. Your agent works in its own branch and worktree, asks you its questions,
  and stops at a PR labelled `<QC-ready label>`. <!-- env LABEL_QC_READY -->

## QC

[if the repo has a UI]
Every PR that changes what users see gets one **QC Checklist** comment: steps to try in the running app, naming data
by <what the app calls its top-level record, e.g. "project"> and UI path, never by a URL or id. <!-- profile §QC data -->

- **Run it locally:** <the plain start commands from profile §Dev servers' "Human run" line, in one or two lines;
  never the agents' port scheme>.
  Seed data: <profile §QC data seed: users, sample records>.
- **Test data:** when the seed doesn't cover a case, the checklist's first item links a fixture on the never-merged
  `qc-fixtures` branch. Download it and <import steps from profile §QC data, e.g. "Projects → Import">.
[end if]
[if the repo is headless (profile §QC data says it has no UI)]
This repo has no UI, so QC means checking outputs: every PR that changes behaviour gets one **QC Checklist** comment
whose cases are named by their inputs (a fixture input file, a request to replay) with the expected output for
each, plus any evidence the agent already gathered. <!-- profile §QC data -->

- **Run a case:** <the command from profile §QC data / §Dev servers' "Human run" line, e.g. "`npm run replay --
  <file>`, then compare with the expected output in the checklist">.
- **Test data:** the inputs live on the never-merged `qc-fixtures` branch; the checklist links each one.
[end if]
- **Give feedback** with a PR comment that starts `QC: ` followed by your findings or answers. Where the team runs
  the orchestrator, the PR's agent gets it and replies on the PR; otherwise point the agent that built the PR at it.
- **Pass it:** <where the team runs the orchestrator (full mode): "a comment that starts `Claude, QC pass` (it swaps
  `<QC-ready label>` for `<QC-done label>`)"; otherwise: "apply the `<QC-done label>` label yourself (only a human
  does)">. Neither needs a preview service. <!-- env LABEL_QC_READY, LABEL_QC_DONE -->
[if full mode and the env sets QC_HOOK]
- **QC servers on the manager's machine:** the manager can start this PR's QC servers with `/project-qc-review
  <PR#>`; ask them in the PR if you want that.
[end if]

[if the profile's §QC preview describes a service]
- **Preview in the browser, with nothing installed:** two more comment triggers start and stop a hosted preview.
  `QC:` and `Claude, QC pass` work as above.

  | Comment (must start the comment) | What happens |
  |---|---|
  | `<start trigger, e.g. Claude, spin up QC>` | builds this PR (about <build time>) and replies with the link |
  | `<stop trigger, e.g. Claude, tear down>` | stops the preview (idle ones stop after <idle timeout>) |

  Preview link: `<link pattern>`. Log in as <preview login>. Only repo owners, members and collaborators can
  trigger it. <!-- profile §QC preview -->
[end if]

## Changelog

<profile §Changelog in one or two lines: where the entry goes, its format, one example, and any trap. Or "No
changelog: nothing to add.">

Your agent writes the entry; check it reads well to a user.

## What your agent does, and won't do

- Works in its own branch from `<base>`, passes the checks, opens a PR with `Closes #<n>`, and stops at
  `<QC-ready label>`. **Nobody's agent merges.** The manager merges.
- Doesn't fix things it notices outside its task: it files them as `needs-triage` issues (or queues them for the
  intake agent, where the team runs one).
- Asks before touching any repo other than this one. Reading is fine; branches, PRs, issues, comments or
  `Closes <org>/<other-repo>#<n>` lines wait for your yes.
- Never commits QC fixtures to a PR branch, and never moves board columns the orchestrator owns.
- Never switches the machine's `gh` account; it pins one per command.
- Follows this repo's own prohibitions: <profile §Do not, one line each, or "none beyond the above">.

## Don't

- Don't merge, or apply `<QC-done label>` without doing QC.
- Don't put issues on the board's queue column or set priorities unless you're the manager.
- Don't type into another agent's session; talk to agents through PR comments or the manager.
- Don't commit `.agents/local/`.

[if profile §Identity has "Human guide notes"]
## Notes for this repo

<profile §Identity "Human guide notes", one bullet each, in plain words>
[end if]

## Local notes

<!-- Anything the team adds here is kept: /project-setup never edits below this heading. -->
