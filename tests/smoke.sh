#!/usr/bin/env bash
# smoke.sh — offline smoke test of the engine's config contract and the scripts that can run
# without herdr or GitHub. Everything happens under a temp dir: temp PDO_CONFIG_DIRS, PDO_STATE_DIR,
# a fake project env, local git remotes, and fake `gh` / `herdr` commands on PATH.
#
# Usage: tests/smoke.sh [-v]     exit 0 when every check passes
set -uo pipefail
ENGINE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
BIN="$ENGINE/bin"
VERBOSE=0; [[ "${1:-}" == -v ]] && VERBOSE=1
T="$(mktemp -d "${TMPDIR:-/tmp}/pdo-smoke.XXXXXX")"
trap 'rm -rf -- "$T"' EXIT
PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); [[ $VERBOSE -eq 1 ]] && echo "ok   $1"; return 0; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL $1"; [[ -n "${2:-}" ]] && printf '     %s\n' "$2"; return 0; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name" "command: $*"; fi; }
eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
has() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "[$2] lacks [$3]"; fi; }

# --- isolated environment ---
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state"
mkdir -p "$HOME"
export PDO_CONFIG_DIRS="$T/cfg-a:$T/cfg-b" PDO_STATE_DIR="$T/state" PYTHONDONTWRITEBYTECODE=1
export PDO_GATE_DIR="$T/gate"   # never the machine's shared gate (/var/lib/pdo-gate)
export TMP_SWEEP_ROOT="$T/tmproot"  # the watcher and hibernate run tmp-sweep: never the real /tmp
export PDO_GATE_DIR="$T/gate" PDO_MEM_AVAIL_MB=64000  # the memory gate: never the machine's real lock or RAM
unset PDO_INBOX INTAKE_INBOX PDO_PROJECT PDO_SKILL_PREFIX GH_USER GH_TOKEN
export GIT_AUTHOR_NAME=smoke GIT_AUTHOR_EMAIL=smoke@example.com GIT_COMMITTER_NAME=smoke GIT_COMMITTER_EMAIL=smoke@example.com
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global init.defaultBranch main

# fake gh and herdr: canned answers, every call logged
mkdir -p "$T/fakebin"
cat >"$T/fakebin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$SMOKE_LOG"
[[ -n "${SMOKE_TOKEN_LOG:-}" ]] && echo "${GH_TOKEN:-none} $*" >>"$SMOKE_TOKEN_LOG"
case "$*" in
  "auth token -u nobody") exit 1 ;;
  "api user --jq .login") echo me ;;
  # claim / release (managed-by labels, claim comment)
  "api repos/acme/widget/labels/managed-by%3A"*) [[ -f "$SMOKE_DIR/label-exists" ]] || { echo "HTTP 404" >&2; exit 1; } ;;
  "label create managed-by:"*) touch "$SMOKE_DIR/label-exists" ;;
  "api repos/acme/widget/issues/"*"/labels -f labels[]="*) ;;
  "api -X DELETE repos/acme/widget/issues/"*"/labels/managed-by%3A"*) ;;
  "api repos/acme/widget/issues/"*"/comments -f body="*) echo 9001 ;;
  "issue edit"*) ;;
  # lane-merge: the PR in $SMOKE_DIR/lane-pr.json; acme/widget's default branch is main
  "pr view "*" -R acme/widget --json number,title,state,isDraft,baseRefName"*) cat "$SMOKE_DIR/lane-pr.json" ;;
  "api repos/acme/widget --jq .default_branch") echo main ;;
  "pr merge "*" -R acme/widget "*) ;;
  "pr list -R acme/widget --state open"*) echo feat/61 ;;
  "pr list -R acme/widget --head feat/77"*) echo '[{"number":77,"labels":[{"name":"ready for QC"}],"state":"OPEN","isDraft":false}]' ;;
  "api repos/acme/widget/issues/77 --jq"*) echo '{"state":"open","labels":[]}' ;;
  "api repos/acme/widget/issues/79 --jq"*) echo '{"state":"open","labels":["awaiting-ux-gate"]}' ;;
  "api repos/acme/widget/issues/8"[01]" --jq"*) echo '{"state":"open","labels":[]}' ;;
  "pr list -R acme/widget --head feat/"[78][019]*) echo '[]' ;;
  "api repos/acme/widget/issues/80") cat "$SMOKE_DIR/issue80.json" ;;
  "api repos/acme/widget/issues/80/dependencies/blocked_by --jq"*join*) echo 'acme/widget#5' ;;
  "api repos/acme/widget/issues/80/dependencies/blocked_by --jq"*) echo '["acme/widget#5"]' ;;
  "api repos/acme/widget/issues/"*"/dependencies/blocked_by --jq"*join*) echo '' ;;
  "api repos/acme/widget/issues/"*"/dependencies/blocked_by --jq"*) echo '[]' ;;
  "label create awaiting-"*|"issue comment "*|"pr comment "*) ;;  # tmp-sweep: open PRs keep their agents' scratchpads
  # qc-fixture-push: the fixture release and its assets
  "release view "*" -R acme/"*) [[ -f "$SMOKE_DIR/fixture-release" ]] || exit 1 ;;
  "release create "*" -R acme/"*) touch "$SMOKE_DIR/fixture-release" ;;
  "release upload "*" -R acme/"*) [[ -z "${SMOKE_UPLOAD_FAIL:-}" ]] || exit 1 ;;
  "api repos/acme/widget/issues/13") cat "$SMOKE_DIR/issue13.json" ;;
  "api repos/acme/widget/issues/14") cat "$SMOKE_DIR/issue14.json" ;;
  "api graphql"*"projectItems"*)
    echo '{"data":{"repository":{"issue":{"projectItems":{"nodes":[]}}},"organization":{"projectV2":{"id":"PVT_b7","field":{"id":"F1","options":[{"id":"o3","name":"In Progress"},{"id":"o4","name":"Done"}]}}}}}' ;;
  "api graphql"*"addProjectV2ItemById"*) echo ITEM_1 ;;
  "api graphql"*"updateProjectV2ItemFieldValue"*) echo '{}' ;;
  # queue: native blockers of alpha/tool#23
  "api graphql"*"query blockers"*)
    echo '{"data":{"repository":{"i23":{"blockedBy":{"nodes":[{"number":9,"state":"OPEN","repository":{"nameWithOwner":"alpha/tool"}},{"number":7,"state":"OPEN","repository":{"nameWithOwner":"gamma/lib"}},{"number":2,"state":"CLOSED","repository":{"nameWithOwner":"alpha/tool"}}]}}}}}' ;;
  # fleet: native dependencies (one cross-repo edge on alpha/tool, one same-repo edge on gamma/lib)
  "api graphql"*"query fleetdeps"*)
    if [[ "$*" == *"r=tool"* ]]; then
      echo '{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"number":1,"blockedBy":{"nodes":[{"number":7,"state":"OPEN","repository":{"nameWithOwner":"gamma/lib"}}]}},{"number":12,"blockedBy":{"nodes":[{"number":9,"state":"OPEN","repository":{"nameWithOwner":"gamma/lib"}}]}}]}}}}'
    else
      echo '{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"number":3,"blockedBy":{"nodes":[{"number":4,"state":"OPEN","repository":{"nameWithOwner":"gamma/lib"}}]}}]}}}}'
    fi ;;
  # fleet deps: native dependency add/remove, fallback comments, coordination notes
  "api repos/alpha/tool/issues/5 --jq"*) printf '5005\tfalse\n' ;;
  "api repos/alpha/tool/issues/8 --jq"*) printf '8008\ttrue\n' ;;
  "api repos/gamma/lib/issues/7 --jq"*) printf '7007\tfalse\n' ;;
  "api -X POST repos/gamma/lib/issues/7/dependencies/blocked_by -F issue_id=5005") echo '{"number":7}' ;;
  "api -X POST repos/alpha/tool/issues/1/dependencies/blocked_by -F issue_id=7007")
    echo 'gh: Validation failed: Target issue has already been taken (HTTP 422)' >&2; exit 1 ;;
  "api -X DELETE repos/"*"/dependencies/blocked_by/"*) echo '{}' ;;
  "api repos/"*"/comments -f body="*) printf '7001\thttps://github.com/x/y/issues/1#issuecomment-7001\n' ;;
  "auth token -u "*) echo "token-for-${@: -1}" ;;
  "auth git-credential"*) cat >/dev/null; printf 'protocol=https\nhost=github.com\nusername=x-access-token\npassword=%s\n' "${GH_TOKEN:-none}" ;;
  "pr edit"*|"pr comment"*) ;;
  "api graphql"*"query board"*)
    echo '{"data":{"organization":{"projectV2":{"id":"PVT_b7","number":7,"title":"Acme Board","field":{"id":"PVTSSF_s","options":[{"id":"o1","name":"Backlog"},{"id":"o2","name":"Claude Work This"}]}}}}}' ;;
  "api repos/acme/widget/issues/12") cat "$SMOKE_DIR/issue12.json" ;;
  "api repos/acme/widget/issues/12/comments"*|"api repos/acme/widget/issues/80/comments"*|"api repos/acme/docs/issues/12/comments"*) ;;
  "api repos/acme/docs/issues/12") cat "$SMOKE_DIR/issue12.json" ;;
  "pr view 5 -R acme/widget"*) cat "$SMOKE_DIR/pr5.json" ;;
  "project item-list 9 --owner alpha"*) echo '{"items":[{"content":{"number":2},"repository":"alpha/tool","status":"Claude Work This"}]}' ;;
  "project item-list"*) echo '{"items":[]}' ;;
  "api graphql --paginate -f query=query queueBoard"*"-F o=alpha -F n=9 "*) echo '{"repo":"tool","number":2,"status":"Claude Work This"}' ;;
  "api graphql --paginate -f query=query queueBoard"*) ;;
  "api repos/alpha/tool/issues?state=open"*) cat "$SMOKE_DIR/alpha-issues.jsonl" ;;
  "api repos/alpha/tool/issues/5") echo '{"state":"closed"}' ;;
  "api repos/alpha/tool/issues/8") echo '{"state":"closed","pull_request":{"merged_at":"2026-01-01T00:00:00Z"}}' ;;
  "api repos/gamma/lib/issues/7") echo '{"state":"open"}' ;;
  "api rate_limit --jq"*) echo 4000 ;;
  "api rate_limit")
    [[ -n "${SMOKE_GH_RATE_FAIL:-}" ]] && exit 1
    echo '{"resources":{"graphql":{"limit":5000,"remaining":4000,"reset":4102444800},"core":{"limit":5000,"remaining":4900,"reset":4102444800}}}' ;;
  "api graphql"*"query fleet"*)
    if [[ "$*" == *"r=tool"* ]]; then cat "$SMOKE_DIR/fleet-tool.json"
    else echo '{"data":{"repository":{"pullRequests":{"totalCount":0,"nodes":[]},"gates":{"nodes":[]}}}}'; fi ;;
  "api repos/acme/"*"/issues?state=open"*) [[ -z "${SMOKE_OPEN_ISSUES:-}" ]] || cat "$SMOKE_OPEN_ISSUES" ;;
  "api repos/delta/tool/issues?state=open"*) cat "$SMOKE_DIR/delta-issues.jsonl" ;;
  "api repos/delta/tool/issues/24/dependencies/blocking"*) echo "tool 25" ;;
  "api graphql -f query={rateLimit{remaining}} --jq"*) echo 4000 ;;
  "api graphql"*"open: pullRequests"*)
    if [[ -n "${SMOKE_PRS:-}" ]]; then cat "$SMOKE_PRS"; else echo '{"data":{"repository":{"open":{"nodes":[]},"done":{"nodes":[]}}}}'; fi ;;
  "api graphql"*) echo '{"data":{"repository":{"pullRequests":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}' ;;
  *) echo "fake gh: unhandled: $*" >&2; exit 1 ;;
esac
EOF
cat >"$T/fakebin/herdr" <<'EOF'
#!/usr/bin/env bash
echo "herdr $*" >>"$SMOKE_LOG"
[[ -n "${SMOKE_HERDR_FAIL:-}" ]] && exit 1
case "$1 ${2:-}" in
  "workspace list") if [[ -n "${SMOKE_HERDR_WS:-}" ]]; then cat "$SMOKE_HERDR_WS"; else echo '{"result":{"workspaces":[]}}'; fi ;;
  "agent list") if [[ -n "${SMOKE_HERDR_AGENTS:-}" ]]; then cat "$SMOKE_HERDR_AGENTS"; else echo '{"result":{"agents":[]}}'; fi ;;
  # SMOKE_HERDR_EXIT: /exit makes the agent disappear and `pane run` (a relaunch) brings it back
  "agent prompt") if [[ -n "${SMOKE_HERDR_EXIT:-}" && "${4:-}" == /exit ]]; then
                    mv "$SMOKE_HERDR_AGENTS" "$SMOKE_HERDR_AGENTS.saved"; echo '{"result":{"agents":[]}}' >"$SMOKE_HERDR_AGENTS"; fi
                  echo '{"result":{}}' ;;
  "pane run") if [[ -n "${SMOKE_HERDR_EXIT:-}" && -f "$SMOKE_HERDR_AGENTS.saved" ]]; then mv "$SMOKE_HERDR_AGENTS.saved" "$SMOKE_HERDR_AGENTS"; fi
              echo '{"result":{}}' ;;
  "pane list") echo "{\"result\":{\"panes\":[{\"pane_id\":\"${SMOKE_HERDR_PANE:-}\"}]}}" ;;
  "pane read") [[ -n "${SMOKE_HERDR_SCREEN:-}" ]] && cat "$SMOKE_HERDR_SCREEN"; true ;;  # an ANSI screen
  "tab list") if [[ -n "${SMOKE_HERDR_TABS:-}" ]]; then cat "$SMOKE_HERDR_TABS"; else echo '{"result":{"tabs":[]}}'; fi ;;
  # a new place: SMOKE_HERDR_NEW names the new workspace (or, for a tab, the home's) id
  "tab create") w="${SMOKE_HERDR_NEW:-wH}"; echo "{\"result\":{\"tab\":{\"tab_id\":\"$w:t9\"},\"root_pane\":{\"pane_id\":\"$w:p9\"}}}" ;;
  "workspace create") w="${SMOKE_HERDR_NEW:-wN}"
    echo "{\"result\":{\"workspace\":{\"workspace_id\":\"$w\"},\"tab\":{\"tab_id\":\"$w:t1\"},\"root_pane\":{\"pane_id\":\"$w:p1\"}}}" ;;
  *) echo '{"result":{}}' ;;
esac
EOF
chmod +x "$T/fakebin/gh" "$T/fakebin/herdr"
export PATH="$T/fakebin:$PATH" SMOKE_LOG="$T/calls.log" SMOKE_DIR="$T"

# --- repos: a local "origin", a bare clone with a worktree, and a plain clone ---
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
echo hello >"$T/seed/README.md"; git -C "$T/seed" add README.md; git -C "$T/seed" commit -qm init
git -C "$T/seed" push -q origin main
mkdir -p "$T/repos"
git clone -q --bare "$T/origin.git" "$T/repos/widget.git"
git -C "$T/repos/widget.git" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git -C "$T/repos/widget.git" fetch -q origin
git -C "$T/repos/widget.git" worktree add -q "$T/repos/widget.git/7-feature" -b feat/7 origin/main
git clone -q "$T/origin.git" "$T/repos/docs"
mkdir -p "$T/elsewhere"

# --- config dirs: acme in cfg-a (shadowing a broken copy in cfg-b), beta only in cfg-b ---
mkdir -p "$T/cfg-a/projects" "$T/cfg-a/hooks" "$T/cfg-a/prompts" "$T/cfg-b/projects"
cat >"$T/cfg-a/projects/acme.env" <<EOF
ORG="acme"
PROJECT_NUMBER=7
declare -A REPO_ROOT=(
  [widget]="$T/repos/widget.git"
  [docs]="$T/repos/docs"
)
SELF_MANAGED_REPOS=(docs)
declare -A ROUTE_SKILL=(
  [small]="\${PDO_SKILL_PREFIX}project-small-feature-or-bug-fix"
  [design]="\${PDO_SKILL_PREFIX}project-feature-design"
  [build]="\${PDO_SKILL_PREFIX}project-feature-build"
)
PRIMARY_REPO="widget"
IDENTITY_HOOK="hooks/identity"
QC_HOOK="hooks/qc"
FIXTURE_EXT=".acme"
declare -A FIXTURE_EXT_BY_REPO=([docs]=".dump")
declare -A AGENT_QC_NOTES_BY_REPO=([docs]="notes/agent-qc-docs.md")
QC_PORTS="3999"
EOF
echo 'ORG="wrong"' >"$T/cfg-b/projects/acme.env"
cat >"$T/cfg-b/projects/beta.env" <<'EOF'
ORG="beta"
declare -A REPO_ROOT=([gadget]="$HOME/nowhere")
BRIEF_TEMPLATE="$HERE/prompts/beta-brief.md"
EOF
echo ': "${SYSTEM_MANAGER_WORKSPACE:=Acme-Ops}"' >"$T/cfg-a/config.env"
echo 'Custom brief {{REF}} via {{ENGINE}}' >"$T/cfg-a/prompts/dispatch-brief.md"
printf '#!/usr/bin/env bash\n[[ "$1" == *docs* ]] && printf %%s extra-identity\n' >"$T/cfg-a/hooks/identity"
cat >"$T/cfg-a/hooks/qc" <<'EOF'
#!/usr/bin/env bash
echo "hook $* pr=${PDO_QC_PR:-} ref=${PDO_QC_REF:-} key=${PDO_QC_KEY:-} wt=${PDO_QC_WORKTREE:-} inst=${PDO_QC_INSTANCE:-} ports=${PDO_QC_PORTS:-}" >>"$SMOKE_LOG"
case "$1" in
  start) echo '{"db":"fake"}' >"$PDO_QC_STATE/hook-current.json" ;;
  wait) echo "qc: up (fake)" ;;
  status) echo ":3999 down" ;;
esac
EOF
chmod +x "$T/cfg-a/hooks/identity" "$T/cfg-a/hooks/qc"

# --- syntax ---
for f in "$BIN"/* "$ENGINE"/tests/*.sh; do
  [[ -f "$f" ]] || continue
  case "$(head -1 "$f")" in
    *bash*) check "bash -n $(basename "$f")" bash -n "$f" ;;
    *python3*) check "python compile $(basename "$f")" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" ;;
  esac
done
check "bash -n lib.sh" bash -n "$BIN/lib.sh"
check "python compile pdo_config.py" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$BIN/pdo_config.py"
for p in queue watch hibernate tmp-sweep pr-priority pr-agent fleet; do check "$p --help" "$BIN/$p" --help; done

# --- project resolution ---
cd "$T/repos/widget.git/7-feature" || exit 1
eq "detect from a worktree of a bare root" "$("$BIN/pdo-config" --name)" acme
cd "$T/repos/docs" && eq "detect from a plain clone" "$("$BIN/pdo-config" --name)" acme
cd "$T/elsewhere"
out="$("$BIN/pdo-config" --name 2>&1)"; rc=$?
eq "no match fails" "$rc" 1
has "no match lists known projects" "$out" "Known projects: acme beta"
eq "--project wins" "$("$BIN/pdo-config" --project beta --name)" beta
eq "PDO_PROJECT used when no --project" "$(PDO_PROJECT=beta "$BIN/pdo-config" --name)" beta
out="$("$BIN/pdo-config" --project nope --name 2>&1)"; has "unknown project fails with list" "$out" "unknown project 'nope'"
eq "first config dir wins" "$("$BIN/pdo-config" --project acme --json | jq -r .org)" acme
J="$("$BIN/pdo-config" --project acme --json)"
eq "hook resolved against its config dir" "$(jq -r .qc_hook <<<"$J")" "$T/cfg-a/hooks/qc"
eq "prompt found in a config dir" "$(jq -r .brief_template <<<"$J")" "$T/cfg-a/prompts/dispatch-brief.md"
eq "beta: \$HERE is its config dir" "$("$BIN/pdo-config" --project beta --json | jq -r .brief_template)" "$T/cfg-b/prompts/beta-brief.md"
eq "state dir from PDO_STATE_DIR" "$(jq -r .state_dir <<<"$J")" "$T/state"
eq "inbox defaults under state" "$(jq -r .inbox <<<"$J")" "$T/state/intake-inbox"
eq "self-managed repos" "$(jq -c .self_managed_repos <<<"$J")" '["docs"]'
eq "config.env install-wide default" "$(jq -r .system_manager_workspace <<<"$J")" Acme-Ops
eq "skill prefix default" "$(jq -r .route_skill.small <<<"$J")" "/pdo:project-small-feature-or-bug-fix"
eq "PDO_SKILL_PREFIX override" "$(PDO_SKILL_PREFIX=/ "$BIN/pdo-config" --project acme --json | jq -r .orchestrate_skill)" "/project-orchestrate"
eq "label defaults" "$(jq -r '.label_qc_ready + "|" + .cwt_status + "|" + (.p_labels | join(","))' <<<"$J")" "ready for QC|Claude Work This|P1-urgent,P2-high,P3-medium,P4-low"
eq "qc ports" "$(jq -c .qc_ports <<<"$J")" "[3999]"
eq "QC-stage label defaults" "$(jq -r '[.label_merge_ready, .label_ux_skipped, .label_needs_ux, .label_qc_escalated] | join("|")' <<<"$J")" "Ready for Merge|UX testing skipped|needs UX review|QC escalated"
eq "agent QC off by default" "$(jq -c '[.agent_qc_ports, .agent_qc_repos, .agent_qc_max_rounds]' <<<"$J")" '[[],["widget"],2]'
eq "CARRY_LABELS with commas keeps spaces" "$(CARRY_LABELS="client-requested, needs UX review" "$BIN/pdo-config" --project acme --json | jq -c .carry_labels)" '["client-requested","needs UX review"]'
eq "CARRY_LABELS with spaces still splits" "$(CARRY_LABELS="a b" "$BIN/pdo-config" --project acme --json | jq -c .carry_labels)" '["a","b"]'
check "agent-qc refuses while agent QC is off" bash -c '! "$0/agent-qc" queue' "$BIN"
eq "AGENT_QC_NOTES_BY_REPO resolved against its config dir" "$(jq -r .agent_qc_notes_by_repo.docs <<<"$J")" "$T/cfg-a/notes/agent-qc-docs.md"
eq "agent-qc notes: a repo's own notes" "$(AGENT_QC_PORTS=3998 AGENT_QC_NOTES=notes/all.md "$BIN/agent-qc" notes docs --project acme)" "$T/cfg-a/notes/agent-qc-docs.md"
eq "agent-qc notes: others fall back to AGENT_QC_NOTES" "$(AGENT_QC_PORTS=3998 AGENT_QC_NOTES=notes/all.md "$BIN/agent-qc" notes widget --project acme)" "$T/cfg-a/notes/all.md"
AGENT_QC_PORTS=3998 "$BIN/agent-qc" notes widget --project acme >/dev/null 2>&1; eq "agent-qc notes: none exits 1" "$?" 1
check "agent-qc notes: unknown repo fails" bash -c '! AGENT_QC_PORTS=3998 "$0/agent-qc" notes nope --project acme' "$BIN"
# recycle-agent-qc: restart the QC Agent between PRs, only when its turn is over and no PR is in progress
RQ="$T/recycle"; mkdir -p "$RQ/state/agent-qc"
echo '{"result":{"workspaces":[{"label":"QC Agent (acme)","workspace_id":"wQ"}]}}' >"$RQ/ws.json"
echo '{"result":{"agents":[{"workspace_id":"wQ","agent":"claude","pane_id":"wQ:p1","agent_status":"idle"}]}}' >"$RQ/agents.json"
R=(env PDO_STATE_DIR="$RQ/state" SMOKE_HERDR_WS="$RQ/ws.json" SMOKE_HERDR_AGENTS="$RQ/agents.json" RECYCLE_SETTLE_SEC=0 AGENT_QC_PORTS=3998)
eq "recycle-agent-qc: AGENT_QC_RECYCLE=0 turns it off" "$("${R[@]}" AGENT_QC_RECYCLE=0 "$BIN/recycle-agent-qc" --project acme)" "recycle is off (AGENT_QC_RECYCLE=0)"
: >"$SMOKE_LOG"; out="$("${R[@]}" "$BIN/recycle-agent-qc" --project acme --foreground)"
check "recycle-agent-qc: idle, nothing in progress -> /exit" grep -qx "herdr agent prompt wQ:p1 /exit" "$SMOKE_LOG"
eq "recycle-agent-qc: ... but an agent that won't exit isn't relaunched" "$(grep -c "pane run" "$SMOKE_LOG")" 0
check "recycle-agent-qc: ... and says so" grep -q "failed: the QC Agent didn't exit" <<<"$out"
: >"$SMOKE_LOG"; out="$("${R[@]}" SMOKE_HERDR_EXIT=1 SMOKE_HERDR_PANE=wQ:p1 DEFAULT_MODEL=opus "$BIN/recycle-agent-qc" --project acme --foreground)"
check "recycle-agent-qc: exits, then relaunches the loop in the same pane" grep -q "herdr pane run wQ:p1 .*claude.*--model.*/loop.*project-agent-qc.*project=acme" "$SMOKE_LOG"
check "start-agent-qc: no remote control for the QC Agent" bash -c "! grep 'herdr pane run wQ:p1' '$SMOKE_LOG' | grep -q -- --remote-control"
check "recycle-agent-qc: ... and logs it" grep -q "QC Agent running in workspace" <<<"$out"
echo '{"repo":"widget","pr":7}' >"$RQ/state/agent-qc/in-progress.json"
: >"$SMOKE_LOG"; out="$("${R[@]}" "$BIN/recycle-agent-qc" --project acme --foreground)"
check "recycle-agent-qc: a PR in progress -> no restart" bash -c '! grep -q "agent prompt" "$0"' "$SMOKE_LOG"
check "recycle-agent-qc: ... and says why" grep -q "skip: a PR is still in progress" <<<"$out"
rm "$RQ/state/agent-qc/in-progress.json"
sed -i 's/"idle"/"working"/' "$RQ/agents.json"
: >"$SMOKE_LOG"; out="$("${R[@]}" "$BIN/recycle-agent-qc" --project acme --foreground)"
check "recycle-agent-qc: still working -> no restart" bash -c '! grep -q "agent prompt" "$0"' "$SMOKE_LOG"
out="$("${R[@]}" SMOKE_HERDR_WS=/dev/null "$BIN/recycle-agent-qc" --project acme --foreground 2>&1)"
check "recycle-agent-qc: no QC Agent tab or workspace -> skip" grep -q "skip: no tab or workspace" <<<"$out"
out="$("${R[@]}" "$BIN/recycle-agent-qc" --project acme)"
check "recycle-agent-qc: detaches by default" grep -q "will restart the QC Agent once this turn ends" <<<"$out"
eq "default state dir" "$(env -u PDO_STATE_DIR "$BIN/pdo-config" --state-dir)" "$T/home/.local/state/project-dev-orchestration"
eq "python state_dir agrees" "$(env -u PDO_STATE_DIR python3 -c "import sys; sys.path.insert(0, '$BIN'); import pdo_config; print(pdo_config.state_dir())")" "$T/home/.local/state/project-dev-orchestration"
eq "python load() agrees" "$(python3 -c "import sys; sys.path.insert(0, '$BIN'); import pdo_config; c = pdo_config.load('acme'); print(c['org'], pdo_config.ref(c, 'widget', 3), pdo_config.ref(c, 'docs', 4))")" "acme #3 docs#4"

# --- project-env ---
cd "$T/repos/widget.git/7-feature"
eq "project-env KEY" "$("$BIN/project-env" PRIMARY_REPO)" widget
eq "project-env map entry" "$("$BIN/project-env" 'REPO_ROOT[docs]')" "$T/repos/docs"
has "project-env all keys" "$("$BIN/project-env")" "REPO_ROOT[widget]=$T/repos/widget.git"
"$BIN/project-env" NO_SUCH_KEY >/dev/null 2>&1; eq "project-env unknown key exits 1" "$?" 1
eq "project-env FIXTURE_EXT_BY_REPO entry" "$("$BIN/project-env" 'FIXTURE_EXT_BY_REPO[docs]')" .dump
eq "project-env AGENT_QC_NOTES_BY_REPO entry" "$("$BIN/project-env" 'AGENT_QC_NOTES_BY_REPO[docs]')" "$T/cfg-a/notes/agent-qc-docs.md"
out="$("$BIN/project-env" --board 2>&1)"
has "project-env --board prints the board node id" "$out" "BOARD_ID=PVT_b7"
has "project-env --board prints Status option ids" "$out" "STATUS_OPTION[Claude Work This]=o2"
out="$("$BIN/project-env" --project beta --board 2>&1)"; has "project-env --board without a board fails clearly" "$out" "no PROJECT_NUMBER"

eq "QC_SKILL default is the human-review skill (renamed from project-qc-review in 0.14)" "$("$BIN/project-env" --project acme QC_SKILL)" "/pdo:project-human-review"
check "the old project-qc-review skill is gone" test ! -e "$ENGINE/skills/project-qc-review"

# --- identity wrapper ---
w="$(cd "$T" && bash -c "source '$BIN/lib.sh'; PROJECT=acme; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; pdo_finalize; identity_wrapper '$T/repos/widget.git'")"
eq "identity: no GH_USER, no hook output = no wrapper" "$w" ""
w="$(cd "$T" && bash -c "source '$BIN/lib.sh'; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; GH_USER=octo; pdo_finalize; identity_wrapper '$T/repos/docs'")"
eq "identity: GH_USER pin + hook word" "$w" "$BIN/with-gh-user --user octo extra-identity"
c="$(cd "$T" && bash -c "source '$BIN/lib.sh'; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; GH_USER=octo; pdo_finalize; agent_command '$T/repos/widget.git' 'Acme-12 x' opus 'do it' --resume s1")"
has "launch command marks the agent dispatched" "$c" "env PDO_DISPATCHED=1 $BIN/with-gh-user --user octo claude --resume s1 --remote-control"
c2="$(cd "$T" && bash -c "source '$BIN/lib.sh'; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; pdo_finalize; PDO_NO_REAP=1 agent_command '$T/repos/widget.git' 'Orchestrator (acme)' opus 'loop'")"
has "PDO_NO_REAP=1 launches exempt from the memory reaper" "$c2" "env PDO_DISPATCHED=1 CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1 "
check "agents launch reapable by default" bash -c "! grep -q DISABLE_BG_SHELL_PRESSURE_REAP <<<'$c'"
check "start-orchestrator launches exempt (ORCHESTRATOR_NO_REAP)" grep -q 'PDO_NO_REAP="$ORCHESTRATOR_NO_REAP" launch_agent' "$BIN/start-orchestrator"
eq "with-gh-user without a login just runs" "$("$BIN/with-gh-user" printenv GH_TOKEN || echo unset)" unset
eq "with-gh-user --user pins GH_TOKEN" "$("$BIN/with-gh-user" --user octo printenv GH_TOKEN)" token-for-octo
cred() { printf 'protocol=https\nhost=github.com\n\n' | GIT_TERMINAL_PROMPT=0 "$@" git credential fill 2>/dev/null | sed -n 's/^password=//p'; }
eq "with-gh-user pins git over HTTPS (gh credential helper)" "$(cred "$BIN/with-gh-user" --user octo)" token-for-octo
eq "with-gh-user without a login adds no git config" "$("$BIN/with-gh-user" printenv GIT_CONFIG_COUNT || echo unset)" unset
out="$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=hookbot "$BIN/with-gh-user" --user octo \
  bash -c 'echo "$GIT_CONFIG_COUNT $GIT_CONFIG_KEY_0 $GIT_CONFIG_KEY_2 $(git config user.name)"')"
eq "with-gh-user appends after existing GIT_CONFIG_* entries" "$out" "3 user.name credential.https://github.com.helper hookbot"
eq "with-gh-user + an outer wrapper's GIT_CONFIG_* still authenticates" \
  "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=hookbot cred "$BIN/with-gh-user" --user octo)" token-for-octo
eq "with-gh-user leaves an outer wrapper's github.com helper in charge" \
  "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.https://github.com.helper GIT_CONFIG_VALUE_0='!f() { cat >/dev/null; echo username=u; echo password=outer; }; f' \
     cred "$BIN/with-gh-user" --user octo)" outer
eq "with-gh-user keeps the outer count when it adds nothing" \
  "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=x "$BIN/with-gh-user" --user octo printenv GIT_CONFIG_COUNT)" 1

# --- every script pins GH_USER (pdo_finalize / pdo_config.load) ---
pin() { (cd "$T" && env "$@" bash -c "source '$BIN/lib.sh'; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; pdo_finalize; echo \"\${GH_TOKEN:-unset} \${PDO_GH_PIN:-unset}\"" 2>&1); }
eq "pin: GH_USER pins GH_TOKEN" "$(pin GH_USER=octo)" "token-for-octo octo"
eq "pin: no GH_USER, no pin" "$(pin)" "unset unset"
eq "pin: a token a person set wins" "$(pin GH_USER=octo GH_TOKEN=mine)" "mine unset"
eq "pin: GITHUB_TOKEN counts as set" "$(pin GH_USER=octo GITHUB_TOKEN=mine)" "unset unset"
eq "pin: another login's engine pin is replaced" "$(pin GH_USER=octo GH_TOKEN=token-for-gbot PDO_GH_PIN=gbot)" "token-for-octo octo"
has "pin: a login gh lacks warns and runs unpinned" "$(pin GH_USER=nobody)" "warning: no gh token for GH_USER=nobody"
eq "pin: git over HTTPS too" "$(cd "$T" && GH_USER=octo bash -c "source '$BIN/lib.sh'; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; pdo_finalize; printf 'protocol=https\nhost=github.com\n\n' | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null | sed -n 's/^password=//p'")" token-for-octo
eq "pin: python load() pins too" "$(cd "$T" && GH_USER=octo python3 -c "import os, sys; sys.path.insert(0, '$BIN'); import pdo_config; pdo_config.load('acme'); print(os.environ['GH_TOKEN'], os.environ['PDO_GH_PIN'], os.environ['GIT_CONFIG_COUNT'])")" "token-for-octo octo 2"
eq "pin: python keeps a person's token with an empty PDO_GH_PIN" "$(cd "$T" && GH_USER=octo GH_TOKEN=mine PDO_GH_PIN= python3 -c "import os, sys; sys.path.insert(0, '$BIN'); import pdo_config; pdo_config.load('acme'); print(os.environ['GH_TOKEN'])")" mine
eq "pin: python keeps a person's token" "$(cd "$T" && GH_USER=octo GH_TOKEN=mine python3 -c "import os, sys; sys.path.insert(0, '$BIN'); import pdo_config; pdo_config.load('acme'); print(os.environ['GH_TOKEN'])")" mine

# --- /project-setup never writes a versioned plugin-cache engine path into AGENTS.md ---
check "AGENTS template: a variant that names no engine path" grep -q '^<!-- pdo-on-PATH variant (names no path): -->$' "$ENGINE/templates/AGENTS-workflow-section.md"
check "setup skill: pdo on PATH = no path; never the plugin cache" grep -q 'no `/plugins/cache/` segment and no version directory' "$ENGINE/skills/project-setup/SKILL.md"

# --- intake inbox ---
out="$("$BIN/intake-submit" "Acme-12 smoke" "a report")"
f="${out#queued for intake: }"
has "intake-submit into the state inbox" "$f" "$T/state/intake-inbox/"
check "intake report written" grep -q "from: Acme-12 smoke" "$f"
out="$(INTAKE_INBOX="$T/legacy-inbox" "$BIN/intake-submit" ws "r2")"; has "INTAKE_INBOX honoured" "$out" "$T/legacy-inbox/"
out="$(INTAKE_INBOX="$T/legacy-inbox" PDO_INBOX="$T/new-inbox" "$BIN/intake-submit" ws "r3")"; has "PDO_INBOX beats INTAKE_INBOX" "$out" "$T/new-inbox/"
echo "" | "$BIN/intake-submit" ws >/dev/null 2>&1; eq "empty report refused" "$?" 1
# the reporting bar: dedup, one report per run, the soft cap
printf 'widget#41\tExport sort ignores facility name casing\n' >"$T/open-issues"
err="$(SMOKE_OPEN_ISSUES="$T/open-issues" PDO_INBOX="$T/bar-inbox" "$BIN/intake-submit" --project acme "Acme-50 a" "## Export sort ignores facility casing [user-visible]" 2>&1 >/dev/null)"
has "intake-submit: warns on a likely duplicate issue" "$err" "possible duplicate of open issue widget#41"
check "intake-submit: records the auto search" grep -q "^checked: auto" "$T"/bar-inbox/*acme-50-a*.md
err="$(PDO_INBOX="$T/bar-inbox" "$BIN/intake-submit" --checked none "Acme-51 b" "## Export sort ignores facility casing [data]" 2>&1 >/dev/null)"
has "intake-submit: warns on a matching pending report" "$err" "a pending report already covers"
check "intake-submit: records --checked" grep -q "^checked: none" "$T"/bar-inbox/*acme-51-b*.md
err="$(PDO_INBOX="$T/bar-inbox" "$BIN/intake-submit" --checked '#9' --append "Acme-51 b" $'## one [data]\n## two\n## three [security]\n## four [edge-case]' 2>&1)"
has "intake-submit: --append adds to the pending report" "$err" "appended to your pending report"
has "intake-submit: soft cap warns past 3" "$err" "4 defects"
has "intake-submit: untagged defect warned" "$err" "no [severity] tag"
eq "intake-submit: --append made no new file" "$(ls "$T/bar-inbox" | grep -c acme-51-b)" 1
err="$(PDO_INBOX="$T/bar-inbox" "$BIN/intake-submit" --checked none "Acme-51 b" "## x [data]" 2>&1 >/dev/null)"
has "intake-submit: a second report hints --append" "$err" "use --append"
PDO_INBOX="$T/bar-inbox" "$BIN/intake-submit" --checked 'maybe' ws "r" >/dev/null 2>&1; eq "intake-submit: bad --checked refused" "$?" 1

# --- herdr-agent draft: a person's unsent text vs Claude Code's dim suggestion ---
R=$'\e[0m' DIM=$'\e[2m' GREY=$'\e[38;2;136;136;136m' RULE="────────────"
printf '%s\n' "${R}${GREY}❯ /reload-plugins${R}" "${R}${GREY}${RULE}${R}" $'❯ '"${R}${DIM}go with your recommendations${R}" "${R}${GREY}${RULE}${R}" "  ${DIM}branch: main${R}" >"$T/screen-ghost"
printf '%s\n' "${R}${GREY}${RULE}${R}" $'❯ '"merge it after lunch${R}" "${R}${GREY}${RULE}${R}" "  ${DIM}branch: main${R}" >"$T/screen-draft"
printf '%s\n' "${R}${GREY}${RULE}${R}" " Which phases first?" $'❯ '"1. Phases 1–3 now (Recommended)${R}" "  2. Phase 1 only" "  3. Type something." "${R}${GREY}${RULE}${R}" " Enter to select · ↑/↓ to navigate · Esc to cancel" >"$T/screen-menu"
eq "draft: a question menu's cursor is not the input box" "$(SMOKE_HERDR_SCREEN="$T/screen-menu" "$BIN/herdr-agent" draft --pane wX:p1; echo $?)" 1
printf '%s\n' "${R}${GREY}${RULE}${R}" $'❯ '"1. merge it after lunch${R}" "${R}${GREY}${RULE}${R}" >"$T/screen-numdraft"
eq "draft: a numbered draft with no menu is still a draft" "$(SMOKE_HERDR_SCREEN="$T/screen-numdraft" "$BIN/herdr-agent" draft --pane wX:p1)" "draft: 1. merge it after lunch"
out="$(SMOKE_HERDR_SCREEN="$T/screen-ghost" "$BIN/herdr-agent" draft --pane wX:p1)"; rc=$?
eq "draft: Claude Code's dim suggestion is not a draft" "$rc" 1
eq "draft: the suggestion is reported as one" "$out" "suggestion: go with your recommendations"
out="$(SMOKE_HERDR_SCREEN="$T/screen-draft" "$BIN/herdr-agent" draft --pane wX:p1)"; rc=$?
eq "draft: a person's unsent text is a draft" "$rc" 0
eq "draft: the draft text" "$out" "draft: merge it after lunch"
eq "draft: unknown agent" "$("$BIN/herdr-agent" draft "Nobody (x)" >/dev/null; echo $?)" 2
echo '{"result":{"workspaces":[{"label":"acme","workspace_id":"wX"}]}}' >"$T/draft-ws.json"
echo '{"result":{"tabs":[{"label":"Orchestrator (acme)","number":1,"workspace_id":"wX","tab_id":"wX:t1"}]}}' >"$T/draft-tabs.json"
echo '{"result":{"agents":[{"agent":"claude","name":"orchestrator-acme","workspace_id":"wX","tab_id":"wX:t1","pane_id":"wX:p1","agent_status":"idle"}]}}' >"$T/draft-agents.json"
out="$(SMOKE_HERDR_WS="$T/draft-ws.json" SMOKE_HERDR_TABS="$T/draft-tabs.json" SMOKE_HERDR_AGENTS="$T/draft-agents.json" SMOKE_HERDR_SCREEN="$T/screen-draft" "$BIN/herdr-agent" draft orchestrator-acme)"
eq "draft: herdr's agent name works too" "$out" "draft: merge it after lunch"

# --- floor ---
eq "floor unset" "$("$BIN/floor")" none
"$BIN/floor" p2 >/dev/null; eq "floor set" "$(cat "$T/state/acme-floor")" P2
eq "floor shown" "$("$BIN/floor" --project acme)" P2
"$BIN/floor" clear >/dev/null; eq "floor cleared" "$("$BIN/floor")" none
"$BIN/floor" P9 >/dev/null 2>&1; eq "bad floor refused" "$?" 1
cd "$T/elsewhere"; "$BIN/floor" >/dev/null 2>&1; eq "floor outside any project fails" "$?" 1
cd "$T/repos/widget.git/7-feature"

# --- rebase-mark ---
"$BIN/rebase-mark" widget-12 >/dev/null; "$BIN/rebase-mark" widget-12 >/dev/null
eq "rebase-mark counts" "$(cat "$T/state/rebase/widget-12")" 2

# --- spawn --dry-run (fake gh: issue 12 is an open Bug) ---
jq -n '{number: 12, state: "open", title: "Fix the widget crash on save", html_url: "https://github.com/acme/widget/issues/12",
  body: "It crashes.", assignees: [], labels: [{name: "P2-high"}], type: {name: "Bug"}}' >"$T/issue12.json"
out="$("$BIN/spawn" widget 12 --dry-run 2>&1)"
eq "spawn dry-run route" "$(jq -r .route <<<"$out" 2>/dev/null)" small
eq "spawn dry-run branch" "$(jq -r .branch <<<"$out" 2>/dev/null)" "fix/12-widget-crash-save"
eq "spawn dry-run worktree" "$(jq -r .worktree <<<"$out" 2>/dev/null)" "$T/repos/widget.git/12-widget-crash-save"
has "spawn dry-run prompt names the skill" "$(jq -r .prompt <<<"$out" 2>/dev/null)" "/pdo:project-small-feature-or-bug-fix Work acme/widget#12"
check "spawn dry-run logged no failure" test ! -e "$T/state/spawn-failures.jsonl"
# BRANCH_PREFIX: issue type, then labels, else default
jq '.type = null | .labels = [{name: "P2-high"}, {name: "Bug"}]' "$T/issue12.json" >"$T/issue12-nt.json"
cp "$T/issue12.json" "$T/issue12-typed.json"; cp "$T/issue12-nt.json" "$T/issue12.json"
eq "no type: the bug label gives fix/" "$("$BIN/spawn" widget 12 --dry-run 2>/dev/null | jq -r .branch)" "fix/12-widget-crash-save"
jq '.labels = [{name: "task"}]' "$T/issue12-nt.json" >"$T/issue12.json"
eq "no type, no mapped label: default feat/" "$("$BIN/spawn" widget 12 --dry-run 2>/dev/null | jq -r .branch)" "feat/12-widget-crash-save"
eq "BRANCH_PREFIX maps a label" "$(BRANCH_PREFIX="bug=fix Task=chore default=feat" "$BIN/spawn" widget 12 --dry-run 2>/dev/null | jq -r .branch)" "chore/12-widget-crash-save"
eq "BRANCH_PREFIX default entry" "$(BRANCH_PREFIX="default=work" "$BIN/spawn" widget 12 --dry-run 2>/dev/null | jq -r .branch)" "work/12-widget-crash-save"
jq '.type = {name: "Feature"} | .labels = [{name: "bug"}]' "$T/issue12-nt.json" >"$T/issue12.json"
eq "the type is matched before labels" "$(BRANCH_PREFIX="feature=feat bug=fix" "$BIN/spawn" widget 12 --dry-run 2>/dev/null | jq -r .branch)" "feat/12-widget-crash-save"
eq "a typed issue's labels are not read (a bug label on a Feature stays feat/)" "$("$BIN/spawn" widget 12 --dry-run 2>/dev/null | jq -r .branch)" "feat/12-widget-crash-save"
echo 'if [[ -n "${SMOKE_LANE:-}" ]]; then declare -A BASE_LANE=([widget:feat/api]="docs" [widget:main]="docs"); fi' >>"$T/cfg-a/projects/acme.env"
# a base:<branch> label spawns on that lane (BASE_LANE), once the branch exists on origin
jq '.labels = [{name: "P2-high"}, {name: "base:feat/api"}]' "$T/issue12-typed.json" >"$T/issue12.json"
has "spawn: a base: label that isn't a BASE_LANE is refused" "$("$BIN/spawn" widget 12 --dry-run 2>&1)" "BASE_LANE has no widget:feat/api"
has "spawn: ... and a lane missing on origin" "$(SMOKE_LANE=1 "$BIN/spawn" widget 12 --dry-run 2>&1)" "no branch feat/api on origin"
git -C "$T/origin.git" branch -q feat/api main
eq "spawn: a lane issue is based on the lane" "$(SMOKE_LANE=1 "$BIN/spawn" widget 12 --dry-run 2>/dev/null | jq -r .base)" "origin/feat/api"
cp "$T/issue12-typed.json" "$T/issue12.json"
cp "$T/issue12-typed.json" "$T/issue12.json"
eq "branch_prefix in the JSON config" "$("$BIN/pdo-config" --project acme --json | jq -c .branch_prefix)" '{"bug":"fix","default":"feat"}'
GH_USER=octo SMOKE_TOKEN_LOG="$T/tokens.log" "$BIN/spawn" widget 12 --dry-run >/dev/null 2>&1
eq "spawn reads the issue as GH_USER (no with-gh-user wrapping)" "$(grep -c '^token-for-octo api repos/acme/widget/issues/12$' "$T/tokens.log")" 1
SMOKE_TOKEN_LOG="$T/tokens-q.log" GH_USER=octo "$BIN/queue" --json >/dev/null 2>&1
eq "queue (python) reads the board as GH_USER" "$(grep -c '^token-for-octo api graphql --paginate -f query=query queueBoard' "$T/tokens-q.log")" 1
"$BIN/spawn" nosuchrepo 12 >/dev/null 2>&1
check "spawn failure is logged" grep -q '"repo":"nosuchrepo"' "$T/state/spawn-failures.jsonl"

# --- WORKTREE_PARENT: the bare root, or "<clone>-worktrees" next to a plain clone ---
eq "worktree parent: bare root / next to a plain clone" "$("$BIN/pdo-config" --project acme --json | jq -c ".worktree_parent | [.widget, .docs]")" "[\"$T/repos/widget.git\",\"$T/repos/docs-worktrees\"]"
eq "project-env WORKTREE_PARENT entry" "$("$BIN/project-env" --project acme 'WORKTREE_PARENT[docs]')" "$T/repos/docs-worktrees"
eq "spawn in a plain clone: the worktree lands outside the checkout" "$("$BIN/spawn" docs 12 --dry-run 2>/dev/null | jq -r .worktree)" "$T/repos/docs-worktrees/12-widget-crash-save"
eq "WORKTREE_PARENT override (~/ expanded)" "$(cd "$T" && bash -c "source '$BIN/lib.sh'; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; declare -A WORKTREE_PARENT=([docs]='~/wt'); pdo_finalize; echo \"\${WORKTREE_PARENT[docs]} \${WORKTREE_PARENT[widget]}\"")" "$HOME/wt $T/repos/widget.git"
has "WORKTREE_PARENT as a scalar is refused" "$(cd "$T" && bash -c "source '$BIN/lib.sh'; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; WORKTREE_PARENT=/x; pdo_finalize" 2>&1)" "WORKTREE_PARENT must be a map"

# --- claim: managed-by label, claim comment, CLAIM_ASSIGNS, release ---
eq "MANAGER_SLUG defaults to a slug of MANAGER" "$("$BIN/project-env" --project acme MANAGER_SLUG)" orchestrator-acme
eq "CLAIM_ASSIGNS defaults to 0" "$("$BIN/project-env" --project acme CLAIM_ASSIGNS)" 0
eq "MANAGER_SLUG override is slugged" "$(MANAGER_SLUG="Gov Team" "$BIN/project-env" --project acme MANAGER_SLUG)" gov-team
eq "claim_label in the JSON config" "$("$BIN/pdo-config" --project acme --json | jq -r .claim_label)" managed-by:orchestrator-acme
: >"$SMOKE_LOG"; rm -f "$T/state/agents/widget-12.json"
out="$("$BIN/claim" widget 12 --agent "widget-12 crash fix" 2>&1)"; rc=$?
eq "claim exit" "$rc" 0
has "claim reports the label and comment" "$out" "managed-by:orchestrator-acme, comment 9001"
check "claim created the missing label with its description" grep -q 'label create managed-by:orchestrator-acme -R acme/widget --color c5def5 --description Worked by agents of Orchestrator (acme)' "$SMOKE_LOG"
check "claim added the label" grep -q 'api repos/acme/widget/issues/12/labels -f labels\[\]=managed-by:orchestrator-acme' "$SMOKE_LOG"
check "claim posted the claim comment" grep -q 'comments -f body=Claimed by widget-12 crash fix (manager: Orchestrator (acme)). Coordinate through that manager' "$SMOKE_LOG"
eq "claim does not self-assign by default" "$(grep -c 'add-assignee' "$SMOKE_LOG")" 0
check "claim set the board Status" grep -q 'updateProjectV2ItemFieldValue' "$SMOKE_LOG"
eq "claim recorded the label and comment id" "$(jq -c '[.claim_label, .claim_comment_id, .claim_released_at]' "$T/state/agents/widget-12.json")" '["managed-by:orchestrator-acme",9001,null]'
: >"$SMOKE_LOG"
CLAIM_ASSIGNS=1 "$BIN/claim" widget 12 >/dev/null 2>&1
check "CLAIM_ASSIGNS=1 self-assigns" grep -q 'issue edit 12 -R acme/widget --add-assignee me' "$SMOKE_LOG"
eq "label exists now: not created twice" "$(grep -c 'label create' "$SMOKE_LOG")" 0
jq -n '{number: 13, state: "open", title: "Held elsewhere", node_id: "I_13", assignees: [], labels: [{name: "managed-by:lib-lead"}]}' >"$T/issue13.json"
out="$("$BIN/claim" widget 13 2>&1)"; rc=$?
eq "claim refuses another manager's label" "$rc" 1
has "claim names the other manager's label" "$out" "held by another manager (managed-by:lib-lead)"
out="$("$BIN/spawn" widget 13 --dry-run 2>&1)"; has "spawn refuses another manager's label" "$out" "held by another manager"
jq -n '{number: 80, state: "open", title: "Blocked epic", node_id: "I_80", assignees: [], labels: []}' >"$T/issue80.json"
out="$("$BIN/spawn" widget 80 --dry-run 2>&1)"; rc=$?
eq "spawn parks an issue with an open blocker (exit 5)" "$rc" 5
has "spawn names the open blocker" "$out" "blocked by acme/widget#5 (open)"
out="$("$BIN/spawn" widget 80 --ignore-blockers --dry-run 2>&1)"; rc=$?
eq "spawn --ignore-blockers passes the blocker check" "$rc" 0
jq -n '{number: 14, state: "open", title: "Mine already", node_id: "I_14", assignees: [{login: "me"}], labels: [{name: "managed-by:orchestrator-acme"}]}' >"$T/issue14.json"
out="$("$BIN/claim" widget 14 2>&1)"; rc=$?
eq "CLAIM_ASSIGNS=0: any assignee is a human lock" "$rc" 1
has "claim says the assignee is a human lock" "$out" "assigned to me (an assignee is a human lock)"
: >"$SMOKE_LOG"
out="$(CLAIM_ASSIGNS=1 "$BIN/claim" widget 14 --keep-status 2>&1)"; rc=$?
eq "CLAIM_ASSIGNS=1: the login's own assignment is the legacy claim" "$rc" 0
eq "re-claim with the label already on posts no second comment" "$(grep -c 'comments -f body=' "$SMOKE_LOG")" 0
eq "--keep-status leaves the board alone" "$(grep -c 'updateProjectV2ItemFieldValue' "$SMOKE_LOG")" 0
: >"$SMOKE_LOG"
out="$("$BIN/claim" --release widget 12 2>&1)"; rc=$?
eq "claim --release exit" "$rc" 0
check "release removed the label" grep -q 'api -X DELETE repos/acme/widget/issues/12/labels/managed-by%3Aorchestrator-acme' "$SMOKE_LOG"
check "release recorded claim_released_at" jq -e '.claim_released_at > 0' "$T/state/agents/widget-12.json"
eq "release keeps the assignee unless --unassign" "$(grep -c 'remove-assignee' "$SMOKE_LOG")" 0
"$BIN/claim" --release widget 12 --unassign >/dev/null 2>&1
check "release --unassign removes the login" grep -q 'remove-assignee me' "$SMOKE_LOG"

# --- python scripts against the fakes ---
out="$("$BIN/queue" --json 2>&1)"; eq "queue (empty board)" "$(jq -c .ranked <<<"$out" 2>/dev/null)" "[]"
out="$(QUEUE_LABEL= "$BIN/queue" --project beta 2>&1)"; has "queue needs a board or a QUEUE_LABEL" "$out" "no PROJECT_NUMBER (board) and no QUEUE_LABEL"
eq "QUEUE_LABEL default" "$("$BIN/project-env" --project beta QUEUE_LABEL)" "queue:work"

# --- deps-link: node_modules from a lockfile-keyed cache ---
D="$T/deps"; mkdir -p "$D" "$T/cfg-d/projects"
printf '%s\n' '#!/usr/bin/env bash' 'echo "$PWD" >>"$SMOKE_NPM_CALLS"; sleep 1; mkdir -p node_modules && echo built >node_modules/marker' >"$T/fakenpm"
chmod +x "$T/fakenpm"; export SMOKE_NPM_CALLS="$T/npm-calls"; : >"$SMOKE_NPM_CALLS"
git init -q -b main "$D/app" && (cd "$D/app" && mkdir web ws && echo '{"name":"app"}' >package.json && echo '{"lockfileVersion":3}' >package-lock.json \
  && echo '{"name":"web"}' >web/package.json && echo '{"lockfileVersion":3,"web":1}' >web/package-lock.json \
  && echo '{"name":"ws","workspaces":["a"]}' >ws/package.json && echo '{"lockfileVersion":3}' >ws/package-lock.json \
  && git add -A && git -c user.email=s@x -c user.name=s commit -qm init)
for w in 1 2 3 4 5; do git -C "$D/app" worktree add -q "$D/wt$w" -b "b$w"; done
printf 'ORG="zeta"\ndeclare -A REPO_ROOT=([app]="%s")\nDEPS_CACHE_DIR="%s"\ndeclare -A DEPS_NPM_CMD=([app]="%s")\n' \
  "$D/app" "$T/depcache" "$T/fakenpm" >"$T/cfg-d/projects/zeta.env"
DL=(env PDO_CONFIG_DIRS="$T/cfg-d" "$BIN/deps-link")
out="$("${DL[@]}" --json "$D/wt1")"
eq "deps-link: builds once per dir and links" "$(jq -c '[.repo, (.dirs[] | "\(.dir):\(.action)")]' <<<"$out")" '["app",".:built-and-linked","web:built-and-linked","ws:skip"]'
has "deps-link: a workspace root is skipped" "$(jq -r '.dirs[2].why' <<<"$out")" "workspace root"
t="$(readlink "$D/wt1/web/node_modules")"
has "deps-link: absolute link into the cache" "$t" "$T/depcache/zeta/app-web/"
eq "deps-link: the entry holds the install" "$(cat "$D/wt1/web/node_modules/marker")" built
out="$("${DL[@]}" --json "$D/wt2")"
eq "deps-link: a second worktree reuses the entry" "$(jq -c '[.dirs[0:2][] | .action]' <<<"$out")" '["linked","linked"]'
eq "deps-link: no second install" "$(grep -c . "$SMOKE_NPM_CALLS")" 2
eq "deps-link: re-run is a no-op" "$("${DL[@]}" --json "$D/wt2" | jq -c '[.dirs[0:2][] | .action]')" '["ok","ok"]'
# a lockfile change: concurrent spawns build the new entry once
for w in 3 4; do echo '{"lockfileVersion":3,"web":2}' >"$D/wt$w/web/package-lock.json"; done
"${DL[@]}" "$D/wt3" >/dev/null & "${DL[@]}" "$D/wt4" >/dev/null; wait
eq "deps-link: concurrent spawns build a new lockfile once (flock)" "$(grep -c . "$SMOKE_NPM_CALLS")" 3
eq "deps-link: both link the new entry" "$(readlink "$D/wt3/web/node_modules")" "$(readlink "$D/wt4/web/node_modules")"
check "deps-link: the old entry is untouched" test "$(readlink "$D/wt1/web/node_modules")" != "$(readlink "$D/wt3/web/node_modules")"
# an old symlink to another worktree's node_modules is migrated; a real dir is kept unless --replace-dir
ln -s "$D/wt1/web/node_modules" "$D/wt5/web/node_modules"; mkdir "$D/wt5/node_modules"
out="$("${DL[@]}" --json "$D/wt5")"
eq "deps-link: migrates an old symlink, keeps a real dir" "$(jq -c '[.dirs[0:2][] | .action]' <<<"$out")" '["kept","linked"]'
eq "deps-link: --replace-dir links over a real dir" "$("${DL[@]}" --json --replace-dir "$D/wt5" | jq -r '.dirs[0].action')" linked
echo '{"lockfileVersion":3,"web":9}' >"$D/wt2/web/package-lock.json"
eq "deps-link: --check builds nothing" "$("${DL[@]}" --check --json "$D/wt2" | jq -r '.dirs[1].action') $(grep -c . "$SMOKE_NPM_CALLS")" "would-build-and-link 3"
# prune: unlinked and old goes, linked stays
git -C "$D/app" worktree remove --force "$D/wt3"; git -C "$D/app" worktree remove --force "$D/wt4"
old="$(dirname "$(readlink "$D/wt1/web/node_modules")")"
gone="$(dirname "$(readlink "$D/wt5/web/node_modules")")"
gone="$(for e in "$T"/depcache/zeta/app-web/*/; do e="${e%/}"; [[ "$e" != "$old" && "$e" != "$gone" ]] && echo "$e"; done | head -1)"
touch -d '30 days ago' "$gone" "$old"
out="$("${DL[@]}" --prune --project zeta --json)"
eq "deps-link --prune: removes the unlinked old entry only" "$(jq -c '[.removed[].path]' <<<"$out")" "[\"$gone\"]"
check "deps-link --prune: a linked entry stays, however old" test -d "$old/node_modules"
check "spawn links deps for the new worktree" grep -q "pdo_deps_link_bg" "$BIN/spawn"
check "resume-agent links deps (migrates old links)" grep -q "pdo_deps_link_bg" "$BIN/resume-agent"

# --- board-less projects: the label queue, and claims without a board ---
mkdir -p "$T/cfg-q/projects"
printf 'ORG="delta"\ndeclare -A REPO_ROOT=([tool]="%s")\n' "$T/repos/docs" >"$T/cfg-q/projects/delta.env"
printf 'ORG="acme"\ndeclare -A REPO_ROOT=([widget]="%s")\n' "$T/repos/widget.git" >"$T/cfg-q/projects/epsilon.env"
dq() { jq -nc --argjson n "$1" --arg t "$2" --argjson l "$3" --argjson d "${4:-{\}}" '{number: $n, title: $t, labels: ($l | map({name: .})), assignees: [],
  type: null, html_url: "h\($n)", url: "u\($n)", created_at: "2026-01-0\($n % 9 + 1)T00:00:00Z", body: "", issue_dependencies_summary: $d}'; }
{ dq 1 "queued P2" '["P2-high","queue:work"]'; dq 2 "unqueued P1" '["P1-urgent"]'
  dq 3 "queued, claimed" '["P1-urgent","Queue:Work","managed-by:other"]'
  dq 24 "unqueued P4 blocker" '["P4-low"]' '{"blocked_by":0,"blocking":1}'
  dq 25 "queued P2, blocked" '["P2-high","queue:work"]' '{"blocked_by":1,"blocking":0}'
  dq 26 "queued P3" '["P3-medium","queue:work"]'
} >"$T/delta-issues.jsonl"
: >"$SMOKE_LOG"
qd="$(PDO_CONFIG_DIRS="$T/cfg-q" "$BIN/queue" --project delta --all --json 2>&1)"
eq "board-less queue: label mode" "$(jq -c '[.mode, .queue_label]' <<<"$qd")" '["label","queue:work"]'
eq "board-less queue: queued work ranked by P-label; a blocker of queued work joins, lifted" "$(jq -c '[.ranked[] | "\(.number):\(.p)"]' <<<"$qd")" '["1:P2","24:P2","26:P3"]'
eq "board-less queue: usual exclusions (label match ignores case)" "$(jq -c '[.excluded[] | "\(.number):\(.excluded | join(","))"]' <<<"$qd")" '["3:managed-by:other","25:blocked-by:1"]'
eq "board-less queue: unqueued work is not listed" "$(jq -c '[.ranked[], .excluded[] | select(.number == 2)] | length' <<<"$qd")" 0
eq "board-less queue: no board read" "$(grep -c 'query queueBoard' "$SMOKE_LOG")" 0
has "board-less queue: summary names the label" "$(PDO_CONFIG_DIRS="$T/cfg-q" "$BIN/queue" --project delta 2>&1)" "board-less: issues labelled queue:work"
eq "QUEUE_LABEL override" "$(PDO_CONFIG_DIRS="$T/cfg-q" QUEUE_LABEL=P3-medium "$BIN/queue" --project delta --json 2>/dev/null | jq -c '[.ranked[].number]')" '[26]'
: >"$SMOKE_LOG"; rm -f "$T/state/agents/widget-12.json" "$T/label-exists"
out="$(PDO_CONFIG_DIRS="$T/cfg-q" "$BIN/claim" widget 12 --project epsilon 2>&1)"; rc=$?
eq "board-less claim: exit" "$rc" 0
has "board-less claim: label, comment, no board" "$out" "(managed-by:epsilon, comment 9001), no board"
check "board-less claim: added the label" grep -q 'api repos/acme/widget/issues/12/labels -f labels\[\]=managed-by:epsilon' "$SMOKE_LOG"
check "board-less claim: posted the claim comment" grep -q 'comments -f body=Claimed by widget-12 (manager: epsilon)' "$SMOKE_LOG"
eq "board-less claim: no board call" "$(grep -c 'graphql' "$SMOKE_LOG")" 0
out="$("$BIN/pr-priority" --dry-run 2>&1)"; has "pr-priority (no PRs)" "$out" "already carry"
check "pr-priority queried only managed + self-managed repos via graphql" grep -q "r=widget" "$SMOKE_LOG"

out="$("$BIN/watch" --peek 2>&1)"
eq "watch --peek snapshot (no agents)" "$(jq -c '[.free_slots, .active, .spawn_floor]' <<<"$out" 2>/dev/null)" '[3,[],"none"]'
has "watch --peek lists the intake inbox" "$(jq -c .waiting_on_you <<<"$out" 2>/dev/null)" '"why":"intake inbox"'
check "watch --peek saved no snapshot" test ! -e "$T/state/acme-watch.json"

# --- qc dispatcher with a fake QC_HOOK ---
out="$("$BIN/qc" start --ref main --fresh-db 2>&1)"; rc=$?
eq "qc start --ref exit" "$rc" 0
has "qc start ran hook wait" "$out" "qc: up (fake)"
check "qc worktree checked out" test -f "$T/repos/widget.git/qc/README.md"
check "qc hook got the key and options" grep -q "hook start --fresh-db pr= ref=main key=ref:main wt=$T/repos/widget.git/qc" "$SMOKE_LOG"
check "qc hook stop ran before start" grep -q "hook stop --fresh-db" "$SMOKE_LOG"
eq "current.json merged hook fields" "$(jq -r '.ref + "/" + .db' "$T/state/qc/current.json")" "main/fake"
out="$("$BIN/qc" status)"; has "qc status shows current" "$out" '"ref":"main"'; has "qc status runs hook" "$out" ":3999 down"
eq "qc stop" "$("$BIN/qc" stop)" "qc: servers stopped"
check "qc stop removed current.json" test ! -e "$T/state/qc/current.json"
check "qc --agent refuses while agent QC is off" bash -c '! "$0/qc" start --ref main --agent' "$BIN"
out="$(AGENT_QC_PORTS="3998 4998" "$BIN/qc" start --ref main --agent 2>&1)"; rc=$?
eq "qc --agent start exit" "$rc" 0
check "qc --agent uses its own worktree" test -f "$T/repos/widget.git/qc-agent/README.md"
check "qc --agent hook told instance and ports" grep -q "hook start pr= ref=main key=ref:main wt=$T/repos/widget.git/qc-agent inst=agent ports=3998 4998" "$SMOKE_LOG"
check "qc --agent state kept apart" test -f "$T/state/agent-qc/current.json"
check "human qc state untouched by --agent" test ! -e "$T/state/qc/current.json"
AGENT_QC_PORTS="3998 4998" "$BIN/qc" stop --agent >/dev/null
# a listener qc didn't start on a QC port (the human's dev server) is never stopped without --force
listen() { (cd "$1" && exec python3 -m http.server "$2" --bind 127.0.0.1 >/dev/null 2>&1) & LPID=$!
  for _ in $(seq 1 50); do ss -ltnH "sport = :$2" | grep -q . && return 0; sleep 0.1; done; }
listen "$T/elsewhere" 3999
out="$("$BIN/qc" start --ref main 2>&1)"; rc=$?
eq "qc start refuses a foreign listener" "$rc" 1
has "qc names the foreign listener" "$out" ":3999 pid $LPID"
has "qc says how to proceed" "$out" "--force"
"$BIN/qc" stop >/dev/null 2>&1; eq "qc stop refuses it too" "$?" 1
eq "QC_PORTS_SHARED=1: qc may stop it" "$(QC_PORTS_SHARED=1 "$BIN/qc" start --ref main >/dev/null 2>&1; echo $?)" 0
eq "--force: qc may stop it" "$("$BIN/qc" start --ref main --force >/dev/null 2>&1; echo $?)" 0
check "--force is not passed to the hook" bash -c '! grep -q "hook start.*--force" "$0"' "$SMOKE_LOG"
eq "qc recorded the listener it started, and the port it held" "$(paste -sd' ' "$T/state/qc/listeners")" "$LPID port:3999"
eq "a listener qc started is its own" "$("$BIN/qc" start --ref main >/dev/null 2>&1; echo $?)" 0
kill $LPID; wait $LPID 2>/dev/null
(cd "$T/elsewhere" && bash -c 'python3 -m http.server 3999 --bind 127.0.0.1 >/dev/null 2>&1; :' 2>/dev/null) & PPID_REC=$!
for _ in $(seq 1 50); do ss -ltnH "sport = :3999" | grep -q . && break; sleep 0.1; done
echo "$PPID_REC" >"$T/state/qc/listeners"
eq "a child of a listener qc started is qc's" "$("$BIN/qc" stop >/dev/null 2>&1; echo $?)" 0
{ kill $(ss -ltnpH "sport = :3999" | grep -o 'pid=[0-9]*' | cut -d= -f2); wait "$PPID_REC"; } 2>/dev/null
listen "$T/repos/widget.git/qc" 3999
rm -f "$T/state/qc/listeners"
eq "a listener running in the QC worktree is qc's" "$("$BIN/qc" stop >/dev/null 2>&1; echo $?)" 0
kill $LPID; wait $LPID 2>/dev/null
out="$("$BIN/qc" start --ref main --repo docs 2>&1)"; rc=$?
eq "qc for a plain clone: exit" "$rc" 0
check "qc for a plain clone: worktree next to the clone" test -f "$T/repos/docs-worktrees/qc/README.md"
check "qc for a plain clone: nothing inside the checkout" test ! -e "$T/repos/docs/qc"
"$BIN/qc" stop >/dev/null 2>&1
eq "QC_PORTS_SHARED default" "$("$BIN/project-env" --project acme QC_PORTS_SHARED)" 0

# --- qc-fixture-push against the local origin ---
echo data >"$T/sample.acme"
out="$("$BIN/qc-fixture-push" 5 "$T/sample.acme" 2>&1)"
has "fixture URL printed" "$out" "https://github.com/acme/widget/blob/qc-fixtures/5/sample.acme"
check "fixture on the origin branch" git -C "$T/origin.git" cat-file -e qc-fixtures:5/sample.acme
has "fixture download link is a release asset" "$out" "download: https://github.com/acme/widget/releases/download/qc-fixtures-assets/5-sample.acme"
check "fixture release created as a prerelease" grep -q "release create qc-fixtures-assets -R acme/widget --target qc-fixtures --prerelease" "$SMOKE_LOG"
check "fixture asset uploaded under <pr#>-<name>" grep -q "release upload qc-fixtures-assets .*/5-sample.acme -R acme/widget --clobber" "$SMOKE_LOG"
has "fixture README uses FIXTURE_EXT" "$(git -C "$T/origin.git" show qc-fixtures:README.md)" "<name>.acme"
echo other >"$T/other.bin"
out="$("$BIN/qc-fixture-push" 5 "$T/other.bin" 2>&1)"; has "fixture extension warning" "$out" "does not end in .acme"
eq "re-push unchanged" "$("$BIN/qc-fixture-push" 5 "$T/sample.acme" 2>/dev/null | head -1)" unchanged
out="$(SMOKE_UPLOAD_FAIL=1 "$BIN/qc-fixture-push" 5 "$T/sample.acme" 2>&1)"
has "a failed asset upload warns and falls back to raw" "$out" "link the raw URL instead"
eq "no download link when the upload failed" "$(grep -c "^download:" <<<"$out")" 0
echo dump >"$T/seed.dump"
out="$("$BIN/qc-fixture-push" 6 "$T/seed.dump" --repo docs 2>&1)"
has "fixture for a second repo uses its FIXTURE_EXT_BY_REPO" "$out" "https://github.com/acme/docs/blob/qc-fixtures/6/seed.dump"
eq "no warning for the second repo's own format" "$(grep -c warning <<<"$out")" 0
out="$("$BIN/qc-fixture-push" 6 "$T/sample.acme" --repo docs 2>&1)"; has "per-repo format warning names the repo" "$out" "does not end in .dump (docs's fixture format)"

# --- fleet: two more projects in their own config dir and state dir ---
FC="$T/fleet-cfg" FS="$T/fleet-state"
mkdir -p "$FC/projects" "$FS/agents" "$FS/inbox"
cat >"$FC/projects/alpha.env" <<EOF
ORG="alpha"
PROJECT_NUMBER=9
declare -A REPO_ROOT=([tool]="$T/repos/docs")
MANAGER="Orchestrator (alpha)"
PORTFOLIO_PRIORITY=1
RESOURCE_PROFILE=heavy
FLEET_ADVICE="\${SMOKE_FLEET_ADVICE:-ignore}"
EOF
cat >"$FC/projects/gamma.env" <<EOF
ORG="gamma"
declare -A REPO_ROOT=([lib]="$T/repos/widget.git")
SELF_MANAGED_REPOS=(lib)
declare -A REPO_MANAGER=([lib]="Lib Lead")
MANAGER="Gamma Lead"
PORTFOLIO_PRIORITY=2
RESOURCE_PROFILE=light
GH_USER=gbot
EOF
iss() { jq -nc --argjson n "$1" --arg t "$2" --arg l "$3" '{number: $n, title: $t, labels: [{name: $l}], assignees: [],
  type: {name: "Task"}, html_url: "https://github.com/alpha/tool/issues/\($n)", url: "https://api.github.com/repos/alpha/tool/issues/\($n)",
  created_at: "2026-01-0\($n)T00:00:00Z", body: "", issue_dependencies_summary: {}}'; }
{ iss 1 "ordinary work" P2-high; iss 2 "urgent work" P1-urgent
  # 21: another manager's claim; 22: this project's own claim; 23: natively blocked by two open issues
  jq -nc '{number: 21, title: "held by another team", labels: [{name: "P2-high"}, {name: "managed-by:docs-team"}], assignees: [], type: {name: "Task"},
    html_url: "h21", url: "u21", created_at: "2026-01-01T00:00:00Z", body: "", issue_dependencies_summary: {}}'
  jq -nc '{number: 22, title: "ours in progress", labels: [{name: "P2-high"}, {name: "managed-by:orchestrator-alpha"}], assignees: [], type: {name: "Task"},
    html_url: "h22", url: "u22", created_at: "2026-01-01T00:00:00Z", body: "", issue_dependencies_summary: {}}'
  jq -nc '{number: 23, title: "natively blocked", labels: [{name: "P2-high"}], assignees: [], type: {name: "Task"},
    html_url: "h23", url: "u23", created_at: "2026-01-01T00:00:00Z", body: "", issue_dependencies_summary: {blocked_by: 2, blocking: 0}}'
} >"$T/alpha-issues.jsonl"
jq -n '{data: {repository: {pullRequests: {totalCount: 2, nodes: [
  {number: 10, title: "agent three", url: "https://github.com/alpha/tool/pull/10", isDraft: false, headRefName: "feat/3", labels: {nodes: [{name: "ready for QC"}]}},
  {number: 11, title: "agent four", url: "https://github.com/alpha/tool/pull/11", isDraft: false, headRefName: "feat/4", labels: {nodes: [{name: "Ready for Merge"}]}}]},
  gates: {nodes: [{number: 6, title: "a prototype", url: "https://github.com/alpha/tool/issues/6"}]},
  claims: {nodes: [
    {name: "managed-by:orchestrator-alpha", issues: {totalCount: 3, nodes: [
      {number: 4, title: "live agent", url: "u4"}, {number: 3, title: "hibernated agent", url: "u3"}, {number: 30, title: "agent gone", url: "u30"}]}},
    {name: "managed-by:docs-team", issues: {totalCount: 1, nodes: [{number: 31, title: "theirs", url: "u31"}]}}]}}}}' >"$T/fleet-tool.json"
echo '{"repo":"tool","number":3,"name":"tool-3 agent three","branch":"feat/3","hibernated_at":1700000000}' >"$FS/agents/tool-3.json"
echo '{"result":{"workspaces":[{"label":"Orchestrator (alpha)","workspace_id":"wA","agent_status":"idle"},{"label":"tool-4 other work","workspace_id":"wB","agent_status":"blocked"},{"label":"lib-5 owned work","workspace_id":"wC","agent_status":"working"}]}}' >"$T/herdr-ws.json"
echo '{"result":{"agents":[{"agent":"claude","name":null,"workspace_id":"wA","pane_id":"wA:p1","agent_status":"idle"},{"agent":"claude","name":"tool-4","workspace_id":"wB","pane_id":"wB:p1","agent_status":"blocked"},{"agent":"claude","name":"lib-5","workspace_id":"wC","pane_id":"wC:p1","agent_status":"working"}]}}' >"$T/herdr-agents.json"
echo r >"$FS/inbox/one.md"
F=(env PDO_CONFIG_DIRS="$FC" PDO_STATE_DIR="$FS" PDO_INBOX="$FS/inbox" SMOKE_HERDR_WS="$T/herdr-ws.json" SMOKE_HERDR_AGENTS="$T/herdr-agents.json"
   PDO_FLEET_WEEKLY=10 PDO_FLEET_FIVE_HOUR=5 PDO_FLEET_DISK_FREE_MB=100000 PDO_FLEET_SWAP_TOTAL_MB=0 PDO_FLEET_SWAP_USED_MB=0)

eq "project-env MANAGER" "$("${F[@]}" "$BIN/project-env" --project gamma MANAGER)" "Gamma Lead"
eq "project-env REPO_MANAGER entry" "$("${F[@]}" "$BIN/project-env" --project gamma 'REPO_MANAGER[lib]')" "Lib Lead"
eq "default MANAGER with a board" "$("$BIN/project-env" --project acme MANAGER)" "Orchestrator (acme)"
eq "default MANAGER without a board" "$("$BIN/project-env" --project beta MANAGER)" ""
eq "portfolio env key defaults" "$("$BIN/pdo-config" --project acme --json | jq -c '[.portfolio_priority, .resource_profile, .fleet_advice]')" '[3,"medium","ignore"]'

out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" --json 2>&1)"
eq "fleet: both projects" "$(jq -c '[.projects[].project]' <<<"$out" 2>/dev/null)" '["alpha","gamma"]'
eq "fleet: plenty of room = go" "$(jq -c '[.advice.alpha.advice, .advice.gamma.advice]' <<<"$out" 2>/dev/null)" '["go","go"]'
eq "fleet: alpha manager live" "$(jq -r '.projects[0].manager | "\(.live) \(.status)"' <<<"$out" 2>/dev/null)" "true idle"
has "fleet: gamma manager not running" "$(jq -r '.projects[1].manager.reach' <<<"$out" 2>/dev/null)" "not running"
eq "fleet: REPO_MANAGER for a self-managed repo" "$(jq -c '.projects[1].self_managed' <<<"$out" 2>/dev/null)" '[{"repo":"lib","manager":"Lib Lead"}]'
eq "fleet: active / hibernated agents" "$(jq -c '.projects[0].agents | [(.active | map(.agent)), (.hibernated | map(.agent + ":" + (.open_pr | tostring)))]' <<<"$out" 2>/dev/null)" '[["tool#4"],["tool#3:true"]]'
eq "fleet: queue depth" "$(jq -c '.projects[0].queue | [.eligible, .urgent]' <<<"$out" 2>/dev/null)" '[2,1]'
has "fleet: a project with no queue is reported, not fatal" "$(jq -r '.projects[1].queue.error' <<<"$out" 2>/dev/null)" "every repo is self-managed"
eq "fleet: PRs vs cap" "$(jq -c '.projects[0].prs | [.open, .awaiting_human, .cap]' <<<"$out" 2>/dev/null)" '[2,2,10]'
eq "fleet: waiting on you ranked by impact" "$(jq -c '[.waiting_on_you[].why]' <<<"$out" 2>/dev/null)" '["merge (QC passed)","UX gate","question","QC","intake inbox"]'
eq "fleet: rate limits per GH_USER identity" "$(jq -c '[.system.gh[] | "\(.user)=\(.graphql.remaining)"]' <<<"$out" 2>/dev/null)" '["(active gh account)=4000","gbot=4000"]'
eq "fleet: agent count" "$(jq -c '.system.agents | [.herdr_total, .claude, .project_active, .self_managed_active]' <<<"$out" 2>/dev/null)" '[3,3,1,1]'
eq "fleet: a self-managed repo's agent is not in the project's active" "$(jq -c '.projects[1].agents | [(.active | length), (.self_managed | map(.agent + ":" + .owner))]' <<<"$out" 2>/dev/null)" '[0,["lib#5:Lib Lead"]]'
eq "fleet: ... nor in its advice" "$(jq -r '.advice.gamma.active' <<<"$out" 2>/dev/null)" 0
eq "fleet: ... but in its memory estimate" "$(jq -r '.projects[1].est_agent_mb' <<<"$out" 2>/dev/null)" 400
has "fleet text: self-managed line names the owner" "$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" --project gamma 2>/dev/null)" "self-managed (owner: Lib Lead) 1 live: lib-5 owned work"
check "fleet: gbot's calls used its own token" grep -q "gh auth token -u gbot" "$SMOKE_LOG"
# a self-managed repo that another project runs with its own orchestrator belongs to that project
ME="$T/cfg-me"; mkdir -p "$ME/projects"; cp "$FC/projects/gamma.env" "$ME/projects/"
printf 'ORG="gamma"\ndeclare -A REPO_ROOT=([lib]="%s")\nMANAGER="Lib Lead"\nCONFLICT_RESOLUTION=merge\n' "$T/repos/widget.git" >"$ME/projects/libteam.env"
eq "managed_elsewhere: lib is libteam's now, not gamma's" "$(PDO_CONFIG_DIRS="$ME" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import pdo_config as c; print(sorted(c.managed_elsewhere(c.try_load("gamma")[0])), sorted(c.managed_elsewhere(c.try_load("libteam")[0])))' "$BIN")" "['lib'] []"
eq "CONFLICT_RESOLUTION: merge, default rebase" "$(PDO_CONFIG_DIRS="$ME" "$BIN/pdo-config" --project libteam --json | jq -r .conflict_resolution) $(PDO_CONFIG_DIRS="$ME" "$BIN/pdo-config" --project gamma --json | jq -r .conflict_resolution)" "merge rebase"
# ... and the old manager's in-flight agents stay its own until their claim is handed over
eq "watch: per-repo slots: each repo its own cap; full repos' queue rows don't auto-spawn" "$(python3 - "$BIN/watch" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
ag = {f"a#{i}": {"repo": "a"} for i in range(3)} | {"b#1": {"repo": "b"}, "c#1": {"repo": "c"}}
active = list(ag)
w.CFG.update(max_active=None, max_active_per_repo=3, max_active_by_repo={"c": 1})
sl = w.repo_slots(ag, active, {"a", "b", "c"})
print(sl, w.free_slots(ag, active, {"a", "b", "c"}, sl))
w.CFG["max_active"] = 4; w.MAX_ACTIVE = 4
print(w.free_slots(ag, active, {"a", "b", "c"}, sl))
w.CFG.update(max_active=None, max_active_per_repo=None, max_active_by_repo={}); w.MAX_ACTIVE = 3
print(w.repo_slots(ag, active, {"a", "b"}), w.free_slots(ag, active, {"a", "b"}, {}))
q = w.mark_pr_capped([{"repo": "a", "auto_spawn": True}, {"repo": "b", "auto_spawn": True}], {"capped": []}, {"a"})
print([(r["repo"], r["auto_spawn"], r.get("repo_full")) for r in q],
      [(r["repo"], r["auto_spawn"], r.get("repo_full")) for r in w.mark_pr_capped(q, {"capped": []}, set())])
PY
)" "{'a': {'active': 3, 'max': 3, 'free': 0}, 'b': {'active': 1, 'max': 3, 'free': 2}, 'c': {'active': 1, 'max': 1, 'free': 0}} 2
0
{} 0
[('a', False, True), ('b', True, None)] [('a', True, None), ('b', True, None)]"
eq "watch: lane PRs, agents and issues count against the lane's bucket repo" "$(python3 - "$BIN/watch" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
w.CFG.update(base_lane={"api:feat/x": "cli"}, max_active=None, max_active_per_repo=2, max_active_by_repo={})
ag = {"api#1": {"repo": "api"}, "api#2": {"repo": "api", "lane": "feat/x"}, "api#3": {"repo": "api", "lane": "feat/x"}}
sl = w.repo_slots(ag, list(ag), {"api", "cli"}); print(sl)
q = w.mark_pr_capped([{"repo": "api", "auto_spawn": True}, {"repo": "api", "base": "feat/x", "auto_spawn": True}], {"capped": []}, {k for k, v in sl.items() if v["free"] == 0})
print([(r.get("base"), r["auto_spawn"]) for r in q])
w.AWAITING_HUMAN = {"ready for QC"}
w.PR_INDEX = {("api", "a"): {"state": "OPEN", "labels": ["ready for QC"], "base": "main"},
              ("api", "b"): {"state": "OPEN", "labels": ["ready for QC"], "base": "feat/x"}}
w.STATE_DIR = "/nonexistent"
print(w.pr_cap("acme", "o", {"api", "cli"})["by_repo"])
import pdo_config as c
print(c.lane_label(["P2-high", "base:feat/x"]), c.lane_label(["P2"]), c.lane_bucket(w.CFG, "api", "origin/feat/x"), c.lane_bucket(w.CFG, "api", "main"))
w.CFG.update(base_lane={}, max_active_per_repo=None)
PY
)" "{'api': {'active': 1, 'max': 2, 'free': 1}, 'cli': {'active': 2, 'max': 2, 'free': 0}}
[(None, True), ('feat/x', False)]
{'api': 1, 'cli': 1}
feat/x None cli api"
LR="$T/lane-origin.git"; git init -q --bare "$LR"; LC="$T/lane-clone"; git clone -q "$LR" "$LC" 2>/dev/null
git -C "$LC" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one; git -C "$LC" push -q origin HEAD:refs/heads/feat/x 2>/dev/null
printf '#!/usr/bin/env bash\necho "$@" >"%s/lane-hook-ran"\n' "$T" >"$T/lane-hook"; chmod +x "$T/lane-hook"
eq "watch: a lane's first head is recorded; a move fires lane_moved and starts LANE_HOOK" "$(python3 - "$BIN/watch" "$LC" "$T" <<'PY'
import importlib.machinery, importlib.util, subprocess, sys, time, os
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
w.CFG.update(base_lane={"api:feat/x": "cli"}, repo_root={"api": sys.argv[2]}, lane_hook=sys.argv[3] + "/lane-hook")
w.STATE_DIR = sys.argv[3] + "/lanestate"
cur = {}; print(w.lanes_moved("acme", {}, cur), sorted(cur["lanes"]))
prev = cur; first = cur["lanes"]["api:feat/x"]
g = ["git", "-C", sys.argv[2], "-c", "user.email=t@t", "-c", "user.name=t"]
subprocess.run(g + ["commit", "-q", "--allow-empty", "-m", "two"], check=True)
subprocess.run(["git", "-C", sys.argv[2], "push", "-q", "origin", "HEAD:refs/heads/feat/x"], check=True, capture_output=True)
cur = {}; ev = w.lanes_moved("acme", prev, cur)
print([(e["type"], e["branch"], e["prev"] == first, e["quiet"]) for e in ev], w.lanes_moved("acme", cur, {}))
for _ in range(50):
    if os.path.exists(sys.argv[3] + "/lane-hook-ran"): break
    time.sleep(0.1)
print(open(sys.argv[3] + "/lane-hook-ran").read().split()[:2])
w.CFG.update(base_lane={}, lane_hook="")
PY
)" "[] ['api:feat/x']
[('lane_moved', 'feat/x', True, True)] []
['api', 'feat/x']"
# lane-merge: only into a BASE_LANE branch, only after agent QC passed
lane_pr() { printf '{"number":501,"title":"G1 gap","state":"OPEN","isDraft":false,"baseRefName":"%s","headRefOid":"abc","mergeable":"%s","labels":[%s],"url":"u"}' "$1" "$2" "$3" >"$T/lane-pr.json"; }
lane_try() { local out rc; out="$(SMOKE_LANE=1 "$BIN/lane-merge" widget 501 --project acme 2>&1)"; rc=$?; echo "$rc ${out#lane-merge: refused: }"; }
eq "BASE_LANE in the config" "$(SMOKE_LANE=1 "$BIN/pdo-config" --project acme | jq -cS .base_lane)" '{"widget:feat/api":"docs","widget:main":"docs"}'
lane_pr feat/other MERGEABLE '{"name":"Ready for Merge"}'
has "lane-merge: refuses a base that isn't a lane" "$(lane_try)" "3 #501's base is feat/other, not a lane branch"
lane_pr main MERGEABLE '{"name":"Ready for Merge"}'
has "lane-merge: refuses the default branch, even listed as a lane" "$(lane_try)" "3 #501 targets the default branch (main)"
lane_pr feat/api MERGEABLE '{"name":"ready for QC"}'
has "lane-merge: refuses before agent QC passed" "$(lane_try)" "3 #501's agent QC hasn't passed"
lane_pr feat/api MERGEABLE '{"name":"QC complete - ready to review"},{"name":"QC escalated"}'
has "lane-merge: refuses an escalated PR" "$(lane_try)" "3 #501's agent QC hasn't passed"
lane_pr feat/api CONFLICTING '{"name":"Ready for Merge"}'
has "lane-merge: refuses an unmergeable PR" "$(lane_try)" "3 #501 isn't mergeable (CONFLICTING)"
lane_pr feat/api MERGEABLE '{"name":"QC complete - ready to review"}'
: >"$SMOKE_LOG"; out="$(lane_try)"
has "lane-merge: merges into the lane, named as the Design Lead's merge" "$out" '0 {"merged": "u", "into": "feat/api", "subject": "Design Lead merge: G1 gap (#501)"}'
check "lane-merge: ... a merge commit pinned to the checked head" grep -q "gh pr merge 501 -R acme/widget --merge --subject Design Lead merge: G1 gap (#501) --match-head-commit abc" "$SMOKE_LOG"
check "lane-merge: ... and says so on the PR" grep -q "gh pr comment 501 -R acme/widget --body \*\*Design Lead merge\*\* into" "$SMOKE_LOG"
eq "watch: another manager's live claim is left alone; a released or own claim is not" "$(python3 - "$BIN/watch" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
w.CFG.update(claim_label="managed-by:libteam")
print([w.foreign_claim(m) for m in ({"claim_label": "managed-by:gamma"}, {"claim_label": "managed-by:gamma", "claim_released_at": 1},
                                    {"claim_label": "Managed-by:LibTeam"}, {})])
w.CFG["claim_label"] = None
print(w.foreign_claim({"claim_label": "managed-by:gamma"}))
PY
)" "[True, False, False, False]
False"
# the watcher's idle reasons and long stalls; a hibernated self-managed agent is counted apart
echo '{"agents":{"tool#4":{"idle_reason":"unpushed","idle_hours":30,"stalled_long":true,"git_hold":"8 commits not pushed to the PR branch"}}}' >"$FS/alpha-watch.json"
echo '{"repo":"lib","number":8,"name":"lib-8 parked","branch":"feat/8","hibernated_at":1700000000}' >"$FS/agents/lib-8.json"
out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" --json 2>/dev/null)"
eq "fleet: idle reason per agent" "$(jq -c '[.projects[0].agents.idle[] | "\(.agent):\(.why):\(.hours)"]' <<<"$out")" '["tool#4:unpushed:30"]'
eq "fleet: a long stall leads the waiting list's second rank" "$(jq -c '[.waiting_on_you[] | select(.why | startswith("stalled")) | "\(.why) \(.item)"]' <<<"$out")" '["stalled 30h (unpushed) tool-4 other work"]'
eq "fleet: hibernated self-managed agents counted apart" "$(jq -c '[(.projects[1].agents.self_managed_hibernated | map(.agent + ":" + .owner)), (.projects[1].agents.hibernated | length), .system.agents.self_managed_hibernated]' <<<"$out")" '[["lib#8:Lib Lead"],0,1]'
has "fleet text: the idle line" "$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" --project alpha 2>/dev/null)" "idle: tool-4 other work (unpushed, 30h)"
rm -f "$FS/alpha-watch.json" "$FS/agents/lib-8.json"
eq "fleet: claimed count per manager" "$(jq -c '[.claims[] | "\(.slug)=\(.count):\(.manager)"]' <<<"$out" 2>/dev/null)" '["orchestrator-alpha=3:Orchestrator (alpha)","docs-team=1:null"]'
eq "fleet: a claim with no live or in-progress agent is stale" "$(jq -c '[.stale_claims[] | "\(.project):\(.ref)"]' <<<"$out" 2>/dev/null)" '["alpha:alpha/tool#30"]'
eq "fleet: project claims" "$(jq -c '.projects[0].claims | [.label, (.claimed | length), .stale_known]' <<<"$out" 2>/dev/null)" '["managed-by:orchestrator-alpha",3,true]'
eq "fleet: native cross-repo dependencies (same-repo edges left to the project)" "$(jq -c '[.native_deps[] | "\(.blocker)>\(.blocked)"]' <<<"$out" 2>/dev/null)" '["gamma/lib#7>alpha/tool#1","gamma/lib#9>alpha/tool#12"]'
txt="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" 2>/dev/null)"
has "fleet text: stale claim with the release command" "$txt" "STALE claim: [alpha] alpha/tool#30 agent gone - no live or in-progress agent (pdo claim --release tool 30 --project alpha)"
has "fleet text: another manager's claims" "$txt" "managed-by:docs-team 1: (another manager: not in this install)"
has "fleet text: GitHub-only native dependency" "$txt" "gamma/lib#9 blocks alpha/tool#12 [GitHub only]"
out2="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 SMOKE_HERDR_FAIL=1 "$BIN/fleet" --json 2>/dev/null)"
eq "fleet: no herdr = stale claims unknown, none flagged" "$(jq -c '[(.stale_claims | length), .projects[0].claims.stale_known]' <<<"$out2" 2>/dev/null)" '[0,false]'
qx="$("${F[@]}" "$BIN/queue" --project alpha --all --json 2>/dev/null)"
eq "queue: another manager's label excludes" "$(jq -c '[.excluded[] | select(.number == 21) | .excluded[]]' <<<"$qx")" '["managed-by:docs-team"]'
eq "queue: our own label is claimed" "$(jq -c '[.excluded[] | select(.number == 22) | .excluded[]]' <<<"$qx")" '["claimed"]'
eq "queue: native blocked-by names the open blockers" "$(jq -c '[.excluded[] | select(.number == 23) | .excluded[]]' <<<"$qx")" '["blocked-by:tool#9,gamma/lib#7"]'
eq "queue: still ranks the unclaimed, unblocked work" "$(jq -c '[.ranked[].number]' <<<"$qx")" '[2,1]'

check "fleet without --write-advice writes nothing" test ! -e "$FS/fleet-advice.json"

out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=2000 "$BIN/fleet" --json 2>/dev/null)"
eq "fleet: low memory holds heavy, slows the rest" "$(jq -c '[.advice.alpha.advice, .advice.gamma.advice]' <<<"$out" 2>/dev/null)" '["hold","slow"]'
has "fleet: hold reason names memory" "$(jq -r .advice.alpha.reason <<<"$out" 2>/dev/null)" "heavy project"
out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 PDO_FLEET_WEEKLY=95 "$BIN/fleet" --json 2>/dev/null)"
eq "fleet: weekly over ceiling = only P1" "$(jq -c '[.advice.alpha.advice, .advice.gamma.advice]' <<<"$out" 2>/dev/null)" '["go","hold"]'
out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=3900 "$BIN/fleet" --json 2>/dev/null)"
eq "fleet: memory budget goes by priority and profile MB" "$(jq -c '[.advice.alpha.advice, .advice.alpha.suggested_max_active, .advice.gamma.advice, .advice.gamma.suggested_max_active]' <<<"$out" 2>/dev/null)" '["slow",2,"slow",0]'
out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 PDO_FLEET_DISK_FREE_MB=1000 "$BIN/fleet" --json 2>/dev/null)"
eq "fleet: low disk holds" "$(jq -r .advice.gamma.advice <<<"$out" 2>/dev/null)" hold

out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 SMOKE_HERDR_FAIL=1 SMOKE_GH_RATE_FAIL=1 "$BIN/fleet" 2>&1)"; rc=$?
eq "fleet: herdr and gh failures don't crash" "$rc" 0
has "fleet: herdr failure is a warning" "$out" "herdr: workspace/agent list failed"
has "fleet: gh failure is a warning" "$out" "gh: rate_limit unavailable"
out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" --project gamma --json 2>/dev/null)"
eq "fleet --project limits the sections" "$(jq -c '[.projects[].project, (.advice | keys)]' <<<"$out" 2>/dev/null)" '["gamma",["alpha","gamma"]]'
"${F[@]}" "$BIN/fleet" --project nope >/dev/null 2>&1; eq "fleet --project unknown fails" "$?" 1

# cross-project dependencies
: >"$SMOKE_LOG"
eq "deps add (native)" "$("${F[@]}" "$BIN/fleet" deps add alpha/tool#5 blocks gamma/lib#7 --note "needs the API")" "added #1: alpha/tool#5 blocks gamma/lib#7 (native)"
check "deps add: native blocked_by takes the blocker's numeric issue id" grep -q "api -X POST repos/gamma/lib/issues/7/dependencies/blocked_by -F issue_id=5005" "$SMOKE_LOG"
err="$("${F[@]}" "$BIN/fleet" deps add alpha/tool#8 blocks gamma/lib#7 2>&1 >/dev/null)"
has "deps add: a PR blocker falls back with a warning" "$err" "native dependency not added (alpha/tool#8 is a pull request"
check "deps add: the fallback comments on the blocked issue" grep -q "api repos/gamma/lib/issues/7/comments -f body=\*\*Coordination (CEO):\*\* Blocked by alpha/tool#8" "$SMOKE_LOG"
eq "deps add: an existing native link counts as added" "$("${F[@]}" "$BIN/fleet" deps add gamma/lib#7 blocks alpha/tool#1 --as "Lib Lead" 2>/dev/null)" "added #3: gamma/lib#7 blocks alpha/tool#1 (native)"
eq "deps: native flag recorded" "$("${F[@]}" "$BIN/fleet" deps list --json | jq -c 'map("\(.id):\(.native):\(.by)")')" '["1:true:CEO","2:false:CEO","3:true:Lib Lead"]'
has "deps add duplicate" "$("${F[@]}" "$BIN/fleet" deps add alpha/tool#5 blocks gamma/lib#7)" "already recorded"
"${F[@]}" "$BIN/fleet" deps add "tool#5" blocks gamma/lib#7 >/dev/null 2>&1; eq "deps add rejects a bare ref" "$?" 1
has "deps list" "$("${F[@]}" "$BIN/fleet" deps list)" "#1 alpha/tool#5 blocks gamma/lib#7 [native]  - needs the API"
out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" --json 2>/dev/null)"
eq "fleet flags closed and merged blockers" "$(jq -c '[.deps[] | "\(.id):\(.blocker_state)"]' <<<"$out" 2>/dev/null)" '["1:closed","2:merged","3:open"]'
has "fleet text says mark done" "$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" 2>/dev/null)" "blocker CLOSED: mark done (pdo fleet deps done 1)"
eq "deps done by pair" "$("${F[@]}" "$BIN/fleet" deps done alpha/tool#5 blocks gamma/lib#7)" "done #1: alpha/tool#5 blocks gamma/lib#7"
check "deps done removes the native link" grep -q "api -X DELETE repos/gamma/lib/issues/7/dependencies/blocked_by/5005" "$SMOKE_LOG"
eq "deps done by id" "$("${F[@]}" "$BIN/fleet" deps done 2)" "done #2: alpha/tool#8 blocks gamma/lib#7"
check "deps done on a fallback dependency posts the matching comment" grep -q "No longer blocked by alpha/tool#8" "$SMOKE_LOG"
eq "deps list shows open only" "$("${F[@]}" "$BIN/fleet" deps list --json | jq -c 'map(.id)')" "[3]"
eq "deps list --all" "$("${F[@]}" "$BIN/fleet" deps list --all --json | jq -c 'map(.id)')" "[1,2,3]"
"${F[@]}" "$BIN/fleet" deps done 2 >/dev/null 2>&1; eq "deps done twice fails" "$?" 1
out="$("${F[@]}" "$BIN/fleet" note alpha/tool#1 "alpha ships the API first; gamma starts after" 2>&1)"
has "fleet note posts and prints the link" "$out" "noted on alpha/tool#1 (CEO): https://"
check "fleet note heads the comment" grep -q "api repos/alpha/tool/issues/1/comments -f body=\*\*Coordination (CEO):\*\* alpha ships the API first" "$SMOKE_LOG"
"${F[@]}" "$BIN/fleet" note gamma/lib#7 "hand-off agreed" --as "Gamma Lead" >/dev/null 2>&1
check "fleet note --as names the manager" grep -q "body=\*\*Coordination (Gamma Lead):\*\* hand-off agreed" "$SMOKE_LOG"
eq "fleet note logs locally" "$(jq -sc 'map(select(.kind == "note") | .by)' "$FS/coordination-log.jsonl")" '["CEO","Gamma Lead"]'
"${F[@]}" "$BIN/fleet" note "tool#1" "x" >/dev/null 2>&1; eq "fleet note rejects a bare ref" "$?" 1

# the advice file, and queue / watch honouring it
"${F[@]}" PDO_FLEET_MEM_AVAIL_MB=2000 "$BIN/fleet" --write-advice >/dev/null 2>&1
eq "fleet --write-advice" "$(jq -r .projects.alpha.advice "$FS/fleet-advice.json" 2>/dev/null)" hold
qa() { "${F[@]}" "$@" "$BIN/queue" --project alpha --json 2>/dev/null; }
out="$(qa SMOKE_FLEET_ADVICE=ignore)"
eq "queue ignores advice by default" "$(jq -c '[.ranked[] | "\(.number):\(.auto_spawn)"]' <<<"$out")" '["2:true","1:true"]'
eq "queue reports advisory advice" "$(jq -c '[.fleet.advice, .fleet.honoured, .max_active]' <<<"$out")" '["hold",false,3]'
out="$(qa SMOKE_FLEET_ADVICE=honour)"
eq "queue honours hold; urgent bypass still wins" "$(jq -c '[.ranked[] | "\(.number):\(.auto_spawn):\(.fleet_hold)"]' <<<"$out")" '["2:true:false","1:false:true"]'
eq "queue: suggested_max_active bounds max_active" "$(jq -c '[.fleet.honoured, .max_active]' <<<"$out")" '[true,1]'
out="$("${F[@]}" SMOKE_FLEET_ADVICE=honour "$BIN/queue" --project alpha 2>/dev/null)"
has "queue summary shows the advice" "$out" "fleet: hold, max 1"
has "queue marks fleet-held rows" "$out" "(fleet hold)"
out="$("${F[@]}" SMOKE_FLEET_ADVICE=honour "$BIN/watch" --project alpha --peek 2>/dev/null)"
eq "watch: honoured advice bounds the slots" "$(jq -c '[.max_active, .free_slots, .fleet.advice]' <<<"$out" 2>/dev/null)" '[1,0,"hold"]'
jq '.generated_at -= 3 * 3600' "$FS/fleet-advice.json" >"$FS/x.json" && mv "$FS/x.json" "$FS/fleet-advice.json"
out="$(qa SMOKE_FLEET_ADVICE=honour)"
eq "queue ignores stale advice" "$(jq -c '[.fleet, .max_active, ([.ranked[].auto_spawn] | all)]' <<<"$out")" '[null,3,true]'

# --- watch: label-based QC pass, review-based feedback, WATCH_EVENT_HOOK ---
NOW_ISO="$(date -u +%FT%TZ)"; OLD_ISO="$(date -u -d '-2 hours' +%FT%TZ)"
mkprs() {  # mkprs <labels json array> <reviews json array>
  jq -n --argjson l "$1" --argjson r "$2" '{data: {repository: {open: {nodes: [{number: 5, state: "OPEN", isDraft: false,
    url: "https://github.com/acme/widget/pull/5", headRefName: "feat/5", headRefOid: "abc123", baseRefName: "main",
    mergeable: "MERGEABLE", labels: {nodes: ($l | map({name: .}))}, reviews: {nodes: $r}}]}, done: {nodes: []}}}}'
}
REVS="$(jq -nc --arg now "$NOW_ISO" --arg old "$OLD_ISO" '[
  {databaseId: 801, url: "https://github.com/acme/widget/pull/5#r801", body: "Button is misaligned", submittedAt: $now, authorAssociation: "MEMBER", author: {login: "boss"}},
  {databaseId: 802, url: "u", body: "drive-by", submittedAt: $now, authorAssociation: "NONE", author: {login: "rando"}},
  {databaseId: 803, url: "u", body: "", submittedAt: $now, authorAssociation: "OWNER", author: {login: "boss"}},
  {databaseId: 800, url: "u", body: "old review", submittedAt: $old, authorAssociation: "OWNER", author: {login: "boss"}}]')"
mkprs '["ready for QC"]' "$REVS" >"$T/prs.json"
WS="$T/watch-state"; mkdir -p "$WS/agents"
# a hibernated agent on widget#5 (branch feat/5) is tracked without herdr, so qc_complete can fire for it
jq -n '{repo: "widget", number: 5, name: "widget-5 thing", branch: "feat/5", hibernated_at: 1, session_id: "s5"}' >"$WS/agents/widget-5.json"
W() { PDO_STATE_DIR="$WS" SMOKE_PRS="$T/prs.json" "$BIN/watch" --project acme "$@" 2>"$T/watch.err"; }
# a closed-out agent whose issue still carries the claim label: the watcher releases it once
jq -n '{repo: "widget", number: 6, name: "widget-6 done", branch: "feat/6", hibernated_at: 1, closed_out: true, done_tracking: true,
  claim_label: "managed-by:orchestrator-acme"}' >"$WS/agents/widget-6.json"
: >"$SMOKE_LOG"
W >/dev/null   # first run: baseline
check "watch: releases a finished agent's claim label" grep -q "api -X DELETE repos/acme/widget/issues/6/labels/managed-by%3Aorchestrator-acme" "$SMOKE_LOG"
check "watch: records the release" jq -e '.claim_released_at > 0' "$WS/agents/widget-6.json"
: >"$SMOKE_LOG"; W >/dev/null
eq "watch: releases once" "$(grep -c 'issues/6/labels' "$SMOKE_LOG")" 0
# rewind the review cursor so the reviews above count as new; the old one stays before it
jq --arg s "$(date -u -d '-1 hour' +%FT%TZ)" '.review_since = $s | .review_seen = []' "$WS/acme-watch.json" >"$WS/x" && mv "$WS/x" "$WS/acme-watch.json"
out="$(W)"
eq "watch: trusted CHANGES_REQUESTED reviews become qc_feedback" "$(jq -c '[.events[] | select(.type == "qc_feedback") | "\(.repo)#\(.number):\(.id):\(.author):\(.source)"]' <<<"$out" 2>/dev/null)" '["widget#5:801:boss:review","widget#5:803:boss:review"]'
has "watch: an empty review body points at the inline comments" "$(jq -r '.events[] | select(.id == 803) | .body' <<<"$out" 2>/dev/null)" "inline comments"
eq "watch: no comment polling or label edits left in the engine" "$(grep -c 'issues/comments\|pr edit\|pr comment' "$SMOKE_LOG")" 0
out="$(W)"
eq "watch: a review is raised once" "$(jq -c '[.events[] | select(.type == "qc_feedback")] | length' <<<"$out" 2>/dev/null)" 0
eq "watch: waiting on QC while 'ready for QC'" "$(jq -c '[.waiting_on_you[] | select(.agent == "widget#5") | .why]' <<<"$out" 2>/dev/null)" '["QC"]'
# the human's pass: add 'QC complete - ready to review' (here without removing 'ready for QC')
mkprs '["ready for QC","QC complete - ready to review"]' '[]' >"$T/prs.json"
out="$(W)"
eq "watch: the QC done label is the pass (qc_complete)" "$(jq -c '[.events[] | select(.type == "qc_complete") | .agent]' <<<"$out" 2>/dev/null)" '["widget#5"]'
eq "watch: a passed PR no longer waits on QC" "$(jq -c '[.waiting_on_you[] | select(.agent == "widget#5")] | length' <<<"$out" 2>/dev/null)" 0
out="$(W)"
eq "watch: qc_complete fires once" "$(jq -c '[.events[] | select(.type == "qc_complete")] | length' <<<"$out" 2>/dev/null)" 0
eq "watch: human_queue lists the UX review" "$(jq -c .human_queue.ux_review <<<"$out" 2>/dev/null)" '[{"pr":"widget#5","url":"https://github.com/acme/widget/pull/5"}]'
# the human's UX pass: QC complete -> Ready for Merge prompts nobody again
mkprs '["Ready for Merge"]' '[]' >"$T/prs.json"
out="$(W)"
eq "watch: the UX pass (QC complete -> Ready for Merge) fires no qc_complete" "$(jq -c '[.events[] | select(.type == "qc_complete")] | length' <<<"$out" 2>/dev/null)" 0
eq "watch: Ready for Merge counts toward the PR cap" "$(jq -c .pr_cap.open_awaiting_human <<<"$out" 2>/dev/null)" 1
eq "watch: human_queue lists Ready for Merge" "$(jq -c '[.human_queue.ready_for_merge[].pr]' <<<"$out" 2>/dev/null)" '["widget#5"]'
eq "watch: the PR cap counts per repo" "$(jq -c '[.pr_cap.by_repo, .pr_cap.capped, .pr_cap.reached]' <<<"$out" 2>/dev/null)" '[{"widget":1},[],false]'
echo 1 >"$WS/acme-pr-cap"; out="$(W)"
eq "watch: a repo at its cap: pr_cap_reached names it" "$(jq -c '[.events[] | select(.type == "pr_cap_reached") | "\(.repo):\(.open_awaiting_human)/\(.cap)"]' <<<"$out" 2>/dev/null)" '["widget:1/1"]'
eq "watch: every repo capped: no free slots" "$(jq -c '[.pr_cap.reached, .free_slots]' <<<"$out" 2>/dev/null)" '[true,0]'
out="$(W)"; eq "watch: pr_cap_reached fires once per repo" "$(jq -c '[.events[] | select(.type == "pr_cap_reached")] | length' <<<"$out" 2>/dev/null)" 0
rm -f "$WS/acme-pr-cap"; out="$(W)"
eq "watch: a repo dropping under its cap frees slots" "$(jq -c '[.events[] | select(.type == "slot_freed")] | length' <<<"$out" 2>/dev/null)" 1
eq "watch: queue rows of a capped repo are held, and recover" "$(python3 - "$BIN/watch" <<'PY'
import importlib.machinery, importlib.util, json, sys
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
q = [{"repo": "widget", "auto_spawn": True}, {"repo": "gizmo", "auto_spawn": True}, {"repo": "widget", "auto_spawn": False}]
held = w.mark_pr_capped(q, {"capped": ["widget"]})
back = w.mark_pr_capped(held, {"capped": []})
print(json.dumps([[r["auto_spawn"] for r in held], [bool(r.get("pr_capped")) for r in held], [r["auto_spawn"] for r in back],
                  any("pr_capped" in r or "auto_spawn_uncapped" in r for r in back)], separators=(",", ":")))
PY
)" '[[false,true,false],[true,false,true],[true,true,false],false]'
# tmp-sweep: stale profiles, finished and orphaned scratchpads, old cache files go; in-use, fresh and home-dir ones stay
C="$TMP_SWEEP_ROOT/claude-$(id -u)"; S1="$C/-x-widget-5/s-live"; S2="$C/-x-widget-6/s-done"; S3="$C/-x-widget-7/s-old"
HS="$C/$(tr / - <<<"$HOME")/s-home"
mkdir -p "$S1/scratchpad/stale/Default" "$S1/scratchpad/busy" "$S1/scratchpad/fresh" "$S2/scratchpad" "$S3" "$HS/scratchpad/prof" "$TMP_SWEEP_ROOT/jest_rs/a"
touch "$S1/scratchpad/stale/Default/Preferences" "$S1/scratchpad/busy/Local State" "$S1/scratchpad/fresh/Local State" \
  "$S1/notes.md" "$S2/scratchpad/brief.md" "$S3/old.txt" "$HS/scratchpad/prof/Local State" "$TMP_SWEEP_ROOT/jest_rs/a/new"
touch -d '2 hours ago' "$S1/scratchpad/stale" "$S1/scratchpad/stale/Default" "$S1/scratchpad/stale/Default/Preferences" \
  "$S1/scratchpad/busy" "$S1/scratchpad/busy/Local State" "$HS/scratchpad/prof" "$HS/scratchpad/prof/Local State"
touch -d '3 days ago' "$TMP_SWEEP_ROOT/jest_rs/a/old"
touch -d '10 days ago' "$S3/old.txt" "$S3"
echo '{"repo":"widget","number":60,"session_id":"s-done","done_tracking":true}' >"$WS/agents/widget-60.json"
(exec -a "chrome --user-data-dir=$S1/scratchpad/busy" sleep 30) & BUSY=$!
sleep 0.2
out="$(PDO_STATE_DIR="$WS" "$BIN/tmp-sweep" --project acme --json)"
kill $BUSY 2>/dev/null; wait $BUSY 2>/dev/null
eq "tmp-sweep: removes stale profile, finished and orphaned sessions, old cache files" \
  "$(jq -c '[.removed[].why] | sort' <<<"$out" 2>/dev/null)" '["browser profile","finished agent","jest_rs cache (files > 1 day)","untouched 7+ days"]'
eq "tmp-sweep: keeps in-use and fresh profiles, notes, new cache files, home-dir sessions" \
  "$(for f in "$S1/scratchpad/busy" "$S1/scratchpad/fresh" "$S1/notes.md" "$TMP_SWEEP_ROOT/jest_rs/a/new" "$HS/scratchpad/prof" "$S1/scratchpad/stale" "$S2" "$S3"; do [[ -e $f ]] && printf 1 || printf 0; done)" "11111000"
out="$(PDO_STATE_DIR="$WS" "$BIN/tmp-sweep" --project acme --session s-live --json)"
eq "tmp-sweep --session: a just-stopped session's profiles go at once" "$(jq -c '[.removed[].path | sub(".*/"; "")] | sort' <<<"$out")" '["busy","fresh"]'
# an agent with an open PR keeps its scratchpad (even untouched 7+ days), but not its idle profiles; --whole clears an ended session
S4="$C/-x-widget-61/s-pr"; S5="$C/-x-widget-62/s-gone"; S6="$C/-x-orch/s-qc"
mkdir -p "$S4/scratchpad/prof" "$S5" "$S6/scratchpad/prof"
touch "$S4/notes.md" "$S4/scratchpad/prof/Local State" "$S5/old.txt" "$S6/scratchpad/prof/Local State"
touch -d '10 days ago' "$S4/notes.md" "$S4/scratchpad/prof/Local State" "$S4/scratchpad/prof" "$S4/scratchpad" "$S4" "$S5/old.txt" "$S5"
echo '{"repo":"widget","number":61,"branch":"feat/61","session_id":"s-pr","hibernated_at":1}' >"$WS/agents/widget-61.json"
echo '{"repo":"widget","number":62,"branch":"feat/62","session_id":"s-gone","hibernated_at":1}' >"$WS/agents/widget-62.json"
out="$(PDO_STATE_DIR="$WS" "$BIN/tmp-sweep" --project acme --json)"
eq "tmp-sweep: open-PR agent keeps its scratchpad, loses its idle profile; no-PR agent ages out" \
  "$(for f in "$S4/notes.md" "$S4/scratchpad/prof" "$S5"; do [[ -e $f ]] && printf 1 || printf 0; done)" "100"
PDO_STATE_DIR="$WS" "$BIN/tmp-sweep" --project acme --session s-pr --whole --json >/dev/null
out="$(PDO_STATE_DIR="$WS" "$BIN/tmp-sweep" --project acme --session s-qc --whole --json)"
eq "tmp-sweep --whole: an ended session goes, an open-PR agent's stays" \
  "$(jq -r '.removed[].why' <<<"$out"; for f in "$S6" "$S4/notes.md"; do [[ -e $f ]] && printf 1 || printf 0; done)" "ended session
01"
rm -f "$WS/agents/widget-61.json" "$WS/agents/widget-62.json"
eq "watch: wrap-up or rebase marker counts as finished" "$(python3 - "$BIN/watch" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
print([w.finished_marker(t) for t in ("x\nWrap-up done", "pushed\nrebase done", "Rebased onto main @ abc; idle")])
PY
)" '[True, True, False]'
eq "watch: a wrap-up marker closes out without the idle grace; others still wait" "$(python3 - "$BIN/watch" <<'PY'
import importlib.machinery, importlib.util, sys, types
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
w.subprocess.run = lambda *a, **k: types.SimpleNamespace(returncode=0, stdout="ok", stderr="")
def agent(n, labels, done, status="idle", mins=0):
    return {"repo": "widget", "number": n, "status": status, "question_pending": False, "session_id": "s",
            "unchanged_min": mins, "wrapup_done": done, "pr": {"state": "OPEN", "labels": labels}}
ag = {"a": agent(1, [w.QC_DONE], True), "b": agent(2, [w.QC_DONE], True, status="working"),
      "c": agent(3, [w.QC_READY], False), "d": agent(4, [w.QC_DONE], False), "e": agent(5, [w.QC_READY], False, mins=9)}
print(sorted((e["agent"], e["type"]) for e in w.auto_hibernate("acme", ag)))
PY
)" "[('a', 'closed_out'), ('e', 'hibernated')]"
eq "watch: idle reasons and long stalls" "$(python3 - "$BIN/watch" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
def agent(labels=(), state="OPEN", status="idle", mins=60, **kw):
    a = {"status": status, "question_pending": False, "unchanged_min": mins, "issue_state": "open",
         "pr": {"state": state, "labels": list(labels)} if state else None}
    a.update(kw); w.classify(a); return a
cases = [agent(status="working"), agent(question_pending=True), agent(state="MERGED"),
         agent(state=None, issue_state="closed"), agent(git_hold="2 commits not pushed to the PR branch"),
         agent(ux_gate=True), agent([w.QC_READY]), agent([w.QC_DONE]), agent([w.MERGE_READY]),
         agent([w.QC_ESCALATED]), agent(state=None, likely_fixed=True), agent(state=None, on_hold=True),
         agent(state=None, stalled=True), agent()]
print([a["idle_reason"] for a in cases])
long = [agent(state=None, stalled=True, mins=24 * 60), agent(git_hold="1 commit not pushed", mins=24 * 60),
        agent([w.QC_READY], mins=48 * 60), agent(state=None, stalled=True, mins=23 * 60),
        agent(state=None, question_pending=True, mins=48 * 60), agent(state="MERGED", mins=48 * 60)]
print([a["stalled_long"] for a in long])
prev = {"agents": {}, "queue": [], "pr_cap": {}}
cur = {"agents": {"x#1": dict(long[1], repo="x", number=1, parked=False, merged=False, stalled=False, workspace="x-1 w", design_ready=False)},
       "self_managed_agents": {"g#2": dict(long[0], repo="g", workspace="g-2 w")},
       "queue": [], "pr_cap": {}, "usage_over_ceiling": False, "free_slots": 0}
print(sorted((e["type"], e["agent"], bool(e.get("quiet"))) for e in w.events(prev, cur) if e["type"] == "stalled_long"))
print([e["type"] for e in w.events(cur, cur) if e["type"] == "stalled_long"])
PY
)" "[None, 'question', 'finished-should-close', 'finished-should-close', 'unpushed', 'UX gate', 'waiting on QC', 'waiting on UX review', 'waiting on merge', 'QC escalated', 'confirm likely-fixed', 'on hold', 'stalled', 'idle']
[True, True, False, False, False, False]
[('stalled_long', 'g#2', True), ('stalled_long', 'x#1', False)]
[]"
eq "watch: self-managed agents are closed out and paused, never parked" "$(python3 - "$BIN/watch" <<'PY'
import importlib.machinery, importlib.util, sys, types
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
w.subprocess = types.SimpleNamespace(run=lambda *a, **k: types.SimpleNamespace(returncode=0, stdout="ok", stderr=""))
w.CFG["repo_manager"] = {"gov": "Repo Manager (gov)"}
def agent(n, state, labels=(), issue="open"):
    return {"repo": "gov", "number": n, "status": "idle", "question_pending": False, "session_id": "s", "unchanged_min": 30,
            "wrapup_done": False, "issue_state": issue, "pr": {"state": state, "labels": list(labels)} if state else None}
ag = {"m": agent(1, "MERGED"), "q": agent(2, "OPEN", [w.QC_READY]), "c": agent(3, None, issue="closed"),
      "a": dict(agent(4, None), ux_gate=True, unchanged_min=61), "b": dict(agent(5, None), question_pending=True, status="blocked", unchanged_min=61),
      "d": dict(agent(6, None), question_pending=True, status="blocked")}
print(sorted((e["agent"], e["type"], e["owner"]) for e in w.auto_hibernate("acme", ag, closeout_only=True)))
PY
)" "[('a', 'paused', 'Repo Manager (gov)'), ('b', 'paused', 'Repo Manager (gov)'), ('c', 'closed_out', 'Repo Manager (gov)'), ('m', 'closed_out', 'Repo Manager (gov)')]"
# feedback took the pass labels off; agent QC escalates; then a direct no-UX pass fires once
mkprs '["QC escalated"]' '[]' >"$T/prs.json"
out="$(W)"
eq "watch: QC escalated waits on the human" "$(jq -c '[.waiting_on_you[] | select(.agent == "widget#5") | .why]' <<<"$out" 2>/dev/null)" '["QC escalated"]'
mkprs '["Ready for Merge","UX testing skipped"]' '[]' >"$T/prs.json"
out="$(W)"
eq "watch: Ready for Merge as the first pass fires qc_complete" "$(jq -c '[.events[] | select(.type == "qc_complete") | .label]' <<<"$out" 2>/dev/null)" '["Ready for Merge"]'
eq "watch: human_queue marks UX skipped" "$(jq -c '[.human_queue.ready_for_merge[].ux_skipped]' <<<"$out" 2>/dev/null)" '[true]'
# with agent QC on, 'ready for QC' is the QC Agent's queue, not the human's
mkprs '["ready for QC"]' '[]' >"$T/prs.json"
out="$(AGENT_QC_PORTS="3998 4998" W)"
eq "watch: agent QC on: ready for QC leaves waiting_on_you" "$(jq -c '[.waiting_on_you[] | select(.agent == "widget#5")] | length' <<<"$out" 2>/dev/null)" 0
eq "watch: agent QC on: human_queue.agent_qc" "$(jq -c '[.human_queue.agent_qc[].pr]' <<<"$out" 2>/dev/null)" '["widget#5"]'

# WATCH_EVENT_HOOK: context in, events out, merged; quiet ones ride along
cat >"$T/hook-ok" <<'EOF'
#!/usr/bin/env bash
cat >"$SMOKE_DIR/hook-ctx.json"
echo "peek=${PDO_WATCH_PEEK:-}" >>"$SMOKE_LOG"
echo '[{"type":"qc_feedback","repo":"widget","number":5,"id":77,"author":"boss","url":"u","body":"from the hook"},{"type":"hook_note","quiet":true,"detail":"x"},"junk",{"notype":1}]'
EOF
printf '#!/usr/bin/env bash\necho nope >&2; exit 3\n' >"$T/hook-fail"
printf '#!/usr/bin/env bash\nsleep 5; echo []\n' >"$T/hook-slow"
printf '#!/usr/bin/env bash\necho "not json"\n' >"$T/hook-bad"
chmod +x "$T/hook-ok" "$T/hook-fail" "$T/hook-slow" "$T/hook-bad"
jq '.event_since = null | .qc_since = "2026-01-02T03:04:05Z"' "$WS/acme-watch.json" >"$WS/x" && mv "$WS/x" "$WS/acme-watch.json"
LEGACY="$(jq -r .qc_since "$WS/acme-watch.json")"
out="$(WATCH_EVENT_HOOK="$T/hook-ok" W)"; rc=$?
eq "watch hook: exit 0" "$rc" 0
eq "watch hook: wake events merged" "$(jq -c '[.events[] | select(.type == "qc_feedback") | .id]' <<<"$out" 2>/dev/null)" '[77]'
eq "watch hook: quiet events ride along" "$(jq -c '[.events[] | select(.quiet == true) | .type]' <<<"$out" 2>/dev/null)" '["hook_note"]'
has "watch hook: malformed events dropped with a warning" "$(cat "$T/watch.err")" "dropped 2 malformed"
eq "watch hook: context keys" "$(jq -c '[.org, .repos, .trusted_associations, .labels.qc_ready, .peek]' "$T/hook-ctx.json" 2>/dev/null)" '["acme",["widget"],["COLLABORATOR","MEMBER","OWNER"],"ready for QC",false]'
eq "watch hook: context PR index has labels and heads" "$(jq -c '[.prs[] | "\(.repo)#\(.number):\(.head):\(.head_sha)"]' "$T/hook-ctx.json" 2>/dev/null)" '["widget#5:feat/5:abc123"]'
has "watch hook: the legacy cursor seeds since (clamped to 7 days)" "$(jq -r .since "$T/hook-ctx.json")" "$(date -u -d '-7 days' +%F)"
SINCE1="$(jq -r .event_since "$WS/acme-watch.json")"
check "watch hook: a clean run advances event_since" test "$SINCE1" != null -a "$SINCE1" != "$LEGACY"
out="$(WATCH_EVENT_HOOK="$T/hook-ok" PDO_STATE_DIR="$WS" SMOKE_PRS="$T/prs.json" "$BIN/watch" --project acme --peek 2>/dev/null)"
# the rate guard reads GraphQL's own rateLimit (the login's enforced bucket), not REST rate_limit
WR="$T/watch-rate"; cp -r "$WS" "$WR"
PDO_STATE_DIR="$WR" SMOKE_PRS="$T/prs.json" "$BIN/watch" --project acme >/dev/null 2>&1
eq "watch: no rateLimit in the PR query falls back to a GraphQL rateLimit read" "$(jq -c .github.graphql_left "$WR/acme-watch.json")" 4000
jq '.data.rateLimit = {remaining: 120}' "$T/prs.json" >"$T/prs-low.json"
PDO_STATE_DIR="$WR" SMOKE_PRS="$T/prs-low.json" "$BIN/watch" --project acme >/dev/null 2>&1
eq "watch: the PR query's rateLimit sets graphql_left and rate_low" "$(jq -c '[.github.graphql_left, .github.rate_low]' "$WR/acme-watch.json")" "[120,true]"
eq "watch hook: --peek tells the hook" "$(jq -c .peek "$T/hook-ctx.json")" true
check "watch hook: --peek sets PDO_WATCH_PEEK" grep -q "peek=1" "$SMOKE_LOG"
for h in fail slow bad; do
  out="$(WATCH_EVENT_HOOK="$T/hook-$h" WATCH_EVENT_HOOK_TIMEOUT=1 W)"; rc=$?
  eq "watch hook ($h): no crash" "$rc" 0
  eq "watch hook ($h): event_hook_failed (quiet)" "$(jq -c '[.events[] | .type]' <<<"$out" 2>/dev/null)" '["event_hook_failed"]'
  eq "watch hook ($h): event_since kept" "$(jq -r .event_since "$WS/acme-watch.json")" "$SINCE1"
done
has "watch hook: failures warn on stderr" "$(cat "$T/watch.err")" "WATCH_EVENT_HOOK"
out="$(WATCH_EVENT_HOOK="$T/missing-hook" W)"
eq "watch hook: a missing hook is a warning" "$(jq -c '[.events[] | .type]' <<<"$out" 2>/dev/null)" '["event_hook_failed"]'
eq "project-env prints WATCH_EVENT_HOOK" "$(WATCH_EVENT_HOOK=hooks/x "$BIN/project-env" --project acme WATCH_EVENT_HOOK)" "$T/cfg-a/hooks/x"

# --- herdr layouts: one tab per agent in its manager's home, old one-workspace-per-agent, mixed ---
HL="$T/layout"; mkdir -p "$HL"
# home "acme" (tabs: Orchestrator, widget-7) + an old-layout workspace widget-5 + intake on its own
echo '{"result":{"workspaces":[{"label":"acme","workspace_id":"wH","agent_status":"blocked"},{"label":"widget-5 old fix","workspace_id":"wO","agent_status":"idle"},{"label":"intake","workspace_id":"wI","agent_status":"idle"}]}}' >"$HL/ws.json"
echo '{"result":{"tabs":[{"label":"Orchestrator (acme)","number":1,"tab_id":"wH:t1","workspace_id":"wH","agent_status":"idle"},{"label":"widget-7 tabbed fix","number":2,"tab_id":"wH:t2","workspace_id":"wH","agent_status":"blocked"},{"label":"1","number":1,"tab_id":"wO:t1","workspace_id":"wO","agent_status":"idle"},{"label":"1","number":1,"tab_id":"wI:t1","workspace_id":"wI","agent_status":"idle"},{"label":"2","number":2,"tab_id":"wI:t2","workspace_id":"wI","agent_status":"unknown"}]}}' >"$HL/tabs.json"
echo '{"result":{"agents":[{"agent":"claude","name":"orchestrator-acme","workspace_id":"wH","tab_id":"wH:t1","pane_id":"wH:p1","agent_status":"idle"},{"agent":"claude","name":"widget-7","workspace_id":"wH","tab_id":"wH:t2","pane_id":"wH:p2","agent_status":"blocked"},{"agent":"claude","name":"widget-5","workspace_id":"wO","tab_id":"wO:t1","pane_id":"wO:p1","agent_status":"idle"},{"agent":"claude","name":"intake","workspace_id":"wI","tab_id":"wI:t1","pane_id":"wI:p1","agent_status":"idle"}]}}' >"$HL/agents.json"
L=(env SMOKE_HERDR_WS="$HL/ws.json" SMOKE_HERDR_TABS="$HL/tabs.json" SMOKE_HERDR_AGENTS="$HL/agents.json")
eq "layout: find a tab agent by its tab label" "$("${L[@]}" "$BIN/herdr-agent" find "widget-7 tabbed fix" | jq -c '[.layout, .workspace, .tab_id, .pane_id, .status]')" '["tab","acme","wH:t2","wH:p2","blocked"]'
eq "layout: find an old-layout agent by its workspace label" "$("${L[@]}" "$BIN/herdr-agent" find "widget-5 old fix" | jq -c '[.layout, .tab_id, .pane_id]')" '["workspace","wO:t1","wO:p1"]'
eq "layout: the manager is tab 1 of its home" "$("${L[@]}" "$BIN/herdr-agent" find "Orchestrator (acme)" | jq -c '[.layout, .tab_id]')" '["tab","wH:t1"]'
eq "layout: names = tab labels + old workspace labels, not the home or unnamed extra tabs" "$("${L[@]}" "$BIN/herdr-agent" names | LC_ALL=C sort | paste -sd'|')" 'Orchestrator (acme)|intake|widget-5 old fix|widget-7 tabbed fix'
check "layout: an unknown name is not found" bash -c "! ${L[*]} '$BIN/herdr-agent' find 'widget-9 nothing'"
: >"$SMOKE_LOG"
"${L[@]}" "$BIN/herdr-agent" close "widget-7 tabbed fix"
check "layout: closing a tab agent closes only its tab" grep -qx "herdr tab close wH:t2" "$SMOKE_LOG"
"${L[@]}" "$BIN/herdr-agent" close "widget-5 old fix"
check "layout: closing an old-layout agent closes its (only) tab" grep -qx "herdr tab close wO:t1" "$SMOKE_LOG"
eq "layout: nothing ever closes a workspace" "$(grep -c 'workspace close' "$SMOKE_LOG")" 0
: >"$SMOKE_LOG"
eq "layout: place in an existing home = a new tab there" "$("${L[@]}" "$BIN/herdr-agent" place acme "widget-8 new fix" /tmp | jq -c '[.workspace_id, .tab_id, .pane_id, .home]')" '["wH","wH:t9","wH:p9","acme"]'
check "layout: the new tab carries the agent's name" grep -q "herdr tab create --workspace wH --cwd /tmp --label widget-8 new fix --no-focus" "$SMOKE_LOG"
: >"$SMOKE_LOG"
eq "layout: place in a missing home creates it, this agent as tab 1" "$("${L[@]}" SMOKE_HERDR_NEW=wD "$BIN/herdr-agent" place docs "Repo Manager (docs)" /tmp | jq -c '[.workspace_id, .tab_id, .pane_id]')" '["wD","wD:t1","wD:p1"]'
check "layout: the new home is labelled with its name" grep -q "herdr workspace create --cwd /tmp --label docs --no-focus" "$SMOKE_LOG"
check "layout: its first tab is renamed to the agent" grep -qx "herdr tab rename wD:t1 Repo Manager (docs)" "$SMOKE_LOG"
: >"$SMOKE_LOG"
"${L[@]}" AGENT_LAYOUT=workspaces "$BIN/herdr-agent" place acme "widget-8 new fix" /tmp >/dev/null
check "layout: AGENT_LAYOUT=workspaces keeps one workspace per agent" grep -q "herdr workspace create --cwd /tmp --label widget-8 new fix --no-focus" "$SMOKE_LOG"
eq "layout: no herdr tab data = one slot per workspace (pre-0.12 herdr)" "$(SMOKE_HERDR_WS="$HL/ws.json" SMOKE_HERDR_AGENTS="$HL/agents.json" "$BIN/herdr-agent" find "widget-5 old fix" | jq -c '[.layout, .pane_id]')" '["workspace","wO:p1"]'
homes="$(bash -c 'source "$1/lib.sh"; pdo_resolve_project acme; HERE="$PDO_ENV_DIR" source "$PDO_ENV_FILE"; pdo_finalize
  echo "$(pdo_home_of widget) $(pdo_home_of docs) $(pdo_team_home) $AGENT_LAYOUT"' _ "$BIN")"
eq "layout: homes (orchestrated repo -> project, self-managed repo -> itself, team -> project)" "$homes" "acme docs acme tabs"
eq "layout: a project whose every repo is self-managed homes its team in the primary repo's" "$(bash -c 'source "$1/lib.sh"; pdo_resolve_project acme; HERE="$PDO_ENV_DIR" source "$PDO_ENV_FILE"; SELF_MANAGED_REPOS=(docs widget); pdo_finalize; pdo_team_home' _ "$BIN")" "widget"
# mixed layout in the queue and the watcher: an agent in a tab blocks a second spawn, and is tracked
cat >"$HL/delta-tabs.json" <<'EOF'
{"result":{"tabs":[{"label":"Orchestrator (delta)","number":1,"tab_id":"wD:t1","workspace_id":"wD","agent_status":"idle"},{"label":"tool-1 tabbed work","number":2,"tab_id":"wD:t2","workspace_id":"wD","agent_status":"working"}]}}
EOF
echo '{"result":{"workspaces":[{"label":"delta","workspace_id":"wD","agent_status":"working"},{"label":"tool-26 old work","workspace_id":"wX","agent_status":"idle"}]}}' >"$HL/delta-ws.json"
qd="$(PDO_CONFIG_DIRS="$T/cfg-q" SMOKE_HERDR_WS="$HL/delta-ws.json" SMOKE_HERDR_TABS="$HL/delta-tabs.json" "$BIN/queue" --project delta --all --json 2>&1)"
eq "layout: queue excludes issues with a live agent in a tab or an old workspace (no double spawn)" "$(jq -c '[.excluded[] | select(.number == 1 or .number == 26) | "\(.number):\(.excluded | join(","))"]' <<<"$qd")" '["1:workspace-open","26:workspace-open"]'
pk="$(PDO_CONFIG_DIRS="$T/cfg-q" SMOKE_HERDR_WS="$HL/delta-ws.json" SMOKE_HERDR_TABS="$HL/delta-tabs.json" "$BIN/watch" --project delta --peek 2>/dev/null)"
eq "layout: the watcher tracks agents in tabs and in old workspaces" "$(jq -c '[.agents | to_entries[] | select(.value.hibernated | not) | .key] | sort' <<<"$pk" 2>/dev/null)" '["tool#1","tool#26"]'
eq "layout: the watcher records a tab agent's tab and home" "$(jq -c '.agents["tool#1"] | [.tab_id, .home, .workspace]' <<<"$pk" 2>/dev/null)" '["wD:t2","delta","tool-1 tabbed work"]'

# hibernate in the tab layout: it closes the agent's tab, never its manager's home
mkdir -p "$T/state/agents" "$HOME/.claude/projects/p"; : >"$HOME/.claude/projects/p/sess77.jsonl"
echo '{"repo":"widget","number":77,"name":"widget-77 tab hibernate","branch":"feat/77","session_id":"sess77","worktree":"'"$T"'/nowhere-77","workspace_id":"wH","tab_id":"wH:t3"}' >"$T/state/agents/widget-77.json"
echo '{"result":{"workspaces":[{"label":"acme","workspace_id":"wH","agent_status":"idle"}]}}' >"$HL/hb-ws.json"
echo '{"result":{"tabs":[{"label":"Orchestrator (acme)","number":1,"tab_id":"wH:t1","workspace_id":"wH","agent_status":"idle"},{"label":"widget-77 tab hibernate","number":3,"tab_id":"wH:t3","workspace_id":"wH","agent_status":"idle"}]}}' >"$HL/hb-tabs.json"
echo '{"result":{"agents":[{"agent":"claude","workspace_id":"wH","tab_id":"wH:t1","pane_id":"wH:p1","agent_status":"idle"},{"agent":"claude","workspace_id":"wH","tab_id":"wH:t3","pane_id":"wH:p3","agent_status":"idle"}]}}' >"$HL/hb-agents.json"
: >"$SMOKE_LOG"
out="$(SMOKE_HERDR_WS="$HL/hb-ws.json" SMOKE_HERDR_TABS="$HL/hb-tabs.json" SMOKE_HERDR_AGENTS="$HL/hb-agents.json" "$BIN/hibernate" widget 77 --project acme 2>&1)"; rc=$?
eq "hibernate (tabs): exit" "$rc" 0
check "hibernate (tabs): closes the agent's tab" grep -qx "herdr tab close wH:t3" "$SMOKE_LOG"
eq "hibernate (tabs): never closes a workspace (the manager's home)" "$(grep -c 'workspace close' "$SMOKE_LOG")" 0
eq "hibernate (tabs): metadata drops the stale ids" "$(jq -c '[(.hibernated_at > 0), .workspace_id, .tab_id]' "$T/state/agents/widget-77.json")" '[true,null,null]'

# the git hold: never release an agent mid-rebase or with commits its PR branch lacks
GH8="$T/hold"; G8=(git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main)
"${G8[@]}" init -q --bare "$GH8/origin.git" && "${G8[@]}" clone -q "$GH8/origin.git" "$GH8/wt" 2>/dev/null
(cd "$GH8/wt" && echo a >f && "${G8[@]}" add f && "${G8[@]}" commit -qm a && "${G8[@]}" push -q -u origin main 2>/dev/null)
hold() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import pdo_config as c; print(c.git_hold(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None))' "$BIN" "$@"; }
eq "git hold: a pushed worktree is free" "$(hold "$GH8/wt")" "None"
eq "git hold: no worktree on disk is free" "$(hold "$T/nowhere")" "None"
(cd "$GH8/wt" && echo b >f && "${G8[@]}" commit -qam b)
eq "git hold: a commit the upstream lacks" "$(hold "$GH8/wt")" "1 commit not pushed to the PR branch"
eq "git hold: ... unless the PR's head has it" "$(hold "$GH8/wt" "$(git -C "$GH8/wt" rev-parse HEAD)")" "None"
eq "git hold: the PR's head wins over the upstream" "$(hold "$GH8/wt" "$(git -C "$GH8/wt" rev-parse HEAD~1)")" "1 commit not pushed to the PR branch"
(cd "$GH8/wt" && "${G8[@]}" push -q 2>/dev/null && "${G8[@]}" checkout -qb side HEAD~1 && echo c >f && "${G8[@]}" commit -qam c \
  && "${G8[@]}" rebase -q main >/dev/null 2>&1)
eq "git hold: a rebase in progress" "$(hold "$GH8/wt")" "a rebase is in progress"
(cd "$GH8/wt" && "${G8[@]}" rebase --abort && "${G8[@]}" checkout -q main && "${G8[@]}" cherry-pick side >/dev/null 2>&1)
eq "git hold: a cherry-pick in progress" "$(hold "$GH8/wt")" "a cherry-pick is in progress"
(cd "$GH8/wt" && "${G8[@]}" cherry-pick --abort && "${G8[@]}" merge -q side >/dev/null 2>&1)
eq "git hold: a merge in progress" "$(hold "$GH8/wt")" "a merge is in progress"
"${G8[@]}" -C "$GH8/wt" merge --abort
"${G8[@]}" -C "$GH8/wt" worktree add -q "$GH8/linked" side 2>/dev/null
(cd "$GH8/linked" && "${G8[@]}" rebase -q main >/dev/null 2>&1)
eq "git hold: a rebase in a linked worktree" "$(hold "$GH8/linked")" "a rebase is in progress"
eq "watch: an agent mid-rebase at 'ready for QC' is held, not hibernated" "$(python3 - "$BIN/watch" "$GH8/linked" <<'PY'
import importlib.machinery, importlib.util, sys, types
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
w.subprocess = types.SimpleNamespace(run=lambda *a, **k: types.SimpleNamespace(returncode=0, stdout="ok", stderr=""))  # bin/hibernate only; git_hold runs real git
ag = {"h": {"repo": "widget", "number": 8, "status": "idle", "question_pending": False, "session_id": "s",
            "unchanged_min": 30, "wrapup_done": True, "worktree": sys.argv[2],
            "pr": {"state": "OPEN", "labels": [w.QC_READY], "head_sha": None}}}
print(w.auto_hibernate("acme", ag), ag["h"].get("git_hold"), ag["h"]["status"])
PY
)" "[] a rebase is in progress idle"
echo '{"repo":"widget","number":88,"name":"widget-88 held","branch":"feat/88","session_id":"sess77","worktree":"'"$GH8/linked"'"}' >"$T/state/agents/widget-88.json"
HB8=(env SMOKE_HERDR_WS="$HL/hb-ws.json" SMOKE_HERDR_TABS="$HL/hb-tabs.json" SMOKE_HERDR_AGENTS="$HL/hb-agents.json")
out="$("${HB8[@]}" "$BIN/hibernate" widget 88 --project acme --servers-only --dry-run 2>&1)"; rc=$?
eq "hibernate: refuses while the worktree is mid-rebase (exit 3)" "$rc" 3
has "hibernate: ... and says why" "$out" "a rebase is in progress"
"${HB8[@]}" "$BIN/hibernate" widget 88 --project acme --servers-only --dry-run --force >/dev/null 2>&1
eq "hibernate: --force releases it anyway (bin/shutdown)" "$?" 0
check "shutdown: passes --force to hibernate" grep -q '"--servers-only", "--force"' "$BIN/shutdown"

# pausing an agent that waits on the human: session kept, NOTIFY_CMD run, refused without its signal
printf '#!/bin/sh\nprintf "%%s|" "$@" >>"%s"; echo >>"%s"\n' "$T/notified" "$T/notified" >"$T/notify" && chmod +x "$T/notify"
"${G8[@]}" clone -q "$GH8/origin.git" "$GH8/clean" 2>/dev/null
for n in 79 80 81; do
  echo '{"repo":"widget","number":'$n',"name":"widget-'$n' waits","branch":"feat/'$n'","session_id":"sess77","worktree":"'"$GH8/clean"'","gate":{"kind":"ux","name":"phase 2 map","link":"https://example.com/proto","notified_at":null}}' >"$T/state/agents/widget-$n.json"
done
NOTIFY_CMD="$T/notify" "${HB8[@]}" "$BIN/hibernate" widget 79 --project acme --pause ux-gate >/dev/null 2>&1
eq "pause: a UX gate hibernates, keeping the session" "$?" 0
eq "pause: ... records why, the gate and its link" "$(jq -c '[.paused.reason, .paused.detail, .paused.link, (.hibernated_at > 0), .session_id]' "$T/state/agents/widget-79.json")" '["ux-gate","phase 2 map","https://example.com/proto",true,"sess77"]'
has "pause: ... and notifies the human" "$(cat "$T/notified" 2>/dev/null)" "widget-79 waits waits at a UX gate|phase 2 map|https://example.com/proto|"
NOTIFY_CMD="$T/notify" "${HB8[@]}" "$BIN/hibernate" widget 80 --project acme --blocked >/dev/null 2>&1
eq "pause --blocked: open blockers and a clean worktree" "$(jq -c '[.paused.reason, .paused.blockers]' "$T/state/agents/widget-80.json")" '["blocked",["acme/widget#5"]]'
"${HB8[@]}" "$BIN/hibernate" widget 81 --project acme --pause decision 2>/dev/null; eq "pause: refused without the gate label" "$?" 3
"${HB8[@]}" "$BIN/hibernate" widget 81 --project acme --blocked 2>/dev/null; eq "pause --blocked: refused with no blockers" "$?" 3
"${HB8[@]}" "$BIN/hibernate" widget 81 --project acme --pause question 2>/dev/null; eq "pause question: refused without a live tab" "$?" 3
eq "watch: a reply ends a pause; questions and gates pause after the grace hour, desk gates never" "$(python3 - "$BIN/watch" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1]))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
w.run = lambda *a, **k: "[]"  # no comments
w.pdo_config.open_blockers = lambda o, r, n: [] if n == 3 else ["x/y#1"]
R = lambda reason, labels=(), n=1, **kw: (w.reply_for("o", "r", n, dict({"reason": reason, "since": 1}, **kw), set(labels), None) or {}).get("kind")
print([R("ux-gate"), R("ux-gate", ["awaiting-ux-gate"]), R("decision", ["awaiting-ux-gate"]), R("parked", ["on-hold"]),
       R("parked"), R("question"), R("question", answer="use metres"), R("blocked", n=2), R("blocked", n=3)])
def ag(**kw):
    a = {"session_id": "s", "unchanged_min": 15, "status": "idle", "question_pending": False, "issue_state": "open", "pr": None,
         "repo": "r", "number": 2, "idle_reason": "idle"}
    a.update(kw); return a
w.CFG["org"] = "o"
H = 61  # past QUESTION_GRACE_MIN (60)
print([w.pause_reason(a) for a in (ag(question_pending=True, status="blocked"), ag(question_pending=True, status="blocked", unchanged_min=H),
       ag(question_pending=True, unchanged_min=5), ag(ux_gate=True), ag(ux_gate=True, unchanged_min=H),
       ag(ux_gate=True, unchanged_min=H, git_hold="1 commit not pushed"), ag(decision_gate=True, unchanged_min=H),
       ag(decision_gate=True, unchanged_min=600, gate={"desk": True, "since": 1}),
       ag(decision_gate=True, unchanged_min=H, gate={"desk": True, "since": 1, "cleared_at": 2}),
       ag(question_pending=True, status="blocked", unchanged_min=600, design_lead_held=True), ag(likely_fixed=True),
       ag(), ag(number=3), ag(status="working", ux_gate=True, unchanged_min=H), ag(ux_gate=True, hibernated=True, unchanged_min=H),
       ag(ux_gate=True, pause_refused="x", unchanged_min=H), ag(ux_gate=True, question_pending=True, status="blocked", unchanged_min=H))])
w.QUESTION_GRACE_MIN = 30
print(w.pause_reason(ag(question_pending=True, status="blocked", unchanged_min=31)))
prev = {"agents": {"r#1": {"paused": {"reason": "question", "reply": None}}}, "queue": [], "pr_cap": {}}
cur = {"agents": {"r#1": {"repo": "r", "number": 1, "workspace": "r-1 w", "parked": True, "merged": False, "stalled": False, "pr": None,
                          "paused": {"reason": "question", "reply": {"kind": "answer", "detail": "yes"}}}},
       "queue": [], "pr_cap": {}, "usage_over_ceiling": False, "free_slots": 0}
print([(e["type"], e["kind"], e["detail"]) for e in w.events(prev, cur) if e["type"] == "reply_arrived"], [e["type"] for e in w.events(cur, cur) if e["type"] == "reply_arrived"])
PY
)" "['gate cleared', None, 'gate cleared', None, 'unparked', None, 'answer', None, 'unblocked']
[None, 'question', None, None, 'ux-gate', None, 'decision', None, 'decision', None, 'parked', 'blocked', None, None, None, None, 'ux-gate']
question
[('reply_arrived', 'answer', 'yes')] []"
# a standing loop that is down: an auth error in its latest reply, or no tick past its interval
LD="$T/loopstate"; mkdir -p "$LD/agent-qc" "$LD/design-lead"
touch -d '-3 hours' "$LD/acme-watch.json"; touch "$LD/agent-qc/heartbeat"; touch -d '-2 hours' "$LD/design-lead/acme.heartbeat"
eq "loops: an auth error in the latest reply, a stale tick, old scrollback and a working loop" "$(python3 - "$BIN" "$LD" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import pdo_herdr as h
cfg = {"project": "acme", "state_dir": sys.argv[2], "agent_qc_ports": [1], "design_lead": {"name": "Design Lead (acme)"},
       "manager": "Repo Manager (acme)", "orchestrate_skill": "orch"}
screens = {"p1": "● Login expired · Please run /login\n✻ Worked for 0s\n❯ ",
           "p2": "● Login expired · Please run /login\n❯ /login\n● Login successful\n❯ ",
           "p3": "● Nothing to answer.\n❯ ", "p4": "● I saw 'Login expired' in a log\n❯ ", "p5": ""}
snap = [{"name": "QC Agent (acme)", "pane_id": "p1", "status": "done"}, {"name": "Repo Manager (acme)", "pane_id": "p2", "status": "idle"},
        {"name": "Design Lead (acme)", "pane_id": "p3", "status": "idle"}, {"name": "intake", "pane_id": "p4", "status": "idle"},
        {"name": "Orchestrator (acme)", "pane_id": "p5", "status": "working"}]
rows = h.loops_down([cfg], snap, read=lambda pane: screens.get(pane, ""))
print([(r["workspace"], r["reason"].split(" (")[0]) for r in rows])
print(rows[0]["fix"].startswith("run /login in its tab"))
snap[4]["status"] = "idle"
print([r["workspace"] for r in h.loops_down([cfg], snap, read=lambda pane: screens.get(pane, ""))])
PY
)" "[('QC Agent (acme)', 'login or API auth failure on screen'), ('Design Lead (acme)', 'no tick for 2.0h')]
True
['Orchestrator (acme)', 'QC Agent (acme)', 'Design Lead (acme)']"
check "fleet: a loop that is down leads the waiting list" python3 -c '
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("fleet", importlib.machinery.SourceFileLoader("fleet", sys.argv[1] + "/fleet"))
f = importlib.util.module_from_spec(spec); spec.loader.exec_module(f)
w = f.waiting_list([], {}, [{"project": "acme", "workspace": "QC Agent (acme)", "reason": "r", "fix": "x"}])
assert w[0]["why"] == "loop down" and w[0]["item"] == "QC Agent (acme): r" and w[0]["title"] == "fix: x", w' "$BIN"
# the machine-wide memory gate: recent starts count as used; a refusal reserves nothing
G="$T/gate-test"
gate() { PDO_GATE_DIR="$G" PDO_MEM_AVAIL_MB="$1" "$BIN/mem-gate" reserve --project acme --agent "$2" >/dev/null 2>&1; echo $?; }
eq "mem-gate: reserve until the floor, then refuse (exit 4)" "$(gate 5000 a; gate 5000 b; gate 5000 c; gate 9000 d)" "0
0
4
0"
eq "mem-gate: status counts the live reservations" "$(PDO_GATE_DIR="$G" PDO_MEM_AVAIL_MB=9000 "$BIN/mem-gate" status --json | jq -c '[.reserved_mb, [.reservations[].agent]]')" '[2700,["a","b","d"]]'
# external jobs (a CI runner's hooks): --mb with no project, counted with the agents', released by label
XG="$T/gate-ext"; mkdir -p "$T/standalone"; cp "$BIN/mem-gate" "$T/standalone/pdo-mem-gate"
xg() { PDO_GATE_DIR="$XG" PDO_MEM_AVAIL_MB="$1" "$T/standalone/pdo-mem-gate" "${@:2}" >/dev/null 2>&1; echo $?; }
eq "mem-gate --mb: a standalone copy reserves an external job (no project config)" "$(xg 6000 reserve --mb 2000 --agent ci:x:1)" 0
eq "mem-gate --mb: the engine's reserve counts the job" "$(PDO_GATE_DIR="$XG" PDO_MEM_AVAIL_MB=5000 "$BIN/mem-gate" reserve --project acme --agent a 2>/dev/null | jq -c '[.ok, .reserved_mb]')" '[false,2000]'
eq "mem-gate --mb: the job's floor is the one the engine last used" "$(PDO_GATE_DIR="$XG" PDO_MEM_AVAIL_MB=99999 "$BIN/mem-gate" reserve --project acme --agent b >/dev/null; jq .floor_mb "$XG/floor.json"; PDO_GATE_DIR="$XG" PDO_MEM_AVAIL_MB=99999 "$T/standalone/pdo-mem-gate" reserve --mb 100 --agent ci:x:2 2>/dev/null | jq .floor_mb)" "3072
3072"
start=$(date +%s); rc="$(xg 4000 reserve --mb 9999999 --agent ci:test --wait 3)"
eq "mem-gate --wait: retries, then exit 4 when it never fits" "$rc $(( $(date +%s) - start >= 2 && $(date +%s) - start <= 6 ))" "4 1"
eq "mem-gate release: drops the label's reservations only" "$(xg 6000 release --agent ci:x:1; PDO_GATE_DIR="$XG" PDO_MEM_AVAIL_MB=6000 "$BIN/mem-gate" status --json | jq -c '[.reservations[].agent]')" '0
["b","ci:x:2"]'
check "mem-gate --mb: needs a label" bash -c '! PDO_GATE_DIR="$0" "$1" reserve --mb 5 2>/dev/null' "$XG" "$BIN/mem-gate"
eq "mem-gate: AGENT_MB_BY_REPO before the profile" "$(PDO_CONFIG_DIRS="$ME" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import pdo_config as c
print(c.agent_mb({"resource_profile": "heavy", "agent_mb_by_repo": {"docs": 500}}, "docs"), c.agent_mb({"resource_profile": "heavy"}, "docs"), c.agent_mb({"resource_profile": "x", "agent_mb": 700}))' "$BIN")" "500 1800 700"
# a plain question stays live; pdo questions reads it (and a paused one) from the transcript
CC="$T/claude-cfg"; mkdir -p "$CC/projects/-w"
printf '%s\n' '{"type":"assistant","timestamp":"2026-11-08T10:00:00.000Z","message":{"content":[{"type":"tool_use","id":"t1","name":"AskUserQuestion","input":{"questions":[{"question":"Old?","header":"o","options":[{"label":"A"}]}]}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"A"}]}}' \
  '{"type":"assistant","timestamp":"2026-11-08T12:00:00.000Z","message":{"content":[{"type":"tool_use","id":"t2","name":"AskUserQuestion","input":{"questions":[{"question":"Which order?","header":"Order","multiSelect":false,"options":[{"label":"Sort both (Recommended)","description":"stable"},{"label":"Accept"}]}]}}]}}' \
  >"$CC/projects/-w/s-live.jsonl"
head -2 "$CC/projects/-w/s-live.jsonl" >"$CC/projects/-w/s-done.jsonl"
eq "questions: the transcript's unanswered AskUserQuestion, or none" "$(CLAUDE_CONFIG_DIR="$CC" python3 -c '
import sys, json; sys.path.insert(0, sys.argv[1]); import pdo_config as c
q = c.pending_question("s-live"); print(q["asked_at"], [(x["question"], [o["label"] for o in x["options"]]) for x in q["questions"]])
print(c.pending_question("s-done"), c.pending_question("nope"), c.pending_question(None))' "$BIN")" "1794139200 [('Which order?', ['Sort both (Recommended)', 'Accept'])]
None None None"
QS="$T/qstate"; mkdir -p "$QS/agents"
echo '{"repo":"widget","number":7,"name":"widget-7 paused one","session_id":"s-live","hibernated_at":1794139200,"paused":{"reason":"question","since":1794139200}}' >"$QS/agents/widget-7.json"
echo '{"repo":"widget","number":8,"name":"widget-8 answered","session_id":"s-live","hibernated_at":1794139200,"paused":{"reason":"question","since":1794139200,"answer":"x"}}' >"$QS/agents/widget-8.json"
echo '{"repo":"widget","number":9,"name":"widget-9 gate","session_id":"s-live","hibernated_at":1794139200,"paused":{"reason":"ux-gate","since":1794139200}}' >"$QS/agents/widget-9.json"
echo '{"repo":"widget","number":5,"name":"widget-5 live one","session_id":"s-live"}' >"$QS/agents/widget-5.json"
eq "questions: live and paused questions, with how to answer each" "$(CLAUDE_CONFIG_DIR="$CC" python3 - "$BIN" "$QS" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("questions", importlib.machinery.SourceFileLoader("questions", sys.argv[1] + "/questions"))
q = importlib.util.module_from_spec(spec); spec.loader.exec_module(q)
q.pdo_config.projects = lambda: ["acme"]
q.pdo_config.try_load = lambda p: ({"project": p, "org": "o", "repo_root": {"widget": "/x"}, "state_dir": sys.argv[2]}, None)
q.pdo_config.managed_elsewhere = lambda cfg: set()
slots = [{"name": "widget-5 live one", "status": "blocked", "agent": {}, "pane_id": "p5"},
         {"name": "widget-6 working", "status": "working", "agent": {}, "pane_id": "p6"},
         {"name": "Orchestrator (acme)", "status": "idle", "agent": {}}]
rows = q.collect(slots=slots, now=1794139200 + 7200)
print([(r["agent"], r["state"], r["hours"], r["questions"][0]["question"], r["answer"]) for r in rows])
print([(r["question"], r["recommended"], r["desk"]) for r in rows])
print(q.text(rows).splitlines()[:5])
PY
)" "[('widget#5', 'live', 2.0, 'Which order?', 'in its tab \"widget-5 live one\"'), ('widget#7', 'paused', 2.0, 'Which order?', 'pdo answer widget 7 \"<text>\" --project acme')]
[('Which order?', ['Sort both (Recommended)'], False), ('Which order?', ['Sort both (Recommended)'], False)]
['widget-5 live one (acme/widget, live: menu on screen, waiting 2h)  https://github.com/o/widget/issues/5', '  Q: Which order?', '     1. Sort both (Recommended): stable', '     2. Accept', '     recommended: Sort both (Recommended)']"
echo '{"repo":"widget","number":6,"name":"widget-6 desk","session_id":"s-live","hibernated_at":1794139200,"gate":{"kind":"decision","name":"cutover","link":"https://example.com/cutover","since":1794139200,"desk":true}}' >"$QS/agents/widget-6.json"
echo '{"repo":"widget","number":10,"name":"widget-10 two","session_id":"s-none","hibernated_at":1794139200,"gate":{"kind":"decision","name":"rows and sync","link":"https://github.com/o/widget/pull/11","since":1794139200,"questions":[{"question":"Rows?","options":[{"label":"One (Recommended)"},{"label":"Many"}]},{"question":"Sync?","options":[{"label":"Push"},{"label":"Pull"}]},{"question":"Have you reviewed it? Good to proceed?","options":[{"label":"Yes, proceed"},{"label":"Not yet"}]}]}}' >"$QS/agents/widget-10.json"
eq "questions: a desk gate says answer at the desk" "$(CLAUDE_CONFIG_DIR="$CC" python3 - "$BIN" "$QS" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("questions", importlib.machinery.SourceFileLoader("questions", sys.argv[1] + "/questions"))
q = importlib.util.module_from_spec(spec); spec.loader.exec_module(q)
q.pdo_config.projects = lambda: ["acme"]
q.pdo_config.try_load = lambda p: ({"project": p, "org": "o", "repo_root": {"widget": "/x"}, "state_dir": sys.argv[2]}, None)
q.pdo_config.managed_elsewhere = lambda cfg: set()
r = [r for r in q.collect(slots=[], now=1794139200 + 3600) if r["agent"] == "widget#6"][0]
print(r["desk"], r["answer"].startswith("at the desk: pdo resume-agent widget 6"), r["question"], r["repo"], r["issue"], r["issue_url"], r["url"])
print([l for l in q.text([r]).splitlines() if l.startswith("  gate") or l.startswith("  look at") or l.startswith("  screen")])
g = [r for r in q.collect(slots=[], now=1794139200 + 3600) if r["agent"] == "widget#10"][0]
print([x["question"] for x in g["questions"]], g["recommended"], g["answer"], g["url_kind"])
print([q.url_kind(u) for u in ("https://github.com/o/r/pull/3", "https://github.com/o/r/issues/3#issuecomment-9", "https://github.com/o/r/blob/b/docs/d.md", "https://claude.ai/artifact/x", None)])
PY
)" "True True Which order? widget 6 https://github.com/o/widget/issues/6 https://example.com/cutover
['  gate (decision): cutover  [answer at the desk]', '  look at (artifact): https://example.com/cutover']
['Rows?', 'Sync?'] ['One (Recommended)', None] pdo gate clear widget 10 --note \"Q1=1; Q2=?\" --project acme pr
['pr', 'comment', 'doc', 'artifact', None]"
rm -f "$QS/agents/widget-6.json" "$QS/agents/widget-10.json"
# Design Lead: one per project (DESIGN_LEAD=1); active once its intent doc is on its home repo's origin/main
DLR="$T/dl-repo"; git init -q "$DLR"; git -C "$DLR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$DLR" update-ref refs/remotes/origin/main HEAD
eq "design-lead: off by default" "$("$BIN/pdo-config" --project acme | jq -c .design_lead)" "null"
eq "design-lead: DESIGN_LEAD=1 defaults its name and scope" "$(DESIGN_LEAD=1 "$BIN/pdo-config" --project acme | jq -c '[.design_lead.name, (.design_lead.repos | index("widget") != null), .design_lead.escalate_hours, .design_lead.live_answer]')" '["Design Lead (acme)",true,2,false]'
eq "design-lead: its home repo is the primary when in scope, else the first" "$(DESIGN_LEAD=1 DESIGN_LEAD_REPOS="docs widget" DESIGN_LEAD_NAME="Design Lead (docs)" "$BIN/pdo-config" --project acme | jq -c '[.design_lead.name, .design_lead.repos, .design_lead.home_repo]'; DESIGN_LEAD=1 DESIGN_LEAD_REPOS="docs" "$BIN/pdo-config" --project acme | jq -r .design_lead.home_repo)" '["Design Lead (docs)",["docs","widget"],"widget"]
docs'
check "design-lead: status refuses a project without one" bash -c '! "$0/design-lead" status --project acme' "$BIN"
DLC='{"project": "acme", "state_dir": "'"$T"'/dlstate", "repo_root": {"widget": "'"$DLR"'"}, "design_lead": {"name": "Design Lead (acme)", "repos": ["widget"], "home_repo": "widget", "intent": "docs/intent.md", "escalate_hours": 2}}'
DLPY='import sys, json; sys.path.insert(0, sys.argv[1]); import pdo_config as c; cfg = json.loads(sys.argv[2])'
eq "design-lead: inactive until the intent doc is on main" "$(python3 -c "$DLPY"'
print(c.design_lead_active(cfg), c.design_lead_route(cfg, "widget", 5, 0.1))' "$BIN" "$DLC")" "False ('human', None)"
mkdir -p "$DLR/docs"; echo "# Intent" >"$DLR/docs/intent.md"; git -C "$DLR" add docs
git -C "$DLR" -c user.email=t@t -c user.name=t commit -q -m intent; git -C "$DLR" update-ref refs/remotes/origin/main HEAD
mkdir -p "$T/dlstate/design-lead"; echo '{"escalated": {"widget#6": {"reason": "costs money", "at": 1}}}' >"$T/dlstate/design-lead/acme.json"
eq "design-lead: active questions are its own; escalated, waiting 2h, or out of scope go to the human" "$(python3 -c "$DLPY"'
print(c.design_lead_active(cfg)); print(c.design_lead_route(cfg, "widget", 5, 0.5)); print(c.design_lead_route(cfg, "widget", 6, 0.5))
print(c.design_lead_route(cfg, "widget", 5, 2.0)); print(c.design_lead_route(cfg, "other", 5, 0.5))' "$BIN" "$DLC")" "True
('design-lead', None)
('human', 'the Design Lead escalated it: costs money')
('human', \"the Design Lead hasn't answered it in 2h\")
('human', None)"
echo '{"repo":"widget","number":79,"name":"widget-77 x","hibernated_at":1,"paused":{"reason":"question","since":1}}' >"$T/state/agents/widget-77.json"
out="$(DESIGN_LEAD=1 "$BIN/answer" widget 77 "x" --project acme --design-lead 2>&1)"; rc=$?
eq "answer --design-lead: refused (exit 3) before the intent doc is approved" "$rc $(grep -c "isn't approved yet" <<<"$out")" "3 1"
out="$("$BIN/answer" widget 77 "x" --project acme --design-lead 2>&1)"; rc=$?
eq "answer --design-lead: refused without a Design Lead" "$rc $(grep -c "has no Design Lead" <<<"$out")" "3 1"
rm -f "$T/state/agents/widget-77.json"
out="$(DESIGN_LEAD=1 "$BIN/design-lead" ask widget 12 "which layout?" --project acme 2>&1)"; rc=$?
eq "design-lead ask: refused (exit 3) before approval, so the worker asks the human" "$rc $(grep -c "ask the human" <<<"$out")" "3 1"
check "design-lead ask: refused for a repo out of scope" bash -c '! DESIGN_LEAD=1 DESIGN_LEAD_REPOS=docs "$0/design-lead" ask widget 12 "q?" --project acme' "$BIN"
eq "design-lead: escalate, then reply clears the hold and the escalation" "$(DESIGN_LEAD=1 "$BIN/design-lead" escalate widget 12 "outward-facing" --project acme >/dev/null
DESIGN_LEAD=1 "$BIN/design-lead" status --project acme --json | jq -c '[.active, (.escalated | keys), .address]'
DESIGN_LEAD=1 "$BIN/design-lead" reply widget 12 answered "B" --project acme >/dev/null
DESIGN_LEAD=1 "$BIN/design-lead" status --project acme --json | jq -c '[.held, .escalated]')" '[false,["widget#12"],null]
[{},{}]'
echo '{"repo":"widget","number":4,"name":"widget-4 at a gate","hibernated_at":1794139200,"gate":{"kind":"decision","name":"layout","since":1794139200}}' >"$QS/agents/widget-4.json"
echo '{"repo":"widget","number":3,"name":"widget-3 asked it","session_id":"s-done"}' >"$QS/agents/widget-3.json"
mkdir -p "$QS/design-lead"; echo '{"held": {"widget#3": {"question": "Grid or list?", "asked_at": 1794139200}}}' >"$QS/design-lead/acme.json"
eq "questions: a paused gate and a held question are listed; an active Design Lead's rows route to it" "$(CLAUDE_CONFIG_DIR="$CC" python3 - "$BIN" "$QS" "$DLR" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("questions", importlib.machinery.SourceFileLoader("questions", sys.argv[1] + "/questions"))
q = importlib.util.module_from_spec(spec); spec.loader.exec_module(q)
q.pdo_config.projects = lambda: ["acme"]
q.pdo_config.try_load = lambda p: ({"project": p, "org": "o", "repo_root": {"widget": sys.argv[3]}, "state_dir": sys.argv[2],
                                    "design_lead": {"name": "Design Lead (acme)", "repos": ["widget"], "home_repo": "widget",
                                                    "intent": "docs/intent.md", "escalate_hours": 3}}, None)
q.pdo_config.managed_elsewhere = lambda cfg: set()
rows = q.collect(slots=[], now=1794139200 + 7200, only_repo="widget")
print([(r["agent"], r["state"], r["route"], r["answer"]) for r in rows])
print(q.text(rows).splitlines()[0])
PY
)" "[('widget#4', 'paused', 'design-lead', 'Design Lead (acme) answers it'), ('widget#7', 'paused', 'design-lead', 'Design Lead (acme) answers it'), ('widget#3', 'held', 'design-lead', 'Design Lead (acme) answers it (held: asked by peer message)')]
widget-4 at a gate (acme/widget, paused, waiting 2h)  https://github.com/o/widget/issues/4 → Design Lead"
eq "watch: a question held by the Design Lead is its own idle reason, never stalled or paused" "$(python3 - "$BIN" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("watch", importlib.machinery.SourceFileLoader("watch", sys.argv[1] + "/watch"))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
a = {"status": "idle", "question_pending": False, "design_lead_held": True, "unchanged_min": 2000, "session_id": "s", "stalled": False}
w.classify(a); print(a["idle_reason"], a["stalled_long"], w.pause_reason(a))
PY
)" "design lead question False None"
rm -f "$QS/agents/widget-4.json" "$QS/agents/widget-3.json" "$QS/design-lead/acme.json"
out="$("$BIN/answer" widget 79 "go with the second layout" --project acme 2>&1)"
has "answer: a paused agent's reply is recorded for the orchestrator" "$out" '"answer": "recorded"'
eq "answer: ... in its metadata" "$(jq -r .paused.answer "$T/state/agents/widget-79.json")" "go with the second layout"
: >"$SMOKE_LOG"
check "gate enter: a generic name is refused" bash -c '! "$0" enter widget 81 --kind decision --name "design decisions" --question "a? | x | y" --project acme 2>/dev/null' "$BIN/gate"
check "gate enter: refused without a question" bash -c '! "$0" enter widget 81 --kind decision --name "storage layout" --project acme 2>/dev/null' "$BIN/gate"
out="$(NOTIFY_CMD="$T/notify" "$BIN/gate" enter widget 81 --kind decision --name "storage layout" --link https://example.com/doc \
  --question "Where do rows live? | One table (Recommended) | A table per tenant" --question "Sync? | Push | Pull" --project acme 2>&1)"
eq "gate enter: records each question with its options" "$(jq -c '[.gate.questions[] | [.question, [.options[].label]]]' "$T/state/agents/widget-81.json")" '[["Where do rows live?",["One table (Recommended)","A table per tenant"]],["Sync?",["Push","Pull"]]]'
check "gate enter: the comment lists the questions and the answer format" bash -c 'grep -q "Q2.\*\* Sync?" "$0" && grep -q "Q1=2; Q2=1" "$0"' "$SMOKE_LOG"
eq "gate ask: appends to the open gate's questions" "$("$BIN/gate" ask widget 81 --question "Third? | A | B (Recommended)" --project acme | jq -r .questions) $(jq -c '[.gate.questions[].question]' "$T/state/agents/widget-81.json")" '3 ["Where do rows live?","Sync?","Third?"]'
eq "gate ask --replace: drops the old ones first" "$("$BIN/gate" ask widget 81 --replace --question "Only? | A | B (Recommended)" --project acme | jq -r .questions) $(jq -c '[.gate.questions[].question]' "$T/state/agents/widget-81.json")" '1 ["Only?"]'
check "gate ask: a question needs two options" bash -c '! "$0" ask widget 81 --question "Only? | A" --project acme 2>/dev/null' "$BIN/gate"
check "gate enter: labels the issue" grep -qx "gh issue edit 81 -R acme/widget --add-label awaiting-decision" "$SMOKE_LOG"
check "gate enter: posts one comment naming the gate" grep -q "gh issue comment 81 -R acme/widget --body \*\*Design decision gate: storage layout\*\*" "$SMOKE_LOG"
eq "gate enter: records it and notifies" "$(jq -c '[.gate.kind, .gate.name, (.gate.notified_at > 0)]' "$T/state/agents/widget-81.json")" '["decision","storage layout",true]'
eq "gate enter: not a desk gate by default" "$(jq -c .gate.desk "$T/state/agents/widget-81.json")" false
eq "gate desk: marks the open gate" "$("$BIN/gate" desk widget 81 --project acme 2>/dev/null | jq -r .gate) $(jq -c .gate.desk "$T/state/agents/widget-81.json")" "desk true"
"$BIN/gate" clear widget 81 --project acme >/dev/null 2>&1
check "gate desk: refused once the gate is cleared" bash -c '! "$0" desk widget 81 --project acme 2>/dev/null' "$BIN/gate"
check "gate clear: removes the label" grep -qx "gh issue edit 81 -R acme/widget --remove-label awaiting-decision" "$SMOKE_LOG"
rm -f "$T/state/agents/widget-79.json" "$T/state/agents/widget-80.json" "$T/state/agents/widget-81.json"
bash -c 'exec -a fake/bin/watch sleep 300' & SLP=$!
ASD="$("$BIN/project-env" --project acme PDO_STATE_DIR)"; echo '{"pid":'$SLP'}' >"$ASD/acme-watch.lock"
has "watch --closeout: left to the project's running watcher" "$("$BIN/watch" --project acme --closeout 2>&1)" "the project's watcher does this"
kill $SLP 2>/dev/null; rm -f "$ASD/acme-watch.lock"
rm -f "$T/state/agents/widget-88.json"

# start-manager: the project's Repo Manager opens tab 1 of a new home and starts nothing else
echo '{"result":{"agents":[{"agent":"claude","workspace_id":"wN","tab_id":"wN:t1","pane_id":"wN:p1","agent_status":"idle"}]}}' >"$HL/sm-agents.json"
echo '{"result":{"workspaces":[]}}' >"$HL/empty-ws.json"
SM=(env MANAGER="Repo Manager (acme)" SMOKE_HERDR_AGENTS="$HL/sm-agents.json")
: >"$SMOKE_LOG"
out="$("${SM[@]}" SMOKE_HERDR_WS="$HL/empty-ws.json" "$BIN/start-manager" --project acme 2>&1)"; rc=$?
eq "start-manager: exit" "$rc" 0
check "start-manager: creates the home labelled with the project" grep -q "herdr workspace create --cwd .* --label acme --no-focus" "$SMOKE_LOG"
check "start-manager: the Repo Manager is tab 1" grep -qx "herdr tab rename wN:t1 Repo Manager (acme)" "$SMOKE_LOG"
check "start-manager: runs the repo-manager skill" grep -q "herdr pane run wN:p1 .*project-repo-manager.*project=acme" "$SMOKE_LOG"
eq "start-manager: starts nothing else (no orchestrator, no QC)" "$(grep -cE 'orchestrate|human-review|project-agent-qc|project-intake' "$SMOKE_LOG")" 0
out="$(MANAGER= "$BIN/start-manager" --project acme 2>&1)"; has "start-manager: needs a MANAGER" "$out" "no MANAGER"
out="$("$BIN/start-manager" --project acme 2>&1)"; has "start-manager: refuses when the orchestrator is the manager" "$out" "MANAGER is the orchestrator"
out="$("$BIN/start-manager" --project acme --repo widget 2>&1)"; has "start-manager --repo: only a self-managed repo" "$out" "not self-managed"
: >"$SMOKE_LOG"
out="$("${SM[@]}" SMOKE_HERDR_WS="$HL/empty-ws.json" "$BIN/start-qc" --project acme 2>&1)"
has "placement: nothing but the manager may create a home (start-qc says what to start)" "$out" "pdo start-manager --project acme"
eq "placement: the refused start created nothing" "$(grep -cE 'workspace create|tab create' "$SMOKE_LOG")" 0
out="$("${SM[@]}" SMOKE_HERDR_WS="$HL/empty-ws.json" "$BIN/team-up" --project acme --no-hook 2>&1)"; rc=$?
eq "team-up: refuses while the Repo Manager isn't running" "$rc" 1
has "team-up: says to start the Repo Manager first" "$out" "start it first (pdo start-manager --project acme)"

# human review: "Human Review (<p>)" / review-<p>; a live tab under the pre-0.15 name "QC (<p>)" is reused
echo '{"result":{"agents":[{"agent":"claude","workspace_id":"wH","tab_id":"wH:t1","pane_id":"wH:p1","agent_status":"idle"},{"agent":"claude","workspace_id":"wH","tab_id":"wH:t9","pane_id":"wH:p9","agent_status":"idle"}]}}' >"$HL/hr-agents.json"
echo '{"result":{"tabs":[{"label":"Orchestrator (acme)","number":1,"tab_id":"wH:t1","workspace_id":"wH","agent_status":"idle"}]}}' >"$HL/hr-tabs.json"
HR=(env SMOKE_HERDR_WS="$HL/ws.json" SMOKE_HERDR_TABS="$HL/hr-tabs.json" SMOKE_HERDR_AGENTS="$HL/hr-agents.json")
: >"$SMOKE_LOG"
out="$("${HR[@]}" "$BIN/start-qc" --project acme 2>&1)"
check "human review: start-qc opens a 'Human Review (acme)' tab in the home" grep -q "herdr tab create --workspace wH --cwd .* --label Human Review (acme) --no-focus" "$SMOKE_LOG"
check "human review: its agent is named review-acme" grep -qx "herdr agent rename wH:p9 review-acme" "$SMOKE_LOG"
check "human review: runs the human-review skill" grep -q "herdr pane run wH:p9 .*project-human-review" "$SMOKE_LOG"
echo '{"result":{"tabs":[{"label":"Orchestrator (acme)","number":1,"tab_id":"wH:t1","workspace_id":"wH","agent_status":"idle"},{"label":"QC (acme)","number":2,"tab_id":"wH:t2","workspace_id":"wH","agent_status":"idle"}]}}' >"$HL/hr-old-tabs.json"
echo '{"result":{"agents":[{"agent":"claude","workspace_id":"wH","tab_id":"wH:t1","pane_id":"wH:p1","agent_status":"idle"},{"agent":"claude","workspace_id":"wH","tab_id":"wH:t2","pane_id":"wH:p2","agent_status":"idle"}]}}' >"$HL/hr-old-agents.json"
HO=(env SMOKE_HERDR_WS="$HL/ws.json" SMOKE_HERDR_TABS="$HL/hr-old-tabs.json" SMOKE_HERDR_AGENTS="$HL/hr-old-agents.json")
: >"$SMOKE_LOG"
out="$("${HO[@]}" "$BIN/start-qc" --project acme 2>&1)"
has "human review: a live 'QC (acme)' tab (pre-0.15 name) is the same agent, not a second one" "$out" 'already running in tab "QC (acme)"'
eq "human review: no second tab opened" "$(grep -c 'tab create' "$SMOKE_LOG")" 0
check "human review: the old tab's agent takes the new name" grep -qx "herdr agent rename wH:p2 review-acme" "$SMOKE_LOG"
rl="$("${HO[@]}" "$BIN/relayout" --project acme --json 2>&1)"
eq "relayout: an idle 'QC (acme)' tab is relabelled to 'Human Review (acme)'" "$(jq -c '[.[0].steps[] | select(.kind == "qc") | "\(.action):\(.name)"]' <<<"$rl" 2>/dev/null)" '["relabel:QC (acme)"]'
: >"$SMOKE_LOG"
"${HO[@]}" "$BIN/relayout" --project acme --apply >/dev/null 2>&1
check "relayout --apply: the tab takes the new label" grep -qx "herdr tab rename wH:t2 Human Review (acme)" "$SMOKE_LOG"
check "relayout --apply: and its agent the new name" grep -qx "herdr agent rename wH:p2 review-acme" "$SMOKE_LOG"

# shutdown: everything of the project, in order; refuses a tab with a question; never the CEO or others
echo '{"repo":"widget","number":78,"name":"widget-78 shut me","branch":"feat/78","session_id":"sess78","worktree":"'"$T"'/nowhere-78"}' >"$T/state/agents/widget-78.json"
echo '{"result":{"workspaces":[{"label":"acme","workspace_id":"wH","agent_status":"blocked"},{"label":"CEO","workspace_id":"wC","agent_status":"idle"},{"label":"System Manager","workspace_id":"wS","agent_status":"working"},{"label":"my notes","workspace_id":"wP","agent_status":"idle"}]}}' >"$HL/sd-ws.json"
echo '{"result":{"tabs":[{"label":"Repo Manager (acme)","number":1,"tab_id":"wH:t1","workspace_id":"wH","agent_status":"idle"},{"label":"Orchestrator (acme)","number":2,"tab_id":"wH:t2","workspace_id":"wH","agent_status":"idle"},{"label":"widget-78 shut me","number":3,"tab_id":"wH:t3","workspace_id":"wH","agent_status":"working"},{"label":"QC (acme)","number":4,"tab_id":"wH:t4","workspace_id":"wH","agent_status":"blocked"},{"label":"1","number":1,"tab_id":"wC:t1","workspace_id":"wC","agent_status":"idle"},{"label":"1","number":1,"tab_id":"wS:t1","workspace_id":"wS","agent_status":"working"},{"label":"1","number":1,"tab_id":"wP:t1","workspace_id":"wP","agent_status":"idle"}]}}' >"$HL/sd-tabs.json"
echo '{"result":{"agents":[{"agent":"claude","workspace_id":"wH","tab_id":"wH:t1","pane_id":"wH:p1","agent_status":"idle"},{"agent":"claude","workspace_id":"wH","tab_id":"wH:t2","pane_id":"wH:p2","agent_status":"idle"},{"agent":"claude","workspace_id":"wH","tab_id":"wH:t3","pane_id":"wH:p3","agent_status":"working"},{"agent":"claude","workspace_id":"wH","tab_id":"wH:t4","pane_id":"wH:p4","agent_status":"blocked"},{"agent":"claude","workspace_id":"wC","tab_id":"wC:t1","pane_id":"wC:p1","agent_status":"idle"},{"agent":"claude","workspace_id":"wS","tab_id":"wS:t1","pane_id":"wS:p1","agent_status":"working"}]}}' >"$HL/sd-agents.json"
SD=(env MANAGER="Repo Manager (acme)" SMOKE_HERDR_WS="$HL/sd-ws.json" SMOKE_HERDR_TABS="$HL/sd-tabs.json" SMOKE_HERDR_AGENTS="$HL/sd-agents.json")
: >"$SMOKE_LOG"
sd="$("${SD[@]}" "$BIN/shutdown" --project acme --json 2>&1)"
eq "shutdown dry run: orchestrator, agent, QC refused (question), Repo Manager last" "$(jq -c '[.[0].steps[] | select(.kind != "qc-stack" and .kind != "watcher") | "\(.action):\(.name)"]' <<<"$sd" 2>/dev/null)" '["stop:Orchestrator (acme)","stop:widget-78 shut me","refuse:QC (acme)","stop:Repo Manager (acme)"]'
eq "shutdown dry run: changes nothing" "$(grep -cE 'tab close|workspace close|agent prompt|hibernate' "$SMOKE_LOG")" 0
has "shutdown dry run: lists what it leaves alone" "$("${SD[@]}" "$BIN/shutdown" --project acme 2>&1)" "left alone: CEO, System Manager, my notes"
: >"$SMOKE_LOG"
"${SD[@]}" SMOKE_HERDR_EXIT=1 "$BIN/shutdown" --project acme --apply >/dev/null 2>&1
cp "$HL/sd-agents.json.saved" "$HL/sd-agents.json" 2>/dev/null || true
check "shutdown --apply: exits the orchestrator and the Repo Manager" bash -c "grep -qx 'herdr agent prompt wH:p2 /exit' '$SMOKE_LOG' && grep -qx 'herdr agent prompt wH:p1 /exit' '$SMOKE_LOG'"
check "shutdown --apply: closes their tabs and the agent's" bash -c "grep -qx 'herdr tab close wH:t2' '$SMOKE_LOG' && grep -qx 'herdr tab close wH:t3' '$SMOKE_LOG' && grep -qx 'herdr tab close wH:t1' '$SMOKE_LOG'"
eq "shutdown --apply: the tab with a question is left alone" "$(grep -cE 'wH:t4|wH:p4 /exit' "$SMOKE_LOG")" 0
eq "shutdown --apply: never the CEO, the System Manager or the human's own" "$(grep -cE 'w[CSP]:' "$SMOKE_LOG")" 0
eq "shutdown --apply: never closes a workspace" "$(grep -c 'workspace close' "$SMOKE_LOG")" 0
eq "shutdown --apply: the agent is hibernated (reason shutdown), session and resumability kept" "$(jq -c '[(.hibernated_at > 0), .hibernate_reason, .session_id, .tab_id]' "$T/state/agents/widget-78.json")" '[true,"shutdown","sess78",null]'
eq "shutdown: the Repo Manager exits after everything else" "$(grep -E '/exit$' "$SMOKE_LOG" | tail -1)" "herdr agent prompt wH:p1 /exit"

# relayout: rename an idle old-layout manager workspace into its home; a busy one waits; dry run first
echo '{"result":{"workspaces":[{"label":"Orchestrator (acme)","workspace_id":"wM","agent_status":"idle"},{"label":"widget-5 old fix","workspace_id":"wO","agent_status":"working"},{"label":"CEO","workspace_id":"wC","agent_status":"idle"}]}}' >"$HL/rl-ws.json"
echo '{"result":{"tabs":[{"label":"1","number":1,"tab_id":"wM:t1","workspace_id":"wM","agent_status":"idle"},{"label":"1","number":1,"tab_id":"wO:t1","workspace_id":"wO","agent_status":"working"},{"label":"1","number":1,"tab_id":"wC:t1","workspace_id":"wC","agent_status":"idle"}]}}' >"$HL/rl-tabs.json"
echo '{"result":{"agents":[{"agent":"claude","workspace_id":"wM","tab_id":"wM:t1","pane_id":"wM:p1","agent_status":"idle"},{"agent":"claude","workspace_id":"wO","tab_id":"wO:t1","pane_id":"wO:p1","agent_status":"working"}]}}' >"$HL/rl-agents.json"
RL=(env SMOKE_HERDR_WS="$HL/rl-ws.json" SMOKE_HERDR_TABS="$HL/rl-tabs.json" SMOKE_HERDR_AGENTS="$HL/rl-agents.json")
: >"$SMOKE_LOG"
rl="$("${RL[@]}" "$BIN/relayout" --project acme --json 2>&1)"
eq "relayout dry run: idle manager -> rename into its home; live old agent listed, untouched" "$(jq -c '[.[0].steps[] | "\(.action):\(.name)"]' <<<"$rl" 2>/dev/null)" '["rename:Orchestrator (acme)","none:widget-5 old fix"]'
eq "relayout dry run: changes nothing" "$(grep -cE 'herdr (workspace|tab) (rename|close|create)|agent prompt' "$SMOKE_LOG")" 0
"${RL[@]}" "$BIN/relayout" --project acme --apply >/dev/null 2>&1
check "relayout --apply: the workspace becomes the home" grep -qx "herdr workspace rename wM acme" "$SMOKE_LOG"
check "relayout --apply: its tab 1 takes the manager's name" grep -qx "herdr tab rename wM:t1 Orchestrator (acme)" "$SMOKE_LOG"
eq "relayout --apply: live command agents and the CEO are never touched" "$(grep -cE '(^| )w[OC](:| |$)' "$SMOKE_LOG")" 0

# --- pdo dispatcher ---
has "pdo help lists commands" "$("$BIN/pdo" help)" "intake-submit"
eq "pdo runs a command" "$("$BIN/pdo" floor)" none
"$BIN/pdo" lib.sh >/dev/null 2>&1; eq "pdo refuses non-commands" "$?" 2

# --- install (temp HOME only, link mode) ---
out="$("$BIN/install" --codex --grok --claude --bin --link --prefix "$T/home/bin" 2>&1)"
check "install linked codex skills dir" test -L "$HOME/.agents/skills/project-orchestrate" -o ! -d "$ENGINE/skills/project-orchestrate"
check "install linked grok skills dir" test -L "$HOME/.grok/skills/project-orchestrate" -o ! -d "$ENGINE/skills/project-orchestrate"
check "install linked claude skills dir" test -L "$HOME/.claude/skills/project-orchestrate" -o ! -d "$ENGINE/skills/project-orchestrate"
check "install linked pdo" test -L "$T/home/bin/pdo"
eq "linked pdo works" "$("$T/home/bin/pdo" floor)" none
has "install --bin checks requirements" "$out" "requirements:"

# --- install --bin from a plugin cache: a launcher that follows the newest version ---
PC="$T/plugcache/project-dev-orchestration"
mkdir -p "$PC/0.9.0" "$PC/0.10.0/bin"
cp -r "$ENGINE/bin" "$PC/0.9.0/bin"
printf '#!/usr/bin/env bash\necho "newest $*"\n' >"$PC/0.10.0/bin/pdo"; chmod +x "$PC/0.10.0/bin/pdo"
out="$("$PC/0.9.0/bin/install" --bin --prefix "$T/plugbin" 2>&1)"
check "plugin install writes a launcher, not a link" test -f "$T/plugbin/pdo" -a ! -L "$T/plugbin/pdo"
eq "launcher runs the newest version" "$("$T/plugbin/pdo" floor)" "newest floor"
eq "PDO_HOME overrides the launcher" "$(PDO_HOME="$ENGINE" "$T/plugbin/pdo" floor)" none
rm -rf "$PC/0.10.0"
eq "launcher falls back to the remaining version" "$("$T/plugbin/pdo" floor)" none
"$PC/0.9.0/bin/install" --bin --prefix "$T/plugbin" >/dev/null 2>&1
check "re-running the plugin install keeps one launcher" test -f "$T/plugbin/pdo" -a ! -L "$T/plugbin/pdo"
"$BIN/install" --bin --prefix "$T/plugbin" >/dev/null 2>&1
check "a checkout install replaces the launcher with a link" test -L "$T/plugbin/pdo"
rm -f "$T/plugbin/pdo"; printf '#!/bin/sh\necho mine\n' >"$T/plugbin/pdo"
has "plugin install leaves a foreign pdo alone" "$("$PC/0.9.0/bin/install" --bin --prefix "$T/plugbin" 2>&1)" "skip:"

# --- gh identities: the gh shim, the git credential helper, install / uninstall ---
# Own HOME / XDG dirs / global gitconfig; a stub "real gh" records GH_TOKEN and argv.
G="$T/ghid"
export HOME="$G/home" XDG_CONFIG_HOME="$G/home/.config" XDG_DATA_HOME="$G/home/.local/share" GIT_CONFIG_GLOBAL="$G/home/.gitconfig"
unset PDO_GH_IDENTITIES PDO_GH_ALLOW_SWITCH PDO_GH_SHIM PDO_GH_EXPLAIN GITHUB_TOKEN
mkdir -p "$G/real" "$G/shim2" "$HOME"
GLOG="$G/calls.log" TLOG="$G/tokens.log"; export GLOG TLOG
cat >"$G/real/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2 $3" == "auth token -u" ]]; then
  echo "$4" >>"$TLOG"
  [[ "$4" == ghost ]] && exit 1
  echo "tok-$4"; exit 0
fi
if [[ "$1 $2" == "auth git-credential" ]]; then cat >/dev/null; printf 'username=x-access-token\npassword=%s\n' "${GH_TOKEN:-}"; exit 0; fi
printf 'token=%s argv=%s\n' "${GH_TOKEN:-}" "$*" >>"$GLOG"
EOF
chmod +x "$G/real/gh"
cat >"$G/map" <<'EOF'
# owners for the smoke test
acme-corp  alice-work  alice@acme-corp.example  Alice Example   # work
alice      alice       alice@example.com
lone       ghost
default    alice
EOF
printf '[init]\n\tdefaultBranch = main\n[user]\n\temail = base@example.com\n[credential "https://github.com"]\n\thelper =\n\thelper = !gh auth git-credential\n' >"$GIT_CONFIG_GLOBAL"
cp "$GIT_CONFIG_GLOBAL" "$G/gitconfig.orig"
SHIMD="$XDG_DATA_HOME/project-dev-orchestration/shims"
GCFG="$XDG_CONFIG_HOME/project-dev-orchestration"
OLDPATH="$PATH"
export PATH="$SHIMD:$G/real:$OLDPATH"
out="$("$BIN/install" --gh-identities --map "$G/map" --dry-run 2>&1)"; rc=$?
eq "ghid: --dry-run exits 0" "$rc" 0
check "ghid: --dry-run writes nothing" test ! -e "$SHIMD/gh" -a ! -e "$GCFG/gh-identities"
eq "ghid: --dry-run leaves the gitconfig" "$(cmp -s "$GIT_CONFIG_GLOBAL" "$G/gitconfig.orig" && echo same)" same
out="$("$BIN/install" --gh-identities --map "$G/map" 2>&1)"; rc=$?
eq "ghid: install exits 0" "$rc" 0
check "ghid: shim installed as gh" test -x "$SHIMD/gh"
check "ghid: map installed" cmp -s "$G/map" "$GCFG/gh-identities"
has "ghid: prints the PATH line" "$out" "export PATH=\"$SHIMD:\$PATH\""
eq "ghid: one include line" "$(git config --global --get-all include.path)" "$GCFG/gitconfig-identities"
cp "$GIT_CONFIG_GLOBAL" "$G/gitconfig.installed"
"$BIN/install" --gh-identities >/dev/null 2>&1
eq "ghid: install is idempotent (gitconfig unchanged)" "$(cmp -s "$GIT_CONFIG_GLOBAL" "$G/gitconfig.installed" && echo same)" same
eq "ghid: the original entries are untouched" "$(head -c "$(wc -c <"$G/gitconfig.orig")" "$GIT_CONFIG_GLOBAL" | cmp -s - "$G/gitconfig.orig" && echo same)" same

# the shim: owner detection
rm -f "$GLOG" "$TLOG"
last() { tail -1 "$GLOG" 2>/dev/null; }
gh pr list -R acme-corp/widget;                        eq "shim: -R owner/repo" "$(last)" "token=tok-alice-work argv=pr list -R acme-corp/widget"
gh pr list --repo=alice/notes;                         eq "shim: --repo=owner/repo" "$(last)" "token=tok-alice argv=pr list --repo=alice/notes"
gh issue list -Racme-corp/widget;                      has "shim: -Rowner/repo" "$(last)" "token=tok-alice-work"
gh pr list -R github.com/acme-corp/widget;             has "shim: -R HOST/OWNER/REPO" "$(last)" "token=tok-alice-work"
gh pr view https://github.com/alice/notes/pull/1 -R acme-corp/widget; has "shim: -R beats a URL" "$(last)" "token=tok-alice-work"
gh repo clone acme-corp/widget;                        has "shim: gh repo <sub> OWNER/REPO" "$(last)" "token=tok-alice-work"
gh api repos/acme-corp/widget/pulls;                   has "shim: api repos/OWNER/" "$(last)" "token=tok-alice-work"
gh api /orgs/acme-corp/teams;                          has "shim: api /orgs/OWNER/" "$(last)" "token=tok-alice-work"
gh api -X GET repos/ACME-CORP/widget;                  has "shim: owners are case-insensitive" "$(last)" "token=tok-alice-work"
gh api graphql -f query='query { repository(owner: "acme-corp", name: "w") { id } }'; has "shim: GraphQL owner:\"X\"" "$(last)" "token=tok-alice-work"
gh api graphql -f query='query { user(login:"alice") { id } }'; has "shim: GraphQL login:\"X\"" "$(last)" "token=tok-alice"
gh api graphql -F owner=acme-corp -f query='query($owner: String!) { x }'; has "shim: GraphQL owner= field" "$(last)" "token=tok-alice-work"
gh project item-list 3 --owner acme-corp;              has "shim: project --owner" "$(last)" "token=tok-alice-work"
gh project list --owner=alice;                         has "shim: project --owner=" "$(last)" "token=tok-alice"
gh pr view https://github.com/acme-corp/widget/pull/3; has "shim: a github.com URL" "$(last)" "token=tok-alice-work"
gh browse https://github.com/orgs/acme-corp/projects/1; has "shim: an orgs/ URL names the org" "$(last)" "token=tok-alice-work"
gh pr list -R stranger/thing;                          has "shim: unmapped owner = default" "$(last)" "token=tok-alice"
mkdir -p "$G/repos"
for f in https:https://github.com/acme-corp/widget.git ssh:git@github.com:acme-corp/widget.git sshurl:ssh://git@github.com/acme-corp/widget.git \
         alice:https://github.com/alice/notes.git other:https://github.com/acme-corpx/widget.git; do
  git init -q "$G/repos/${f%%:*}"; git -C "$G/repos/${f%%:*}" remote add origin "${f#*:}"
done
(cd "$G/repos/https" && gh issue list);  eq "shim: origin remote (https)" "$(last)" "token=tok-alice-work argv=issue list"
(cd "$G/repos/ssh" && gh issue list);    has "shim: origin remote (git@ ssh)" "$(last)" "token=tok-alice-work"
(cd "$G/repos/sshurl" && gh issue list); has "shim: origin remote (ssh://)" "$(last)" "token=tok-alice-work"
(cd "$G/repos/other" && gh issue list);  has "shim: an owner prefix is not the owner" "$(last)" "token=tok-alice argv"
(cd "$G/repos/alice" && gh pr list -R acme-corp/widget); has "shim: -R beats the origin remote" "$(last)" "token=tok-alice-work"
(cd "$G" && gh issue list);              has "shim: no owner anywhere = default" "$(last)" "token=tok-alice argv"
eq "shim: PDO_GH_EXPLAIN" "$(cd "$G/repos/ssh" && PDO_GH_EXPLAIN=1 gh status 2>&1 | cut -d' ' -f1-4)" "owner=acme-corp rule=origin login=alice-work via=map"
grep -v '^default' "$G/map" >"$G/map-nodefault"
PDO_GH_IDENTITIES="$G/map-nodefault" gh pr list -R stranger/thing; eq "shim: no match, no default = the active account" "$(last)" "token= argv=pr list -R stranger/thing"
gh pr list -R lone/x 2>"$G/err"; eq "shim: a login without a token exits 4" "$?" 4
has "shim: ... and says which login" "$(cat "$G/err")" "'ghost'"
# pass-through: GH_TOKEN / GITHUB_TOKEN set, auth, PDO_GH_SHIM=off
: >"$TLOG"
GH_TOKEN=pinned gh pr list -R acme-corp/widget;        eq "shim: GH_TOKEN set = unchanged" "$(last)" "token=pinned argv=pr list -R acme-corp/widget"
GITHUB_TOKEN=bot gh pr list -R acme-corp/widget;       eq "shim: GITHUB_TOKEN set = unchanged" "$(last)" "token= argv=pr list -R acme-corp/widget"
eq "shim: pass-through looks up no token" "$(wc -l <"$TLOG")" 0
PDO_GH_SHIM=off gh pr list -R acme-corp/widget;        eq "shim: PDO_GH_SHIM=off = unchanged" "$(last)" "token= argv=pr list -R acme-corp/widget"
gh auth status;                                        eq "shim: other auth calls pass through" "$(last)" "token= argv=auth status"
# auth switch / login refusal
n0="$(wc -l <"$GLOG")"
gh auth switch -u alice-work 2>"$G/err"; eq "shim: gh auth switch refused (exit 3)" "$?" 3
has "shim: the refusal explains" "$(cat "$G/err")" "PDO_GH_ALLOW_SWITCH=1"
gh auth login 2>/dev/null; eq "shim: gh auth login without --hostname refused" "$?" 3
eq "shim: refused calls never reach gh" "$(wc -l <"$GLOG")" "$n0"
gh auth login --hostname github.com;                   eq "shim: gh auth login --hostname passes" "$(last)" "token= argv=auth login --hostname github.com"
PDO_GH_ALLOW_SWITCH=1 gh auth switch -u alice;         eq "shim: PDO_GH_ALLOW_SWITCH=1 allows a switch" "$(last)" "token= argv=auth switch -u alice"
# no recursion: another shim copy earlier on PATH is skipped; a shim alone fails fast
cp "$BIN/gh-identity-shim" "$G/shim2/gh"; chmod +x "$G/shim2/gh"
PATH="$SHIMD:$G/shim2:$G/real:$OLDPATH" gh pr list -R alice/notes; eq "shim: skips other shim copies on PATH" "$(last)" "token=tok-alice argv=pr list -R alice/notes"
mkdir -p "$G/tools"; for t in bash env readlink dirname head grep git timeout; do ln -sf "$(command -v "$t")" "$G/tools/$t"; done
out="$(PATH="$SHIMD:$G/shim2:$G/tools" timeout 10 gh pr list 2>&1)"; rc=$?
eq "shim: no real gh = exit 127, no loop" "$rc" 127
has "shim: ... with a message" "$out" "no real gh on PATH"
ln -sf "$SHIMD/gh" "$G/shim2/gh"
out="$(PATH="$SHIMD:$G/shim2:$G/tools" timeout 10 gh pr list 2>&1)"; eq "shim: a symlink to the shim is skipped too" "$?" 127
# the engine's pin still wins through the shim
eq "shim: with-gh-user pin passes through" "$("$BIN/with-gh-user" --user octo gh pr list -R acme-corp/widget >/dev/null; last)" "token=tok-octo argv=pr list -R acme-corp/widget"
# the review guard: agent sessions never post PR reviews as a guarded login
printf '# test rules\nacme-corp/gov alice-work all\nacme-corp/* alice-work verdicts\n' >"$G/guard"
gx() { env -u PDO_DISPATCHED -u CODEX_SANDBOX -u CODEX_SANDBOX_NETWORK_DISABLED CLAUDECODE=1 PDO_GH_REVIEW_GUARD_FILE="$G/guard" "$@"; }
n0="$(wc -l <"$GLOG")"
gx env GH_TOKEN=tok-alice-work gh pr review 5 --approve -R acme-corp/gov 2>"$G/err"; eq "guard: approve on a guarded repo as the login = exit 5" "$?" 5
has "guard: ... says to comment instead" "$(cat "$G/err")" "gh pr comment"
has "guard: ... and names the browser" "$(cat "$G/err")" "in the browser"
gx env GH_TOKEN=tok-alice-work gh pr review 5 -c -b hi -R acme-corp/gov 2>/dev/null; eq "guard: scope all refuses a comment review" "$?" 5
gx env GH_TOKEN=tok-alice-work gh pr review https://github.com/acme-corp/gov/pull/5 -r -b no 2>/dev/null; eq "guard: the repo from a PR URL" "$?" 5
gx env GH_TOKEN=tok-alice-work gh api repos/acme-corp/gov/pulls/5/reviews -f event=COMMENT -f body=x 2>/dev/null; eq "guard: reviews API (fields imply POST)" "$?" 5
gx env GH_TOKEN=tok-alice-work gh api -X POST repos/acme-corp/gov/pulls/5/comments -f body=x 2>/dev/null; eq "guard: scope all refuses a review comment" "$?" 5
gx env GH_TOKEN=tok-alice-work gh api repos/acme-corp/widget/pulls/5/reviews/9/events -f event=APPROVE 2>/dev/null; eq "guard: submitting a pending review as APPROVE" "$?" 5
gx env GH_TOKEN=tok-alice-work gh pr review 5 --approve -R acme-corp/widget 2>/dev/null; eq "guard: scope verdicts refuses approve" "$?" 5
gx env GH_TOKEN=tok-alice-work gh api graphql -f query='mutation { addPullRequestReview(input: {pullRequestId: "x", event: APPROVE}) { clientMutationId } }' 2>/dev/null
eq "guard: a GraphQL review mutation (repo unknown)" "$?" 5
gx env GH_TOKEN=tok-alice-work PDO_GH_SHIM=off gh pr review 5 --approve -R acme-corp/gov 2>/dev/null; eq "guard: PDO_GH_SHIM=off doesn't step around it" "$?" 5
(cd "$G/repos/https" && gx gh pr review 3 --approve 2>/dev/null); eq "guard: the map's login, repo from origin" "$?" 5
env -u CLAUDECODE PDO_DISPATCHED=1 PDO_GH_REVIEW_GUARD_FILE="$G/guard" GH_TOKEN=tok-alice-work gh pr review 5 --approve -R acme-corp/gov 2>/dev/null
eq "guard: an engine-launched agent (PDO_DISPATCHED)" "$?" 5
eq "guard: refused calls never reach gh" "$(wc -l <"$GLOG")" "$n0"
gx env GH_TOKEN=tok-alice-work gh pr review 5 -c -b hi -R acme-corp/widget; has "guard: scope verdicts lets a comment review through" "$(last)" "argv=pr review 5 -c -b hi -R acme-corp/widget"
gx env GH_TOKEN=tok-alice-work gh api repos/acme-corp/widget/pulls/5/reviews -f body=x; has "guard: ... and a pending review" "$(last)" "argv=api repos/acme-corp/widget/pulls/5/reviews"
gx env GH_TOKEN=tok-alice-work gh api repos/acme-corp/gov/pulls/5/reviews; has "guard: reading reviews is fine" "$(last)" "argv=api repos/acme-corp/gov/pulls/5/reviews"
gx env GH_TOKEN=tok-bot gh pr review 5 --approve -R acme-corp/gov; has "guard: another login's token (a bot) passes" "$(last)" "token=tok-bot argv=pr review"
gx gh pr review 5 --approve -R alice/notes; has "guard: an unguarded repo passes" "$(last)" "token=tok-alice argv=pr review 5 --approve -R alice/notes"
env -u CLAUDECODE -u PDO_DISPATCHED PDO_GH_REVIEW_GUARD_FILE="$G/guard" GH_TOKEN=tok-alice-work gh pr review 5 --approve -R acme-corp/gov
has "guard: the person's own shell passes" "$(last)" "argv=pr review 5 --approve -R acme-corp/gov"
gx env GH_TOKEN=tok-alice-work gh pr comment 5 -b hi -R acme-corp/gov; has "guard: a PR comment is not a review" "$(last)" "argv=pr comment 5"
# install writes the rules from each project's GH_REVIEW_GUARD (login = its GH_USER)
mkdir -p "$G/gcfg/projects"
printf 'ORG="acme-corp"\nGH_USER="alice-work"\ndeclare -A REPO_ROOT=([gov]="%s")\nGH_REVIEW_GUARD=("acme-corp/gov" "acme-corp/*=verdicts")\n' "$G/repos/https" >"$G/gcfg/projects/guarded.env"
PDO_CONFIG_DIRS="$G/gcfg" "$BIN/install" --review-guard >/dev/null 2>&1
eq "guard: install --review-guard writes the rules" "$(grep -v '^#' "$GCFG/gh-review-guard")" "$(printf 'acme-corp/* alice-work verdicts\nacme-corp/gov alice-work all')"
eq "guard: project-env lists GH_REVIEW_GUARD" "$(PDO_CONFIG_DIRS="$G/gcfg" "$BIN/project-env" --project guarded GH_REVIEW_GUARD)" "acme-corp/gov acme-corp/*=verdicts"
out="$(cd "$G/repos/https" && "$BIN/install" --gh-identities --check 2>&1)"
has "guard: --check flags rules that no longer match the projects" "$out" "STALE: the review guard"
rm -f "$GCFG/gh-review-guard"

# git: per-owner credentials (a real `git credential fill`) and per-owner user.email
gcred() {  # gcred <dir> <path>: username:password git answers for https://github.com/<path>
  (cd "$1" && printf 'protocol=https\nhost=github.com\npath=%s\n\n' "$2" | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null \
    | awk -F= '/^username=/{u=$2} /^password=/{p=$2} END{print u ":" p}')
}
eq "git: https remote, its owner" "$(gcred "$G/repos/https" acme-corp/widget.git)" "alice-work:tok-alice-work"
eq "git: ssh remote repo, https URL of its owner" "$(gcred "$G/repos/ssh" acme-corp/widget.git)" "alice-work:tok-alice-work"
eq "git: another owner from the same repo" "$(gcred "$G/repos/https" alice/notes.git)" "alice:tok-alice"
eq "git: outside any repo (clone)" "$(gcred "$G" acme-corp/new.git)" "alice-work:tok-alice-work"
eq "git: an owner prefix is not the owner (default)" "$(gcred "$G" acme-corpx/widget.git)" "alice:tok-alice"
eq "git: unmapped owner = default" "$(gcred "$G" stranger/x.git)" "alice:tok-alice"
eq "git: includeIf email (https remote)" "$(git -C "$G/repos/https" config user.email)" "alice@acme-corp.example"
eq "git: includeIf name (https remote)" "$(git -C "$G/repos/https" config user.name)" "Alice Example"
eq "git: includeIf email (git@ remote)" "$(git -C "$G/repos/ssh" config user.email)" "alice@acme-corp.example"
eq "git: includeIf email (ssh:// remote)" "$(git -C "$G/repos/sshurl" config user.email)" "alice@acme-corp.example"
eq "git: second owner's email" "$(git -C "$G/repos/alice" config user.email)" "alice@example.com"
eq "git: other owners keep the global email" "$(git -C "$G/repos/other" config user.email)" "base@example.com"
eq "git: the env pin (with-gh-user) beats the owner helper" "$(cd "$G/repos/https" && printf 'protocol=https\nhost=github.com\npath=acme-corp/w.git\n\n' \
  | GIT_TERMINAL_PROMPT=0 "$BIN/with-gh-user" --user octo git credential fill 2>/dev/null | sed -n 's/^password=//p')" "tok-octo"
# helper order: a github.com helper appended after the include (a later `gh auth setup-git`)
LATE='[credential "https://github.com"]\n\thelper =\n\thelper = "!f() { echo username=late; echo password=late; }; f"\n'
printf "$LATE" >>"$GIT_CONFIG_GLOBAL"
{ cat "$G/gitconfig.orig"; printf "$LATE"; } >"$G/gitconfig.late"
eq "git: a later github.com reset overrides (the problem)" "$(gcred "$G/repos/https" acme-corp/widget.git)" "late:late"
"$BIN/install" --gh-identities >/dev/null 2>&1
eq "git: re-install moves the include below it" "$(gcred "$G/repos/https" acme-corp/widget.git)" "alice-work:tok-alice-work"
eq "git: still one include line" "$(git config --global --get-all include.path | wc -l)" 1
# --check / --status / fleet
out="$(cd "$G/repos/https" && "$BIN/install" --gh-identities --check 2>&1)"; rc=$?
eq "ghid --check: exit 0 when all is well" "$rc" 0
has "ghid --check: owner -> login" "$out" "owner acme-corp (origin) -> login alice-work (map)"
has "ghid --check: email" "$out" "<alice@acme-corp.example>"
has "ghid --check: git answers as the login" "$out" "username alice-work"
has "ghid --check: shim active" "$out" "shim: active"
out="$(cd "$G/repos/https" && PATH="$G/real:$SHIMD:$OLDPATH" "$BIN/install" --gh-identities --check 2>&1)"; rc=$?
eq "ghid --check: shim not first = exit 1" "$rc" 1
has "ghid --check: says so" "$out" "not first on PATH"
eq "ghid --status" "$("$BIN/install" --gh-identities --status)" "shim active; map: acme-corp->alice-work, alice->alice, lone->ghost; default alice"
has "fleet: gh identities line" "$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" --no-queue 2>/dev/null)" "== gh identities: shim active; map: acme-corp->alice-work"
check "sysreport: gh identities line" grep -q 'gh identities: .*--gh-identities --status' "$BIN/sysreport"
# a bad map is refused
printf 'acme-corp\n' >"$G/badmap"
"$BIN/install" --gh-identities --map "$G/badmap" >/dev/null 2>&1; eq "ghid: a malformed map is refused" "$?" 1
check "ghid: ... and the installed map is kept" cmp -s "$G/map" "$GCFG/gh-identities"
# uninstall
out="$("$BIN/install" --gh-identities --uninstall 2>&1)"; rc=$?
eq "ghid --uninstall: exit 0" "$rc" 0
check "ghid --uninstall: shim removed" test ! -e "$SHIMD/gh"
check "ghid --uninstall: helper and git files removed" test ! -e "$GCFG/gitconfig-identities" -a ! -e "$GCFG/gitconfig-identities.d" \
  -a ! -e "$XDG_DATA_HOME/project-dev-orchestration/gh-identity-credential"
check "ghid --uninstall: the map is kept" test -f "$GCFG/gh-identities"
eq "ghid --uninstall: only the include line is gone" "$(cmp -s "$GIT_CONFIG_GLOBAL" "$G/gitconfig.late" && echo same || diff "$G/gitconfig.late" "$GIT_CONFIG_GLOBAL")" same
"$BIN/install" --gh-identities --uninstall >/dev/null 2>&1; eq "ghid --uninstall: twice is fine" "$?" 0
eq "ghid --status after uninstall" "$("$BIN/install" --gh-identities --status)" "shim not installed; map: acme-corp->alice-work, alice->alice, lone->ghost; default alice"
export PATH="$OLDPATH"

echo "smoke: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
