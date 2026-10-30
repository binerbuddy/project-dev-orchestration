# Design doc contract

`/project-feature-design` writes a design doc to this contract, and `/project-feature-build` validates the doc against
it before building. The doc lives where the profile's §Docs says design docs go (default `docs/design/<slug>.md`).

Sections, in order:

1. **Header**: `Status`, `Date`, `Audience`, `Feeds into: /project-feature-build`, current revision.
2. **Goal**: what, for whom, and the expandability/consistency promise.
3. **What exists today**: survey table with `file:line` evidence; conventions to match.
4. **Design**: model, storage, API, client architecture, UI (as many subsections as needed). Every claim about
   existing code carries a `file:line`.
5. **Scope (v1)**: what ships, per area.
6. **Non-goals**: with the reserved seams for each.
7. **Security summary**.
8. **Delivery phases**: table or list; each phase has `depends-on`, acceptance criteria, `ux-gate` with reason, and a
   spike time-box/go-no-go where applicable. Gates: ≤2, ≤1 blocking.
9. **Follow-ups**: pre-existing bugs and deferred scope. The build lists them in the PR body's "Follow-ups (not
   filed)"; only items that clear the reporting bar go to intake.
10. **Decisions**: numbered, each `decided (date)` / `provisional` / `open`; open must be empty when Status is Ready.
11. **Tracking**: dispositions table, then (after the epic is filed) epic number and phase → issue table.
12. **Revision log**: rev, date, what changed and why (consortium round, user decision, build divergence).

## Status values

- `Ready for implementation — revision N, all decisions taken <date>` after the decisions gate.
- `Implemented — rev N` once `/project-feature-build` finalizes.

## Phase fields

Each phase in §Delivery phases carries:

- number and name;
- a one-paragraph summary;
- `depends-on`: phase numbers, or `none`;
- **acceptance criteria**: verifiable statements, each compile-level, headless-checkable, or `manual: …`;
- **ux-gate**: `none` | `async` | `blocking`, with the reason (which gate heuristic justified it);
- for spikes: a time-box and go/no-go criteria.
