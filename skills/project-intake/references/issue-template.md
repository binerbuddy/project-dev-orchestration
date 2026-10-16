# Issue body template (intake)

```markdown
## Summary
<one or two sentences in the human's terms>

## Details
<Bug: steps to reproduce / expected / actual / where seen. Feature: goal, who it's for, acceptance
criteria as a short checklist. Task: what "done" means.>

## Starting points (unverified)
_Gathered at intake by a bounded look; locations only, no diagnosis. Verify before relying on them._
- Related issues: …
- Memory / design docs: …
- Candidate code: `path` — why it's relevant (one line)

<sub>Filed via /project-intake</sub>
```

For a report from the inbox, the footer credits the sender:
`<sub>Filed via /project-intake · reported from <workspace name></sub>`.

## Business-critical block

When an item is high-importance business logic (see SKILL.md, Rules) and leaves a business-rule
choice to the build, add to Details:

```markdown
> [!IMPORTANT]
> Business-rule choice: <what must be decided, e.g. which cases are excluded>. The build recommends
> the options with evidence; the human manually verifies and approves them before implementation.
> This is a blocking gate, never waived, even under `route:small`.
```

and the matching acceptance-criteria item:
`- [ ] Human approved the business-rule choice before implementation`.

## Without an engine

A collaborator with no orchestrator install files the same body by hand, in the right repo, with
`needs-triage` and no P label (unless a maintainer gave one), via `gh issue create`; it skips the
board and the type unless they have the rights.
