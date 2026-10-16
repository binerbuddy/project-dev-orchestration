"""pdo_config — project configuration for the python engine scripts.

Resolution lives in one place, bin/lib.sh: this module runs bin/pdo-config and reads its JSON, so
bash and python always agree (config dirs, project detection, state dir, inbox, hooks).
"""
import json
import os
import subprocess
import sys

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
