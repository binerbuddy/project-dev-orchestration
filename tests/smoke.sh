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
  "api repos/acme/widget/issues/12") cat "$SMOKE_DIR/issue12.json" ;;
  "api repos/acme/widget/issues/12/comments"*) ;;
  "pr view 5 -R acme/widget"*) cat "$SMOKE_DIR/pr5.json" ;;
  "project item-list"*) echo '{"items":[]}' ;;
  "api repos/acme/"*"/issues?state=open"*) ;;
  "api graphql"*"open: pullRequests"*) echo '{"data":{"repository":{"open":{"nodes":[]},"done":{"nodes":[]}}}}' ;;
  "api graphql"*) echo '{"data":{"repository":{"pullRequests":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}' ;;
  *) echo "fake gh: unhandled: $*" >&2; exit 1 ;;
esac
EOF
cat >"$T/fakebin/herdr" <<'EOF'
#!/usr/bin/env bash
echo "herdr $*" >>"$SMOKE_LOG"
case "$1 ${2:-}" in
  "workspace list") echo '{"result":{"workspaces":[]}}' ;;
  "agent list") echo '{"result":{"agents":[]}}' ;;
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
for p in queue watch hibernate pr-priority pr-agent; do check "$p --help" "$BIN/$p" --help; done

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

# --- identity wrapper ---
w="$(cd "$T" && bash -c "source '$BIN/lib.sh'; PROJECT=acme; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; pdo_finalize; identity_wrapper '$T/repos/widget.git'")"
eq "identity: no GH_USER, no hook output = no wrapper" "$w" ""
w="$(cd "$T" && bash -c "source '$BIN/lib.sh'; pdo_resolve_project acme; HERE=\"\$PDO_ENV_DIR\" source \"\$PDO_ENV_FILE\"; GH_USER=octo; pdo_finalize; identity_wrapper '$T/repos/docs'")"
eq "identity: GH_USER pin + hook word" "$w" "$BIN/with-gh-user --user octo extra-identity"
eq "with-gh-user without a login just runs" "$("$BIN/with-gh-user" printenv GH_TOKEN || echo unset)" unset
eq "with-gh-user --user pins GH_TOKEN" "$("$BIN/with-gh-user" --user octo printenv GH_TOKEN)" token-for-octo

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
