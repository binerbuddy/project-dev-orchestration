# The UX QC checklist

The human-QC checklist that every lifecycle skill posts on its PR. `/project-small-feature-or-bug-fix` (phase 7) and
`/project-feature-build` (Finalize) both follow this file. `§Name` means a `##` section of the project profile
(`.agents/project-profile.md`).

## Content and format

- Concrete steps in the running app ("open X, do Y, confirm Z"), covering every user-visible behaviour the change adds
  or alters, plus anything that couldn't be verified statically or headlessly: visual layout, timing, realtime push,
  DB-dependent paths.
- GitHub task-list markdown: every step is a `- [ ]` item, so it renders as interactive checkboxes.
- The document starts with the HTML marker `<!-- ux-qc-checklist -->` (used to find and update the comment later),
  followed immediately by the heading `## QC Checklist`. Always this exact title, so the human can find it on any PR.
- Save it to the scratchpad. It is posted as a PR comment, which is the canonical copy the user works from and ticks off.

## Headless repos (no UI)

When §QC data says the repo has no UI (an engine, library, CLI or API), QC means checking outputs, not clicking
through an app. Each item is a QC case named by its input (a fixture input file, a request to replay) with the
expected output and the command from §QC data that checks it, e.g. "`npm run replay -- 412/rounding.json`: the
total is 10.05, not 10.04". Put the evidence you already gathered (the actual output, a diff against the base
branch) under the case, so a human can pass it by reading. The rules below still apply: no host URLs, ports or
ids; inputs go on `qc-fixtures`, never on the PR branch; the same marker, heading and handoff block.

## Name data by project, never by link

The human may QC on a local dev server, a hosted preview, or any other host, so the checklist never contains a
localhost (or any host) URL, port, or record id. Refer to data by **project name** (or the app's equivalent top-level
record, as §QC data names it) and UI path instead: e.g. "open Projects → *Acme Demo* → Map", or "import the fixture,
then open the project *QC kept arcs*". Name the exact project, and the records inside it where it matters.

## QC fixture project

QC runs against the small shared seed data described in §QC data. If checking this change needs specific data the seed
lacks, don't make the human build it:

1. Create a fixture project in your own QC environment that already shows every case on the checklist.
2. Export it in the fixture format from §QC data, using the export steps there.
3. Publish it with `pdo qc-fixture-push <PR#> <file>` (if `pdo` isn't on PATH, `<engine checkout>/bin/qc-fixture-push`;
   a dispatch brief gives the absolute path). That stores it on the never-merged `qc-fixtures` branch and prints its link. **Never commit
   fixtures to the PR branch**: they would merge into the base branch with the PR. Keep each file under ~5 MB, and
   strip anything not needed.
4. Open the checklist (right under the `## QC Checklist` heading) with a **"Test data"** item: the script's
   `download:` link (`https://github.com/<org>/<repo>/releases/download/<FIXTURE_RELEASE>/<PR#>-<name>`; it downloads
   the file, where the `blob`/`raw` links only show it in the browser. Use the `raw:` link only if no `download:` line was printed), the import steps from
   §QC data, and which project(s) the following items use.

Skip all of this when the seed data already covers the checklist.

## QC handoff block

End the checklist comment with this block, verbatim except for the label names (the project env's
`LABEL_QC_READY` / `LABEL_QC_DONE`; `pdo project-env <KEY>` prints them):

```markdown
---
#### When you've worked through it
- **Feedback or answers:** submit a PR review with **Request changes** (line comments welcome). The agent that built
  this PR picks it up and replies here.
- **Pass:** add the `QC complete - ready to review` label (and remove `ready for QC`).
```

Where no orchestrator runs (a collaborator's repo with no engine), replace the feedback line with "Feedback or
answers: a PR review or comment; point the agent that built this PR at it."

**Optional QC commands.** If the profile's §Project extras has a `### QC commands` section (comment commands, a hosted
preview, its link pattern and login), append that table after the block, filling any `<…>` placeholders for this PR.
No §Project extras, or none for QC: the block above is the whole ending.

## Updating the posted checklist

When a later step (review triage, a gate fix) changes user-visible behaviour, regenerate the checklist to this same
standard and edit the existing comment **in place**: never post a second one.

1. Re-read the comment by its recorded id and confirm its body starts with `<!-- ux-qc-checklist -->`.
2. Preserve the checked state (`- [x]`) of every item that survives unchanged; append new items under a heading that
   names their origin (e.g. `### Added after review triage`).
3. PATCH it: `gh api -X PATCH repos/<org>/<repo>/issues/comments/<comment-id> -F body=@<file>`.
