# For collaborators

You can work on a repo that uses project-dev-orchestration with your own agent (Claude Code, Codex or
Grok Build) on your own machine. You don't need the orchestrator, herdr, or any of the engine scripts.

## Setup

1. Install the skills for your tool:
   - Claude Code: `/plugin marketplace add binerbuddy/project-dev-orchestration`, then
     `/plugin install project-dev-orchestration@project-dev-orchestration`.
   - Codex: `codex plugin marketplace add binerbuddy/project-dev-orchestration`, then
     `codex plugin add project-dev-orchestration@project-dev-orchestration`.
   - Grok Build: `grok plugin install binerbuddy/project-dev-orchestration`.
2. Clone the product repo and read its `AGENTS.md`, especially "How work flows here".
3. Ask your agent to load the **`project-how-it-works`** skill. It explains the pipeline, the labels, and
   which rules apply when no orchestrator is running.

The repo's `.agents/project-profile.md` tells your agent how to build, test, run the dev servers and
prepare QC data.

## What changes without the engine

- **Bugs and ideas you notice:** open an issue with the `needs-triage` label and no P-label, using the
  intake skill's template, and say who reported it. Don't fix out-of-scope things in passing.
- **Picking work:** take issues a maintainer assigns you, or ask. An issue assigned to someone is
  theirs; the orchestrator won't start it either.
- **Your PR:** follow the lifecycle skill for the route (`project-small-feature-or-bug-fix`, or design →
  build for big features), post the QC checklist, and label the PR `ready for QC`. Never merge.
- **QC feedback** arrives as PR comments (`QC: …`). Answer on the PR.
- **gh identity:** never `gh auth switch` on a shared machine; pin with
  `GH_TOKEN=$(gh auth token -u <you>) gh …`.
