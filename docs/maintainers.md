# For maintainers

You own a repo that uses the system, or you run its agent team. This page is the overview; the day-to-day manual is
the [user guide](user-guide.md).

## Set a repo up: `/project-setup`

Open your agent in the repo and run `/project-setup`. In **full** mode (the default when the engine's `pdo` is on
PATH) it also registers the repo with the engine; `/project-setup collaborator` touches the repo only. It:

- detects the layout, origin, default branch and the build, typecheck and test commands;
- drafts `.agents/project-profile.md`, the facts every agent reads (build commands, dev servers and ports, QC data
  and preview, changelog, conventions, prohibitions);
- adds the "How work flows here" section to `AGENTS.md`;
- writes the human guide, `docs/agent-workflow.md`, for your collaborators: which labels and routes to use, how to
  request work, QC comments and the preview login, fixtures, the changelog rule, who the manager is and where to
  ask; and offers a link to it from your README;
- adds `.agents/local/` (per-clone agent state) to `.gitignore`;
- creates the GitHub labels the pipeline uses (never deletes or renames one);
- in full mode, writes the engine's `projects/<name>.env` and optionally wires up a GitHub Project board;
- asks only what it can't detect, and opens one PR on `chore/agent-workflow-setup`.

**Re-run it whenever things change.** It reports what is present, what has drifted and what is missing, fills only
the gaps, and applies a fix to anything drifted only on your yes. When the profile or env changes what the human
guide says, it regenerates the guide and bumps its `guide-version`; your collaborators' agents then ask them, once,
to read the new version.

The profile's sections are described in [profile.md](profile.md).

## Run a team

Install the engine (only on the machine that runs the team): clone the repository, then

```
bin/install --bin                 # puts `pdo` on PATH
pdo team-up --project <name>      # intake, QC and orchestrator agents, then a status report
```

Sessions you start yourself (not dispatched by the engine) find it through `pdo` on PATH; on a machine where it isn't,
the repo's `AGENTS.md` names the engine checkout (`/project-setup` fills that in). To run one git or gh command as
the project's GitHub login without switching the machine's account: `pdo with-gh-user --user <login> git push …`
(it pins gh's token and injects gh's credential helper for git over HTTPS).

It needs bash 4+, python 3.8+, git 2.31+, jq, the GitHub CLI and [herdr](https://herdr.dev). Then you talk to one
session, the **System Manager** (`/project-system-manager`), which starts and checks everything else:

| Agent | Does |
|---|---|
| Orchestrator | Ranks the board (queue column first, then P1 to P4), starts a command agent per issue, watches them, hibernates idle ones, closes them out. Never edits code or merges. |
| Command agents | One per issue, in its own worktree, from start to a PR labelled `ready for QC`. They ask you their questions directly. |
| QC agent | Serves a PR on your local QC ports and relays your feedback to the PR's agent. |
| Intake | Turns bug reports and ideas, yours and every agent's, into proper issues. |

Things to say to the System Manager: `status`, `fire up the dev team`, `what's waiting on me`, `work #123 now`,
`pause new work`, `QC PR #264`. The full list, the labels, the spawn floor and the engine commands are in the
[user guide](user-guide.md); how the engine works is in [design.md](design.md).

You still merge every PR by hand.

## Several projects: the portfolio manager

When one machine runs teams for several projects, the **portfolio manager** (`/project-portfolio-manager`) oversees
all the project managers. Its skill describes what it watches and when to use it.

## Your collaborators

Point them at [For collaborators](collaborators.md) and your repo's `docs/agent-workflow.md`. Fill in who the manager
is and where to ask when `/project-setup` asks you; that's the part of the guide they'll need most. Their agents
need only the plugin; they never run the engine.
