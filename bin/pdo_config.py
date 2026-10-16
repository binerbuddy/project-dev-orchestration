"""pdo_config — project configuration for the python engine scripts.

Resolution lives in one place, bin/lib.sh: this module runs bin/pdo-config and reads its JSON, so
bash and python always agree (config dirs, project detection, state dir, inbox, hooks).
"""
import json
import os
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
    return cfg


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
    """The portfolio manager's advice for this project, from $PDO_STATE_DIR/fleet-advice.json
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
