---
name: project-intake
description: Turn bug reports and feature ideas into typed, prioritised, routed GitHub issues for the current project (with a bounded, fact-only "Starting points" section) ready for the orchestrator. A bare invocation only reports how many agent reports wait in the intake inbox; the `inbox` argument works them. Use when asked to file a bug or idea, run intake, or triage the intake inbox.
argument-hint: "[inbox | <bug report(s) or idea(s), free text; screenshots/paths welcome>]"
---

# Intake

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH). Paths written `$PDO_STATE_DIR`, `$PDO_INBOX` or `$PDO_HOME` (the engine checkout) mean the values `pdo project-env <KEY>` prints; agent sessions don't have them set.

Turn what the human describes into well-formed GitHub issues that a command agent can pick up without
re-exploring from scratch.

**Project facts.** The project is the one whose repo contains the current directory, or the engine
project you were started for (`--project`). From its project env (read each key with
`pdo project-env [--project <p>] <KEY>`) take `ORG`, `PROJECT_NUMBER` (the
board), `REPO_ROOT` (the repos) and `GH_USER`. From `.agents/project-profile.md` take `## Identity`
(what each related repo holds, so you can route an item to the right repo), `## Docs` (design-doc
locations) and `## Conventions` (its list of business-critical areas, if any).

**gh identity.** If `GH_USER` is set, run gh through `pdo with-gh-user gh …`. Never `gh auth switch`.

## Arguments

- **Empty:** count the inbox files (don't read them), say "Ready. N reports waiting in the inbox
  (`/project-intake inbox` to work them).", and wait. **Never start on the inbox unasked.** A bare
  start (a launcher script, a team start-up) must only report the count.
- **`inbox`:** work the inbox (below). Only this argument does.
- **Anything else:** the human's own items. Handle them on their own; don't pull pending inbox reports
  into that batch. If reports are waiting, mention the count in one line at the end.
- **Legacy format:** a direct `/project-intake From <workspace name>: …` prompt is handled like an
  inbox report from that workspace.

## The intake inbox

Agents don't prompt intake; they queue reports with
`pdo intake-submit "<workspace name>" "<report>"` (or the report on stdin). Each report is one
Markdown file with `from:` and `submitted:` frontmatter in the inbox dir: `$PDO_INBOX` (default
`$PDO_STATE_DIR/intake-inbox`; `INTAKE_INBOX` is still honoured).

With `inbox`: list the files at the top level only (ignore `done/` and dotfiles). None: say you're
ready and wait. Otherwise read every file and treat each report as one item in a single batch. Tell
the human how many there are and who sent them. Credit the `from:` workspace in the footer
(`references/issue-template.md`), and ask the human, never the sending agent, anything you need.

The input can hold several items. Handle each separately, present them in one batch.

**Conventions.** Types: Epic / Feature / Bug / Task (org issue types; personal repos have none and the
API silently drops `type`). Labels: `P1-urgent` … `P4-low`, `needs-triage`, `Security`, `small-win`,
`needs-design`, `on-hold`, `client-requested` (the human says a client or customer asked for it),
the `route:*` labels, plus area labels. These are the engine defaults; a project may rename the P-labels in
its env (`P_LABELS`; read it with `pdo project-env P_LABELS`). Board = org (or user) Project `PROJECT_NUMBER` of `ORG`.
Filing is done by `pdo file-issue`.

## 1. Classify each item (no tools yet)

- **Repo:** pick from the related repos in the profile's `## Identity` (what each one holds). If
  there's only one repo, that's it.
- **Type:** Bug (behaves wrongly), Feature (new capability), Task (chore, infra, clean-up), Epic
  (several deliverables, or needs a design doc).
- **Route label** (which lifecycle the orchestrator runs):
  - `route:small`: fits one context window with no design questions;
  - `route:design`: needs a design doc; Epics and anything with open UX or architecture choices;
  - `route:build`: only when a READY design doc already exists.
- **Priority** (suggested; the human decides):
  - P1: data loss, a security hole being exploited, production down;
  - P2: security flaws, wrong computed/business-logic results, things users need soon;
  - P3: real but tolerable bugs; normal features;
  - P4: polish, clean-up, ideas.

  Security issues and logic bugs lean one level higher than their cosmetic twins.
- **`Security`:** authn/authz, injection, secrets, exposure, unsafe input. Not general infra hardening.
- **Area labels:** pick from the repo's existing labels (`gh label list -R <ORG>/<repo>`). Never invent labels.
- **Parent epic:** an open Epic this clearly belongs to. Blank if unsure.

## 2. Bounded, fact-only look (one sub-agent for the whole batch)

Spawn **one** read-only exploration sub-agent if your tool supports it (Claude Code: the `Explore`
agent, `model: "opus"`; Codex/Grok: their subagents); otherwise do it yourself under the same budget.
Give it every item and a hard budget: **at most ~15 tool calls, medium breadth.** Per item it returns
**facts only**:

1. **Possible duplicates or related issues:** `gh search issues --owner <ORG> "<keywords>" --state all
   --limit 10`, plus a title scan of open issues. Number, title, state, one-line reason.
2. **Related memory and design docs:** your tool's memory index for this project if it keeps one
   (Claude Code: the project's auto-memory `MEMORY.md`), and the design-doc dir from the profile's
   `## Docs`, read from the default branch's checkout. File names plus one line each.
3. **Candidate entry points:** files, components, endpoints or classes where the behaviour lives
   (`path:line` when cheap). Locations only.

It must **not** propose root causes, fixes or designs, and must not read whole files beyond what
locating needs. This keeps the command agent from being steered by a guess made during a skim.

If it finds a likely **duplicate**, don't draft a new issue: propose a comment on the existing issue
and show the text.

## 3. At most one clarification round

Ask only what the issue can't do without, in one batch (Claude Code: AskUserQuestion): for a bug,
repro steps or where it happens; for a feature, the core behaviour when genuinely ambiguous. Skip it
if nothing is missing. Later details belong to the command agent's own intake phase.

## 4. Draft and confirm (gate)

Show each draft as **key decision points only**: repo, type, title, labels, priority, parent, route,
board status, plus any notable design or scope choice baked into the body (one line each). Do **not**
print the full body unless asked. For a high-importance business-logic item, show it as its own
decision point, `Blocking approval: yes — <reason>`, so the human can keep or drop it. Body template:
`references/issue-template.md`.

Rules:
- Titles are specific and ≤80 characters. A bug title states the symptom, not the fix.
- Every new issue gets `needs-triage` **unless** the human gave its priority explicitly in this
  conversation; then apply that P label and drop `needs-triage`.
- **High-importance business logic:** the human flags it, **or** the item could change computed
  results, permissions, or what gets saved or deleted, or touches an area the profile's
  `## Conventions` lists as business-critical. Judge this yourself for every item. When it applies and
  the item leaves a business-rule choice to the build, add the `[!IMPORTANT]` block and acceptance
  item from the reference. That is a **blocking gate**, never waived, even under `route:small`.
- Board status is `Backlog` by default. Use the queue status (default `Claude Work This`) only when
  the human says to work it right away; the orchestrator picks that up and starts it.

The repo line is how the human approves where each item is filed: never file, comment or close in a repo the gate
didn't show.

Ask once: **file as drafted, adjust, or drop items?** Apply adjustments, then file. Don't re-confirm
unless something material changed.

## 5. File

Per approved item, write the body to a scratchpad file and run:

```bash
pdo file-issue <repo> --title "<title>" --body-file <file> --type <Type> \
  --label <l1> --label <l2> ... [--parent <n | Repo#n>] [--status "Backlog"|"Claude Work This"] [--project <p>]
```

It validates labels (unknown ones fail loudly), attaches the parent, and adds the card to the board.
For an **Epic with obvious parts**, file the Epic first, then each part with `--parent <epic#>`;
otherwise one Epic with `needs-design` and `route:design`. For a **duplicate**, post the approved
comment with `gh issue comment` instead.

## 6. Close out and report

**Inbox:** move each processed file into `<inbox>/done/` and append a `## Outcome` section (issue
numbers, the duplicate comment, or "dropped by human", with the date). Leave unapproved items in the
inbox.

**Reply to each reporting agent** with its issue numbers, in one
`herdr agent prompt <agent> "From intake: …"`. Find it with `herdr agent list`, matching name or
workspace label. **Only reply when it's idle (`idle`/`done`) and no question is pending on its
screen** (`herdr pane read`: no "Enter to select" or "Do you want to proceed"). Typing into a pending
question answers it with the wrong text. Skip the reply if the agent is gone, hibernated, working or
asking; the outcome is already in `done/`. Refer to agents by workspace **name**, never a bare id.

List one line per item: `Repo#n title — labels, status` with the URL (bare `#n` for `PRIMARY_REPO`),
plus any duplicate comments posted. If anything went to the queue status, say the orchestrator picks
it up within about 5 minutes (its queue refresh).
