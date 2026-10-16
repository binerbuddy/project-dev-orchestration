# Labels, routes and the board

The names below are the engine defaults. A project's env may rename four of them: `CWT_STATUS` (the queue status), `P_LABELS` (the P-levels, best first), `LABEL_QC_READY` and `LABEL_QC_DONE`
(`pdo project-env <KEY>` prints the value in use). Its `.agents/project-profile.md` and `AGENTS.md`
say which names it uses; theirs win over this table.

## Priority (P-levels)

| Label | Meaning |
|---|---|
| `P1-urgent` | Data loss, a security hole being exploited, production down. |
| `P2-high` | Security flaws, wrong computed or business-logic results, things users need soon. |
| `P3-medium` | Real but tolerable bugs; normal features. |
| `P4-low` | Polish, clean-up, ideas. |
| (none) | "P-": unprioritised; sorts after P4. |

Security issues and logic bugs lean one level higher than their cosmetic twins. A PR carries the best
P-label of the issues it closes and is **never downgraded**.

People speak only P-levels and CWT (below), never "tiers".

## Routes (which lifecycle a command agent runs)

| Label | Lifecycle skill | When |
|---|---|---|
| `route:small` | `project-small-feature-or-bug-fix` | A single Bug/Task/Feature that fits one context window, no design questions. |
| `route:design` | `project-feature-design` | Needs a design doc: Epics, open UX or architecture choices. |
| `route:build` | `project-feature-build` | An Epic whose design doc is READY. |

A project can map routes to other skills (`ROUTE_SKILL` in its env). An agent that finds its route is
wrong (a "small" fix that needs a migration or a design decision) stops and asks to re-route.

## Other labels

| Label | Meaning |
|---|---|
| `needs-triage` | Not yet reviewed by a human; the queue skips it. Every new issue gets it unless a human set the priority. |
| `Security` | Authn/authz, injection, secrets, exposure, unsafe input. Ranks first within its P-level. |
| `needs-design` | Needs a design doc before work. |
| `small-win` | Cheap, worthwhile. |
| `client-requested` | A client or customer asked for it; carried onto PRs. |
| `on-hold` | Parked by a human; never started. |
| `epic-phase` | A phase of an epic; worked only by the epic's build agent, never dispatched alone. |
| `ready for QC` | The PR is ready for human QC (and has its QC checklist). |
| `QC complete - ready to review` | QC passed; awaiting code review and a manual merge. |
| `awaiting-ux-gate` | The agent waits for a human's prototype sign-off. |
| `likely-fixed` | The agent thinks main already does this; a human confirms and closes. |
| `blocked-by-pr` | The PR can't merge until another PR lands. |
| `orchestrator-system` | Work on the orchestration system itself, for its System Manager. |
| `managed-by:<slug>` | Claimed: agents of that manager are working it (the label's description names the manager). Set by `pdo claim`, removed when the agent finishes. Not yours: don't work it; ask that manager. |

## The board

Issues live on an org (or user) GitHub Project. Its **Status** field:

| Status | Owner | Meaning |
|---|---|---|
| Backlog | humans, intake | Default for new issues. |
| Scheduled | humans | Parked until its Due date. |
| Todo | humans | Planned. |
| **Claude Work This** (CWT) | humans | The orchestrator's queue: put an issue here to have it worked. |
| In Progress | orchestrator | Claimed by a command agent. |
| In Review | orchestrator | PR open. |
| Done | orchestrator | Closed. |

Humans put issues on CWT (or ask the System Manager to); agents never move cards, except that a /project-feature-build run moves its own epic and phase cards (the orchestrator never dispatches phases). In Progress, In
Review and Done are orchestrator-owned: leave them alone.

## The queue and the spawn floor

Deterministic, no model judgement:
1. CWT first, then P1 → P4; within a level Security, then Bugs, then items of an epic already in
   progress, then oldest.
2. A blocker runs at the P-level of what it holds up ("a P4 blocking a P2 runs as P2").
3. Excluded: assigned issues (an assignee is a human lock), another manager's `managed-by:` label
   (this manager's own label means already in progress), `needs-triage`, `on-hold`, `likely-fixed`,
   `epic-phase`, issues GitHub shows as "blocked by" an open issue, issues already in flight, Epics
   without a `route:*` label, `orchestrator-system`, and repos another manager owns.
4. CWT, P1, P2 and P3 start automatically; P4 and P- wait for an explicit "drain".
5. **Spawn floor:** a maintainer can set the lowest P-level that may start (`pdo floor P2`).
   Nothing below it starts, CWT included.
6. **Urgent bypass:** P1-urgent **and** on CWT starts even when every slot is full. Neither alone does.

At most a few command agents are active at once (default 3); agents parked at QC or a UX gate don't
count.
