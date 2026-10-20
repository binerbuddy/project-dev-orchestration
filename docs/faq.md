# FAQ

**Do I need the orchestrator or the engine to contribute?**
No. Install the plugin for your agent tool and follow [For collaborators](collaborators.md). The engine is for
whoever runs the team.

**Which agent tools work?**
Claude Code, Codex and Grok Build all load the skills. The engine launches Claude Code today.

**My agent keeps asking whether I've read the guide.**
It should ask once per clone. When you say yes it writes `.agents/local/guide-ack`; it asks again only if the repo's
`docs/agent-workflow.md` gets a new `guide-version`. If it asks every time, check that the file exists and that
`.agents/local/` isn't being cleaned away. Agents started by an orchestrator never ask.

**Can my agent merge my PR once QC passes?**
No. Humans merge, always.

**Where does QC test data go?**
On the repo's never-merged `qc-fixtures` branch, linked from the PR's QC checklist. Never on the PR branch: it would
merge with the PR.

**How do I give QC feedback or pass QC from the browser?**
Feedback: a PR review with **Request changes** (on a PR you opened yourself GitHub won't allow that; tell the agent
in its session). Pass: add the `Ready for Merge` label. Anything beyond that, such as a hosted preview
or comment commands, is specific to the repo; its human guide lists them.

**My agent found a bug unrelated to its task. Should it fix it?**
No. It files it (a `needs-triage` issue, or a report to the intake agent where there is one) and stays on task.

**Can my agent open a PR or issue in another repo?**
Only after you say yes. Reading other repos is fine; any write there waits for your OK.

**Who sets priorities and the route?**
Maintainers. You file with `needs-triage`; they add the P-label and route, or put it in the board's queue column.

**Why does my agent refuse `gh auth switch`?**
The active GitHub account is machine-wide, and switching it breaks other sessions. It pins an account per command
instead.

**Where do I ask something this site doesn't answer?**
Where your repo's `docs/agent-workflow.md` says, or ask your agent to load `/project-how-it-works`.
