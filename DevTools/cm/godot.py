"""Running headless Godot from the content manager.

- find_godot(): the saved path if it still works, else auto-detect (env var
  GODOT, PATH, usual install folders on Windows / macOS / Linux). On Windows the
  *_console.exe build is preferred because it reliably prints to a pipe.
- GodotJob: runs one command on a background thread; the UI polls lines().
- parse_*(): turn the output of the three test scenes into results.
- SimHistory: balance-sim runs saved as JSON in DevTools/sim_history/ (git-ignored).
"""
from __future__ import annotations

import datetime
import glob
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading

from .validate import Issue

DEVTOOLS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HISTORY_DIR = os.path.join(DEVTOOLS_DIR, "sim_history")

# Godot prints these on every headless run; they are not content problems.
NOISE = [
    "ObjectDB instances leaked", "resources still in use", "audio_driver", "All audio drivers failed",
    "Equipment.gd)::_init': Method expected 1 arguments", "Condition \"status < 0\" is true",
    "at: cleanup", "at: clear (core/io/resource", "at: _create_instance", "at: init_output_device",
]


# ------------------------------------------------------------------ finding Godot

def _candidates(env=None, platform=None) -> list[str]:
    env = os.environ if env is None else env
    platform = platform or sys.platform
    out: list[str] = []
    if env.get("GODOT"):
        out.append(env["GODOT"])
    for name in ("godot4", "godot", "Godot", "godot4.4", "godot.exe", "godot4.exe"):
        p = shutil.which(name)
        if p:
            out.append(p)
    home = os.path.expanduser("~")
    pats: list[str] = []
    if platform.startswith("win"):
        roots = [env.get("LOCALAPPDATA", ""), env.get("ProgramFiles", r"C:\Program Files"),
                 env.get("ProgramFiles(x86)", r"C:\Program Files (x86)"), os.path.join(home, "Downloads"),
                 os.path.join(home, "Desktop"), os.path.join(home, "Documents"), "C:\\", "D:\\"]
        for r in roots:
            if not r:
                continue
            pats += [os.path.join(r, "Godot*", "Godot_v4*_console.exe"), os.path.join(r, "Godot*", "Godot_v4*.exe"),
                     os.path.join(r, "Godot_v4*", "Godot_v4*_console.exe"), os.path.join(r, "Godot_v4*_console.exe"),
                     os.path.join(r, "Programs", "Godot*", "*.exe"), os.path.join(r, "Godot_v4*.exe")]
        pats += [os.path.join(env.get("ProgramFiles(x86)", r"C:\Program Files (x86)"), "Steam", "steamapps", "common",
                              "Godot Engine", "godot.windows.opt.tools.64.exe"),
                 os.path.join(home, "scoop", "apps", "godot", "current", "*.exe")]
    elif platform == "darwin":
        pats += ["/Applications/Godot*.app/Contents/MacOS/Godot", os.path.join(home, "Applications", "Godot*.app", "Contents", "MacOS", "Godot")]
    else:
        pats += [os.path.join(home, ".local", "bin", "godot*"), os.path.join(home, "bin", "Godot_v4*"),
                 os.path.join(home, "Downloads", "Godot_v4*"), "/opt/godot*/Godot_v4*", "/usr/local/bin/godot*"]
    for pat in pats:
        out += sorted(glob.glob(pat), reverse=True)     # newest version first
    # prefer the console build next to a GUI exe on Windows
    pref = []
    for p in out:
        if p.lower().endswith(".exe") and "_console" not in p.lower():
            c = p[:-4] + "_console.exe"
            if os.path.isfile(c):
                pref.append(c)
        pref.append(p)
    seen, uniq = set(), []
    for p in pref:
        if p and p not in seen and os.path.isfile(p) and not p.lower().endswith(".zip"):
            seen.add(p)
            uniq.append(p)
    return uniq


def godot_version(path: str) -> str:
    try:
        r = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=20)
        return (r.stdout or r.stderr).strip().splitlines()[0] if (r.stdout or r.stderr).strip() else ""
    except (OSError, subprocess.SubprocessError, IndexError):
        return ""


def find_godot(saved: str = "") -> tuple[str, str]:
    """(path, version) of a Godot 4 executable, or ("", "") if none found."""
    for p in ([saved] if saved else []) + _candidates():
        if p and os.path.isfile(p):
            v = godot_version(p)
            if v.startswith("4."):
                return p, v
    return "", ""


# ------------------------------------------------------------------ running

class GodotJob:
    """One Godot process. Output lines go to a queue the UI drains with lines()."""

    def __init__(self, godot: str, root: str, args: list[str], label: str):
        self.cmd = [godot, "--headless", "--path", root] + args
        self.root = root
        self.label = label
        self.q: queue.Queue = queue.Queue()
        self.output: list[str] = []
        self.returncode: int | None = None
        self.proc: subprocess.Popen | None = None
        self.stopped = False
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.thread.start()
        return self

    def _run(self):
        try:
            flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
            self.proc = subprocess.Popen(self.cmd, cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                         text=True, encoding="utf-8", errors="replace", bufsize=1, creationflags=flags)
            for line in self.proc.stdout:
                self.q.put(line.rstrip("\n"))
            self.returncode = self.proc.wait()
        except OSError as e:
            self.q.put(f"Could not start Godot: {e}")
            self.returncode = -1

    def lines(self) -> list[str]:
        out = []
        while True:
            try:
                out.append(self.q.get_nowait())
            except queue.Empty:
                break
        self.output.extend(out)
        return out

    @property
    def done(self) -> bool:
        return self.returncode is not None and self.q.empty()

    def stop(self):
        self.stopped = True
        if self.proc and self.proc.poll() is None:
            self.proc.kill()


def needs_import(root: str) -> bool:
    """A fresh checkout has no .godot/ cache; scripts using class_name fail until imported."""
    return not os.path.isdir(os.path.join(root, ".godot"))


# ------------------------------------------------------------------ parsing

def is_noise(line: str) -> bool:
    return any(n in line for n in NOISE)


def godot_errors(lines: list[str]) -> list[str]:
    """SCRIPT ERROR / ERROR lines (with their 'at:' line), minus known noise."""
    out = []
    for i, line in enumerate(lines):
        if (line.startswith("SCRIPT ERROR") or line.startswith("ERROR:")) and not is_noise(line):
            at = lines[i + 1].strip() if i + 1 < len(lines) and lines[i + 1].strip().startswith("at:") else ""
            out.append(line + (f"  ({at})" if at else ""))
    return out


def parse_validate(lines: list[str], find_ref=None) -> tuple[list[Issue], str]:
    """Issues from tests/validate_content.tscn. find_ref(tab, entry) -> EntryRef|None."""
    issues: list[Issue] = []
    summary = "Godot validation did not finish."
    for line in lines:
        if line.startswith("VALIDATE ERROR|"):
            _, tab, entry, msg = (line.split("|", 3) + ["", "", ""])[:4]
            ref = find_ref(tab, entry) if find_ref else None
            issues.append(Issue("error", tab, ref, "", msg if ref or not entry else f"{entry}: {msg}", source="godot"))
        elif line.startswith("VALIDATE RESULT:"):
            summary = "Godot: " + line.split(":", 1)[1].strip()
    for e in godot_errors(lines):
        issues.append(Issue("error", "", None, "", e, source="godot"))
    return issues, summary


def parse_smoke(lines: list[str]) -> dict:
    res = {"passed": 0, "failed": 0, "failures": [], "finished": False}
    for line in lines:
        m = re.match(r"SMOKE RESULT: (\d+) passed, (\d+) failed", line)
        if m:
            res.update(passed=int(m.group(1)), failed=int(m.group(2)), finished=True)
        elif line.startswith("FAIL: "):
            res["failures"].append(line[6:])
    res["errors"] = godot_errors(lines)
    return res


def parse_sim(lines: list[str]) -> dict:
    res = {"rows": [], "progress": (0, 0), "finished": False}
    for line in lines:
        if line.startswith("SIM PROGRESS|"):
            _, a, b = line.split("|")
            res["progress"] = (int(a), int(b))
        elif line.startswith("SIM ROW|"):
            _, cls, dmg, setup, best, style = line.split("|")
            res["rows"].append({"class": cls, "damage_only": int(dmg), "set_up": int(setup), "best": int(best), "style": style})
        elif line.strip() == "SIM DONE":
            res["finished"] = True
    res["errors"] = godot_errors(lines)
    return res


def sim_args(opts: dict) -> list[str]:
    return ["res://tests/balance_sim.tscn", "--", "tool",
            f"--classes={','.join(opts.get('classes') or [])}" if opts.get("classes") else "--classes=" + ",".join(DEFAULT_CLASSES),
            f"--location={opts.get('location', 'the_dungeon')}",
            f"--setup={'both' if opts.get('set_up') == 'both' else ('on' if opts.get('set_up', True) else 'off')}",
            f"--potions={int(opts.get('potions', 0))}", f"--runs={int(opts.get('runs', 150))}",
            f"--floor={int(opts.get('floor', 1))}"]


DEFAULT_CLASSES = ["Paladin", "Necromancer", "Myrmidon", "Cleric", "Samurai", "Elementalist", "Druid", "Monk",
                   "Berserker", "Shinobi", "Kannagi", "Beastmaster"]


# ------------------------------------------------------------------ sim history

class SimHistory:
    def __init__(self, directory: str = HISTORY_DIR):
        self.dir = directory

    def save(self, options: dict, rows: list, label: str = "", root: str = "") -> str:
        os.makedirs(self.dir, exist_ok=True)
        now = datetime.datetime.now()
        rec = {"time": now.isoformat(timespec="seconds"), "label": label, "options": options, "rows": rows,
               "commit": _git_head(root)}
        path = os.path.join(self.dir, now.strftime("%Y%m%d-%H%M%S") + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(rec, f, indent=1)
        return path

    def load_all(self) -> list[dict]:
        out = []
        if not os.path.isdir(self.dir):
            return out
        for name in sorted(os.listdir(self.dir), reverse=True):
            if name.endswith(".json"):
                try:
                    with open(os.path.join(self.dir, name), encoding="utf-8") as f:
                        rec = json.load(f)
                    rec["_file"] = name
                    out.append(rec)
                except (OSError, ValueError):
                    pass
        return out

    def delete(self, rec: dict) -> None:
        try:
            os.remove(os.path.join(self.dir, rec["_file"]))
        except (OSError, KeyError):
            pass


def _git_head(root: str) -> str:
    if not root:
        return ""
    try:
        r = subprocess.run(["git", "-C", root, "rev-parse", "--short", "HEAD"], capture_output=True, text=True, timeout=5)
        dirty = subprocess.run(["git", "-C", root, "status", "--porcelain", "data"], capture_output=True, text=True, timeout=5)
        return r.stdout.strip() + ("+data edits" if dirty.stdout.strip() else "")
    except (OSError, subprocess.SubprocessError):
        return ""


def describe_options(o: dict) -> str:
    cls = o.get("classes") or []
    cls_txt = "all classes" if not cls or len(cls) >= len(DEFAULT_CLASSES) else ", ".join(cls)
    style = {"both": "best style", True: "set-up", False: "damage-only"}.get(o.get("set_up", "both"), "best style")
    return f"{o.get('location', 'the_dungeon')} floor {o.get('floor', 1)}, {cls_txt}, {style}, {o.get('potions', 0)} potions, {o.get('runs', 150)} runs"


def compare(a: dict, b: dict) -> list[dict]:
    """Rows for two runs side by side: class, a.best, b.best, change."""
    ra = {r["class"]: r for r in a.get("rows", [])}
    rb = {r["class"]: r for r in b.get("rows", [])}
    out = []
    for cls in list(ra) + [c for c in rb if c not in ra]:
        x = ra.get(cls, {}).get("best")
        y = rb.get(cls, {}).get("best")
        out.append({"class": cls, "a": x, "b": y, "change": (y - x) if x is not None and y is not None else None})
    return out
