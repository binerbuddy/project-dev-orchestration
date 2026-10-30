---
name: project-setup
description: Set up, initialise or onboard the current git repo for project-dev-orchestration (the orchestration / agent workflow) - detect the layout, origin, stack and its build/typecheck/test commands, draft .agents/project-profile.md, add the "How work flows here" section to AGENTS.md, check and create the GitHub labels, record the QC fixture format, generate the human guide (docs/agent-workflow.md or the repo's human-docs dir) and gitignore .agents/local/, and when an orchestrator team will run here (repo+team) register the repo with the engine (projects/<name>.env, optional project board), then deliver the repo files as a PR on chore/agent-workflow-setup that follows the repo's own changeset/CI rules. Asks at most three short rounds of questions, each with a recommended answer, leading with detected defaults. Handles repos that are one of several in a project. Idempotent - a re-run reports what is present and what has drifted, and only fills gaps. Use when asked to set up, initialise, onboard or bootstrap a repo for the orchestration or agent workflow, or to check or repair an existing setup.
argument-hint: "[repo-only|repo+team]"
---

# Project setup

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH). Paths written `$PDO_STATE_DIR`, `$PDO_INBOX` or `$PDO_HOME` (the engine checkout) mean the values `pdo project-env <KEY>` prints; agent sessions don't have them set.

Initialise the **current working repo** to use project-dev-orchestration: the repo files every agent reads (the
profile and `AGENTS.md`), the guide its humans read (`docs/agent-workflow.md` by default), the GitHub labels the
pipeline relies on, and, when an orchestrator team will run the repo from this machine, the engine's registration of
the repo.

**Idempotent.** Every step first checks what is already there. A re-run prints what is present, what has drifted
(present but out of date, or disagreeing with what detection finds), and what is missing, and only fills gaps.
Drifted items get a proposed fix that is applied only on the human's yes. Nothing already present is overwritten,
renamed or deleted without it.

**Rules for the whole run.**
- **Don't invent anything.** Every fact in the profile, the workflow section and the env file comes from detection
  (with its source) or from the human. Anything neither gives stays marked `TODO(setup): <question>`, so the next
  run finds it.
- **Verify what you didn't detect.** A command, script, path or branch that comes from the human, from a draft, or
  from an existing file is still checked against the repo's default branch (step 2's verification pass) before it
  is written or kept. A mismatch is flagged, never silently dropped or kept.
- **This repo only.** Reading related repos for context is fine. Writing to any other repo (files, branches, PRs,
  issues, comments, labels) needs the human's yes first; offer to run `/project-setup` there separately instead.
- **Never push to the default branch.** Repo-file changes go on `chore/agent-workflow-setup` and a PR.
- **Never delete or rename a GitHub label**, and never use `gh label create --force` on one that exists.
- **Show before you move.** Moving the human's existing `CLAUDE.md` (or any other) content needs the diff shown and
  an explicit yes.
- **Few questions, in at most three short rounds** (section "Questions" below). Lead with what you detected, so
  most answers are one "yes". Every question carries a recommended answer, and every question can be answered
  "skip": the item stays `TODO(setup)`. Never ask about something the profile can leave as `TODO(setup)` without
  blocking the run; collect those at the end as optional.
- **gh and git identity.** Never `gh auth switch`.
  - **`GH_TOKEN` already set** (a dispatched agent runs inside `pdo with-gh-user`; or the human exported it): gh
    already uses it. Check who it is with `gh api user --jq .login`, use that login, and don't re-pin (no
    `with-gh-user`, no second `gh auth token -u`). For git over HTTPS, `git config --get-all
    credential.https://github.com.helper` showing `!gh auth git-credential` means plain `git push` already uses the
    token; otherwise add the helper for that one command (`git -c credential.https://github.com.helper= -c
    'credential.https://github.com.helper=!gh auth git-credential' push …`), which reads the `GH_TOKEN` already set.
  - **Not set:** once a `GH_USER` is known (an existing project env, or the human's answer in round 2), run gh as
    `pdo with-gh-user gh …` or `GH_TOKEN=$(gh auth token -u <user>) gh …`. `git push` and `git fetch` over HTTPS
    don't read `GH_TOKEN` on their own: run them as `pdo with-gh-user --user <login> git push …`, which also injects
    gh's credential helper for github.com. Without the engine: `GH_TOKEN=$(gh auth token -u <login>) git -c
    credential.https://github.com.helper= -c 'credential.https://github.com.helper=!gh auth git-credential' push …`.
- LF line endings in every file you write. Normalise anything you copy from an existing file to LF first.

## 0. Mode: will an orchestrator team run here?

Two setups. Name them this way to the human:
- **repo-only**: only the repo files that tell everyone's agents how to work here (profile, `AGENTS.md` section,
  human guide, labels). Nothing on this machine changes. For someone who works the repo with their own agent.
- **repo+team**: the same, plus registering the repo with the engine on this machine (step 6: an env file, and a
  board if wanted), so an orchestrator team (`pdo`) can run it.

The arguments `repo-only` and `repo+team` pick one; the older names `collaborator` (= repo-only) and `full`
(= repo+team) still work. Without an argument, decide in this order, and **state the decision** in one line with
its reason instead of asking whenever detection settles it:
1. **Already registered** (`pdo project-env`, run from the repo, resolves a project): repo+team, checking that
   registration. "This repo is already registered with the engine as project `<p>`; I'll check that too."
2. **No engine reachable and none shipped with this plugin**: repo-only. "The engine (`pdo`) isn't installed
   here, so I'll only add the repo files." The engine is reachable when `pdo` is on PATH, or the human names an
   engine checkout: a directory whose `bin/` holds `pdo` and `project-env`. If they name a wrapper or overlay
   directory with its own `bin/`, use it only if its `bin/` runs every command this skill calls (`<dir>/bin/pdo help`
   lists them); otherwise ask for the engine checkout itself. **The plugin ships the engine:** this skill's base
   directory is `<plugin>/skills/project-setup/`, and `<plugin>/bin/install` (`../../bin/install` from the base
   directory) is the engine's installer. When it exists, the engine is installable, not missing: go to 3.
3. **Otherwise ask one plain question** (in round 1, below): "Is an orchestrator team (pdo) going to run on this
   machine for this repo? **Yes:** I'll also register the repo with the engine (and install the engine from this
   plugin, when `pdo` isn't on PATH yet). **No:** I'll only add the repo files that tell everyone's agents how to work
   here." Recommend **Yes** when the config dirs already hold other projects (this machine runs teams), else **No**.

`repo+team` (by argument or answer) with no `pdo` on PATH installs the engine first (step 6, "Install the engine").

**One of several repos in a project:** if `pdo project-env` run from this repo resolves a project whose
`PRIMARY_REPO` is another repo, this repo is a secondary repo of that project. Use repo+team against that
project's env (step 6 edits it, never creates a second one), and treat its board as shared (step 2, §Identity).

## Questions: at most three short rounds

Run detection (step 1) first, then ask. Claude Code: one `AskUserQuestion` call per round (at most 4 questions);
Codex and Grok: one short numbered list per round. Each question states the recommended answer first, from
detection where possible (`Manager (recommended: <login>, the repo's top committer)`), so "yes" accepts it. Ask
only what isn't settled; a round with nothing left is skipped.

1. **The plan.** One list of what you detected and will write, approved with one "yes" (or "yes, except …"): the mode
   when step 0 didn't settle it, the files to add or change (profile, `AGENTS.md` section, guide path and the docs
   dir chosen, `.gitignore`), the `CLAUDE.md` move (with its diff, step 3), the README link (step 7), and the labels
   to create (step 4).
2. **People.** `Manager` (who runs the team, sets priorities and merges, and how to reach them) and `Where to ask`
   (where collaborators ask questions). repo+team adds the engine's few: the project name (recommended: the repo
   name in lower case), `GH_USER` (recommended: the login `gh api user` shows, when it has push access), and the
   board (recommended: the board linked to the repo if `gh project list` finds one, else none). repo-only asks about
   the board as an optional question: "Is there a project board for this repo? (recommended: skip; record it later)".
3. **What can't be detected and would leave QC unusable:** the QC data and fixture format (step 5; recommend
   what the stack suggests, e.g. an input file with its expected output for a headless repo), the ports reserved for
   the human's QC servers and the agents' port scheme, and the "Human run" line (recommend the detected start
   command). For the QC ports, ask explicitly: "Does QC get its own ports, or share the ports you run your own dev
   servers on? **Own (recommended):** e.g. <dev ports +2>; QC never touches your dev servers. **Shared:** QC uses
   <dev ports>, and starting QC stops whatever you have running there." Recommend own ports, distinct from the
   detected dev-server ports, and the same ports +100 for agents. Shared sets `QC_PORTS_SHARED=1` (step 6); with own
   ports, `pdo qc` refuses to stop a listener it didn't start.

**Optional, at the end.** Everything else the profile can leave as `TODO(setup)` without blocking: extra review
roles, related repos, §Conventions and §Do not, §Project extras, `Human guide notes`, worktree naming when there's
nothing to infer, type labels on a user-owned repo. List them in one message as optional ("answer any now, or skip
and they stay `TODO(setup)`"), each with a recommendation where you have one. Never hold the run for them.

## 1. Detect (read-only)

Recipes for each item: `references/detection.md`. Find:

1. **Repo root and layout:** the worktree top level, the git common dir, and whether it is a **bare-root** layout
   (worktrees as subdirectories of a bare clone). This gives `REPO_ROOT` and the profile's §Layout.
2. **`<org>/<repo>`** from `origin`, the **default branch** (`gh repo view … --json defaultBranchRef`), whether the
   owner is an organization or a user (issue types and the board depend on it), the org's issue types, and your
   permission on the repo (below WRITE: no label creation, and the PR comes from a fork).
3. **Stack and the authoritative build, typecheck and test commands**, per part of the repo: CI workflows first, then
   `package.json` scripts, `*.sln`/`*.csproj`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Makefile`. Record only
   commands that exist on the default branch. Dev servers and their ports where obvious. Whether the repo has a UI
   at all (a web or desktop front end), or is headless (an engine, library, CLI or API with no UI).
4. **Existing files:** `AGENTS.md` (and whether it already has `## How work flows here`), `CLAUDE.md` (and its line
   endings), `.agents/project-profile.md` (worktree and default branch), the human guide (`<docs dir>/agent-workflow.md`;
   its `guide-version:`), whether `.gitignore` covers `.agents/local/`, docs dirs (and which are gitignored), issue
   and PR templates, and the repo's labels.
5. **Changelog and PR rules (CI):** the changelog convention (changesets, a CHANGELOG file, release tooling), and any
   workflow that fails a PR without one: a required-changeset or changelog check, the label that skips it (e.g.
   `skip changeset`), and the paths it exempts. Step 8 applies these to the setup PR itself.
6. **Engine:** whether `pdo` is reachable, whether the repo is already registered (`pdo project-env` run from the repo resolves a project,
   and whether this repo is its `PRIMARY_REPO`), the config dirs, and the gh logins on the machine.

7. **A fresh `origin/<base>`.** Every check against the default branch reads `origin/<base>`, so update it first
   with the recipe in `references/detection.md` ("Fresh origin/<base>"): a bare clone made without a fetch refspec
   doesn't move `refs/remotes/origin/<base>` on a plain `git fetch`, and the recipe detects that and fetches with an
   explicit refspec.

Print a short **detection report**: one line per item with its value, its source, and its state (present, missing,
drifted). On a re-run this report is the main output; the later steps act only on the missing and drifted lines.

## 2. Profile: `.agents/project-profile.md`

Start from this plugin's `templates/project-profile.md` (`../../templates/project-profile.md` from this skill's
directory). **Keep the template's `##` headings exactly** (`Identity`, `Layout`, `Build & checks`, `Tests`,
`Dev servers`, `QC data`, `Changelog`, `Review roles`, `Docs`, `Conventions`, `Project extras`, `Do not`; `Project extras`
is optional and is deleted when empty); the lifecycle skills cite them as `§<Section>`. Drop the template's guidance comment and the commented examples, and replace each
guidance paragraph with facts.

- Fill from detection: §Identity (org, primary repo, issue types or "none: user-owned repo"), §Layout (bare root or
  plain clone, worktree naming if it can be inferred, base branch, branch prefixes seen in `git branch -r`),
  §Build & checks and §Tests (the commands, each with the directory it runs in; "none defined" where there is none),
  §Dev servers (start commands and ports found, with their files), §Changelog (the convention found, with an example
  entry copied from the repo, plus the CI check, skip label and exempt paths from step 1), §Docs (the dirs found).
- **The unknowns detection can't give** go into the question rounds above (round 2: the §Identity guide lines;
  round 3: §QC data, §Dev servers ports and "Human run"; the rest is optional at the end). What each one holds:
  - **§QC data:** what human QC runs against. With a UI: seed data, what the top-level record is called in the UI,
    the fixture format and extension, how to export and import one, any size limit (see step 5). Headless: what a
    QC case is (an input file or request plus its expected output), the fixture format, and the command a human
    runs to check one;
  - **§Project extras:** does the project have conventions of its own on top of the engine's label/review QC
    handoff that humans or agents must know: PR-comment commands handled by a service or a `WATCH_EVENT_HOOK`, a
    hosted preview (how to start and stop it, link pattern, login), chat or bot commands, extra QC steps? Record
    each with its exact trigger text; QC commands go under `### QC commands` as a table (it ends every QC checklist).
    None: delete the section;
  - **§Review roles:** extra reviewer roles (a UI designer for the project's component library, a data reviewer for
    migrations), or none;
  - **§Identity related repos:** other repos agents may need to search or file against, and when each is in scope;
  - **§Identity board:** the project board, if any (repo+team handles it in step 6; repo-only only records what the
    human says, and "Board: TODO(setup)" when they skip);
  - **§Dev servers:** the ports reserved for the human's QC servers and the port scheme agents use instead; the
    database rules; and the plain commands a person runs to start the app for QC (the "Human run" line);
  - **§Conventions** and **§Do not:** anything the human wants stated now (both may start short);
  - **§Identity, for the human guide (step 7):** `Manager` (the person who runs the team, sets priorities and
    merges, and how to reach them), `Where to ask` (where collaborators ask questions), and `Human guide notes`
    (anything repo-specific the guide must tell people: which repo to file in, house prohibitions in plain words).
    These are round 2. The guide is rendered from these lines, so a re-run never loses the answers.
- Write answers in; unanswered items stay `TODO(setup): <question>` under their heading.
- **Shared board (a project with several repos).** The primary repo's profile holds the board's ids. A secondary
  repo's §Identity names the board and points at the ids instead of copying them: "Board: org Project #<n>, shared
  with `<org>/<primary>`; ids: `pdo project-env --board` (without the engine: `gh project field-list <n> --owner
  <org> --format json`)." Copies go stale when a column is edited.
- **Verification pass (every run, whatever the source).** When the profile's content comes from a draft, an
  existing profile, or the human's answers, check every concrete claim against the default branch before writing or
  keeping it: each `npm run <x>` exists in that `package.json`'s `scripts` (`git show origin/<base>:<dir>/package.json`),
  each make/just target exists, each path and file exists, each named branch exists on origin, each label exists
  (step 4). A mismatch (e.g. a script that exists only on an unmerged branch) is flagged in the detection report and
  the PR's open questions with what was found; keep it only if the human says so, and then with a note saying where
  it does exist.
- **Profile already present:** don't rewrite it. Report missing or renamed headings, `TODO(setup)` markers, template
  text left in, missing §Identity guide lines (`Manager`, `Where to ask`, `Human guide notes`), and facts that
  disagree with detection or fail the verification pass (a base branch that changed, a build script that no longer
  exists, a different `<org>/<repo>`). Propose a fix for each and apply only what the human accepts.

## 3. `AGENTS.md`: the workflow section

Fill this plugin's `templates/AGENTS-workflow-section.md` (`../../templates/AGENTS-workflow-section.md`): drop its
leading comment, replace every `<placeholder>` (`<org>/<repo>`, `<project#>`, `<base>`) and use the project's label
names where its env renames them. `<guide path>` is where step 7 writes the human guide. With no board, replace the
"on org Project `<project#>`" clause with "with no project board (the `<queue label>` label puts an issue in the
orchestrator's queue)", or, in repo-only, "with no project board (a maintainer dispatches agents by hand)".
`<engine checkout>` must be a path that survives engine upgrades, or nothing. In repo+team, decide in this order:
1. **`pdo` is on PATH** (`command -v pdo`): use the template's pdo-on-PATH variant of the engine paragraph, which names no path.
2. **Else `pdo project-env PDO_HOME` is a stable checkout:** a git work tree (`git -C <path> rev-parse
   --is-inside-work-tree`) whose path has no `/plugins/cache/` segment and no version directory (e.g. `…/0.8.0`).
   Write it with `~/` when it is under the home directory (person-started sessions without `pdo` on PATH find the
   engine through it; a dispatch brief's absolute path still wins).
3. **Else** (the engine only exists in a tool's versioned plugin cache, which the next upgrade replaces): never write
   that path. Install the engine (step 6, "Install the engine"), which puts a version-following `pdo` on PATH, and
   use case 1. If the human declines, use "your project-dev-orchestration checkout".
In repo-only, replace it with "your project-dev-orchestration checkout".
A re-run reports an `AGENTS.md` that names a plugin-cache path as drifted and proposes the fix. For a headless repo, use the template's headless wording in the QC Checklist rule.

- **No `AGENTS.md`:** create it with a one-line title and the section.
- **`AGENTS.md` without the section:** append it at the end, unchanged otherwise.
- **Section present:** compare it with a freshly filled template. Report placeholders left, wrong org/repo/base or
  label names, and rules the template has that the section lacks. Propose the edits; apply on yes. Never drop rules
  the human added.
- **A human-approved draft of the section** (the human hands you one, or it is in a draft PR or file): merge it with
  the freshly filled template. The approved wording wins on content: keep its rules, its stricter variants (e.g.
  "every PR gets a checklist" over the template's "every user-visible PR"), and its repo-specific labels in the
  labels list. The template supplies the required parts the draft lacks: the first-session guide rule, the labels
  and routes, the must and must-not rules, "Other repos", the intake rule and the QC Checklist rule. Where the two
  conflict, keep the draft's wording and list each conflict (template rule, draft rule, which was kept) in the PR
  body's open questions.
- **`CLAUDE.md` with content** (anything beyond `@AGENTS.md` and Claude-only notes): offer to move the
  tool-neutral content into `AGENTS.md`, so Codex and Grok read it too, and leave `CLAUDE.md` as `@AGENTS.md` plus
  the Claude-only notes (slash commands, Claude Code hooks or settings, Claude-specific tool names).
  - Build both new files in the scratchpad **from the default branch's current `CLAUDE.md`**
    (`git show origin/<base>:CLAUDE.md`), read at run time. If a draft of the move predates that file's last commit,
    re-diff the draft against it and carry over what changed since.
  - **Normalise to LF before diffing** (`tr -d '\r'`), so a CRLF file doesn't show every line as changed; say in the
    PR body that the moved content was converted from CRLF to LF.
  - **Show the diff** (`git diff --no-index <old, LF> <new>` for each file), and move only after the human's yes. If
    they decline, leave `CLAUDE.md` as it is and report it as skipped. `CLAUDE.md` absent: create it as `@AGENTS.md`
    only if the human uses Claude Code; it is harmless either way, so ask.

## 4. GitHub labels

Check every label the engine and skills rely on, then create the missing ones with `gh label create` (in this repo
only): `route:small`, `route:design`, `route:build`; the P-labels (`P_LABELS`, default `P1-urgent P2-high P3-medium
P4-low`); `LABEL_QC_READY` and `LABEL_QC_DONE` (default `ready for QC`, `QC complete - ready to review`),
`LABEL_MERGE_READY`, `LABEL_UX_SKIPPED`, `LABEL_NEEDS_UX`, `LABEL_QC_ESCALATED` (default `Ready for Merge`,
`UX testing skipped`, `needs UX review`, `QC escalated`); the
`CARRY_LABELS` (default `client-requested`); and `needs-triage`, `epic-phase`, `awaiting-ux-gate`, `likely-fixed`,
`has-follow-ups`, `blocked-by-pr`, `on-hold`, `needs-design`, `Security`, `small-win`, `orchestrator-system`. Also check (never
create) the repo-specific labels the profile, the workflow section or CI name, such as the changeset skip label.
Colors, descriptions, what relies on each, and the check-then-create loop: `references/labels.md`. On a user-owned
repo (no issue types), also create the type labels the human names, and record them in §Identity.

- **Check-only mode** (`CREATE=0` in the recipe): a re-run, a run without write access, or a human who only wants
  the report. It lists present and missing labels and prints the `gh label create` commands, creating nothing.
- **The repo's own labels:** list every label the repo has that the engine set doesn't name, as information only
  (no judgement, no rename, no delete). They go in the PR body's label check.

Never delete or rename a label. A case-only difference counts as present (GitHub names are case-insensitive); report
it. Yellow is reserved for "a human acts now" (`references/labels.md`, Colors). A label that breaks that rule (a human
label that isn't yellow, or another label that looks yellow) is **drifted**: propose `gh label edit --color` (color
only) and apply it on the human's yes. Other color differences are the repo's choice; report them, change nothing. Without write access, run check-only, list the commands for a maintainer, and carry on.

## 5. QC fixtures

Tell the human, in two or three lines:
- QC fixtures (test data a QC checklist links to) live on a never-merged `qc-fixtures` branch (`FIXTURE_BRANCH`).
  You don't create it now: `pdo qc-fixture-push <PR#> <file>` creates it the first time an agent publishes a fixture.
  The same push uploads each fixture to a `qc-fixtures-assets` prerelease (`FIXTURE_RELEASE`, `""` = off), so the
  checklist links a file download instead of GitHub's Raw view.
- It is per repo, and its format is this repo's own (an app export, a database dump, a JSON seed file; for a
  headless repo, typically an input file with its expected output).

Ask for the fixture format (what it is, its file extension, how to export one and import or run it, any size limit)
and record it in the profile's §QC data. In repo+team also set the extension in the env file: `FIXTURE_EXT` (e.g.
`.json`, `.tar.gz`) for the project's primary repo, and for a secondary repo with its own format an entry in
`FIXTURE_EXT_BY_REPO` (`declare -A FIXTURE_EXT_BY_REPO=([<repo>]=".<ext>")`), which `qc-fixture-push --repo <repo>`
uses before `FIXTURE_EXT`. `qc-fixture-push` warns when a file doesn't match. No fixtures (the seed data covers
QC): say so in §QC data and leave both unset.

## 6. repo+team: engine registration

Skip this whole step in repo-only.

**Install the engine** (only when `command -v pdo` finds nothing). Run this plugin's installer, `<plugin>/bin/install
--bin` (`../../bin/install` from this skill's base directory). From a plugin it writes `~/.local/bin/pdo`, a launcher
that always runs the newest installed plugin version, so plugin updates need no re-install; from a git checkout it
links `bin/pdo`. Report its output to the human:
- `note: … is not on your PATH`: give the line to add to their shell profile (`export PATH="$HOME/.local/bin:$PATH"`),
  and use the full path (`~/.local/bin/pdo`) for the rest of this run.
- `requirements: missing …`: list what to install (the engine needs bash 4+, python 3.8+, git, jq, gh and herdr).
  Carry on with the registration; `pdo team-up` waits until they are installed.
- `skip: … exists`: a `pdo` that isn't the engine's is in the way; show it and ask before doing anything about it.
Then create the config dir (`${XDG_CONFIG_HOME:-~/.config}/project-dev-orchestration/projects`) if it doesn't exist.

**Env file.** The project name is the human's choice (suggest the repo name in lower case; it is what `--project`
takes). Write `projects/<name>.env` into the first dir of `PDO_CONFIG_DIRS`, or the default
`${XDG_CONFIG_HOME:-~/.config}/project-dev-orchestration` when it is unset. If step 1 found the repo already
registered, edit that file instead: add missing keys, and show any value that disagrees with detection as a diff for
the human to accept or keep. Plain bash; a related repo goes in `REPO_ROOT` only if the human named it in step 2.

```bash
# <config dir>/projects/<name>.env
ORG="<org>"
declare -A REPO_ROOT=(
  [<repo>]="<repo root: the bare root, or the clone's top level>"
)
PRIMARY_REPO="<repo>"
declare -A ROUTE_SKILL=(
  [small]="${PDO_SKILL_PREFIX}project-small-feature-or-bug-fix"
  [design]="${PDO_SKILL_PREFIX}project-feature-design"
  [build]="${PDO_SKILL_PREFIX}project-feature-build"
)
DEFAULT_MODEL="opus"            # the engine default; ask if the human wants another
GH_USER="<login>"               # the gh login this project's agents use (gh and git push)
# PROJECT_NUMBER=<n>            # only with a board (below)
# declare -A WORKTREE_PARENT=([<repo>]="<dir>")  # where agent/QC worktrees go; default: the bare root, or
#                                                # "<clone>-worktrees" next to a plain clone (only set to override)
# BRANCH_PREFIX="bug=fix default=feat"   # small-route branch prefix by issue type (by label when untyped); a user-owned repo
#                                         # (no issue types) maps its type labels here, e.g. "bug=fix task=chore default=feat"
# FIXTURE_EXT=".<ext>"          # from step 5: the primary repo's fixture format
# declare -A FIXTURE_EXT_BY_REPO=([<other repo>]=".<ext>")   # repos with another format
# QC_PORTS="<ports>"            # the ports QC serves on, from round 3 (own ports, not the human's dev servers')
# QC_PORTS_SHARED=1             # only when the human chose to share their dev ports with QC (qc may stop their servers)
# AGENT_QC_PORTS="<ports>"      # agent QC (QC Agent workspace) ports, distinct from QC_PORTS and agents' ranges; off when unset
# AGENT_QC_NOTES="docs/agent-qc-<name>.md"   # the project's agent-QC know-how (login, seed users, browser notes)
# declare -A AGENT_QC_NOTES_BY_REPO=([<repo>]="docs/agent-qc-<repo>.md")   # a repo with its own recipe or pass rule
# AGENT_QC_REVIEW_HOOK="hooks/<name>"         # run with <repo> <pr#> after a UX-review pass (e.g. request a preview)
# AGENT_QC_RECYCLE=0                         # keep one QC Agent session (default: a fresh session after each verdict)
# WATCH_EVENT_HOOK="hooks/<name>"  # only for project events of its own (e.g. §Project extras comment commands)
# MANAGER="<workspace name>"    # who manages it; default "Orchestrator (<name>)" with a board
# PORTFOLIO_PRIORITY=3          # CEO (pdo fleet): 1 = highest
# RESOURCE_PROFILE=medium       # light | medium | heavy
# FLEET_ADVICE=ignore           # honour = follow pdo fleet's go/slow/hold advice
```

- **`GH_USER`:** show the logins `gh auth status` lists and ask which one this project's agents use. Leave it unset
  only if the human says the active account is fine (the engine then pins nothing).
- **A secondary repo** (step 0): its entry in the project's `REPO_ROOT` is already there or is added; add its
  `FIXTURE_EXT_BY_REPO` entry if its format differs. Don't change `PRIMARY_REPO` or `PROJECT_NUMBER`.
- Write renamed label keys (`CWT_STATUS`, `P_LABELS`, the `LABEL_*` keys) only when the repo already
  uses other names; otherwise the defaults apply and the keys stay out.
- Hooks (`QC_HOOK`, `IDENTITY_HOOK`, `TEAM_UP_HOOK`) are project-specific code: list them as next steps, don't write
  them. An `IDENTITY_HOOK` wrapper that sets `GIT_CONFIG_*` should append after the existing `GIT_CONFIG_COUNT`, as
  `bin/with-gh-user` does, since it runs inside it.

**Board (optional).** Offer to set up a GitHub Projects v2 board. The engine's board writes (`claim`,
`board-status`, `file-issue`) query an organization project, so the board must be org-owned; for a user-owned repo,
recommend skipping it.
- **Use an existing one:** `gh project list --owner <org> --format json`, then
  `gh project field-list <n> --owner <org> --format json` (needs the `read:project` scope; if gh lacks it, ask the
  human to run `gh auth refresh -s read:project,project` themselves). Record `PROJECT_NUMBER` in the env, and in
  the primary repo's §Identity the board's number, title, node id, the Status field id, and the option id of each
  Status column (`pdo project-env --board` prints them once `PROJECT_NUMBER` is set). The queue column
  (`CWT_STATUS`, default `Claude Work This`) must be one of the options; the others the engine uses are Backlog,
  In Progress, In Review and Done (see `../project-how-it-works/references/labels-and-board.md`). Report missing
  options and ask the human to add them in the board's UI: editing the field's options through the API replaces
  the whole list and changes every option id.
- **Create one:** only on the human's explicit yes. `gh project create --owner <org> --title "<title>"`, then
  `gh project link <n> --owner <org> --repo <org>/<repo>`, then have the human add the Status options above in the UI,
  and record it as for an existing board.
- **Skip:** no board. Leave `PROJECT_NUMBER` out; §Identity says "Board: none". The queue is then board-less: the open
  issues labelled `QUEUE_LABEL` (default `queue:work`; create that label in step 4's loop), ranked by P-label, and
  `pdo spawn` still claims (the `managed-by:` label and claim comment; only the board move is skipped).

**Verify.**
- `pdo project-env --project <name>`: every key resolves as intended (`REPO_ROOT`, `PRIMARY_REPO`, `GH_USER`, the
  `ROUTE_SKILL` entries, `FIXTURE_EXT_BY_REPO`); and `pdo project-env` with no `--project`, run from the repo,
  resolves to `<name>`. With a board, `pdo project-env --board` lists its columns.
- `pdo queue --project <name>`: a dry read (it ranks; it doesn't claim or move anything). With a board it lists the
  eligible issues; without one it lists the issues labelled `QUEUE_LABEL` ("board-less" in its summary line).

## 7. The human guide

The page the repo's collaborating humans read: which labels and routes to use, how to request work, how QC works
here (the label/review handoff, fixtures, and any §Project extras), the changelog rule, who the manager is and where to ask. Agents
check it once per clone (`AGENTS.md`'s first-session rule), so it must exist and stay current.

- **Location.** Choose the docs dir, then check it, and say in the summary and the PR body which dir was chosen and
  why:
  1. the dir the profile's §Docs names for human docs ("Human guide: `<path>`" from an earlier run wins outright);
  2. else the dir that already holds the repo's other human-facing docs (developer or user guides, contributing
     notes), preferred over a design-doc, ADR or plan dir;
  3. else `docs/`.
  Then run `git check-ignore -v <dir>/agent-workflow.md`: if the path is ignored, that dir can't hold it; take the
  next candidate (the repo root is the last resort) and never edit the ignore rule without the human's yes. Record
  the path in §Docs ("Human guide: `<path>`") and use it for `AGENTS.md`'s `<guide path>`.
- **Fill** this plugin's `templates/agent-workflow-guide.md` (`../../templates/agent-workflow-guide.md`) from the
  profile as written in steps 2 and 5, and in repo+team from the env file of step 6 (renamed labels, the queue
  column, the board). Each placeholder names its source; the manager, where to ask and the repo notes come from
  §Identity's `Manager`, `Where to ask` and `Human guide notes` lines, and "Run it locally" from §Dev servers'
  "Human run" line (never the agent port scheme). Keep the `[if …]` blocks whose condition holds and delete the
  rest; drop the leading guidance comment; keep `<!-- guide-version: 1 -->` as the first line. Facts the profile
  doesn't give stay `TODO(setup): <question>`, as in the profile (and the answer goes into the profile, not only the
  guide). Plain words for people: no engine internals, no host paths, no agent port schemes or ids; ports a person
  uses themselves (their reserved QC ports) only as §Dev servers states them.
- **Already present (a re-run): drift detection.** Fill the template afresh in the scratchpad from the current
  profile and env, and compare everything above `## Local notes` with the committed file (ignore the
  `guide-version:` line). Because every guide fact comes from a profile line, an answer given on an earlier run
  renders the same and shows no drift. Text in the committed guide that no profile line produces is the human's:
  propose moving it into §Identity's `Human guide notes` (or under `## Local notes`), and keep it. Report each other
  difference as drifted, with the reason where it shows (a renamed label, a new §Project extras command, a changed base branch, a
  template rule the file lacks). Show the diff, apply on the human's yes, and when anything above `## Local notes`
  changes, add 1 to `guide-version` (that makes agents ask collaborators to re-read it once). Never touch
  `## Local notes` or what's under it, and never drop text the human added elsewhere without showing it in the diff.
- **README link:** if the product repo's `README.md` doesn't link the guide, offer one line (in its contributing
  section, else at the end), with `<guide path>` filled in: `Working on this repo with an agent? Read
  [<guide path>](<guide path>) first (general guide: https://claude.ai/artifact/VRfq3L15X4LTrgKwGHiCZM).`
  Add it only on the human's yes.
- **`.gitignore`:** make sure it ignores `.agents/local/` (per-clone agent state, such as `guide-ack`). Missing:
  append `.agents/local/`, optionally preceded by one comment line (`# per-clone agent state
  (project-dev-orchestration)`); create `.gitignore` if there is none. Never reorder or rewrite existing lines. If a
  rule already ignores all of `.agents/`, report that it would also hide the profile, and ask.

## 8. Deliver

1. **Branch.** If nothing in the repo files changed, skip to the summary. Otherwise put the changes on
   `chore/agent-workflow-setup`, created from `origin/<base>` **without tracking it** (a branch that tracks
   `origin/<base>` makes a bare `git push` or `git pull` target the default branch):
   - bare-root layout: a new worktree named `agent-workflow-setup` (the worktree name for issue-less setup work;
     use §Layout's case style, e.g. `agentWorkflowSetup` for camelCase):
     refresh `origin/<base>` (detection's "Fresh origin/<base>" recipe), then
     `git worktree add --no-track -b chore/agent-workflow-setup <bare-root>/agent-workflow-setup origin/<base>`;
   - plain clone: `git switch --no-track -c chore/agent-workflow-setup origin/<base>` when the working tree is
     clean; when it isn't, use a separate worktree (`git worktree add --no-track -b chore/agent-workflow-setup
     ../<repo>-worktrees/agent-workflow-setup origin/<base>`, the engine's default worktree parent for a plain clone) and leave the human's checkout alone;
   - the branch or its PR already exists (a re-run): reuse it and add a commit; never open a second PR.
2. **Changeset / CI rules.** Apply the convention step 1 found to this PR, so it doesn't fail the repo's checks:
   - every changed path is exempt (docs-only, if the exempt list covers `AGENTS.md`, `CLAUDE.md`, `.agents/`, the
     guide and `.gitignore`): nothing to add;
   - otherwise, if the repo has a skip label and the change has no user-visible effect, apply that label to the PR
     (it is the documented route; say so in the body);
   - otherwise add the entry the convention asks for (a changeset file, a CHANGELOG line) in the repo's own format,
     as an internal or non-user-facing change if the format has such a type.
   Check the PR's checks after opening it (`gh pr checks <n>`) and report the result.
3. **Commit** the profile, `AGENTS.md`, the human guide, `.gitignore`, and (if changed) `CLAUDE.md`, `README.md`
   and the changeset, with the attribution line your tool or session prescribes, if any. Push the branch with
   `git push -u origin chore/agent-workflow-setup` (as `pdo with-gh-user --user <GH_USER> git push …` when a
   `GH_USER` is set; never the default branch), and open the PR against `<base>`:
   `gh pr create -R <org>/<repo> --base <base> --head chore/agent-workflow-setup`. The body has these sections:
   - **Adds:** each file with one line on what it is; name the human guide's path and the docs dir chosen (and why),
     so reviewers read it; what was detected and from where.
   - **Docs/config only:** a statement that the PR changes no product code or behaviour (or what it does change),
     that the profile takes effect for agents once merged (skills read the default branch's copy), and the LF
     conversion of any moved CRLF content.
   - **Label check:** present, created, missing (with commands for a maintainer), case differences, and the repo's
     own extra labels (listed, not judged).
   - **CI/changeset handling:** the convention found and what this PR did about it (exempt, skip label, or entry).
   - **Open questions:** every `TODO(setup)` left, every verification-pass mismatch, every draft-versus-template
     conflict, and anything else waiting on the human.
4. **Summary** to the human:
   - **Created:** files (with the PR link), labels, the env file and its path, the board.
   - **Present / unchanged:** what was already right.
   - **Drifted:** what was fixed on their yes, and what they chose to keep.
   - **Skipped:** declined items, labels that need a maintainer, `TODO(setup)` questions still open.
   - **Next steps:** merge the PR; point collaborators at the human guide, which links the general guide
     (https://claude.ai/artifact/VRfq3L15X4LTrgKwGHiCZM) for installing the plugin; in repo+team, install any
     missing requirements the engine install reported, write any hooks the project needs, then start the team: open
     a herdr session named CEO (`claude -n CEO`) and run `/ceo fire up <name>` (or
     `pdo team-up --project <name>`).
