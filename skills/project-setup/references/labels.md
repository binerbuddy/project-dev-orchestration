# The label set

Every label the engine scripts and the lifecycle skills read or write. `/project-setup` checks for each one and
creates the missing ones. Names with an env key follow the project env when it renames them (repo+team:
`pdo project-env <KEY>`; repo-only: the names the repo's `AGENTS.md` or profile already uses, else the
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
| `P3-medium` | `P_LABELS` (3rd) | `0969da` | Real but tolerable bugs; normal features | queue, pr-priority, intake |
| `P4-low` | `P_LABELS` (4th) | `c2e0c6` | Polish, clean-up, ideas | queue, pr-priority, intake |
| `ready for QC` | `LABEL_QC_READY` | `1b998b` | Automated review+triage done; awaiting QC (agent QC first, where it runs) | lifecycle skills, watch, hibernate, qc-review, agent-qc |
| `QC complete - ready to review` | `LABEL_QC_DONE` | `fbca04` | Agent QC passed; awaiting human UX review | qc-review, agent-qc, watch |
| `Ready for Merge` | `LABEL_MERGE_READY` | `0e8a16` | QC passed (agent, plus human UX review where needed); awaiting code review and a manual merge | qc-review, agent-qc, watch, fleet |
| `UX testing skipped` | `LABEL_UX_SKIPPED` | `c5def5` | Agent QC passed; no visible change, so no human UX review (the agent's comment says why) | agent-qc, watch |
| `needs UX review` | `LABEL_NEEDS_UX` | `d4c5f9` | Change is visible to users or design-sensitive: a human UX review is required after agent QC | intake, agent-qc, pr-priority (via `CARRY_LABELS`) |
| `QC escalated` | `LABEL_QC_ESCALATED` | `fbca04` | Agent QC failed twice; waiting on the human to decide | agent-qc, watch, hibernate, fleet |
| `client-requested` | `CARRY_LABELS` (each) | `0052cc` | A client or customer asked for it; carried onto PRs | pr-priority, intake |
| `needs-triage` | | `fbca04` | Not yet reviewed by a human; the queue skips it | queue, intake, collaborators |
| `epic-phase` | | `c5def5` | A phase of an epic; worked only by the epic's build agent | queue, spawn, feature-design |
| `awaiting-ux-gate` | | `fbca04` | An agent waits for a human's prototype sign-off (on the issue and its PR) | hibernate, watch, feature-build, dispatch brief |
| `likely-fixed` | | `fbca04` | An agent thinks the default branch already does this; a human confirms | queue, watch, hibernate, dispatch brief |
| `blocked-by-pr` | | `e99695` | The PR can't merge until another PR lands | small-fix, feature-build |
| `on-hold` | | `6a737d` | Parked by a human; never started | queue, watch, intake |
| `needs-design` | | `d4c5f9` | Needs a design doc before work | spawn (routes to design), intake |
| `Security` | | `ee0701` | Authn/authz, injection, secrets, exposure, unsafe input | queue (ranks first in its P-level), intake |
| `small-win` | | `7ee787` | Cheap and worthwhile | intake, status |
| `orchestrator-system` | | `5a5a5a` | Work on the orchestration system itself (System Manager) | queue (excluded) |
| `queue:work` | `QUEUE_LABEL` | `0e8a16` | In the orchestrator's queue (projects without a board) | queue (board-less mode) |

**Colors.** Yellow (`fbca04`) means a human must act now, and only those labels are yellow: `needs-triage`,
`likely-fixed`, `awaiting-ux-gate`, `QC complete - ready to review`, `QC escalated`, plus any repo-specific label
with the same meaning (e.g. a "requires criteria review" label). `Ready for Merge` is the exception: a human merges it,
but it stays green (`0e8a16`). Every other label avoids yellow: P1 red, P2 orange, P3 blue, P4 pale; agent and
pipeline states in teal, purple, blue or grey; blocked in pale red.

`queue:work` matters only to a repo+team project without a board (no `PROJECT_NUMBER`); create it there only.

The last four QC labels matter only where agent QC runs (`AGENT_QC_PORTS`), but create them everywhere: a human can
still pass a PR to `Ready for Merge` by hand, and `needs UX review` is set at intake.

Not in the set: the `managed-by:<slug>` claim labels. `pdo claim` creates its own manager's label the first time
it claims an issue in a repo; setup never creates them.

If `P_LABELS` names more or fewer than four labels, give them the P colors in order and reuse `c2e0c6` for any past
the fourth.

**Type labels.** Issue types (Epic / Feature / Bug / Task) exist only on organization repos. On a repo owned by a user
account the API drops `type` silently, so the project uses type labels instead. Which names it uses is the human's
choice (ask; many repos already have `bug` and `enhancement`). Create only the ones they name, and record them in the
profile's §Identity. In repo+team, map them to branch prefixes in the env's `BRANCH_PREFIX` (e.g.
`bug=fix task=chore default=feat`), which `pdo spawn` matches against the labels of an issue that has no type.

## Check, then create the missing ones

Never pass `--force` (it rewrites an existing label's color and description), and never delete or rename a label.
`CREATE=0` makes the same loop check-only: it creates nothing and prints the command a maintainer would run for
each missing label (use it on a re-run, without write access, or when the human only wants the report).

```bash
R=<org>/<repo>; CREATE=${CREATE:-1}
colors="$(gh label list -R "$R" --limit 500 --json name,color)"
have="$(jq -r '.[].name' <<<"$colors")"
[[ "$(wc -l <<<"$have")" -lt 500 ]] || { echo "label list may be truncated; raise --limit" >&2; exit 1; }
wanted=()
yellow() {  # yellow <hex>: true for a yellow-looking color (hue 40-65°, saturated, not too dark or pale)
  awk -v h="$1" 'BEGIN { r = strtonum("0x" substr(h,1,2))/255; g = strtonum("0x" substr(h,3,2))/255; b = strtonum("0x" substr(h,5,2))/255
    mx = r; if (g > mx) mx = g; if (b > mx) mx = b; mn = r; if (g < mn) mn = g; if (b < mn) mn = b; d = mx - mn; l = (mx + mn) / 2
    if (d == 0) exit 1; s = d / (1 - (2*l - 1 < 0 ? 1 - 2*l : 2*l - 1))
    hue = (mx == r) ? 60 * (((g - b) / d) % 6) : (mx == g) ? 60 * ((b - r) / d + 2) : 60 * ((r - g) / d + 4); if (hue < 0) hue += 360
    exit !(hue >= 40 && hue <= 65 && s >= 0.5 && l >= 0.3 && l <= 0.93) }'
}
want() {  # want <name> <color> <description>
  wanted+=("$1")
  if grep -qixF -- "$1" <<<"$have"; then
    grep -qxF -- "$1" <<<"$have" && echo "present  $1" || echo "present  $1 (as '$(grep -ixF -- "$1" <<<"$have")', case differs)"
    c="$(jq -r --arg n "$1" '.[] | select((.name|ascii_downcase) == ($n|ascii_downcase)) | .color' <<<"$colors")"
    if [[ "${c,,}" != "${2,,}" ]] && { [[ "${2,,}" == fbca04 ]] || yellow "$c"; }; then
      printf 'drifted  %s   color %s, engine %s   (gh label edit %q -R %s --color %s)\n' "$1" "$c" "$2" "$(grep -ixF -- "$1" <<<"$have")" "$R" "$2"
    elif [[ "${c,,}" != "${2,,}" ]]; then
      echo "color    $1   $c (engine $2; cosmetic, left alone)"
    fi
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

Report each label as present, created, missing (check-only), drifted (present, but its color differs from the
table) or failed (with gh's error: usually missing write access), and list the `extra` ones as the repo's own labels.
Drifted means the yellow rule (Colors, above) is broken: a human-acts-now label that isn't yellow, or another label
that looks yellow. It's fixed only on the human's yes, with the printed `gh label edit … --color` (color only; the
description and name stay). Any other color difference is the repo's own choice: report it on a `color` line and
leave it. Also look at the `extra` labels: one that looks yellow but doesn't mean "a human acts now", or one that
means it but isn't yellow, gets the same proposal (`fbca04` for a human label, a non-yellow color otherwise).
