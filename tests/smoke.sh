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
unset PDO_INBOX INTAKE_INBOX PDO_PROJECT PDO_SKILL_PREFIX GH_USER GH_TOKEN
export GIT_AUTHOR_NAME=smoke GIT_AUTHOR_EMAIL=smoke@example.com GIT_COMMITTER_NAME=smoke GIT_COMMITTER_EMAIL=smoke@example.com
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global init.defaultBranch main

# fake gh and herdr: canned answers, every call logged
mkdir -p "$T/fakebin"
cat >"$T/fakebin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$SMOKE_LOG"
case "$*" in
  "api user --jq .login") echo me ;;
  "auth token -u "*) echo "token-for-${@: -1}" ;;
  "auth git-credential"*) cat >/dev/null; printf 'protocol=https\nhost=github.com\nusername=x-access-token\npassword=%s\n' "${GH_TOKEN:-none}" ;;
  "pr edit"*|"pr comment"*) ;;
  "api repos/acme/widget/issues/comments?since="*) [[ -n "${SMOKE_COMMENTS:-}" ]] && cat "$SMOKE_COMMENTS" ;;
  "api graphql"*"query board"*)
    echo '{"data":{"organization":{"projectV2":{"id":"PVT_b7","number":7,"title":"Acme Board","field":{"id":"PVTSSF_s","options":[{"id":"o1","name":"Backlog"},{"id":"o2","name":"Claude Work This"}]}}}}}' ;;
  "api repos/acme/widget/issues/12") cat "$SMOKE_DIR/issue12.json" ;;
  "api repos/acme/widget/issues/12/comments"*) ;;
  "pr view 5 -R acme/widget"*) cat "$SMOKE_DIR/pr5.json" ;;
  "project item-list 9 --owner alpha"*) echo '{"items":[{"content":{"number":2},"repository":"alpha/tool","status":"Claude Work This"}]}' ;;
  "project item-list"*) echo '{"items":[]}' ;;
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
  "api repos/acme/"*"/issues?state=open"*) ;;
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
echo "hook $* pr=${PDO_QC_PR:-} ref=${PDO_QC_REF:-} key=${PDO_QC_KEY:-} wt=${PDO_QC_WORKTREE:-}" >>"$SMOKE_LOG"
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
for p in queue watch hibernate pr-priority pr-agent fleet; do check "$p --help" "$BIN/$p" --help; done

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
eq "skill prefix default" "$(jq -r .route_skill.small <<<"$J")" "/project-dev-orchestration:project-small-feature-or-bug-fix"
eq "PDO_SKILL_PREFIX override" "$(PDO_SKILL_PREFIX=/ "$BIN/pdo-config" --project acme --json | jq -r .orchestrate_skill)" "/project-orchestrate"
eq "label defaults" "$(jq -r '.label_qc_ready + "|" + .cwt_status + "|" + (.p_labels | join(","))' <<<"$J")" "ready for QC|Claude Work This|P1-urgent,P2-high,P3-medium,P4-low"
eq "qc ports" "$(jq -c .qc_ports <<<"$J")" "[3999]"
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
out="$("$BIN/project-env" --board 2>&1)"
has "project-env --board prints the board node id" "$out" "BOARD_ID=PVT_b7"
has "project-env --board prints Status option ids" "$out" "STATUS_OPTION[Claude Work This]=o2"
out="$("$BIN/project-env" --project beta --board 2>&1)"; has "project-env --board without a board fails clearly" "$out" "no PROJECT_NUMBER"

# --- identity wrapper ---
w="$(cd "$T" && bash -c "source '$BIN/lib.sh'; PROJECT=acme; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; pdo_finalize; identity_wrapper '$T/repos/widget.git'")"
eq "identity: no GH_USER, no hook output = no wrapper" "$w" ""
w="$(cd "$T" && bash -c "source '$BIN/lib.sh'; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; GH_USER=octo; pdo_finalize; identity_wrapper '$T/repos/docs'")"
eq "identity: GH_USER pin + hook word" "$w" "$BIN/with-gh-user --user octo extra-identity"
c="$(cd "$T" && bash -c "source '$BIN/lib.sh'; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; GH_USER=octo; pdo_finalize; agent_command '$T/repos/widget.git' 'Acme-12 x' opus 'do it' --resume s1")"
has "launch command marks the agent dispatched" "$c" "env PDO_DISPATCHED=1 $BIN/with-gh-user --user octo claude --resume s1 --remote-control"
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

# --- intake inbox ---
out="$("$BIN/intake-submit" "Acme-12 smoke" "a report")"
f="${out#queued for intake: }"
has "intake-submit into the state inbox" "$f" "$T/state/intake-inbox/"
check "intake report written" grep -q "from: Acme-12 smoke" "$f"
out="$(INTAKE_INBOX="$T/legacy-inbox" "$BIN/intake-submit" ws "r2")"; has "INTAKE_INBOX honoured" "$out" "$T/legacy-inbox/"
out="$(INTAKE_INBOX="$T/legacy-inbox" PDO_INBOX="$T/new-inbox" "$BIN/intake-submit" ws "r3")"; has "PDO_INBOX beats INTAKE_INBOX" "$out" "$T/new-inbox/"
echo "" | "$BIN/intake-submit" ws >/dev/null 2>&1; eq "empty report refused" "$?" 1

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
has "spawn dry-run prompt names the skill" "$(jq -r .prompt <<<"$out" 2>/dev/null)" "/project-dev-orchestration:project-small-feature-or-bug-fix Work acme/widget#12"
check "spawn dry-run logged no failure" test ! -e "$T/state/spawn-failures.jsonl"
"$BIN/spawn" nosuchrepo 12 >/dev/null 2>&1
check "spawn failure is logged" grep -q '"repo":"nosuchrepo"' "$T/state/spawn-failures.jsonl"

# --- python scripts against the fakes ---
out="$("$BIN/queue" --json 2>&1)"; eq "queue (empty board)" "$(jq -c .ranked <<<"$out" 2>/dev/null)" "[]"
out="$("$BIN/queue" --project beta 2>&1)"; has "queue needs a PROJECT_NUMBER" "$out" "no PROJECT_NUMBER"
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

# --- qc-fixture-push against the local origin ---
echo data >"$T/sample.acme"
out="$("$BIN/qc-fixture-push" 5 "$T/sample.acme" 2>&1)"
has "fixture URL printed" "$out" "https://github.com/acme/widget/blob/qc-fixtures/5/sample.acme"
check "fixture on the origin branch" git -C "$T/origin.git" cat-file -e qc-fixtures:5/sample.acme
has "fixture README uses FIXTURE_EXT" "$(git -C "$T/origin.git" show qc-fixtures:README.md)" "<name>.acme"
echo other >"$T/other.bin"
out="$("$BIN/qc-fixture-push" 5 "$T/other.bin" 2>&1)"; has "fixture extension warning" "$out" "does not end in .acme"
eq "re-push unchanged" "$("$BIN/qc-fixture-push" 5 "$T/sample.acme" 2>/dev/null | head -1)" unchanged
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
{ iss 1 "ordinary work" P2-high; iss 2 "urgent work" P1-urgent; } >"$T/alpha-issues.jsonl"
jq -n '{data: {repository: {pullRequests: {totalCount: 2, nodes: [
  {number: 10, title: "agent three", url: "https://github.com/alpha/tool/pull/10", isDraft: false, headRefName: "feat/3", labels: {nodes: [{name: "ready for QC"}]}},
  {number: 11, title: "agent four", url: "https://github.com/alpha/tool/pull/11", isDraft: false, headRefName: "feat/4", labels: {nodes: [{name: "QC complete - ready to review"}]}}]},
  gates: {nodes: [{number: 6, title: "a prototype", url: "https://github.com/alpha/tool/issues/6"}]}}}}' >"$T/fleet-tool.json"
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
has "fleet: no board is reported, not fatal" "$(jq -r '.projects[1].queue.error' <<<"$out" 2>/dev/null)" "no board"
eq "fleet: PRs vs cap" "$(jq -c '.projects[0].prs | [.open, .awaiting_human, .cap]' <<<"$out" 2>/dev/null)" '[2,2,10]'
eq "fleet: waiting on you ranked by impact" "$(jq -c '[.waiting_on_you[].why]' <<<"$out" 2>/dev/null)" '["merge (QC passed)","question","UX gate","QC","intake inbox"]'
eq "fleet: rate limits per GH_USER identity" "$(jq -c '[.system.gh[] | "\(.user)=\(.graphql.remaining)"]' <<<"$out" 2>/dev/null)" '["(active gh account)=4000","gbot=4000"]'
eq "fleet: agent count" "$(jq -c '.system.agents | [.herdr_total, .claude, .project_active, .self_managed_active]' <<<"$out" 2>/dev/null)" '[3,3,1,1]'
eq "fleet: a self-managed repo's agent is not in the project's active" "$(jq -c '.projects[1].agents | [(.active | length), (.self_managed | map(.agent + ":" + .owner))]' <<<"$out" 2>/dev/null)" '[0,["lib#5:Lib Lead"]]'
eq "fleet: ... nor in its advice" "$(jq -r '.advice.gamma.active' <<<"$out" 2>/dev/null)" 0
eq "fleet: ... but in its memory estimate" "$(jq -r '.projects[1].est_agent_mb' <<<"$out" 2>/dev/null)" 400
has "fleet text: self-managed line names the owner" "$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" --project gamma 2>/dev/null)" "self-managed (owner: Lib Lead) 1: lib-5 owned work"
check "fleet: gbot's calls used its own token" grep -q "gh auth token -u gbot" "$SMOKE_LOG"
check "fleet without --write-advice writes nothing" test ! -e "$FS/fleet-advice.json"

out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=2000 "$BIN/fleet" --json 2>/dev/null)"
eq "fleet: low memory holds heavy, slows the rest" "$(jq -c '[.advice.alpha.advice, .advice.gamma.advice]' <<<"$out" 2>/dev/null)" '["hold","slow"]'
has "fleet: hold reason names memory" "$(jq -r .advice.alpha.reason <<<"$out" 2>/dev/null)" "heavy project"
out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 PDO_FLEET_WEEKLY=85 "$BIN/fleet" --json 2>/dev/null)"
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
eq "deps add" "$("${F[@]}" "$BIN/fleet" deps add alpha/tool#5 blocks gamma/lib#7 --note "needs the API")" "added #1: alpha/tool#5 blocks gamma/lib#7"
"${F[@]}" "$BIN/fleet" deps add alpha/tool#8 blocks gamma/lib#7 >/dev/null
"${F[@]}" "$BIN/fleet" deps add gamma/lib#7 blocks alpha/tool#1 >/dev/null
has "deps add duplicate" "$("${F[@]}" "$BIN/fleet" deps add alpha/tool#5 blocks gamma/lib#7)" "already recorded"
"${F[@]}" "$BIN/fleet" deps add "tool#5" blocks gamma/lib#7 >/dev/null 2>&1; eq "deps add rejects a bare ref" "$?" 1
has "deps list" "$("${F[@]}" "$BIN/fleet" deps list)" "#1 alpha/tool#5 blocks gamma/lib#7  - needs the API"
out="$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" --json 2>/dev/null)"
eq "fleet flags closed and merged blockers" "$(jq -c '[.deps[] | "\(.id):\(.blocker_state)"]' <<<"$out" 2>/dev/null)" '["1:closed","2:merged","3:open"]'
has "fleet text says mark done" "$("${F[@]}" PDO_FLEET_MEM_AVAIL_MB=20000 "$BIN/fleet" 2>/dev/null)" "blocker CLOSED: mark done (pdo fleet deps done 1)"
eq "deps done by pair" "$("${F[@]}" "$BIN/fleet" deps done alpha/tool#5 blocks gamma/lib#7)" "done #1: alpha/tool#5 blocks gamma/lib#7"
eq "deps done by id" "$("${F[@]}" "$BIN/fleet" deps done 2)" "done #2: alpha/tool#8 blocks gamma/lib#7"
eq "deps list shows open only" "$("${F[@]}" "$BIN/fleet" deps list --json | jq -c 'map(.id)')" "[3]"
eq "deps list --all" "$("${F[@]}" "$BIN/fleet" deps list --all --json | jq -c 'map(.id)')" "[1,2,3]"
"${F[@]}" "$BIN/fleet" deps done 2 >/dev/null 2>&1; eq "deps done twice fails" "$?" 1

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

# --- watch: a "Claude, QC pass" comment swaps the QC labels (no preview service needed) ---
jq -n '{data: {repository: {open: {nodes: [{number: 5, state: "OPEN", isDraft: false, url: "https://github.com/acme/widget/pull/5",
  headRefName: "feat/5", baseRefName: "main", mergeable: "MERGEABLE", labels: {nodes: [{name: "ready for QC"}]}}]}, done: {nodes: []}}}}' >"$T/prs.json"
{ jq -nc '{id: 901, body: "Claude, QC pass", html_url: "https://github.com/acme/widget/pull/5#c901", issue_url: "https://api.github.com/repos/acme/widget/issues/5", user: "boss", assoc: "OWNER"}'
  jq -nc '{id: 902, body: "claude, qc pass", html_url: "u", issue_url: "https://api.github.com/repos/acme/widget/issues/5", user: "drive-by", assoc: "NONE"}'
  jq -nc '{id: 903, body: "Claude, QC pass", html_url: "u", issue_url: "https://api.github.com/repos/acme/widget/issues/9", user: "boss", assoc: "MEMBER"}'; } >"$T/comments.jsonl"
WS="$T/watch-state"; mkdir -p "$WS"
out="$(PDO_STATE_DIR="$WS" SMOKE_PRS="$T/prs.json" SMOKE_COMMENTS="$T/comments.jsonl" "$BIN/watch" --project acme 2>/dev/null)"
check "watch: QC pass swapped the labels" grep -q "gh pr edit 5 -R acme/widget --remove-label ready for QC --add-label QC complete - ready to review" "$SMOKE_LOG"
check "watch: QC pass replied on the PR" grep -q "gh pr comment 5 -R acme/widget --body QC pass recorded" "$SMOKE_LOG"
eq "watch: QC pass events (untrusted ignored, unknown PR reported)" "$(jq -c '[.events[] | select(.type | startswith("qc_pass")) | "\(.type):\(.pr)"]' <<<"$out" 2>/dev/null)" '["qc_pass_recorded:widget#5","qc_pass_ignored:widget#9"]'
: >"$SMOKE_LOG"
PDO_STATE_DIR="$WS" SMOKE_PRS="$T/prs.json" SMOKE_COMMENTS="$T/comments.jsonl" "$BIN/watch" --project acme >/dev/null 2>&1
check "watch: a QC pass comment is acted on once" bash -c "! grep -q 'gh pr edit' '$SMOKE_LOG'"
out="$(PDO_STATE_DIR="$T/watch-peek" SMOKE_PRS="$T/prs.json" SMOKE_COMMENTS="$T/comments.jsonl" "$BIN/watch" --project acme --peek 2>/dev/null)"
check "watch --peek never applies a QC pass" bash -c "! grep -q 'gh pr edit' '$SMOKE_LOG'"

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

echo "smoke: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
