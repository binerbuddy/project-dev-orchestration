---
name: project-status
description: Read-only snapshot of a project's GitHub work tracking (board, open issues, epics, PRs, recently closed), most urgent first. Never creates, edits, labels or closes anything. Use when asked "where are things?", for a project status, backlog overview, epic progress, or what's in flight; optionally narrowed by repo, epic, label or keyword.
argument-hint: "[repo | epic #n / Repo#n | label | keyword]"
---

# Project status (read-only snapshot)

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH).

Answer "where are things?" across the project's work tracking. **Read-only: never create, edit,
label or close anything.**

**Project facts.** From the project env, read with `pdo project-env [--project <p>] <KEY>`: `ORG`, `PROJECT_NUMBER` (the board), the repos (keys of
`REPO_ROOT`), `PRIMARY_REPO` and `GH_USER`. With no engine install, take the repos and board from the
profile's `## Identity` (`.agents/project-profile.md`). The profile's `## Identity` may also name a
legacy tracker; mention legacy work only if asked.

**gh identity.** If `GH_USER` is set, run gh through `pdo with-gh-user gh …`. Never `gh auth switch`.

The argument (optional) narrows the report: a repo name, an epic (`#212`, `Repo#140`), a label
(`P2-high`, `small-win`, an area label), or a keyword. Empty = full snapshot.

**Conventions.** Type = org issue type (Epic/Feature/Bug/Task). Priority = `P1-urgent` … `P4-low`.
`needs-triage` = not yet reviewed. Status (Backlog / Scheduled / Todo / Claude Work This / In Progress
/ In Review / Done) lives on the board only. Scheduled = parked until its Due date: exclude it from
queues and list it separately as "Upcoming (due ≤14d)". Label and status names are the engine
defaults; a project's env may rename the queue status and the P-labels (`pdo project-env CWT_STATUS`,
`pdo project-env P_LABELS`).

## Gather (few calls, then filter locally)

1. Board, once:
   `gh project item-list <PROJECT_NUMBER> --owner <ORG> --format json --limit 1000 > <scratchpad>/board.json`.
   Items carry `status`, `labels`, `repository`, `content.number/title/type`. `item-list` truncates
   silently: if the count equals the limit, raise it and refetch.
2. Open issues with timestamps and types, once per repo:
   `gh issue list -R <ORG>/<repo> --state open --limit 500 --json number,title,labels,updatedAt,url`,
   plus `gh api "repos/<ORG>/<repo>/issues?state=open&per_page=100" --paginate --jq
   '.[]|select(.pull_request|not)|{number,type:.type.name,sub:.sub_issues_summary,updated_at}'` for
   type and sub-issue progress.
3. Recently closed: `gh search issues --owner <ORG> --closed ">=<today-7d>" --json
   repository,number,title,closedAt --limit 100`.
4. Open PRs touching tracked issues: `gh pr list -R <ORG>/<repo> --state open --json
   number,title,isDraft,labels,closingIssuesReferences`, for the repos that take code PRs (the
   profile's `## Identity` may say which; default all).

Filter the saved JSON with `jq` or `python3`; don't fetch issues one by one unless drilling into a
single epic or item.

With a narrowing argument: an epic → its body summary, every sub-issue with status and priority,
blockers (`gh api repos/<ORG>/<repo>/issues/<n>/dependencies/blocked_by`), linked PRs. Otherwise filter
the same data by repo, label or keyword (title match) and keep the section layout.

## Report (most urgent first, ≤60 lines)

1. **Needs attention:** P1 items; In Progress with no update in 14+ days (stale); blocked items whose
   blocker closed (unblocked but not moved).
2. **Triage queue:** count of `needs-triage` per repo, oldest 5 by title.
3. **In flight:** Claude Work This (queued for the orchestrator) / In Progress / In Review, with
   `Repo#n`, title, P label, linked PR (draft?).
4. **P2-high backlog:** open P2 items not in flight.
5. **Upcoming (due ≤14d):** Scheduled items, when any.
6. **Epics:** each open Epic `Repo#n title — done/total (pct%)`, status, next unstarted sub-issue.
7. **Closed in the last 7 days:** `Repo#n title`.
8. **Counts:** open by repo × type, and by P label (one compact table).

Format: `Repo#n` refs (bare `#n` for `PRIMARY_REPO`), one line per item, no bodies. End with at most
two suggestions (e.g. "5 untriaged since last month; run a triage pass?"). No other commentary.
