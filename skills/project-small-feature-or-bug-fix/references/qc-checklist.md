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
ids; inputs go on `qc-fixtures`, never on the PR branch; the same marker, heading and commands block.

## Name data by project, never by link

The human may QC on a local dev server, a remote preview, or any other host, so the checklist never contains a
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
4. Open the checklist (right under the `## QC Checklist` heading) with a **"Test data"** item: the link the script
   printed (`https://github.com/<org>/<repo>/blob/qc-fixtures/<PR#>/<name>`, raw download), the import steps from
   §QC data, and which project(s) the following items use.

Skip all of this when the seed data already covers the checklist.

## QC commands block

End the checklist comment with this block, verbatim except for the PR-specific placeholders. Fill each `<…>` from
§QC preview (its comment triggers, preview link pattern, login, build time and idle timeout). If the profile has no
QC preview service, drop the two preview rows (spin up, tear down) and the "(no local setup)" words from the heading:
the `QC:` and `Claude, QC pass` rows stay, because the orchestrator's watcher handles them, preview or not. Only
where no orchestrator runs (a collaborator's repo with no engine), replace the `Claude, QC pass` row with "Apply the
`QC complete - ready to review` label when QC passes".

```markdown
---
#### QC from a browser (no local setup)
Reply on this PR with a comment that starts with one of these:

| Comment | What happens |
|---|---|
| `<spin-up trigger>` | Builds this PR into a preview (about <build time>). A reply posts the link, <preview link pattern>. Log in <login>. |
| `QC: <findings or answers>` | Sends feedback, or answers to questions, to the agent that built this PR. It replies here. |
| `Claude, QC pass` | Marks QC complete (`QC complete - ready to review`). |
| `<tear-down trigger>` | Stops the preview and frees its slot. Idle previews stop on their own after <idle timeout>. |
```

## Updating the posted checklist

When a later step (review triage, a gate fix) changes user-visible behaviour, regenerate the checklist to this same
standard and edit the existing comment **in place**: never post a second one.

1. Re-read the comment by its recorded id and confirm its body starts with `<!-- ux-qc-checklist -->`.
2. Preserve the checked state (`- [x]`) of every item that survives unchanged; append new items under a heading that
   names their origin (e.g. `### Added after review triage`).
3. PATCH it: `gh api -X PATCH repos/<org>/<repo>/issues/comments/<comment-id> -F body=@<file>`.
