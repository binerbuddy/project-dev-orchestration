# The label set

Every label the engine scripts and the lifecycle skills read or write. `/project-setup` checks for each one and
creates the missing ones. Names in the first four groups follow the project env when it renames them (full mode:
`pdo project-env <KEY>`; collaborator mode: the names the repo's `AGENTS.md` or profile already uses, else the
defaults below).

GitHub label names are case-insensitive: `p1-urgent` already present counts as `P1-urgent` present. Report the case
difference; never rename it.

| Label (default name) | Env key | Color | Description | Relied on by |
|---|---|---|---|---|
| `route:small` | | `0e8a16` | Route: small feature or bug fix (project-small-feature-or-bug-fix) | spawn, intake, queue |
| `route:design` | | `5319e7` | Route: needs a design doc (project-feature-design) | spawn, intake, design hand-off |
| `route:build` | | `1d76db` | Route: build an epic from a READY design doc (project-feature-build) | spawn, watch, design hand-off |
| `P1-urgent` | `P_LABELS` (1st) | `b60205` | Data loss, an exploited security hole, production down | queue, pr-priority, intake |
| `P2-high` | `P_LABELS` (2nd) | `d93f0b` | Security flaws, wrong results, things users need soon | queue, pr-priority, intake |
| `P3-medium` | `P_LABELS` (3rd) | `fbca04` | Real but tolerable bugs; normal features | queue, pr-priority, intake |
| `P4-low` | `P_LABELS` (4th) | `c2e0c6` | Polish, clean-up, ideas | queue, pr-priority, intake |
| `ready for QC` | `LABEL_QC_READY` | `e8b339` | Automated review+triage done; awaiting human UX QC | lifecycle skills, watch, hibernate, qc-review |
| `QC complete - ready to review` | `LABEL_QC_DONE` | `0e8a16` | Human QC passed; awaiting code review and a manual merge | qc-review, watch |
| `client-requested` | `CARRY_LABELS` (each) | `0052cc` | A client or customer asked for it; carried onto PRs | pr-priority, intake |
| `needs-triage` | | `ededed` | Not yet reviewed by a human; the queue skips it | queue, intake, collaborators |
| `epic-phase` | | `c5def5` | A phase of an epic; worked only by the epic's build agent | queue, spawn, feature-design |
| `awaiting-ux-gate` | | `f9d0c4` | An agent waits for a human's prototype sign-off | hibernate, watch, feature-build, dispatch brief |
| `likely-fixed` | | `bfdadc` | An agent thinks the default branch already does this; a human confirms | queue, watch, hibernate, dispatch brief |
| `blocked-by-pr` | | `fef2c0` | The PR can't merge until another PR lands | small-fix, feature-build |
| `on-hold` | | `6a737d` | Parked by a human; never started | queue, watch, intake |
| `needs-design` | | `d4c5f9` | Needs a design doc before work | spawn (routes to design), intake |
| `Security` | | `ee0701` | Authn/authz, injection, secrets, exposure, unsafe input | queue (ranks first in its P-level), intake |
| `small-win` | | `7ee787` | Cheap and worthwhile | intake, status |
| `orchestrator-system` | | `5a5a5a` | Work on the orchestration system itself (System Manager) | queue (excluded) |

If `P_LABELS` names more or fewer than four labels, give them the P colors in order and reuse `c2e0c6` for any past
the fourth.

**Type labels.** Issue types (Epic / Feature / Bug / Task) exist only on organization repos. On a repo owned by a user
account the API drops `type` silently, so the project uses type labels instead. Which names it uses is the human's
choice (ask; many repos already have `bug` and `enhancement`). Create only the ones they name, and record them in the
profile's §Identity.

## Check, then create the missing ones

Never pass `--force` (it rewrites an existing label's color and description), and never delete or rename a label.
`CREATE=0` makes the same loop check-only: it creates nothing and prints the command a maintainer would run for
each missing label (use it on a re-run, without write access, or when the human only wants the report).

```bash
R=<org>/<repo>; CREATE=${CREATE:-1}
have="$(gh label list -R "$R" --limit 500 --json name --jq '.[].name')"
[[ "$(wc -l <<<"$have")" -lt 500 ]] || { echo "label list may be truncated; raise --limit" >&2; exit 1; }
wanted=()
want() {  # want <name> <color> <description>
  wanted+=("$1")
  if grep -qixF -- "$1" <<<"$have"; then
    grep -qxF -- "$1" <<<"$have" && echo "present  $1" || echo "present  $1 (as '$(grep -ixF -- "$1" <<<"$have")', case differs)"
  elif [[ "$CREATE" == 1 ]]; then
    gh label create "$1" -R "$R" --color "$2" --description "$3" && echo "created  $1" || echo "failed   $1"
  else
    printf 'missing  %s   (gh label create %q -R %s --color %s --description %q)\n' "$1" "$1" "$R" "$2" "$3"
  fi
}
check() {  # check <name>: a repo-specific label the profile, AGENTS.md or CI names; never created
  wanted+=("$1")
  grep -qixF -- "$1" <<<"$have" && echo "present  $1 (repo-specific)" || echo "MISSING  $1 (repo-specific: ask the human)"
}
want "route:small" 0e8a16 "Route: small feature or bug fix (project-small-feature-or-bug-fix)"
# ...one line per row of the table above, with the project's names
# check "skip changeset"            # e.g. the changeset skip label from step 1
# the repo's own labels, listed for information only (no judgement, never renamed or deleted)
while IFS= read -r l; do
  [[ -n "$l" ]] || continue
  printf '%s\n' "${wanted[@]}" | grep -qixF -- "$l" || echo "extra    $l"
done <<<"$have"
```

Report each label as present, created, missing (check-only), or failed (with gh's error: usually missing write
access), and list the `extra` ones as the repo's own labels.
