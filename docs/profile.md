# The project profile

Each product repo describes itself to the skills in **`.agents/project-profile.md`**, committed in the repo.
The template, with every section documented, is [`templates/project-profile.md`](https://github.com/binerbuddy/project-dev-orchestration/blob/main/templates/project-profile.md):
copy it, fill it in, and commit it.

## Where skills look

1. `.agents/project-profile.md` at the worktree's top level (`git rev-parse --show-toplevel`).
2. For a bare-root layout (worktrees as subdirectories of a bare clone), the default branch's copy:
   `git show origin/HEAD:.agents/project-profile.md`, run against the bare root
   (`git rev-parse --git-common-dir`).
3. No profile: the skill detects the obvious build tooling (package.json scripts, `*.sln`, pyproject,
   Cargo, go.mod), proceeds with that, and offers to write a profile from the template.

## Sections

Skills cite these `##` sections by name, so keep the headings exactly:

| Section | What goes there |
|---|---|
| `Identity` | related repos, the GitHub org, and the project board (a repo sharing another repo's board points at `pdo project-env --board` instead of copying ids); `Manager`, `Where to ask` and `Human guide notes`, which the human guide is rendered from |
| `Layout` | bare root or plain clone, the worktree convention, the base branch |
| `Build & checks` | the authoritative compile and typecheck commands, and known-noise errors |
| `Tests` | how to run unit and end-to-end tests |
| `Dev servers` | how to run them, the ports (including the human's reserved QC ports and the per-issue ports agents use), database rules, and a "Human run" line for people |
| `QC data` | the fixture format, how to export one, and that it's published with `pdo qc-fixture-push`; for a repo with no UI, what a QC case is (inputs with expected outputs) |
| `QC preview` | an optional hosted preview service: its PR-comment triggers and login |
| `Changelog` | changesets or another convention, and the CI check that enforces it (skip label, exempt paths) |
| `Review roles` | extra reviewer roles, e.g. a UI designer for your component library |
| `Docs` | the user guide and design-doc locations |
| `Conventions` | anything else agents must follow |
| `Do not` | hard prohibitions |

The profile is project knowledge for agents. Engine settings (repo roots, the board, hooks) live in the
engine's project env instead; see [design.md](design.md#configuration).

Alongside the profile, the repo's `AGENTS.md` gets a short "How work flows here" section from
[`templates/AGENTS-workflow-section.md`](https://github.com/binerbuddy/project-dev-orchestration/blob/main/templates/AGENTS-workflow-section.md), and `CLAUDE.md` becomes
`@AGENTS.md` plus any Claude-only notes.

`/project-setup` also writes the repo's human guide, `docs/agent-workflow.md` (or in the repo's human-docs dir when
that is another one, never a gitignored one; §Docs records the path), from
[`templates/agent-workflow-guide.md`](https://github.com/binerbuddy/project-dev-orchestration/blob/main/templates/agent-workflow-guide.md),
filled from the profile; it regenerates it on re-runs when the profile changes, and bumps its `guide-version`.
