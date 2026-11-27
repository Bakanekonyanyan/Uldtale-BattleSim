"""Phase 3 UI: buttons that run the Godot tests, a live output page, the
balance-sim options dialog and the sim history / comparison page."""
from __future__ import annotations

import os
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from . import godot
from .godot import GodotJob, SimHistory, compare, describe_options
from .widgets import COLORS



def noise_band(runs: int) -> int:
    """Clear-rate change (points) that two identical runs exceed only ~5% of the
    time: 2 x the standard error of a difference at p=0.5 = 141 / sqrt(runs)."""
    return max(3, round(141 / max(1, runs) ** 0.5))


class OutputPanel(ttk.Frame):
    def __init__(self, master, runner):
        super().__init__(master, padding=4)
        self.runner = runner
        bar = ttk.Frame(self)
        bar.pack(fill="x")
        self.head = ttk.Label(bar, text="Nothing has run yet.", style="Bar.TLabel")
        self.head.pack(side="left")
        ttk.Button(bar, text="Clear", command=self.clear).pack(side="right")
        self.stop_btn = ttk.Button(bar, text="Stop", command=runner.stop, state="disabled")
        self.stop_btn.pack(side="right", padx=4)
        self.only_important = tk.BooleanVar(value=True)
        ttk.Checkbutton(bar, text="Hide routine lines", variable=self.only_important, style="Bar.TCheckbutton").pack(side="right", padx=8)
        self.text = tk.Text(self, height=10, wrap="none", font=("TkFixedFont", 9), relief="flat",
                            bg=COLORS["panel"], fg=COLORS["fg"], insertbackground=COLORS["fg"])
        sb = ttk.Scrollbar(self, orient="vertical", command=self.text.yview)
        self.text.configure(yscrollcommand=sb.set)
        self.text.pack(side="left", fill="both", expand=True, pady=(4, 0))
        sb.pack(side="right", fill="y", pady=(4, 0))
        self.text.tag_configure("bad", foreground="#e07a5f")
        self.text.tag_configure("good", foreground="#8fd46a")
        self.text.tag_configure("info", foreground=COLORS["accent"])

    def clear(self):
        self.text.delete("1.0", "end")

    def append(self, line: str):
        tag = ""
        if line.startswith(("FAIL", "SCRIPT ERROR", "VALIDATE ERROR", "ERROR")) and not godot.is_noise(line):
            tag = "bad"
        elif line.startswith(("SMOKE RESULT", "VALIDATE RESULT", "SIM ROW", "SIM DONE", "PASS")):
            tag = "good" if not line.startswith("PASS") else ""
        elif line.startswith((">>", "==")):
            tag = "info"
        if self.only_important.get() and not tag and not line.startswith(("SIM PROGRESS",)):
            return
        if line.startswith("SIM PROGRESS"):
            return
        self.text.insert("end", line + "\n", tag)
        self.text.see("end")


class SimOptionsDialog(tk.Toplevel):
    def __init__(self, app, last: dict):
        super().__init__(app)
        self.app = app
        self.result = None
        self.title("Balance sim")
        self.configure(bg=COLORS["panel"])
        self.transient(app)
        body = ttk.Frame(self, style="Form.TFrame", padding=16)
        body.pack(fill="both", expand=True)
        ttk.Label(body, text="Floor full runs (5 waves + boss) through the real combat code, judged per class.",
                  style="Help.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 8))
        ttk.Label(body, text="Classes", style="Field.TLabel").grid(row=1, column=0, sticky="nw")
        cf = ttk.Frame(body, style="Form.TFrame")
        cf.grid(row=1, column=1, columnspan=2, sticky="w")
        playable = app.project.source("playable_classes") or godot.DEFAULT_CLASSES
        chosen = set(last.get("classes") or playable)
        self.class_vars = {}
        for i, c in enumerate(playable):
            v = tk.BooleanVar(value=c in chosen)
            ttk.Checkbutton(cf, text=c, variable=v).grid(row=i // 4, column=i % 4, sticky="w", padx=(0, 10))
            self.class_vars[c] = v
        row = 2
        ttk.Label(body, text="Location", style="Field.TLabel").grid(row=row, column=0, sticky="w", pady=4)
        self.loc = tk.StringVar(value=last.get("location", "the_dungeon"))
        ttk.Combobox(body, textvariable=self.loc, values=app.project.source("locations"), state="readonly", width=20).grid(row=row, column=1, sticky="w")
        row += 1
        ttk.Label(body, text="Play style", style="Field.TLabel").grid(row=row, column=0, sticky="w", pady=4)
        self.style = tk.StringVar(value={True: "set-up", False: "damage-only"}.get(last.get("set_up"), "best of both"))
        ttk.Combobox(body, textvariable=self.style, values=["best of both", "set-up", "damage-only"], state="readonly", width=20).grid(row=row, column=1, sticky="w")
        ttk.Label(body, text="best of both runs each class twice", style="Help.TLabel").grid(row=row, column=2, sticky="w", padx=6)
        row += 1
        self.spins = {}
        for key, label, lo, hi, default, hint in [("potions", "Potions", 0, 5, 0, "Health + Mana potions carried"),
                                                  ("runs", "Runs per class", 20, 2000, 150, "more = less noise, slower"),
                                                  ("floor", "Floor", 1, 30, 1, "")]:
            ttk.Label(body, text=label, style="Field.TLabel").grid(row=row, column=0, sticky="w", pady=4)
            v = tk.IntVar(value=int(last.get(key, default)))
            ttk.Spinbox(body, from_=lo, to=hi, textvariable=v, width=8).grid(row=row, column=1, sticky="w")
            ttk.Label(body, text=hint, style="Help.TLabel").grid(row=row, column=2, sticky="w", padx=6)
            self.spins[key] = v
            row += 1
        ttk.Label(body, text="Label", style="Field.TLabel").grid(row=row, column=0, sticky="w", pady=4)
        self.label = tk.StringVar(value="")
        ttk.Entry(body, textvariable=self.label, width=30).grid(row=row, column=1, columnspan=2, sticky="w")
        row += 1
        ttk.Label(body, text="e.g. \"Iaido power 60\" - shown in the history", style="Help.TLabel").grid(row=row, column=1, columnspan=2, sticky="w")
        row += 1
        btns = ttk.Frame(body, style="Form.TFrame")
        btns.grid(row=row, column=0, columnspan=3, sticky="e", pady=(12, 0))
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right")
        ttk.Button(btns, text="Run", style="Accent.TButton", command=self._ok).pack(side="right", padx=6)
        self.bind("<Escape>", lambda e: self.destroy())
        self.grab_set()

    def _ok(self):
        classes = [c for c, v in self.class_vars.items() if v.get()]
        if not classes:
            return
        try:
            nums = {k: int(v.get()) for k, v in self.spins.items()}
        except (tk.TclError, ValueError):
            return
        self.result = {"classes": classes, "location": self.loc.get(),
                       "set_up": {"set-up": True, "damage-only": False}.get(self.style.get(), "both"),
                       "label": self.label.get().strip(), **nums}
        self.destroy()


class SimPanel(ttk.Frame):
    def __init__(self, master, app):
        super().__init__(master, padding=4)
        self.app = app
        self.history = SimHistory()
        self.records: list = []
        pw = ttk.PanedWindow(self, orient="horizontal")
        pw.pack(fill="both", expand=True)
        left = ttk.Frame(pw)
        right = ttk.Frame(pw)
        pw.add(left, weight=1)
        pw.add(right, weight=1)
        bar = ttk.Frame(left)
        bar.pack(fill="x")
        ttk.Label(bar, text="Runs (select one, or two to compare)", style="Bar.TLabel").pack(side="left")
        ttk.Button(bar, text="Delete", command=self._delete).pack(side="right")
        self.runs = ttk.Treeview(left, columns=("time", "label", "opts"), show="headings", selectmode="extended", height=7)
        for c, w, t in [("time", 130, "When"), ("label", 150, "Label"), ("opts", 360, "Options")]:
            self.runs.heading(c, text=t)
            self.runs.column(c, width=w, stretch=(c == "opts"))
        self.runs.pack(fill="both", expand=True, pady=(4, 0))
        self.runs.bind("<<TreeviewSelect>>", lambda e: self._show())
        self.caption = ttk.Label(right, text="", style="Bar.TLabel", wraplength=520, justify="left")
        self.caption.pack(fill="x")
        self.table = ttk.Treeview(right, columns=("c1", "c2", "c3", "c4"), show="headings", height=8)
        self.table.pack(fill="both", expand=True, pady=(4, 0))
        self.table.tag_configure("up", foreground="#8fd46a")
        self.table.tag_configure("down", foreground="#e07a5f")
        self.table.tag_configure("noise", foreground=COLORS["muted"])
        self.reload()

    def reload(self, select_latest=False, compare_previous=False):
        self.records = self.history.load_all()
        self.runs.delete(*self.runs.get_children())
        for i, r in enumerate(self.records):
            self.runs.insert("", "end", iid=str(i), values=(r.get("time", "").replace("T", " "), r.get("label", ""),
                                                            describe_options(r.get("options", {}))))
        if select_latest and self.records:
            sel = ["0"]
            if compare_previous:
                same = [i for i, r in enumerate(self.records[1:], 1) if _comparable(r.get("options", {}), self.records[0].get("options", {}))]
                if same:
                    sel.append(str(same[0]))
            self.runs.selection_set(sel)
            self._show()

    def _cols(self, names):
        for c, n in zip(("c1", "c2", "c3", "c4"), names):
            self.table.heading(c, text=n)
            self.table.column(c, width=150 if c == "c1" else 110, anchor="w" if c == "c1" else "center")

    def _show(self):
        sel = [self.records[int(i)] for i in self.runs.selection()]
        self.table.delete(*self.table.get_children())
        if len(sel) == 1:
            r = sel[0]
            self._cols(["Class", "Damage-only %", "Set-up %", "Best %"])
            for row in r.get("rows", []):
                fmt = lambda v: "-" if v is None or v < 0 else f"{v}%"  # noqa: E731
                self.table.insert("", "end", values=(row["class"], fmt(row.get("damage_only")), fmt(row.get("set_up")),
                                                     f"{row.get('best')}%  ({row.get('style')})"))
            self.caption.configure(text=f"{describe_options(r.get('options', {}))}   commit {r.get('commit') or '?'}")
        elif len(sel) >= 2:
            newer, older = sel[0], sel[1]
            if newer.get("time", "") < older.get("time", ""):
                newer, older = older, newer
            self._cols(["Class", f"Before ({older.get('label') or older.get('time', '')[11:16]})",
                        f"After ({newer.get('label') or newer.get('time', '')[11:16]})", "Change"])
            band = noise_band(min(int(older.get("options", {}).get("runs", 150)), int(newer.get("options", {}).get("runs", 150))))
            for row in compare(older, newer):
                ch = row["change"]
                tag = "noise" if ch is None or abs(ch) < band else ("up" if ch > 0 else "down")
                self.table.insert("", "end", tags=(tag,), values=(
                    row["class"], "-" if row["a"] is None else f"{row['a']}%", "-" if row["b"] is None else f"{row['b']}%",
                    "-" if ch is None else f"{ch:+d}"))
            note = (f"Best clear rate per class. Changes under {band} points (grey) are normal run-to-run noise "
                    f"at this many runs - raise 'Runs per class' to detect smaller effects.")
            if not _comparable(older.get("options", {}), newer.get("options", {})):
                note += "  These runs used different options."
            self.caption.configure(text=note)
        else:
            self.caption.configure(text="Run the balance sim from the toolbar; results are kept here (only on this computer).")

    def _delete(self):
        sel = [self.records[int(i)] for i in self.runs.selection()]
        if sel and messagebox.askyesno("Delete runs", f"Delete {len(sel)} saved run(s)?", parent=self.app):
            for r in sel:
                self.history.delete(r)
            self.reload()


def _comparable(a: dict, b: dict) -> bool:
    keys = ("location", "set_up", "potions", "floor")
    return all(a.get(k) == b.get(k) for k in keys) and set(a.get("classes") or []) == set(b.get("classes") or [])


class TestRunner:
    """Owns the Godot job and the toolbar buttons."""

    def __init__(self, app):
        self.app = app
        self.job: GodotJob | None = None
        self.queue: list = []          # (label, args, on_finish) chained after an import
        self.buttons = []
        for text, cmd in [("Validate in Godot", self.validate_godot), ("Smoke test", self.smoke), ("Balance sim...", self.sim)]:
            b = ttk.Button(app.tools, text=text, command=cmd)
            b.pack(side="left", padx=(6, 0))
            self.buttons.append(b)
        ttk.Button(app.tools, text="Godot...", command=self.choose_godot).pack(side="left", padx=(6, 0))
        self.output = OutputPanel(app.dock, self)
        app.dock.add(self.output, text="Godot output")
        self.simpanel = SimPanel(app.dock, app)
        app.dock.add(self.simpanel, text="Balance sim")
        self.sim_opts = None

    # ------------------------------------------------------------ godot path

    def godot_path(self, ask=True) -> str:
        saved = self.app.cfg.get("godot_path", "")
        path, version = godot.find_godot(saved)
        if path:
            if path != saved:
                self.app.cfg["godot_path"] = path
                self.app.cfg.save()
            return path
        if not ask:
            return ""
        messagebox.showinfo("Godot", "Couldn't find Godot 4 automatically.\n\nPick your Godot executable "
                            "(on Windows, the *_console.exe build if you have it).", parent=self.app)
        return self.choose_godot()

    def choose_godot(self) -> str:
        p = filedialog.askopenfilename(title="Godot 4 executable", parent=self.app)
        if not p:
            return ""
        v = godot.godot_version(p)
        if not v.startswith("4."):
            messagebox.showerror("Godot", f"That doesn't look like Godot 4 (version: {v or 'unknown'}).", parent=self.app)
            return ""
        self.app.cfg["godot_path"] = p
        self.app.cfg.save()
        self.app.status(f"Using Godot {v}: {p}")
        return p

    # ------------------------------------------------------------ jobs

    def _start(self, label, args, on_finish):
        if self.job is not None:
            self.app.status("Godot is already running - wait for it or press Stop.")
            return
        exe = self.godot_path()
        if not exe:
            return
        saved = self.app.project.save_all()
        if saved:
            self.app.mark_changed()
        self.app.show_dock(self.output)
        if saved:
            self.output.append(f">> Saved {', '.join(saved)} before running")
        if godot.needs_import(self.app.project.root):
            self.queue.insert(0, (label, args, on_finish))
            label, args, on_finish = "Importing project (first run only)", ["--editor", "--quit"], lambda job: None
        self.output.append(f">> {label}")
        self.output.head.configure(text=f"Running: {label} ...")
        self.output.stop_btn.configure(state="normal")
        for b in self.buttons:
            b.configure(state="disabled")
        self.job = GodotJob(exe, self.app.project.root, args, label).start()
        self._on_finish = on_finish
        self.app.after(100, self._poll)

    def _poll(self):
        job = self.job
        if job is None:
            return
        for line in job.lines():
            self.output.append(line)
            if line.startswith("SIM PROGRESS|"):
                a, b = line.split("|")[1:3]
                self.output.head.configure(text=f"Running: {job.label} ... {a}/{b}")
        if not job.done:
            self.app.after(100, self._poll)
            return
        self.job = None
        self.output.stop_btn.configure(state="disabled")
        for b in self.buttons:
            b.configure(state="normal")
        if job.stopped:
            self.output.head.configure(text=f"Stopped: {job.label}")
            self.queue.clear()
            return
        self._on_finish(job)
        if self.queue:
            label, args, fin = self.queue.pop(0)
            self._start(label, args, fin)

    def stop(self):
        if self.job:
            self.job.stop()

    # ------------------------------------------------------------ the three tests

    def validate_godot(self):
        self._start("Validate in Godot", ["res://tests/validate_content.tscn"], self._validated)

    def _validated(self, job):
        def find_ref(tab, entry):
            for i in range(len(self.app.project.by_tab.get(tab).sections) if tab in self.app.project.by_tab else 0):
                for r in self.app.project.entries(tab, i):
                    if str(r.key) == entry:
                        return r
            return None
        issues, summary = godot.parse_validate(job.output, find_ref)
        if "did not finish" in summary and job.returncode not in (0, None):
            summary += f" (exit code {job.returncode})"
        self.app.problems.remove_source("godot")
        self.app.problems.add_issues(issues)
        self.app.problems.summary.configure(text=summary + (" - problems listed below" if issues else " - all good"))
        self.output.head.configure(text=summary)
        self.app.status(summary)
        if issues:
            self.app.show_dock(self.app.problems)

    def smoke(self):
        self._start("Smoke test", ["res://tests/battle_smoke_test.tscn"], self._smoked)

    def _smoked(self, job):
        r = godot.parse_smoke(job.output)
        if r["finished"]:
            text = f"Smoke test: {r['passed']} passed, {r['failed']} failed"
        else:
            text = f"Smoke test did not finish (exit code {job.returncode})"
        if r["failures"]:
            text += " - failures: " + "; ".join(r["failures"][:5])
        self.output.head.configure(text=text)
        self.app.status(text)

    def sim(self):
        last = self.sim_opts or self.app.cfg.get("sim", {})
        d = SimOptionsDialog(self.app, last)
        self.app.wait_window(d)
        if not d.result:
            return
        opts = d.result
        self.sim_opts = opts
        self.app.cfg["sim"] = {k: v for k, v in opts.items() if k != "label"}
        self.app.cfg.save()
        self._pending_label = opts.pop("label", "")
        self._start("Balance sim: " + describe_options(opts), godot.sim_args(opts), lambda job, o=dict(opts): self._simmed(job, o))

    def _simmed(self, job, opts):
        r = godot.parse_sim(job.output)
        if not r["finished"]:
            self.output.head.configure(text=f"Balance sim did not finish (exit code {job.returncode})")
            return
        self.simpanel.history.save(opts, r["rows"], getattr(self, "_pending_label", ""), self.app.project.root)
        self.simpanel.reload(select_latest=True, compare_previous=True)
        self.app.show_dock(self.simpanel)
        self.output.head.configure(text="Balance sim finished - see the Balance sim tab")
        self.app.status("Balance sim finished. Selected it next to the previous run with the same options.")
