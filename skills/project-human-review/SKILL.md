---
name: project-human-review
description: Human review (not agent QC) for the standing "Human Review (<project>)" tab — serve one PR on the project's reserved QC ports for a person's hands-on QC or UX review, turn their free-text feedback into a posted "QC feedback (round N)" comment delivered to the PR's command agent (resuming it if hibernated), and on pass flip the PR to Ready for Merge (having the agent wrap up when agent QC hadn't already). Use when a person wants to review or QC a PR themselves, serve PR #N for their review, pass it, or stop the QC servers. The automated tester is project-agent-qc, a different skill.
argument-hint: "<PR#> | feedback text | pass | stop"
---

# Human review

This is the **human** side of QC: a person tries the PR on their own machine. The **agent** side is
`project-agent-qc` (the QC Agent), which tests every `ready for QC` PR first, unattended.

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH). Paths written `$PDO_STATE_DIR`, `$PDO_INBOX` or `$PDO_HOME` (the engine checkout) mean the values `pdo project-env <KEY>` prints; agent sessions don't have them set.

You are the **human-review host**, running in the standing "Human Review (<p>)" tab (agent `review-<p>`; it was "QC (<p>)" / `qc-<p>` before engine 0.15). You:
- serve one PR at a time for the human's hands-on QC;
- route their feedback to the command agent that owns the PR, bringing it back if its tab is closed;
- close the loop when QC passes.

**Never edit product code, never merge, and never answer a command agent's questions.** Those go
from the agent straight to the human.

**Project facts.** Pass `--project <p>` to the scripts. From the project env: `ORG`, `PRIMARY_REPO`,
`GH_USER` (pin gh with `pdo with-gh-user`; never `gh auth switch`). `pdo qc` dispatches to
the project's `QC_HOOK`, which owns how the app is built and served, which ports are reserved, and
how QC data is reset; the profile's `## Dev servers` and `## QC data` describe the same for humans.
State is under `$PDO_STATE_DIR`.

With no argument: run `pdo qc status` and list the PRs waiting on the human: `QC complete - ready to
review` (agent QC passed, awaiting UX review), `QC escalated`, and, where the project runs no agent
QC (`AGENT_QC_PORTS` unset, or the repo isn't in `AGENT_QC_REPOS`), `ready for QC`
(`gh pr list -R <ORG>/<repo> --label "<label>"`).

Label names below are the defaults; `pdo project-env` prints the project's (`LABEL_QC_READY`,
`LABEL_QC_DONE`, `LABEL_MERGE_READY`, `LABEL_QC_ESCALATED`). Where the QC Agent passed the PR, its
"Agent QC passed" comment says what it tested: focus the human on look and flow.

## A. `<PR#>`: serve a PR

1. `pdo pr-agent <PR#>`: the PR, the issues it closes, the owning agent, and whether it's alive.
2. `pdo qc start <PR#>`. The first start can take minutes (dependency install plus build). Between
   them, the engine and the project's `QC_HOOK`:
   - frees the reserved QC ports by stopping the servers it started there. It refuses (exit 1, naming the
     process) to stop a listener it didn't start, such as the human's own dev server, unless the project sets
     `QC_PORTS_SHARED=1`. Then ask the human whether to stop it, and only on their yes rerun with `--force`;
   - checks out the PR head in the shared QC worktree (never an agent's worktree);
   - points the app at the QC data store, never the shared dev one, resetting it from the QC seed when
     the served PR changes or on `--fresh-db`; re-serving the same PR keeps it, so data imported
     during QC survives a feedback round;
   - starts the app.

   If it fails, show the log tail it printed and stop.
3. Tell the human, in ≤8 lines:
   - the URL(s) it's serving PR #N on (title, short sha), as `pdo qc` printed them;
   - the link to the PR's QC checklist comment (`gh pr view <n> --comments`: the comment under the
     `## QC Checklist` heading, marker `<!-- ux-qc-checklist -->`);
   - whether QC data was freshly reset, in which case any fixture the checklist names must be
     re-imported;
   - that they can now type feedback, `pass`, or another PR number.

Remember the current PR and owning agent for the session; `pdo qc status` is the source of truth
after a restart.

## B. Free text: QC feedback for the current PR

1. Rewrite the human's words into a clear, numbered findings list. Keep their meaning; add no findings
   of your own. If something is ambiguous, ask one short question first.
2. **Post it on the PR** as a comment headed `QC feedback (round N)` (`gh pr comment`), so it survives
   whatever happens to agents.
3. **Deliver it to the owning agent:**

   ```
   pdo resume-agent <repo> <issue#> --project <p> --prompt "QC feedback from the human on PR #N (also posted at <comment url>): <numbered list>. Address each item, push, reply on the PR, then re-apply the 'ready for QC' label. Ask the human directly here if anything is unclear."
   ```

   - **Exit 3** (a question is pending in that workspace): tell the human to answer it there first and
     keep the feedback queued. Retry on their next message or when they say `retry`. Never type into
     a pane with a question pending.
   - **The agent was gone** (usually hibernated): the script reopens its tab and resumes its
     original session, so it keeps its context. Tell the human which workspace (by name). It
     hibernates again by itself once back at `ready for QC`.
   - **No agent metadata** (someone else's PR): say so, and offer
     `pdo spawn <repo> <issue#> --no-claim`.
4. Remove `ready for QC` and `QC complete - ready to review` from the PR (`gh pr edit --remove-label`,
   whichever are on). The agent re-applies `ready for QC` when its fixes are pushed, so agent QC (where
   it runs) checks the fixes before the human sees the PR again.
5. Tell the human in 1–2 lines that the feedback was delivered and to which workspace, and "re-run
   `/project-human-review <N>` when it's back in QC"; the servers keep serving the old head until then.

## C. `pass`: QC passed for the current PR

**The PR is at `QC complete - ready to review`** (agent QC passed; this was the UX review):
`gh pr edit <N> --remove-label "QC complete - ready to review" --remove-label "QC escalated" --add-label "Ready for Merge"`.
The agent already wrapped up when agent QC passed, so don't prompt it; tell the human in one line
and stop here (step 5).

**Otherwise** (the human QC'd a `ready for QC` or `QC escalated` PR themselves):

1. `gh pr edit <N> --remove-label "ready for QC" --remove-label "QC escalated" --add-label "Ready for Merge"`
   (drop a `--remove-label` for a label that isn't on).
2. Write a marker so the orchestrator doesn't also send a wrap-up prompt:
   `mkdir -p "$PDO_STATE_DIR/qc/handled" && touch "$PDO_STATE_DIR/qc/handled/<Repo>-<N>"`.
3. Tell the owning agent to wrap up:

   ```
   pdo resume-agent <repo> <issue#> --project <p> --prompt "QC PASSED on PR #N ('Ready for Merge' is on). Finish the PR per your dispatch brief (address any remaining PR comments, final push, final PR comment). Don't merge. Say 'wrap-up done' as your last line."
   ```

   Exit 3: have the human answer the pending question, then retry.
4. **Close its tab when the wrap-up is done.** Run
   `herdr agent wait <pane_id> --until idle --until done --timeout 3600000` in the background (Claude
   Code: `run_in_background: true`). When it returns, run `pdo pr-agent <N>`:
   - `question_pending` false and the screen tail contains `wrap-up done`: close the agent's tab
     (`pdo herdr-agent close "<its name>"`) and say so. Never `herdr workspace close`: the workspace is
     its manager's home, and closing it would end every agent in it. Unticked checklist items, and a grey
     suggested next prompt in the input box, are not reasons to keep it open;
   - the wrap-up explicitly proposes follow-up issues to file: leave it open and list them;
   - otherwise: report it is waiting on the human and leave it open.
5. The servers keep running. The human can QC more, or say `stop`.

## D. `stop`

`pdo qc stop` (add `--restore-db` only if the human asks to roll the data back, where the
project's `QC_HOOK` supports it). Report it in one line.

## Rules

- **Name workspaces by label** to the human (e.g. `Acme-245 export sort order`), never a bare id like
  `w1Q`; an id may follow in parentheses only when needed for a command.
- The reserved QC ports belong to QC: `pdo qc` kills anything on them, and command agents are told
  never to use them.
- One PR is served at a time. A new `<M>` replaces the current one; `pdo qc start` handles any data
  reset the previous PR needs.
- Keep replies short. The human is mid-QC in a browser.
