# shellcheck shell=bash
# Shared helpers for the project-dev-orchestration engine scripts (bin/*).
#
# Config contract (see docs/design.md, "Configuration"):
#   PDO_CONFIG_DIRS  colon-separated config dirs, first match wins
#                    (default ${XDG_CONFIG_HOME:-~/.config}/project-dev-orchestration).
#                    Each may hold projects/<name>.env, prompts/ and hooks/.
#   PDO_STATE_DIR    runtime state (default ${XDG_STATE_HOME:-~/.local/state}/project-dev-orchestration)
#   PDO_INBOX        intake inbox (default $PDO_STATE_DIR/intake-inbox; INTAKE_INBOX is still honoured)
#   PDO_PROJECT      project to use when --project is omitted (before cwd detection)
#   PDO_SKILL_PREFIX the slash prefix for skill names (default "/project-dev-orchestration:", the
#                    Claude Code plugin namespace; set "/" when the skills are linked bare, e.g. by
#                    `bin/install --claude --link`, or for Codex/Grok skill dirs)
# Each config dir may also hold config.env: install-wide defaults, sourced when lib.sh loads (the
# first config dir wins). Write `: "${KEY:=value}"` there so a real environment variable still wins;
# a project env sourced later overrides plain assignments.
#
# A script loads its project like this (top level, so the env file's `declare -A` stays global):
#   pdo_resolve_project "$PROJECT"                      # --project value, may be empty
#   HERE="$PDO_ENV_DIR" source "$PDO_ENV_FILE"; pdo_finalize
# While the env file is sourced, $HERE is the config dir that holds it, so an env file can say
# BRIEF_TEMPLATE="$HERE/prompts/x.md". Relative hook and template paths resolve against that dir too.

PDO_HOME="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
export PDO_HOME

pdo_die() { echo "${PDO_SCRIPT:-$(basename "$0")}: $*" >&2; exit 1; }

# pdo_config_dirs: one config dir per line, in priority order
pdo_config_dirs() {
  local dirs="${PDO_CONFIG_DIRS:-${XDG_CONFIG_HOME:-$HOME/.config}/project-dev-orchestration}" d
  local IFS=:
  for d in $dirs; do [[ -n "$d" ]] && printf '%s\n' "$d"; done
}

# install-wide config.env files: sourced last-dir-first, so the first config dir wins
_pdo_load_globals() {
  local d i dirs=()
  mapfile -t dirs < <(pdo_config_dirs)
  for (( i=${#dirs[@]}-1; i>=0; i-- )); do
    d="${dirs[$i]}"
    # shellcheck source=/dev/null
    [[ -f "$d/config.env" ]] && HERE="$d" source "$d/config.env"
  done
  return 0
}
_pdo_load_globals
: "${PDO_SKILL_PREFIX:=/project-dev-orchestration:}"
export PDO_SKILL_PREFIX

pdo_state_dir() { printf '%s' "${PDO_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/project-dev-orchestration}"; }
pdo_inbox() { printf '%s' "${PDO_INBOX:-${INTAKE_INBOX:-$(pdo_state_dir)/intake-inbox}}"; }

# pdo_project_files: "<name><TAB><env file>" for every project, first config dir wins per name
pdo_project_files() {
  local d f n seen=" "
  while IFS= read -r d; do
    for f in "$d"/projects/*.env; do
      [[ -f "$f" ]] || continue
      n="$(basename "$f" .env)"
      [[ "$seen" == *" $n "* ]] && continue
      seen+="$n "
      printf '%s\t%s\n' "$n" "$f"
    done
  done < <(pdo_config_dirs)
}

pdo_known_projects() { pdo_project_files | cut -f1 | paste -sd' '; }

# pdo_env_file <name>: the env file that defines a project (first config dir wins)
pdo_env_file() { pdo_project_files | awk -F'\t' -v n="$1" '$1 == n && !f {print $2; f = 1}'; }

# pdo_repo_roots_of <env file>: the REPO_ROOT values it declares, one per line
pdo_repo_roots_of() {
  (
    HERE="$(cd "$(dirname "$1")/.." && pwd)"
    # shellcheck source=/dev/null
    source "$1" >/dev/null 2>&1 || exit 0
    declare -p REPO_ROOT >/dev/null 2>&1 || exit 0
    for r in "${REPO_ROOT[@]}"; do printf '%s\n' "$r"; done
  )
}

_pdo_common_dir() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }

# pdo_detect_project [dir]: the project whose REPO_ROOT holds <dir>'s repo (matched on the git
# common dir, so any worktree of a bare root matches), else whose root contains <dir>.
pdo_detect_project() {
  local dir="${1:-$PWD}" want name file root common abs
  want="$(_pdo_common_dir "$dir" || true)"
  abs="$(cd "$dir" 2>/dev/null && pwd -P || printf '%s' "$dir")"
  while IFS=$'\t' read -r name file; do
    while IFS= read -r root; do
      [[ -n "$root" ]] || continue
      if [[ -n "$want" ]]; then
        common="$(_pdo_common_dir "$root" || true)"
        if [[ -n "$common" && "$common" == "$want" ]]; then printf '%s' "$name"; return 0; fi
      fi
      root="$(cd "$root" 2>/dev/null && pwd -P || printf '%s' "$root")"
      if [[ "$abs" == "$root" || "$abs" == "$root"/* ]]; then printf '%s' "$name"; return 0; fi
    done < <(pdo_repo_roots_of "$file")
  done < <(pdo_project_files)
  return 1
}

# pdo_resolve_project <name or empty>: sets PROJECT, PDO_ENV_FILE and PDO_ENV_DIR.
# Order: the argument (--project), then $PDO_PROJECT, then cwd detection. Never a built-in default.
pdo_resolve_project() {
  local name="${1:-${PDO_PROJECT:-}}"
  if [[ -z "$name" ]]; then
    name="$(pdo_detect_project "$PWD" || true)"
    [[ -n "$name" ]] || pdo_die "no project matches $PWD; pass --project <name>. Known projects: $(pdo_known_projects || true) (config dirs: $(pdo_config_dirs | paste -sd:))"
  fi
  PDO_ENV_FILE="$(pdo_env_file "$name")"
  [[ -n "$PDO_ENV_FILE" ]] || pdo_die "unknown project '$name'. Known projects: $(pdo_known_projects || true) (config dirs: $(pdo_config_dirs | paste -sd:))"
  PROJECT="$name"
  PDO_ENV_DIR="$(cd "$(dirname "$PDO_ENV_FILE")/.." && pwd)"
  export PDO_ENV_FILE PDO_ENV_DIR
}

# _pdo_abs <path>: a relative path resolved against the config dir that defined the env
_pdo_abs() {
  case "$1" in
    "") ;;
    /*) printf '%s' "$1" ;;
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    *) printf '%s' "$PDO_ENV_DIR/$1" ;;
  esac
}

# pdo_find_prompt <file>: first config dir holding prompts/<file>, else the engine's copy
pdo_find_prompt() {
  local d
  while IFS= read -r d; do
    [[ -f "$d/prompts/$1" ]] && { printf '%s' "$d/prompts/$1"; return 0; }
  done < <(pdo_config_dirs)
  printf '%s' "$PDO_HOME/prompts/$1"
}

# pdo_finalize: after sourcing the env file, fill defaults, resolve paths, and export what hooks need
pdo_finalize() {
  PDO_STATE_DIR="$(pdo_state_dir)"
  PDO_INBOX="$(pdo_inbox)"
  PDO_PROJECT="$PROJECT"
  export PDO_STATE_DIR PDO_INBOX PDO_PROJECT
  local k
  for k in IDENTITY_HOOK TEAM_UP_HOOK SYSREPORT_HOOK QC_HOOK WATCH_EVENT_HOOK BRIEF_TEMPLATE CONTROL_DIR AGENT_QC_NOTES AGENT_QC_REVIEW_HOOK; do
    [[ -n "${!k:-}" ]] && printf -v "$k" '%s' "$(_pdo_abs "${!k}")"
  done
  BRIEF_TEMPLATE="${BRIEF_TEMPLATE:-$(pdo_find_prompt dispatch-brief.md)}"
  CONTROL_DIR="${CONTROL_DIR:-$PDO_ENV_DIR}"   # where the standing agents (orchestrator, QC, intake) run
  AGENT_CLI="${AGENT_CLI:-claude}"
  DEFAULT_MODEL="${DEFAULT_MODEL:-opus}"
  PRIMARY_REPO="${PRIMARY_REPO:-}"
  GH_USER="${GH_USER:-}"
  FIXTURE_EXT="${FIXTURE_EXT:-}"
  FIXTURE_BRANCH="${FIXTURE_BRANCH:-qc-fixtures}"
  QC_WORKTREE="${QC_WORKTREE:-qc}"
  QC_REPO="${QC_REPO:-$PRIMARY_REPO}"
  QC_PORTS="${QC_PORTS:-}"
  # agent QC (the standing "QC Agent (<project>)" workspace): off unless AGENT_QC_PORTS is set
  AGENT_QC_PORTS="${AGENT_QC_PORTS:-}"            # its reserved ports (e.g. "3200 4400"); hibernation never stops them
  AGENT_QC_REPOS="${AGENT_QC_REPOS:-$QC_REPO}"    # repos whose 'ready for QC' PRs it takes (space-separated)
  AGENT_QC_WORKTREE="${AGENT_QC_WORKTREE:-qc-agent}"  # its own worktree under each repo root
  AGENT_QC_MAX_ROUNDS="${AGENT_QC_MAX_ROUNDS:-2}" # failed rounds before 'QC escalated'
  AGENT_QC_NOTES="${AGENT_QC_NOTES:-}"            # optional: the project's agent-QC know-how (a markdown file)
  AGENT_QC_REVIEW_HOOK="${AGENT_QC_REVIEW_HOOK:-}" # optional: run by `agent-qc verdict … pass-ux` with <repo> <pr#> (e.g. request a hosted preview)
  WATCH_EVENT_HOOK="${WATCH_EVENT_HOOK:-}"   # optional: bin/watch runs it each snapshot for project-specific events
  WATCH_EVENT_HOOK_TIMEOUT="${WATCH_EVENT_HOOK_TIMEOUT:-120}"  # seconds before the watcher gives up on it
  SYSTEM_MANAGER_WORKSPACE="${SYSTEM_MANAGER_WORKSPACE:-System Manager}"
  ORCHESTRATE_SKILL="${ORCHESTRATE_SKILL:-${PDO_SKILL_PREFIX}project-orchestrate}"
  QC_SKILL="${QC_SKILL:-${PDO_SKILL_PREFIX}project-qc-review}"
  INTAKE_SKILL="${INTAKE_SKILL:-${PDO_SKILL_PREFIX}project-intake}"
  AGENT_QC_SKILL="${AGENT_QC_SKILL:-${PDO_SKILL_PREFIX}project-agent-qc}"
  # board Status and label vocabulary (today's names are the defaults)
  CWT_STATUS="${CWT_STATUS:-Claude Work This}"
  P_LABELS="${P_LABELS:-P1-urgent P2-high P3-medium P4-low}"   # best first
  LABEL_QC_READY="${LABEL_QC_READY:-ready for QC}"
  LABEL_QC_DONE="${LABEL_QC_DONE:-QC complete - ready to review}"   # agent QC passed, awaiting human UX review
  LABEL_MERGE_READY="${LABEL_MERGE_READY:-Ready for Merge}"         # all QC done, awaiting code review + merge
  LABEL_UX_SKIPPED="${LABEL_UX_SKIPPED:-UX testing skipped}"        # with LABEL_MERGE_READY: agent QC judged no visible change
  LABEL_NEEDS_UX="${LABEL_NEEDS_UX:-needs UX review}"               # on an issue or PR: always route through UX review
  LABEL_QC_ESCALATED="${LABEL_QC_ESCALATED:-QC escalated}"          # agent QC failed AGENT_QC_MAX_ROUNDS times
  CARRY_LABELS="${CARRY_LABELS:-client-requested}"   # separate with commas when a name has spaces
  SCREENSHOT_DIR="${SCREENSHOT_DIR:-.omc/qa}"
  # portfolio (bin/fleet): who manages this project, its rank and resource weight across projects
  if [[ -z "${MANAGER+x}" ]]; then
    if [[ -n "${PROJECT_NUMBER:-}" ]]; then MANAGER="Orchestrator ($PROJECT)"; else MANAGER=""; fi
  fi
  # coordination: the claim label (managed-by:<slug>) and whether claim also self-assigns
  MANAGER_SLUG="$(pdo_slug "${MANAGER_SLUG:-${MANAGER:-$PROJECT}}")"
  MANAGER_SLUG="${MANAGER_SLUG:0:39}"             # GitHub label names stop at 50 characters
  CLAIM_ASSIGNS="${CLAIM_ASSIGNS:-0}"             # 1 = claim also assigns the gh login (legacy lock)
  PORTFOLIO_PRIORITY="${PORTFOLIO_PRIORITY:-3}"   # 1 = highest
  RESOURCE_PROFILE="${RESOURCE_PROFILE:-medium}"  # light | medium | heavy (bin/fleet has the weights)
  AGENT_MB="${AGENT_MB:-}"                        # override the profile's MB per active agent
  AGENT_USAGE_WEIGHT="${AGENT_USAGE_WEIGHT:-}"    # override the profile's usage weight
  FLEET_ADVICE="${FLEET_ADVICE:-ignore}"          # honour | ignore (fleet-advice.json in queue/watch)
  export ORG PRIMARY_REPO
}

# pdo_slug <text>: lower case, runs of anything but a-z0-9 become one "-", no leading/trailing "-"
# ("Orchestrator (acme)" -> "orchestrator-acme"); used for MANAGER_SLUG
pdo_slug() {
  local s="${1,,}"
  s="$(printf '%s' "$s" | tr -c 'a-z0-9' '-' | tr -s '-')"
  s="${s#-}"; printf '%s' "${s%-}"
}

# pdo_config_json: the loaded project's config as JSON (python scripts read this via bin/pdo-config)
pdo_config_json() {
  local k roots="{}" routes="{}" managed="[]" repo_mgr="{}" fx_by_repo="{}"
  if declare -p REPO_ROOT >/dev/null 2>&1; then
    for k in "${!REPO_ROOT[@]}"; do roots="$(jq -c --arg k "$k" --arg v "${REPO_ROOT[$k]}" '. + {($k): $v}' <<<"$roots")"; done
  fi
  if declare -p ROUTE_SKILL >/dev/null 2>&1; then
    for k in "${!ROUTE_SKILL[@]}"; do routes="$(jq -c --arg k "$k" --arg v "${ROUTE_SKILL[$k]}" '. + {($k): $v}' <<<"$routes")"; done
  fi
  if declare -p REPO_MANAGER >/dev/null 2>&1; then
    for k in "${!REPO_MANAGER[@]}"; do repo_mgr="$(jq -c --arg k "$k" --arg v "${REPO_MANAGER[$k]}" '. + {($k): $v}' <<<"$repo_mgr")"; done
  fi
  if declare -p FIXTURE_EXT_BY_REPO >/dev/null 2>&1; then
    for k in "${!FIXTURE_EXT_BY_REPO[@]}"; do fx_by_repo="$(jq -c --arg k "$k" --arg v "${FIXTURE_EXT_BY_REPO[$k]}" '. + {($k): $v}' <<<"$fx_by_repo")"; done
  fi
  if declare -p SELF_MANAGED_REPOS >/dev/null 2>&1; then
    managed="$(printf '%s\n' ${SELF_MANAGED_REPOS[@]+"${SELF_MANAGED_REPOS[@]}"} | jq -R . | jq -sc 'map(select(length > 0))')"
  fi
  jq -n --arg project "$PROJECT" --arg env_file "$PDO_ENV_FILE" --arg env_dir "$PDO_ENV_DIR" \
    --arg home "$PDO_HOME" --arg state "$PDO_STATE_DIR" --arg inbox "$PDO_INBOX" \
    --arg org "${ORG:-}" --arg num "${PROJECT_NUMBER:-}" --argjson roots "$roots" --argjson routes "$routes" \
    --argjson managed "$managed" --arg model "$DEFAULT_MODEL" --arg brief "$BRIEF_TEMPLATE" \
    --arg gh_user "$GH_USER" --arg primary "$PRIMARY_REPO" --arg identity "${IDENTITY_HOOK:-}" \
    --arg team_up "${TEAM_UP_HOOK:-}" --arg sysreport "${SYSREPORT_HOOK:-}" --arg qc "${QC_HOOK:-}" --arg watch_hook "${WATCH_EVENT_HOOK:-}" --arg watch_hook_timeout "${WATCH_EVENT_HOOK_TIMEOUT:-120}" \
    --arg fixture_ext "$FIXTURE_EXT" --argjson fx_by_repo "$fx_by_repo" --arg fixture_branch "$FIXTURE_BRANCH" --arg agent_cli "$AGENT_CLI" \
    --arg qc_worktree "$QC_WORKTREE" --arg qc_repo "$QC_REPO" --arg qc_ports "$QC_PORTS" \
    --arg sm "$SYSTEM_MANAGER_WORKSPACE" --arg control "$CONTROL_DIR" \
    --arg carry "$CARRY_LABELS" --arg shots "$SCREENSHOT_DIR" \
    --arg cwt "$CWT_STATUS" --arg plabels "$P_LABELS" --arg qc_ready "$LABEL_QC_READY" --arg qc_done "$LABEL_QC_DONE" \
    --arg merge_ready "$LABEL_MERGE_READY" --arg ux_skipped "$LABEL_UX_SKIPPED" --arg needs_ux "$LABEL_NEEDS_UX" --arg qc_escalated "$LABEL_QC_ESCALATED" \
    --arg aqc_ports "$AGENT_QC_PORTS" --arg aqc_repos "$AGENT_QC_REPOS" --arg aqc_wt "$AGENT_QC_WORKTREE" \
    --arg aqc_rounds "$AGENT_QC_MAX_ROUNDS" --arg aqc_notes "$AGENT_QC_NOTES" --arg aqc_skill "$AGENT_QC_SKILL" \
    --arg aqc_review_hook "$AGENT_QC_REVIEW_HOOK" \
    --arg orch "$ORCHESTRATE_SKILL" --arg qc_skill "$QC_SKILL" --arg intake "$INTAKE_SKILL" --arg prefix "$PDO_SKILL_PREFIX" \
    --arg max_active "${MAX_ACTIVE:-}" --arg weekly "${WEEKLY_CEILING:-}" --arg five "${FIVE_HOUR_CEILING:-}" \
    --arg manager "${MANAGER:-}" --arg manager_slug "${MANAGER_SLUG:-}" --arg claim_assigns "${CLAIM_ASSIGNS:-0}" --argjson repo_mgr "$repo_mgr" --arg prio "${PORTFOLIO_PRIORITY:-3}" \
    --arg profile "${RESOURCE_PROFILE:-medium}" --arg agent_mb "${AGENT_MB:-}" --arg weight "${AGENT_USAGE_WEIGHT:-}" \
    --arg fleet "${FLEET_ADVICE:-ignore}" --arg usage_cache "${USAGE_CACHE:-}" \
    '{project: $project, env_file: $env_file, env_dir: $env_dir, engine_home: $home, state_dir: $state,
      inbox: $inbox, org: $org, project_number: $num, repo_root: $roots, route_skill: $routes,
      self_managed_repos: $managed, default_model: $model, brief_template: $brief, gh_user: $gh_user,
      primary_repo: $primary, identity_hook: $identity, team_up_hook: $team_up, sysreport_hook: $sysreport,
      qc_hook: $qc, fixture_ext: $fixture_ext, fixture_ext_by_repo: $fx_by_repo, fixture_branch: $fixture_branch, agent_cli: $agent_cli,
      qc_worktree: $qc_worktree, qc_repo: $qc_repo,
      watch_event_hook: $watch_hook, watch_event_hook_timeout: ($watch_hook_timeout | tonumber? // 120),
      qc_ports: ($qc_ports | split(" ") | map(select(length > 0) | tonumber)),
      agent_qc_ports: ($aqc_ports | split(" ") | map(select(length > 0) | tonumber)),
      agent_qc_repos: ($aqc_repos | split(" ") | map(select(length > 0))), agent_qc_worktree: $aqc_wt,
      agent_qc_max_rounds: ($aqc_rounds | tonumber? // 2), agent_qc_notes: $aqc_notes, agent_qc_skill: $aqc_skill,
      agent_qc_review_hook: $aqc_review_hook,
      system_manager_workspace: $sm, control_dir: $control,
      cwt_status: $cwt, p_labels: ($plabels | split(" ") | map(select(length > 0))),
      label_qc_ready: $qc_ready, label_qc_done: $qc_done, label_merge_ready: $merge_ready,
      label_ux_skipped: $ux_skipped, label_needs_ux: $needs_ux, label_qc_escalated: $qc_escalated, skill_prefix: $prefix,
      orchestrate_skill: $orch, qc_skill: $qc_skill, intake_skill: $intake,
      carry_labels: ($carry | (if test(",") then split(",") else split(" ") end) | map(gsub("^\\s+|\\s+$"; "") | select(length > 0))),
      screenshot_dir: $shots,
      max_active: ($max_active | if . == "" then null else tonumber end),
      weekly_ceiling: ($weekly | if . == "" then null else tonumber end),
      five_hour_ceiling: ($five | if . == "" then null else tonumber end),
      manager: $manager, manager_slug: $manager_slug, claim_assigns: ($claim_assigns == "1"),
      claim_label: (if $manager_slug == "" then null else "managed-by:" + $manager_slug end), repo_manager: $repo_mgr, portfolio_priority: ($prio | tonumber? // 3),
      resource_profile: $profile, agent_mb: ($agent_mb | if . == "" then null else (tonumber? // null) end),
      agent_usage_weight: ($weight | if . == "" then null else (tonumber? // null) end),
      fleet_advice: $fleet, usage_cache: $usage_cache}'
}

# identity_wrapper <dir>: the command prefix that gives an agent working in <dir> its GitHub identity.
#  - GH_USER set: pin gh to that login (bin/with-gh-user), since other sessions can flip gh's
#    machine-wide active account mid-run. Unset: no pin.
#  - IDENTITY_HOOK set: the hook is run with <dir> and prints extra wrapper words (e.g. a bot
#    identity for one repo); they are appended after the pin.
identity_wrapper() {
  [[ -n "${GH_USER:-}" ]] && printf '%s --user %s' "$PDO_HOME/bin/with-gh-user" "$GH_USER"
  if [[ -n "${IDENTITY_HOOK:-}" && -x "$IDENTITY_HOOK" ]]; then
    local extra; extra="$("$IDENTITY_HOOK" "$1" 2>/dev/null || true)"
    [[ -n "$extra" ]] && printf ' %s' "$extra"
  fi
  return 0
}

# launch_agent <pane_id> <trusted_dir> <name> <model> <prompt> [extra agent args...]
# Starts the agent CLI (AGENT_CLI; only `claude` is supported today) in a herdr pane with Remote
# Control on, and waits until it is ready. This is the one seam for supporting other CLIs.
# Uses pane run (not `agent start`, which refuses a pane blocked on startup dialogs).
# Claude asks "trust this folder?" for every new git worktree; the dialog is accepted
# only when it names <trusted_dir>, which the caller created or chose. Returns 2 when
# the agent is blocked on anything else (left for a human), 1 when it never came up.
launch_agent() {
  local pane="$1" dir="$2" name="$3" model="$4" prompt="$5" cmd status="" trusted=0 screen
  shift 5
  case "${AGENT_CLI:-claude}" in
    claude) ;;
    *) echo "launch_agent: AGENT_CLI '${AGENT_CLI}' is not supported yet (only claude)" >&2; return 1 ;;
  esac
  cmd="$(agent_command "$dir" "$name" "$model" "$prompt" "$@")"
  herdr pane run "$pane" "$cmd" >/dev/null
  for _ in $(seq 1 60); do
    sleep 1
    status="$(herdr agent list | jq -r --arg p "$pane" '.result.agents[] | select(.pane_id == $p) | .agent_status' | head -1)"
    case "$status" in
      working|idle|done) return 0 ;;
      blocked)
        screen="$(herdr pane read "$pane")"
        if [[ $trusted -eq 0 ]] && grep -q "one you trust" <<<"$screen" && grep -qF "$dir" <<<"$screen"; then
          herdr pane send-keys "$pane" down enter >/dev/null; trusted=1
        else
          return 2
        fi ;;
    esac
  done
  return 1
}
launch_claude() { launch_agent "$@"; }  # old name, kept for hooks and overlays that call it

# agent_command <trusted_dir> <name> <model> <prompt> [extra agent args...]: the shell command
# launch_agent runs in the pane. PDO_DISPATCHED=1 tells the agent it was started by the engine,
# not by a collaborator (it skips the one-time human-guide check in AGENTS.md).
# No -n: a session name draws a labelled rule under question menus, which hides them from
# herdr's blocked detection (it only reads text after the last horizontal rule).
agent_command() {
  local dir="$1" name="$2" model="$3" prompt="$4" cmd
  shift 4
  # shellcheck disable=SC2046
  printf -v cmd '%q ' env PDO_DISPATCHED=1 $(identity_wrapper "$dir") claude "$@" --remote-control "$name" --model "$model" "$prompt"
  printf '%s' "$cmd"
}

# write_meta <repo> <num> <json-fields>: merge fields into the agent's metadata file, which
# the watcher, qc-review and resume-agent read (route, branch, worktree, cwd, session_id, …).
write_meta() {
  local dir; dir="$(pdo_state_dir)/agents"; local f
  mkdir -p "$dir"; f="$dir/$1-$2.json"
  jq -s '.[0] * .[1]' <([[ -f "$f" ]] && cat "$f" || echo '{}') <(echo "$3") >"$f.tmp" && mv "$f.tmp" "$f"
}

# session_of <pane_id>: the agent session id herdr reports for a pane
session_of() {
  herdr agent list | jq -r --arg p "$1" '.result.agents[] | select(.pane_id == $p) | .agent_session.value // empty' | head -1
}

# pdo_free_port <port>: kill whatever listens on a port. Match by port (ss), never by
# command-line pattern: `pkill -f` patterns also match the invoking shell and kill it.
pdo_free_port() {
  local port="$1" pids
  pids="$(ss -ltnpH "sport = :$port" 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u || true)"
  [[ -z "$pids" ]] && return 0
  echo "${PDO_SCRIPT:-qc}: stopping pid(s) $(echo $pids) on :$port" >&2
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  for _ in $(seq 1 20); do
    ss -ltnH "sport = :$port" | grep -q . || return 0
    sleep 0.5
  done
  # shellcheck disable=SC2086
  kill -9 $pids 2>/dev/null || true
}
