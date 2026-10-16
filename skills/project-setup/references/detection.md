# Detection recipes

Read-only. Record every fact with the file (or command) it came from, so the profile and the report can cite it.
When two sources disagree, record both and ask; don't pick one.

## Repo and layout

```bash
top="$(git rev-parse --show-toplevel 2>/dev/null)"                       # empty when run in a bare root itself
common="$(git rev-parse --path-format=absolute --git-common-dir)"
git -C "$common" rev-parse --is-bare-repository                          # true => bare-root layout
git -C "$common" worktree list --porcelain                               # existing worktrees and their branches
git remote get-url origin                                                # -> <org>/<repo>
git -C "$common" config --get remote.origin.fetch                        # a bare clone needs this to fetch branches
```

- **Bare-root layout:** the common dir is a bare repo (`core.bare=true`) and worktrees sit inside or beside it. The
  engine's `REPO_ROOT` is the bare root (the common dir). In a plain clone the common dir is `<top>/.git` and
  `REPO_ROOT` is `<top>`.
- **Worktree naming:** infer from the existing worktree dir names next to their branch names (kebab-case, camelCase,
  a suffix for design worktrees). With one or no worktrees there's nothing to infer: ask.
- Parse `<org>/<repo>` from `git@github.com:<org>/<repo>.git` or `https://github.com/<org>/<repo>(.git)`. Origin
  not on GitHub: stop; the system needs GitHub issues and PRs.

```bash
gh repo view <org>/<repo> --json defaultBranchRef,owner,isPrivate,hasIssuesEnabled,viewerPermission
gh api users/<org> --jq .type                                            # Organization or User
gh api orgs/<org>/issue-types --jq '.[].name' 2>/dev/null                # org issue types (orgs only)
gh label list -R <org>/<repo> --limit 500 --json name,color,description
```

`viewerPermission` below WRITE means labels can't be created and a PR comes from a fork: say so up front.

## Stack and commands

Prefer what CI runs (`.github/workflows/*.yml`, other CI configs): that is the authoritative set. Then the manifests.
Record only commands that are actually defined; if the repo has no typecheck or test command, write "none defined",
don't make one up.

| Evidence | Commands to record (only those that exist) |
|---|---|
| `package.json` `scripts` (each package in a workspace) | the `build`, `typecheck`/`tsc`, `lint`, `test`, `e2e` scripts as `npm run <name>` (or the lockfile's manager: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb` → bun) |
| `*.sln`, `*.csproj` | `dotnet build <sln>`; `dotnet test <sln>` when a project sets `IsTestProject` or references a test SDK |
| `pyproject.toml`, `setup.cfg`, `tox.ini`, `noxfile.py` | configured tools only: `[tool.pytest]` → `pytest`, `[tool.mypy]` → `mypy`, `[tool.ruff]` → `ruff check`; tox/nox envs by name |
| `Cargo.toml` | `cargo build`, `cargo test`, `cargo clippy` (if CI runs it) |
| `go.mod` | `go build ./...`, `go vet ./...`, `go test ./...` |
| `Makefile`, `justfile`, `Taskfile.yml` | targets named build / check / lint / test (`grep -E '^[A-Za-z0-9_.-]+:' Makefile`) |
| `pom.xml`, `build.gradle*` | `mvn -q verify` / `./gradlew build` (wrapper present) |

Monorepos: one line per part, with the directory it runs in. Note env vars a build visibly needs (from CI `env:`
blocks or `.env.example`), not their values. Never run a build or test suite during detection unless the human asks:
it can be slow and have side effects.

## Dev servers and ports ("where obvious")

| Evidence | What it tells you |
|---|---|
| `package.json` `start` / `dev` / `serve` scripts, `--port` flags | web dev server command and port |
| `angular.json` (`serve.options.port`), `vite.config.*` (`server.port`), `next.config.*` | default web port |
| `Properties/launchSettings.json` `applicationUrl` | .NET API ports |
| `docker-compose*.yml` `ports:` | databases and services, and their host ports |
| `Procfile`, `.env.example`, `README` run instructions | start commands and the env they need |

Record the command, the port, and the file. Which ports are reserved for the human's QC servers, and the port scheme
agents use instead, can't be detected: ask.

## Existing agent and docs files

| Path | Check |
|---|---|
| `AGENTS.md` | exists? has `## How work flows here`? any `<placeholder>` left in it? |
| `CLAUDE.md` | exists? only `@AGENTS.md` (plus Claude-only notes), or real content to move? CRLF line endings (`grep -c $'\r' CLAUDE.md`)? |
| `.agents/project-profile.md` | in the worktree, and on the default branch (`git show origin/<base>:.agents/project-profile.md`) |
| `.changeset/` (`config.json`), `CHANGELOG.md`, `CHANGES.md`, release-please / semantic-release config | the changelog convention |
| `docs/`, `doc/`, `documentation/`, `docs/design/`, `adr/`, a docs site config (`mkdocs.yml`, `docusaurus.config.*`) | design-doc, developer-doc and user-guide locations; which hold human-facing docs; `git check-ignore -v <dir>/agent-workflow.md` for each candidate guide dir |
| `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md` | conventions the PR body and issues must follow |

## UI or headless

A web or desktop front end (an `index.html`, a front-end framework in `package.json` dependencies, `angular.json`,
`vite.config.*`, a desktop app manifest) means QC is steps in the running app. None of these, and the repo is an
engine, library, CLI or API: QC is cases named by their inputs and expected outputs (a fixture input file, a request
to replay, the command that runs it). Record which, and ask when unsure.

## Changelog and PR checks

```bash
ls .changeset/ CHANGELOG.md CHANGES.md 2>/dev/null
grep -lE 'changeset|changelog' .github/workflows/*.y*ml 2>/dev/null       # a workflow that enforces it
```

In each matching workflow, find: whether it fails a PR without an entry; the label that skips it (a
`contains(github.event.pull_request.labels.*.name, '<label>')` condition, or a label named in its error message);
and the paths it exempts (`paths-ignore:`, or a pattern list in the script). Record all three, with the file, in
§Changelog. Note which of the setup PR's paths (`AGENTS.md`, `CLAUDE.md`, `.agents/`, the guide, `.gitignore`) the
exempt list doesn't cover: step 8 needs it.

## Engine registration (full mode)

```bash
command -v pdo                                    # engine on PATH
pdo project-env 2>&1                              # from the repo: resolves the project whose REPO_ROOT holds it
printf '%s\n' "${PDO_CONFIG_DIRS:-${XDG_CONFIG_HOME:-$HOME/.config}/project-dev-orchestration}" | tr : '\n'
ls <config dir>/projects/*.env                    # every registered project, per config dir
gh auth status                                    # the gh logins on this machine (for GH_USER)
```

When `pdo project-env` resolves a project from the repo's directory, the repo is already registered: edit that env
file (gaps only), never create a second one. If that project's `PRIMARY_REPO` (`pdo project-env PRIMARY_REPO`) is
another repo, this is a secondary repo of a multi-repo project: the board is shared (`pdo project-env --board`),
and its fixture format may need a `FIXTURE_EXT_BY_REPO` entry.
