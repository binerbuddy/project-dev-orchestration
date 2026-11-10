"""pdo_config — project configuration for the python engine scripts.

Resolution lives in one place, bin/lib.sh: this module runs bin/pdo-config and reads its JSON, so
bash and python always agree (config dirs, project detection, state dir, inbox, hooks).
"""
import json
import os
import shlex
import shutil
import subprocess
import sys
import time

ENGINE_HOME = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
BIN = os.path.join(ENGINE_HOME, "bin")


def state_dir():
    """The state dir, without needing a project (PDO_STATE_DIR or the XDG default)."""
    return os.environ.get("PDO_STATE_DIR") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "project-dev-orchestration")


def load(project=None, prog=None):
    """The resolved project config (a dict, see pdo_config_json in lib.sh). Exits with the
    resolver's message when the project can't be resolved."""
    cmd = [os.path.join(BIN, "pdo-config"), "--json"] + (["--project", project] if project else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        msg = r.stderr.strip() or "cannot resolve the project"
        sys.exit(f"{prog}: {msg}" if prog and not msg.startswith(prog) else msg)
    cfg = json.loads(r.stdout)
    # child scripts and hooks see the same state dir and inbox as this process
    os.environ["PDO_STATE_DIR"] = cfg["state_dir"]
    os.environ["PDO_INBOX"] = cfg["inbox"]
    pin_gh(cfg.get("gh_user"), prog)
    return cfg


def pin_gh(user, prog=None):
    """Run this process's gh (and git over HTTPS) as the project's GH_USER, as pdo_pin_project_gh in
    lib.sh does for the bash scripts: a token a person set wins; another project's engine pin doesn't."""
    if not user:
        return
    env = os.environ
    if (env.get("GH_TOKEN") or env.get("GITHUB_TOKEN")) and (not env.get("PDO_GH_PIN") or env["PDO_GH_PIN"] == user):
        return
    warn = f"{prog or 'pdo'}: warning: no gh token for GH_USER={user}; using gh's active account"
    try:
        r = subprocess.run(["gh", "auth", "token", "-u", user], capture_output=True, text=True)
    except OSError:
        print(warn, file=sys.stderr)
        return
    tok = r.stdout.strip()
    n = env.get("GIT_CONFIG_COUNT", "0")
    if r.returncode != 0 or not tok or not n.isdigit():
        print(warn, file=sys.stderr)
        return
    env["GH_TOKEN"], env["PDO_GH_PIN"] = tok, user
    n = int(n)
    keys = [env.get(f"GIT_CONFIG_KEY_{i}", "") for i in range(n)]
    if any(k == "credential.helper" or (k.startswith("credential.https://github.com") and k.endswith(".helper")) for k in keys):
        return  # an outer wrapper's helper chain stays in charge (it reads GH_TOKEN)
    gh = shutil.which("gh") or "gh"
    env[f"GIT_CONFIG_KEY_{n}"], env[f"GIT_CONFIG_VALUE_{n}"] = "credential.https://github.com.helper", ""
    env[f"GIT_CONFIG_KEY_{n + 1}"] = "credential.https://github.com.helper"
    env[f"GIT_CONFIG_VALUE_{n + 1}"] = f"!{shlex.quote(gh)} auth git-credential"
    env["GIT_CONFIG_COUNT"] = str(n + 2)


def ref(cfg, repo, number):
    """'#n' for the primary repo, '<repo>#n' otherwise."""
    return f"#{number}" if repo == cfg.get("primary_repo") else f"{repo}#{number}"


def try_load(project):
    """(cfg, None) or (None, error) for one project, without exiting and without changing this
    process's environment (bin/fleet reads every project, and one project's state dir must not
    leak into the next one's resolution)."""
    r = subprocess.run([os.path.join(BIN, "pdo-config"), "--json", "--project", project],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, (r.stderr.strip() or f"cannot resolve project {project}")
    try:
        return json.loads(r.stdout), None
    except ValueError as e:
        return None, f"bad config JSON for {project}: {e}"


def projects():
    """Every known project name along PDO_CONFIG_DIRS (first config dir wins per name)."""
    r = subprocess.run([os.path.join(BIN, "pdo-config"), "--list"], capture_output=True, text=True)
    return [ln.split(" ", 1)[0] for ln in r.stdout.splitlines() if ln.strip()]


def global_state_dir():
    """The install-wide state dir, as lib.sh resolves it (config.env included)."""
    r = subprocess.run([os.path.join(BIN, "pdo-config"), "--state-dir"], capture_output=True, text=True)
    return r.stdout.strip() or state_dir()


FLEET_ADVICE_MAX_AGE_SEC = 2 * 3600


def fleet_advice(cfg, now=None):
    """The CEO's advice for this project, from $PDO_STATE_DIR/fleet-advice.json
    (written by `fleet --write-advice`), or None when absent, stale (2 h+) or unreadable.
    The dict carries advice (go|slow|hold), reason, suggested_max_active, age_min, and
    honoured: whether the project opted in with FLEET_ADVICE=honour."""
    path = os.path.join(cfg.get("state_dir") or state_dir(), "fleet-advice.json")
    try:
        d = json.load(open(path, encoding="utf-8"))
        at = float(d["generated_at"])
        entry = dict(d["projects"][cfg["project"]])
    except (OSError, ValueError, KeyError, TypeError):
        return None
    age = (now if now is not None else time.time()) - at
    if age < 0 or age >= FLEET_ADVICE_MAX_AGE_SEC:
        return None
    entry["age_min"] = int(age / 60)
    entry["honoured"] = (cfg.get("fleet_advice") or "ignore").lower() in ("honour", "honor")
    return entry


GIT_OPS = (("rebase-merge", "a rebase"), ("rebase-apply", "a rebase"), ("MERGE_HEAD", "a merge"),
           ("CHERRY_PICK_HEAD", "a cherry-pick"), ("REVERT_HEAD", "a revert"))


def git_hold(worktree, pr_head=None):
    """Why an agent's worktree must not be released yet, or None: a rebase, merge, cherry-pick or
    revert in progress, or commits on HEAD that the PR's head (pr_head; the upstream branch when
    it isn't known locally) doesn't have. Hibernating then kills the agent's background checks
    before it pushes, and the PR keeps its conflict."""
    if not worktree or not os.path.isdir(worktree):
        return None

    def git(*a):
        r = subprocess.run(["git", "-C", worktree, *a], capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else None

    for name, what in GIT_OPS:
        p = git("rev-parse", "--git-path", name)
        if p and os.path.exists(os.path.join(worktree, p)):
            return f"{what} is in progress"
    if git("rev-parse", "--verify", "-q", "HEAD") is None:
        return None
    if pr_head and git("cat-file", "-e", f"{pr_head}^{{commit}}") is not None:
        n = git("rev-list", "--count", f"{pr_head}..HEAD")
    else:
        n = git("rev-list", "--count", "@{upstream}..HEAD")
    if n and n != "0":
        return f"{n} commit{'s' if n != '1' else ''} not pushed to the PR branch"
    return None


def notify(cfg, title, body, url=None):
    """Run the project's NOTIFY_CMD with <title> <body> [<url>] (a push notification to the human).
    Never raises: a missing or failing command is ignored (the waiting lists still show the item)."""
    cmd = (cfg or {}).get("notify_cmd")
    if not cmd:
        return False
    try:
        r = subprocess.run([cmd, title, body] + ([url] if url else []), capture_output=True, text=True, timeout=30)
        return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def open_blockers(org, repo, number):
    """Open issues blocking <repo>#<number> (GitHub's native "blocked by"), as ["owner/repo#n", ...];
    None when GitHub can't say."""
    r = subprocess.run(["gh", "api", f"repos/{org}/{repo}/issues/{number}/dependencies/blocked_by", "--jq",
                        '[.[] | select(.state == "open") | (.repository_url | sub(".*/repos/"; "")) + "#" + (.number | tostring)]'],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout or "[]")
    except ValueError:
        return None


_ELSEWHERE = {}


def managed_elsewhere(cfg):
    """This project's SELF_MANAGED_REPOS that another project runs with its own orchestrator (in its
    REPO_ROOT and not self-managed there). Kept in REPO_ROOT here only for reading (a spec repo,
    cross-repo work); this project's watcher and fleet leave their agents to that project."""
    p = cfg["project"]
    if p not in _ELSEWHERE:
        mine, out = set(cfg.get("self_managed_repos") or []), set()
        for other in projects() if mine else []:
            if other == p:
                continue
            o, _ = try_load(other)
            if o and o.get("org") == cfg.get("org"):
                out |= (set(o.get("repo_root") or {}) - set(o.get("self_managed_repos") or [])) & mine
        _ELSEWHERE[p] = out
    return _ELSEWHERE[p]


def pending_question(session_id, config_dir=None):
    """The agent's unanswered AskUserQuestion, read from its Claude Code transcript
    (<config dir>/projects/*/<session>.jsonl; CLAUDE_CONFIG_DIR, else ~/.claude): the last call with
    no tool_result yet, as {"questions": [{question, header, options: [{label, description}],
    multiSelect}], "asked_at": epoch or None}. None when there is no transcript or nothing pending
    (another agent CLI, or the question was answered or dismissed)."""
    import calendar
    import glob
    if not session_id:
        return None
    root = config_dir or os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    files = glob.glob(os.path.join(root, "projects", "*", f"{session_id}.jsonl"))
    if not files:
        return None
    last, answered = None, set()
    with open(max(files, key=os.path.getmtime), encoding="utf-8", errors="replace") as f:
        for line in f:
            if "AskUserQuestion" not in line and "tool_result" not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            content = (rec.get("message") or {}).get("content")
            for c in content if isinstance(content, list) else []:
                if c.get("type") == "tool_use" and c.get("name") == "AskUserQuestion":
                    last = (c.get("id"), c.get("input") or {}, rec.get("timestamp"))
                elif c.get("type") == "tool_result":
                    answered.add(c.get("tool_use_id"))
    if not last or last[0] in answered:
        return None
    asked = None
    if last[2]:
        try:
            asked = calendar.timegm(time.strptime(last[2][:19], "%Y-%m-%dT%H:%M:%S"))  # transcript times are UTC
        except ValueError:
            pass
    qs = [{"question": q.get("question", ""), "header": q.get("header", ""), "multiSelect": bool(q.get("multiSelect")),
           "options": [{"label": o.get("label", ""), "description": o.get("description", "")} for o in q.get("options") or []]}
          for q in last[1].get("questions") or []]
    return {"questions": qs, "asked_at": asked} if qs else None


# RESOURCE_PROFILE defaults: RAM one active agent holds (agent CLI, MCP servers, dev servers,
# browser) and its relative draw on the shared usage budget. AGENT_MB / AGENT_USAGE_WEIGHT override.
PROFILES = {"light": (400, 0.5), "medium": (900, 1.0), "heavy": (1800, 2.0)}


def agent_mb(cfg):
    """MB one active agent of this project holds: AGENT_MB, else its RESOURCE_PROFILE's (medium if unknown)."""
    return int(cfg.get("agent_mb") or PROFILES.get((cfg.get("resource_profile") or "medium").lower(), PROFILES["medium"])[0])
