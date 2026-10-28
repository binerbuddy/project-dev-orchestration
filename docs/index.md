# project-dev-orchestration

A way to run a GitHub repo with a team of coding agents (Claude Code, Codex or Grok Build) and a few humans. Humans
decide what gets built, check the result, and merge. Agents do the work in between: they take one issue each, build
it in their own branch, get it reviewed, and hand it back as a pull request with a QC checklist.

It ships as one plugin with two parts:

- **Skills**: step-by-step instructions any of the three agent tools can load, for every step from setting up a
  repo to a merged PR. A collaborator needs only these.
- **Engine**: optional scripts that run the team unattended. Whoever runs the team installs it; nobody else does.

## What this is

```
  issue ──► board ──► orchestrator ──► agent ──► PR ──► QC ──► merge
                                         ▲               │
                                         └── feedback ───┘
```

1. **Issue.** Someone files an issue with a route label (`route:small`, `route:design`, `route:build`) and a
   priority, or `needs-triage` until a maintainer sets one.
2. **Board.** It waits on the repo's GitHub Project board. A maintainer can move it to the queue column to have it
   worked now.
3. **Orchestrator.** A long-lived agent ranks the queue and starts a few agents at a time. It never edits code and
   never merges. Repos without one work the same way, with a maintainer handing out issues instead.
4. **Agent.** One per issue, in its own worktree. It checks whether the work is already done, plans, builds, gets a
   multi-agent review, and asks its human the questions only a human can answer.
5. **PR.** It opens a PR that closes the issue, labels it `ready for QC`, and posts one **QC Checklist** comment.
6. **QC.** A human works the checklist and answers in the agent's session or with a PR review requesting changes.
   Feedback goes back to the same agent, which fixes and re-labels. Where the team runs agent QC, a standing QC
   Agent tests the PR first and routes it to a human UX review (`QC complete - ready to review`) or straight to
   `Ready for Merge`. The human passes QC by adding the `Ready for Merge` label.
7. **Merge.** A human merges. Agents never do.

## Guides

- **[For collaborators](collaborators.md)**: your agent works on a repo that uses this system. What to install,
  which commands to run and when, labels and routes, QC comments, and the rules your agent follows.
- **[For maintainers](maintainers.md)**: setting a repo up with `/project-setup`, running a team, and the
  CEO.
- **[FAQ](faq.md)**.

Each repo that uses the system also has its own human guide, `docs/agent-workflow.md`, with its labels, QC setup
and who to ask. Read that one too.

## More

- [The illustrated pdo User Guide](user-guide/) and its [workflow deep dive](user-guide/workflow.html)
- [The day-to-day guide for whoever runs the team](user-guide.md)
- [How the engine works, and why](design.md)
- [The per-repo project profile](profile.md)
- [Lessons learned](lessons-learned.md)
- [The repository](https://github.com/binerbuddy/project-dev-orchestration)
