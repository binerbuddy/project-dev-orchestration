# QC: checklist, fixtures and the comment protocol

## The QC checklist comment

Every PR that reaches `ready for QC` carries one QC checklist comment, posted by the agent that built it.

- The comment starts with the HTML marker `<!-- ux-qc-checklist -->` (used to find and update it in
  place), followed immediately by the heading **`## QC Checklist`**. Always that exact title, so a
  human finds it on any PR.
- Every step is a GitHub task-list item (`- [ ] open X, do Y, confirm Z`), covering every
  user-visible behaviour the change adds or alters, plus anything that couldn't be verified
  statically or headlessly (visual layout, timing, realtime updates, data-dependent paths).
- **Project-name rule: name data, never link to it.** The human may QC on localhost, a remote
  preview, or any other host, so the checklist never contains a localhost or host URL, a port, or a
  database id. Refer to data the way the app names it (e.g. a project, workspace or dataset name)
  plus the UI path: "open Projects → *Acme Sample* → Map", or "import the fixture, then open the
  project *QC 412 sorted exports*". Name the exact item, and the records inside it where it matters.
- When an optional remote preview exists (profile `## QC preview`), the checklist ends with the
  comment-protocol table below, verbatim except for the PR number.

To edit the comment later, find it by its marker, re-read its body, and confirm the marker before
patching: an id captured earlier may now belong to a different comment.

## QC fixtures

If checking the change needs specific data the QC seed lacks, don't make the human build it:

1. Build a fixture in your own QC environment that already shows every case on the checklist.
2. Export it in the project's fixture format (profile `## QC data`, file extension `FIXTURE_EXT`).
3. Publish it with `pdo qc-fixture-push <PR#> <file>`. It stores the file at `<PR#>/<name>` on the
   never-merged **`qc-fixtures`** branch and prints its link. **Never commit fixtures to the PR
   branch**: they would merge into the default branch with the PR. Keep each file small (under
   ~5 MB) and strip anything not needed.
   Without an engine install: push the file to `qc-fixtures` yourself (an orphan branch, path
   `<PR#>/<name>`), never to the PR branch.
4. Open the checklist (right under the heading) with a **"Test data"** item: the link, the import
   steps, and which data the following items use.

Skip all of this when the seed already covers the checklist.

## Comment protocol (optional; only where the profile's `## QC preview` says it's set up)

Trusted commenters (repo OWNER, MEMBER or COLLABORATOR) drive QC from a browser, with nothing
installed locally. A comment must **start with** one of these:

| Comment | What happens |
|---|---|
| `Claude, spin up QC` | The preview service builds this PR into a preview and replies with the link and login (both per the profile's `## QC preview`). Takes a few minutes. |
| `QC: <findings or answers>` | Feedback, or answers to questions, for the agent that built this PR. The engine's watcher delivers it; the agent replies **on the PR**. |
| `Claude, QC pass` | Marks QC complete (`ready for QC` → `QC complete - ready to review`). |
| `Claude, tear down` | Stops the preview and frees its slot. Idle previews also stop on their own after the profile's idle limit. |

Agents answering remote QC: the reporter reads GitHub, not your session. Reply on the PR, ask any
question there with an `@<author>` mention, and wait for their next `QC:` comment. After fixing:
push, reply on the PR with what changed, re-apply `ready for QC`.

Projects without a preview service skip the table; QC then happens locally (`/project-qc-review` on
an engine install) or however the profile describes.
