# QC checklist, fixtures and the handoff

## The QC checklist comment

Every PR that reaches `ready for QC` carries one QC checklist comment, posted by the agent that built it.

- The comment starts with the HTML marker `<!-- ux-qc-checklist -->` (used to find and update it in
  place), followed immediately by the heading **`## QC Checklist`**. Always that exact title, so a
  human finds it on any PR.
- Every step is a GitHub task-list item (`- [ ] open X, do Y, confirm Z`), covering every
  user-visible behaviour the change adds or alters, plus anything that couldn't be verified
  statically or headlessly (visual layout, timing, realtime updates, data-dependent paths).
- **Headless repos** (an engine, library, CLI or API with no UI; the profile's `## QC data` says
  so): QC means checking outputs. Each item is a case named by its input (a fixture input file, a
  request to replay) with the expected output and the command that checks it, plus the evidence
  already gathered (actual output, a diff against the base branch).
- **Project-name rule: name data, never link to it.** The human may QC on localhost, a hosted
  preview, or any other host, so the checklist never contains a localhost or host URL, a port, or a
  database id. Refer to data the way the app names it (e.g. a project, workspace or dataset name)
  plus the UI path: "open Projects → *Acme Sample* → Map", or "import the fixture, then open the
  project *QC 412 sorted exports*". Name the exact item, and the records inside it where it matters.
- The checklist ends with the QC handoff block (how to give feedback and how to pass, below), then the
  profile's `## Project extras` QC commands table if it has one.

To edit the comment later, find it by its marker, re-read its body, and confirm the marker before
patching: an id captured earlier may now belong to a different comment.

## QC fixtures

If checking the change needs specific data the QC seed lacks, don't make the human build it:

1. Build a fixture in your own QC environment that already shows every case on the checklist.
2. Export it in the project's fixture format (profile `## QC data`, file extension `FIXTURE_EXT`).
3. Publish it with `pdo qc-fixture-push <PR#> <file>`. It stores the file at `<PR#>/<name>` on the
   never-merged **`qc-fixtures`** branch, uploads the same file as the asset `<PR#>-<name>` of the
   `qc-fixtures-assets` prerelease (`FIXTURE_RELEASE`), and prints a `download:` link to it. **Never commit fixtures to the PR
   branch**: they would merge into the default branch with the PR. Keep each file small (under
   ~5 MB) and strip anything not needed.
   Without an engine install: push the file to `qc-fixtures` yourself (an orphan branch, path
   `<PR#>/<name>`), never to the PR branch.
4. Open the checklist (right under the heading) with a **"Test data"** item: the `download:` link (it downloads the file; the `raw` link opens it
   in the browser), the import
   steps, and which data the following items use.

Skip all of this when the seed already covers the checklist.

## The handoff: labels and reviews

The engine's QC handoff uses only GitHub labels and PR reviews, so it works for any project, with or
without extra tooling. Label names are the defaults; the project env may rename them
(`LABEL_QC_READY`, `LABEL_QC_DONE`, `LABEL_MERGE_READY`, `LABEL_UX_SKIPPED`, `LABEL_NEEDS_UX`,
`LABEL_QC_ESCALATED`).

| Step | Who | How |
|---|---|---|
| Draft | the agent | opens the PR as a **draft** and keeps it one through review and triage (draft CI skips the heavy jobs). |
| Ready | the agent | runs `gh pr ready` (one full CI run), labels the PR `ready for QC` after review and triage, posts the checklist, stops. The PR now waits for QC. Agent QC only takes non-draft PRs; `pdo hibernate` flips a still-draft one. |
| Agent QC | the QC Agent (where `AGENT_QC_PORTS` is set) | tests the PR on its own servers and data (`/project-agent-qc`). **Fail:** posts "Agent QC findings (round N)", removes `ready for QC` and resumes the agent; after 2 failed rounds adds `QC escalated` and stops (a human decides). **Pass:** posts a short classification by the visible-change rule, then either `QC complete - ready to review` (UX review needed) or `Ready for Merge` + `UX testing skipped`. A PR or linked issue labelled `needs UX review` always gets UX review. |
| Feedback | the human | in the agent's session (local QC), or a GitHub PR review with **Request changes** (state `CHANGES_REQUESTED`). The orchestrator's watcher raises each new review from a trusted author (repo OWNER, MEMBER or COLLABORATOR) as `qc_feedback`, and the agent is resumed with it; `ready for QC` and `QC complete - ready to review` come off, and the agent re-applies `ready for QC` after fixing (so agent QC runs again). |
| Pass | the human | adds `Ready for Merge` and removes `ready for QC` / `QC complete - ready to review`. Only a human applies it, except agent QC's no-UX pass. |
| Wrap-up | the watcher | `qc_complete` fires once per pass, on whichever of `QC complete - ready to review` / `Ready for Merge` appears first; the orchestrator tells the agent to wrap up. The human's later UX pass (QC complete → Ready for Merge) prompts nobody. |

Every label here except `ready for QC` and `needs UX review` means "waiting on a human" for the
orchestrator's PR cap: `QC complete - ready to review` (UX review), `Ready for Merge` (code review and
merge), `QC escalated` (a decision).

GitHub won't let a PR's author request changes on their own PR: an author gives feedback in the
agent's session (or via `/project-qc-review` on an engine install) instead.

Agents answering remote QC: the reviewer reads GitHub, not your session. Reply on the PR, ask any
question there with an `@<author>` mention, and wait for their next review or reply. After fixing:
push, reply on the PR with what changed, re-apply `ready for QC`.

**Project extras.** A project may add its own conventions on top, for example PR-comment commands
for a hosted preview service, or comment-based feedback, implemented by its `WATCH_EVENT_HOOK` or by a
service of its own. They are documented in the profile's `## Project extras`; follow them there. The
engine itself never reads PR comments.

With no orchestrator at all, reviews wait until someone points the PR's agent at them, and a human
applies `Ready for Merge` by hand.
