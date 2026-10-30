"""herdr layout helpers shared by the engine scripts.

An agent's name is its herdr label. Two layouts are in use, and both resolve the same way:
  - tabs (engine 0.12+, AGENT_LAYOUT=tabs): one workspace per manager (its "home", labelled with the
    project or self-managed repo name), one tab per agent, labelled with the agent's name;
  - workspaces (older): one workspace per agent, labelled with its name (its tab keeps herdr's
    default label, the tab number).
A "slot" is one agent place: {name, workspace_id, workspace, tab_id, pane_id, agent, status, layout}.
Lookups match a tab label first, then a workspace label, so agents of both layouts are found.

Closing an agent always closes its TAB, never its workspace: herdr closes a workspace when its last
tab goes, so an old-layout agent's own workspace still disappears, and a manager's home (other tabs)
never does.

CLI (bin/herdr-agent wraps it):
  find <name>                    print the slot as JSON (exit 1: not found)
  names                          every slot name, one per line
  slots                          every slot as a JSON list
  place <home> <name> <cwd>      open a tab <name> in workspace <home> (creating the home, with this
                                 agent as tab 1, if missing); AGENT_LAYOUT=workspaces opens a
                                 workspace <name> instead. Prints {workspace_id, tab_id, pane_id, home}
  close <name>                   close that agent's tab (exit 1: not found)
  draft <name> | --pane <id>     (name: the tab label or herdr's agent name) what sits in the agent's input box: "draft: <text>" for text a person
                                 typed and hasn't sent, "suggestion: <text>" for Claude Code's dim
                                 prompt suggestion (ghost text, never anyone's). Exit 0: a real draft
                                 is there (don't type into this pane); 1: none; 2: not found
"""
import json
import os
import re
import subprocess
import sys


def call(*args, timeout=15):
    """herdr <args> -> its result dict, or None when herdr fails or isn't running."""
    try:
        r = subprocess.run(["herdr", *args], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout).get("result") or {}
    except ValueError:
        return None


def _default_label(tab):
    label = tab.get("label") or ""
    return label == "" or label == str(tab.get("number"))


def slots(workspaces=None, tabs=None, agents=None):
    """Every agent place, both layouts. Pass the three lists to reuse a snapshot."""
    if workspaces is None:
        workspaces = (call("workspace", "list") or {}).get("workspaces", [])
    if agents is None:
        agents = (call("agent", "list") or {}).get("agents", [])
    if tabs is None:
        tabs = (call("tab", "list") or {}).get("tabs", [])
    ws_by_id = {w.get("workspace_id"): w for w in workspaces}

    def pick(cands):  # a claude pane first, else any agent pane
        cands = [a for a in cands if a]
        return next((a for a in cands if a.get("agent") == "claude"), cands[0] if cands else {})

    out = []
    if not tabs:  # herdr without tab data (or a fake one): one slot per workspace, as before 0.12
        for w in workspaces:
            a = pick([x for x in agents if x.get("workspace_id") == w.get("workspace_id")])
            out.append({"name": w.get("label") or "", "workspace_id": w.get("workspace_id"),
                        "workspace": w.get("label") or "", "tab_id": a.get("tab_id"),
                        "pane_id": a.get("pane_id"), "agent": a,
                        "status": a.get("agent_status") or w.get("agent_status") or "unknown",
                        "layout": "workspace"})
        return out
    by_tab = {}
    for a in agents:
        by_tab.setdefault(a.get("tab_id"), []).append(a)
    first = {}
    for t in tabs:
        wid = t.get("workspace_id")
        if wid not in first or (t.get("number") or 0) < (first[wid].get("number") or 0):
            first[wid] = t
    for t in tabs:
        w = ws_by_id.get(t.get("workspace_id"), {})
        if _default_label(t):
            # an unnamed tab stands for its workspace only when it is the workspace's first tab
            if first.get(t.get("workspace_id")) is not t:
                continue
            name, layout = w.get("label") or "", "workspace"
        else:
            name, layout = t.get("label"), "tab"
        a = pick(by_tab.get(t.get("tab_id"), []))
        out.append({"name": name, "workspace_id": t.get("workspace_id"), "workspace": w.get("label") or "",
                    "tab_id": t.get("tab_id"), "pane_id": a.get("pane_id"), "agent": a,
                    "status": a.get("agent_status") or t.get("agent_status") or "unknown", "layout": layout})
    for w in workspaces:  # a workspace the tab list didn't mention (it raced a create): one slot, as before
        if w.get("workspace_id") not in first:
            a = pick([x for x in agents if x.get("workspace_id") == w.get("workspace_id")])
            out.append({"name": w.get("label") or "", "workspace_id": w.get("workspace_id"),
                        "workspace": w.get("label") or "", "tab_id": a.get("tab_id"), "pane_id": a.get("pane_id"),
                        "agent": a, "status": a.get("agent_status") or w.get("agent_status") or "unknown",
                        "layout": "workspace"})
    return out


def find(name, snapshot=None):
    """The slot named <name>: a tab label wins over a workspace label."""
    s = snapshot if snapshot is not None else slots()
    hits = [x for x in s if x["name"] == name]
    return next((x for x in hits if x["layout"] == "tab"), hits[0] if hits else None)


def workspace_named(label, workspaces=None):
    if workspaces is None:
        workspaces = (call("workspace", "list") or {}).get("workspaces", [])
    return next((w for w in workspaces if w.get("label") == label), None)


def place(home, name, cwd, layout=None):
    """Open a place for agent <name>. Returns {workspace_id, tab_id, pane_id, home} or None."""
    layout = layout or os.environ.get("AGENT_LAYOUT") or "tabs"
    if layout == "workspaces" or not home:
        r = call("workspace", "create", "--cwd", cwd, "--label", name, "--no-focus")
        if r is None:
            return None
        return {"workspace_id": (r.get("workspace") or {}).get("workspace_id"),
                "tab_id": (r.get("tab") or {}).get("tab_id"),
                "pane_id": (r.get("root_pane") or {}).get("pane_id"), "home": None}
    w = workspace_named(home)
    if w:
        r = call("tab", "create", "--workspace", w["workspace_id"], "--cwd", cwd, "--label", name, "--no-focus")
        if r is None:
            return None
        return {"workspace_id": w["workspace_id"], "tab_id": (r.get("tab") or {}).get("tab_id"),
                "pane_id": (r.get("root_pane") or {}).get("pane_id"), "home": home}
    r = call("workspace", "create", "--cwd", cwd, "--label", home, "--no-focus")
    if r is None:
        return None
    tab = (r.get("tab") or {}).get("tab_id")
    if tab:
        call("tab", "rename", tab, name)
    return {"workspace_id": (r.get("workspace") or {}).get("workspace_id"), "tab_id": tab,
            "pane_id": (r.get("root_pane") or {}).get("pane_id"), "home": home}


QUESTION_MARKERS = ("Enter to select", "Do you want to proceed")
PROMPT = "\u276f"  # the ❯ at the start of Claude Code's input box
SGR = re.compile(r"\x1b\[([0-9;]*)m")
CSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def _split_dim(line):
    """(plain, dim) text of one ANSI line: SGR 2 starts dim, 0 / 22 / an empty SGR ends it."""
    plain, dim, faint, pos = [], [], False, 0
    for m in SGR.finditer(line):
        (dim if faint else plain).append(CSI.sub("", line[pos:m.start()]))
        codes = m.group(1).split(";") if m.group(1) else ["0"]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c in ("38", "48", "58"):  # extended colour: 5;n or 2;r;g;b, not attributes
                i += 3 if i + 1 < len(codes) and codes[i + 1] == "5" else 5
                continue
            if c == "2":
                faint = True
            elif c in ("0", "22", ""):
                faint = False
            i += 1
        pos = m.end()
    (dim if faint else plain).append(CSI.sub("", line[pos:]))
    return "".join(plain), "".join(dim)


def read_input(pane):
    """{"draft": text, "suggestion": text} in a Claude Code pane's input box, from the last ❯ line
    (earlier ❯ lines are sent messages in the scrollback) to the box's bottom rule. Dim text is
    Claude Code's prompt suggestion; anything else is a person's unsent draft."""
    if not pane:
        return {"draft": "", "suggestion": ""}
    try:
        r = subprocess.run(["herdr", "pane", "read", pane, "--format", "ansi"], capture_output=True,
                           text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return {"draft": "", "suggestion": ""}
    lines = r.stdout.replace("\r", "").splitlines()[-60:]
    start = next((i for i in range(len(lines) - 1, -1, -1)
                  if CSI.sub("", lines[i]).lstrip().startswith(PROMPT)), None)
    if start is None:
        return {"draft": "", "suggestion": ""}
    plain, dim = [], []
    for i, line in enumerate(lines[start:]):
        p, d = _split_dim(line)
        text = p.replace("\xa0", " ")
        if i == 0:
            text = text.lstrip()[len(PROMPT):]
        elif set(text.strip()) <= set("\u2500\u2501\u2550-") and text.strip():
            break  # the input box's bottom rule
        plain.append(text.strip())
        dim.append(d.replace("\xa0", " ").strip())
    return {"draft": "\n".join(x for x in plain if x).strip(), "suggestion": " ".join(x for x in dim if x).strip()}


def draft_pending(slot):
    """A person's unsent text sits in the agent's input box (Claude Code's dim suggestion doesn't count)."""
    return bool(slot and read_input(slot.get("pane_id"))["draft"])


def question_pending(slot):
    """A question or menu waits on the agent's screen (or herdr reports it blocked), or a person's
    unsent draft sits in its input box: typing into the pane would answer or mangle either."""
    if not slot:
        return False
    if slot.get("status") == "blocked":
        return True
    pane = slot.get("pane_id")
    if not pane:
        return False
    try:
        r = subprocess.run(["herdr", "pane", "read", pane], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return False
    tail = "\n".join(r.stdout.splitlines()[-40:])
    return any(q in tail for q in QUESTION_MARKERS) or draft_pending(slot)


def exit_agent(pane, wait=30):
    """/exit a Claude agent in <pane> and wait until herdr no longer lists it. True when it's gone."""
    import time
    call("agent", "prompt", pane, "/exit")
    time.sleep(3)
    r = subprocess.run(["herdr", "pane", "read", pane], capture_output=True, text=True, timeout=15)
    if "Exit and stop tasks" in "\n".join(r.stdout.splitlines()[-15:]):  # a /loop wakeup is pending
        call("pane", "send-keys", pane, "enter")
    for _ in range(wait):
        if not any(a.get("pane_id") == pane for a in (call("agent", "list") or {}).get("agents", [])):
            return True
        time.sleep(1)
    return False


def close(slot):
    """Close an agent's tab (the workspace goes only if this was its last tab)."""
    if not slot or not slot.get("tab_id"):
        return False
    return call("tab", "close", slot["tab_id"]) is not None


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "find" and len(rest) == 1:
        s = find(rest[0])
        if not s:
            return 1
        print(json.dumps(s))
    elif cmd == "names":
        for s in slots():
            if s["name"]:
                print(s["name"])
    elif cmd == "slots":
        print(json.dumps(slots()))
    elif cmd == "place" and len(rest) == 3:
        p = place(*rest)
        if not p or not p.get("pane_id"):
            print("herdr-agent: could not open a place for the agent", file=sys.stderr)
            return 1
        print(json.dumps(p))
    elif cmd == "draft" and len(rest) in (1, 2):
        pane = rest[1] if rest[0] == "--pane" and len(rest) == 2 else None
        if pane is None:
            snap = slots() if len(rest) == 1 else []
            # the tab label, else herdr's agent name (e.g. orchestrator-acme, review-acme)
            s = find(rest[0], snap) or next((x for x in snap if (x.get("agent") or {}).get("name") == rest[0]), None)
            if not s:
                return 2
            pane = s.get("pane_id")
        got = read_input(pane)
        if got["draft"]:
            print("draft: " + got["draft"])
        if got["suggestion"]:
            print("suggestion: " + got["suggestion"])
        return 0 if got["draft"] else 1
    elif cmd == "close" and len(rest) == 1:
        return 0 if close(find(rest[0])) else 1
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
