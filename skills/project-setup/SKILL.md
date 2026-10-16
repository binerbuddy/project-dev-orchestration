---
name: project-setup
description: Set up, initialise or onboard the current git repo for project-dev-orchestration (the orchestration / agent workflow) - detect the layout, origin, stack and its build/typecheck/test commands, draft .agents/project-profile.md, add the "How work flows here" section to AGENTS.md, create the missing GitHub labels, record the QC fixture format, generate the human guide docs/agent-workflow.md and gitignore .agents/local/, and in full mode register the repo with the engine (projects/<name>.env, optional project board), then deliver the repo files as a PR on chore/agent-workflow-setup. Idempotent - a re-run reports what is present and what has drifted, and only fills gaps. Use when asked to set up, initialise, onboard or bootstrap a repo for the orchestration or agent workflow, or to check or repair an existing setup.
argument-hint: "[collaborator|full]"
---

# Project setup

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path. Paths written `$PDO_STATE_DIR`, `$PDO_INBOX` or `$PDO_HOME` (the engine checkout) mean the values `pdo project-env <KEY>` prints; agent sessions don't have them set.

Initialise the **current working repo** to use project-dev-orchestration: the repo files every agent reads (the
profile and `AGENTS.md`), the guide its humans read (`docs/agent-workflow.md`), the GitHub labels the pipeline relies on, and, in full mode, the engine's registration of
the repo.

**Idempotent.** Every step first checks what is already there. A re-run prints what is present, what has drifted
(present but out of date, or disagreeing with what detection finds), and what is missing, and only fills gaps.
Drifted items get a proposed fix that is applied only on the human's yes. Nothing already present is overwritten,
renamed or deleted without it.

**Rules for the whole run.**
- **Don't invent anything.** Every fact in the profile, the workflow section and the env file comes from detection
  (with its source) or from the human. Anything neither gives stays marked `TODO(setup): <question>`, so the next
  run finds it.
- **This repo only.** Reading related repos for context is fine. Writing to any other repo (files, branches, PRs,
  issues, comments, labels) needs the human's yes first; offer to run `/project-setup` there separately instead.
- **Never push to the default branch.** Repo-file changes go on `chore/agent-workflow-setup` and a PR.
- **Never delete or rename a GitHub label**, and never use `gh label create --force` on one that exists.
- **Show before you move.** Moving the human's existing `CLAUDE.md` (or any other) content needs the diff shown and
  an explicit yes.
- **Ask in batches.** Collect the unknowns and ask once (Claude Code: `AskUserQuestion`, at most 4 questions per call,
  repeated as needed; Codex and Grok: one numbered list in chat). Every question can be answered "skip": the item
  stays `TODO(setup)`.
- **gh identity.** Never `gh auth switch`. Once a `GH_USER` is known (an existing project env, or the human's answer
  in step 6), run gh as `pdo with-gh-user gh …` or `GH_TOKEN=$(gh auth token -u <user>) gh …`.
- LF line endings in every file you write.

## 0. Mode

- `collaborator`: repo files and labels only. No engine, no env file, no board. For someone who works the repo with
  their own agent and no orchestrator.
- `full`: everything in collaborator mode, plus engine registration (step 6).
- No argument: `full` if `pdo` is on PATH (or the human points you at an engine checkout), else `collaborator`.
  Say which mode you picked and why in one line.

## 1. Detect (read-only)

Recipes for each item: `references/detection.md`. Find:

1. **Repo root and layout:** the worktree top level, the git common dir, and whether it is a **bare-root** layout
   (worktrees as subdirectories of a bare clone). This gives `REPO_ROOT` and the profile's §Layout.
2. **`<org>/<repo>`** from `origin`, the **default branch** (`gh repo view … --json defaultBranchRef`), whether the
   owner is an organization or a user (issue types and the board depend on it), the org's issue types, and your
   permission on the repo (below WRITE: no label creation, and the PR comes from a fork).
3. **Stack and the authoritative build, typecheck and test commands**, per part of the repo: CI workflows first, then
   `package.json` scripts, `*.sln`/`*.csproj`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Makefile`. Record only
   commands that exist. Dev servers and their ports where obvious.
4. **Existing files:** `AGENTS.md` (and whether it already has `## How work flows here`), `CLAUDE.md`,
   `.agents/project-profile.md` (worktree and default branch), the human guide (`docs/agent-workflow.md`, or the
   profile §Docs location; its `guide-version:`), whether `.gitignore` covers `.agents/local/`, changesets or a CHANGELOG, docs dirs, issue and PR
   templates, and the repo's labels.
5. **Full mode:** whether the repo is already registered (`pdo project-env` run from the repo resolves a project),
   the config dirs, and the gh logins on the machine.

Print a short **detection report**: one line per item with its value, its source, and its state (present, missing,
drifted). On a re-run this report is the main output; the later steps act only on the missing and drifted lines.

## 2. Profile: `.agents/project-profile.md`

Start from this plugin's `templates/project-profile.md` (`../../templates/project-profile.md` from this skill's
directory). **Keep the template's `##` headings exactly** (`Identity`, `Layout`, `Build & checks`, `Tests`,
`Dev servers`, `QC data`, `QC preview`, `Changelog`, `Review roles`, `Docs`, `Conventions`, `Do not`); the lifecycle
skills cite them as `§<Section>`. Drop the template's guidance comment and the commented examples, and replace each
guidance paragraph with facts.

- Fill from detection: §Identity (org, primary repo, issue types or "none: user-owned repo"), §Layout (bare root or
  plain clone, worktree naming if it can be inferred, base branch, branch prefixes seen in `git branch -r`),
  §Build & checks and §Tests (the commands, each with the directory it runs in; "none defined" where there is none),
  §Dev servers (start commands and ports found, with their files), §Changelog (the convention found, with an example
  entry copied from the repo), §Docs (the dirs found).
- **List the unknowns and ask only for what detection can't give**, typically:
  - **§QC data:** what human QC runs against (seed data, what the top-level record is called in the UI), the
    fixture format and extension, how to export and import one, any size limit (see step 5);
  - **§QC preview:** is there a remote preview service (triggers, link pattern, login), or "None";
  - **§Review roles:** extra reviewer roles (a UI designer for the project's component library, a data reviewer for
    migrations), or none;
  - **§Identity related repos:** other repos agents may need to search or file against, and when each is in scope;
  - **§Identity board:** the project board, if any (full mode handles it in step 6; collaborator mode only records
    what the human says);
  - **§Dev servers:** the ports reserved for the human's QC servers and the port scheme agents use instead; the
    database rules;
  - **§Conventions** and **§Do not:** anything the human wants stated now (both may start short).
  - **For the human guide (step 7):** who the manager is (the person who runs the team, sets priorities and
    merges) and how to reach them, and where collaborators ask questions. Ask these in the same batch.
- Write answers in; unanswered items stay `TODO(setup): <question>` under their heading.
- **Profile already present:** don't rewrite it. Report missing or renamed headings, `TODO(setup)` markers, template
  text left in, and facts that disagree with detection (a base branch that changed, a build script that no longer
  exists, a different `<org>/<repo>`). Propose a fix for each and apply only what the human accepts.

## 3. `AGENTS.md`: the workflow section

Fill this plugin's `templates/AGENTS-workflow-section.md` (`../../templates/AGENTS-workflow-section.md`): drop its
leading comment, replace every `<placeholder>` (`<org>/<repo>`, `<project#>`, `<base>`) and use the project's label
names where its env renames them. `<guide path>` is where step 7 writes the human guide (default
`docs/agent-workflow.md`). With no board, replace the "on org Project `<project#>`" clause with "with no
project board (a maintainer dispatches agents by hand)". Leave `<engine checkout>` as written: a dispatch brief fills
it in.

- **No `AGENTS.md`:** create it with a one-line title and the section.
- **`AGENTS.md` without the section:** append it at the end, unchanged otherwise.
- **Section present:** compare it with a freshly filled template. Report placeholders left, wrong org/repo/base or
  label names, and rules the template has that the section lacks. Propose the edits; apply on yes. Never drop rules
  the human added.
- **`CLAUDE.md` with content** (anything beyond `@AGENTS.md` and Claude-only notes): offer to move the
  tool-neutral content into `AGENTS.md`, so Codex and Grok read it too, and leave `CLAUDE.md` as `@AGENTS.md` plus
  the Claude-only notes (slash commands, Claude Code hooks or settings, Claude-specific tool names). Build both new
  files in the scratchpad, **show the diff** (`git diff --no-index <old> <new>` for each file), and move only after
  the human's yes. If they decline, leave `CLAUDE.md` as it is and report it as skipped. `CLAUDE.md` absent: create it
  as `@AGENTS.md` only if the human uses Claude Code; it is harmless either way, so ask.

## 4. GitHub labels

Check every label the engine and skills rely on, then create the missing ones with `gh label create` (in this repo
only): `route:small`, `route:design`, `route:build`; the P-labels (`P_LABELS`, default `P1-urgent P2-high P3-medium
P4-low`); `LABEL_QC_READY` and `LABEL_QC_DONE` (default `ready for QC`, `QC complete - ready to review`); the
`CARRY_LABELS` (default `client-requested`); and `needs-triage`, `epic-phase`, `awaiting-ux-gate`, `likely-fixed`,
`blocked-by-pr`, `on-hold`, `needs-design`, `Security`, `small-win`, `orchestrator-system`. Colors, descriptions,
what relies on each, and the check-then-create loop: `references/labels.md`. On a user-owned repo (no issue types),
also create the type labels the human names, and record them in §Identity.

Never delete or rename a label. A case-only difference counts as present (GitHub names are case-insensitive); report
it. Without write access, list the missing labels and the commands for a maintainer, and carry on.

## 5. QC fixtures

Tell the human, in two or three lines:
- QC fixtures (test data a QC checklist links to) live on a never-merged `qc-fixtures` branch (`FIXTURE_BRANCH`).
  You don't create it now: `pdo qc-fixture-push <PR#> <file>` creates it the first time an agent publishes a fixture.
- It is per repo, and its format is this repo's own (an app export, a database dump, a JSON seed file).

Ask for the fixture format (what it is, its file extension, how to export one from the running app and import it,
any size limit) and record it in the profile's §QC data. In full mode also set `FIXTURE_EXT` (e.g. `.json`,
`.tar.gz`) in the env file; `qc-fixture-push` warns when a file doesn't match it. No fixtures (the seed data covers
QC): say so in §QC data and leave `FIXTURE_EXT` unset.

## 6. Full mode: engine registration

Skip this whole step in collaborator mode.

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
GH_USER="<login>"               # the gh login this project's agents use
# PROJECT_NUMBER=<n>            # only with a board (below)
# FIXTURE_EXT=".<ext>"          # from step 5
# QC_PORTS="<ports>"            # the human's reserved QC ports, from §Dev servers
```

- **`GH_USER`:** show the logins `gh auth status` lists and ask which one this project's agents use. Leave it unset
  only if the human says the active account is fine (the engine then pins nothing).
- Write renamed label keys (`CWT_STATUS`, `P_LABELS`, `LABEL_QC_READY`, `LABEL_QC_DONE`) only when the repo already
  uses other names; otherwise the defaults apply and the keys stay out.
- Hooks (`QC_HOOK`, `IDENTITY_HOOK`, `TEAM_UP_HOOK`) are project-specific code: list them as next steps, don't write
  them.

**Board (optional).** Offer to set up a GitHub Projects v2 board. The engine's board writes (`claim`,
`board-status`, `file-issue`) query an organization project, so the board must be org-owned; for a user-owned repo,
recommend skipping it.
- **Use an existing one:** `gh project list --owner <org> --format json`, then
  `gh project field-list <n> --owner <org> --format json` (needs the `read:project` scope; if gh lacks it, ask the
  human to run `gh auth refresh -s read:project,project` themselves). Record `PROJECT_NUMBER` in the env, and in
  §Identity the board's number, title, node id, the Status field id, and the option id of each Status column. The
  queue column (`CWT_STATUS`, default `Claude Work This`) must be one of the options; the others the engine uses are
  Backlog, In Progress, In Review and Done (see `../project-how-it-works/references/labels-and-board.md`). Report
  missing options and ask the human to add them in the board's UI: editing the field's options through the API
  replaces the whole list and changes every option id.
- **Create one:** only on the human's explicit yes. `gh project create --owner <org> --title "<title>"`, then
  `gh project link <n> --owner <org> --repo <org>/<repo>`, then have the human add the Status options above in the UI,
  and record it as for an existing board.
- **Skip:** no board means no queue. Leave `PROJECT_NUMBER` out; agents are dispatched by hand with
  `pdo spawn <repo> <n> --no-claim`, and §Identity says "Board: none".

**Verify.**
- `pdo project-env --project <name>`: every key resolves as intended (`REPO_ROOT`, `PRIMARY_REPO`, `GH_USER`, the
  `ROUTE_SKILL` entries); and `pdo project-env` with no `--project`, run from the repo, resolves to `<name>`.
- `pdo queue --project <name>`: a dry read (it ranks; it doesn't claim or move anything). With a board it lists the
  eligible issues; without one it stops with "has no PROJECT_NUMBER", which is expected.

## 7. The human guide: `docs/agent-workflow.md`

The page the repo's collaborating humans read: which labels and routes to use, how to request work, how QC works
here (comment triggers, preview login, fixtures), the changelog rule, who the manager is and where to ask. Agents
check it once per clone (`AGENTS.md`'s first-session rule), so it must exist and stay current.

- **Location:** `docs/agent-workflow.md`, unless the profile's §Docs names another docs dir; then
  `<that dir>/agent-workflow.md`. Record the path in §Docs ("Human guide: `<path>`") and use it for `AGENTS.md`'s
  `<guide path>`.
- **Fill** this plugin's `templates/agent-workflow-guide.md` (`../../templates/agent-workflow-guide.md`) from the
  profile as written in steps 2 and 5, and in full mode from the env file of step 6 (renamed labels, the queue
  column, the board). Each placeholder names its source. Keep the `[if …]` blocks whose condition holds and delete
  the rest; drop the leading guidance comment; keep `<!-- guide-version: 1 -->` as the first line. Facts neither the
  profile nor the human gives stay `TODO(setup): <question>`, as in the profile. Plain words for people: no engine
  internals, no host paths, no ports or ids beyond what the profile already states for humans.
- **Already present (a re-run): drift detection.** Fill the template afresh in the scratchpad from the current
  profile and env, and compare everything above `## Local notes` with the committed file (ignore the
  `guide-version:` line). Report each difference as drifted, with the reason where it shows (a renamed label, a new
  QC preview, a changed base branch, a template rule the file lacks). Show the diff, apply on the human's yes, and
  when anything above `## Local notes` changes, add 1 to `guide-version` (that makes agents ask collaborators to
  re-read it once). Never touch `## Local notes` or what's under it, and never drop text the human added elsewhere
  without showing it in the diff.
- **README link:** if the product repo's `README.md` doesn't link the guide, offer one line (in its contributing
  section, else at the end), with `<guide path>` filled in: `Working on this repo with an agent? Read
  [<guide path>](<guide path>) first (general guide: https://binerbuddy.github.io/project-dev-orchestration/).`
  Add it only on the human's yes.
- **`.gitignore`:** make sure it ignores `.agents/local/` (per-clone agent state, such as `guide-ack`). Missing:
  append the line `.agents/local/` (create `.gitignore` if there is none). Never reorder or rewrite existing lines.
  If a rule already ignores all of `.agents/`, report that it would also hide the profile, and ask.

## 8. Deliver

1. **Branch.** If nothing in the repo files changed, skip to the summary. Otherwise put the changes on
   `chore/agent-workflow-setup` from `origin/<base>`:
   - bare-root layout: a new worktree for the branch, named by §Layout's convention;
   - plain clone: `git switch -c chore/agent-workflow-setup origin/<base>` when the working tree is clean; when it
     isn't, use a separate worktree (`git worktree add`) and leave the human's checkout alone;
   - the branch or its PR already exists (a re-run): reuse it and add a commit; never open a second PR.
2. **Commit** the profile, `AGENTS.md`, the human guide, `.gitignore`, and (if changed) `CLAUDE.md` and
   `README.md`, with the attribution line your tool or session prescribes, if any. Push the branch (never the
   default branch) and open the PR against `<base>`:
   `gh pr create -R <org>/<repo> --base <base> --head chore/agent-workflow-setup`. Body: what was added (name the
   human guide's path, so reviewers read it), what was detected and from where, the `TODO(setup)` items left, and
   that the profile takes effect for agents once merged (skills read the default branch's copy).
3. **Summary** to the human:
   - **Created:** files (with the PR link), labels, the env file and its path, the board.
   - **Present / unchanged:** what was already right.
   - **Drifted:** what was fixed on their yes, and what they chose to keep.
   - **Skipped:** declined items, labels that need a maintainer, `TODO(setup)` questions still open.
   - **Next steps:** merge the PR; point collaborators at the human guide, which links the general guide
     (https://binerbuddy.github.io/project-dev-orchestration/) for installing the plugin; in full mode, write any
     hooks the project needs, then start the team with `pdo team-up --project <name>`.
