# Allocation advice (`pdo fleet`)

`pdo fleet` computes one recommendation per project. The rules are deterministic, so the same
snapshot always gives the same advice; the Portfolio Manager adds the judgement and the human's
consent.

## Inputs

**Per project (project env):**

| Key | Default | Meaning |
|---|---|---|
| `MANAGER` | `Orchestrator (<p>)` with a board, else empty | the workspace/session name of the project's manager; empty = the human |
| `REPO_MANAGER` | `()` | `declare -A`: self-managed repo → its manager's name |
| `PORTFOLIO_PRIORITY` | `3` | 1 = highest; orders the memory share-out and decides "only P1" |
| `RESOURCE_PROFILE` | `medium` | `light` / `medium` / `heavy` (table below) |
| `AGENT_MB` | from the profile | RAM one active agent of this project holds |
| `AGENT_USAGE_WEIGHT` | from the profile | its relative draw on the shared usage budget |
| `FLEET_ADVICE` | `ignore` | `honour`: `pdo queue` and `pdo watch` apply fresh advice |
| `MAX_ACTIVE`, `WEEKLY_CEILING`, `FIVE_HOUR_CEILING` | 3, 90, 90 | the project's own limits; advice never raises them |

| Profile | MB per active agent | Usage weight | Typical |
|---|---|---|---|
| `light` | 400 | 0.5 | docs, scripts, small libraries |
| `medium` | 900 | 1.0 | one app with a dev server |
| `heavy` | 1800 | 2.0 | several dev servers, databases, headless browsers |

**System:** available memory and swap (`/proc/meminfo`), disk free on the state dir and every repo
root, weekly and 5-hour usage (the `USAGE_CACHE` file), GitHub GraphQL and core points left for
each project's `GH_USER`, the number of herdr agents. Per project: active agents (live, not
parked) and the queue's startable count (`auto_spawn` items). Agents working in one of the project's
`SELF_MANAGED_REPOS` are not its active agents: their owner (`REPO_MANAGER`) runs them and the
project's queue and watch skip those repos, so `fleet` lists them on a separate "self-managed
(owner: …)" line and leaves them out of active/MAX and the advice. They still hold memory, which the
measured available memory already reflects; `est_agent_mb` includes them.

## Rules, in order

1. **Disk:** under `FLEET_DISK_HOLD_MB` (5120) free on the state dir or one of the project's repo
   roots → `hold`.
2. **Weekly usage** at or over the project's `WEEKLY_CEILING` → `hold` unless the project is
   `PORTFOLIO_PRIORITY` 1 (only P1 projects keep going; the engine's own ceiling still stops normal
   spawns). Within `FLEET_WEEKLY_MARGIN` × weight points (10 × weight) of the ceiling → `slow` for
   priority > 1.
3. **5-hour usage** at or over `FIVE_HOUR_CEILING` → `hold` for heavy priority > 1 projects, else
   `slow`.
4. **Memory floor:** under `FLEET_MEM_HOLD_MB` (3072) available → `hold` heavy projects; `slow`
   medium ones and any light one below priority 1.
5. **Swap:** `FLEET_SWAP_SLOW_PCT` (50) % or more used → `slow` non-light projects.
6. **GitHub:** fewer than `FLEET_GH_LOW` (600) GraphQL points left for the project's identity →
   `slow`.
7. **Memory share-out:** spare = available − `FLEET_MEM_RESERVE_MB` (2048). In priority order (ties:
   more startable work first), each project not on `hold` gets new agents while spare covers its
   `AGENT_MB`, up to its startable work and its `MAX_ACTIVE`. A project that gets fewer than it
   could use → `slow`.

`hold` sets `suggested_max_active` to the current active count (nothing new; nobody is stopped).
`slow` sets it to active + what fits. `go` leaves `MAX_ACTIVE`. Thresholds are environment
variables of the `fleet` run; tests stub the readings with `PDO_FLEET_MEM_AVAIL_MB`,
`PDO_FLEET_WEEKLY`, `PDO_FLEET_FIVE_HOUR`, `PDO_FLEET_DISK_FREE_MB` and `PDO_FLEET_SWAP_*`.

## What honouring does

`pdo fleet --write-advice` writes `fleet-advice.json` into each project's state dir. A project with
`FLEET_ADVICE=honour` and advice under 2 hours old:

- `pdo queue`: `hold` makes every row `auto_spawn: false` (`fleet_hold: true`) except the urgent
  bypass (P1 and on the queue status); `suggested_max_active` bounds `max_active`.
- `pdo watch`: `free_slots` uses that bound, so the orchestrator spawns fewer.

Both show the advice (age, reason) in their output either way; with `ignore` it is advisory only.
