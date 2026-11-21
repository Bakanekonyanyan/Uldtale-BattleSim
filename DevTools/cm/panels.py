"""Bottom dock panels: Problems (validation results); Godot output and balance
sim history are added in cm/testpanel.py."""
from __future__ import annotations

import tkinter as tk
from tkinter import ttk

from .validate import Issue

SEVERITY_ORDER = {"error": 0, "warning": 1, "info": 2}


class ProblemsPanel(ttk.Frame):
    def __init__(self, master, app):
        super().__init__(master, padding=4)
        self.app = app
        self.issues: list[Issue] = []
        bar = ttk.Frame(self)
        bar.pack(fill="x")
        self.summary = ttk.Label(bar, text="Run Validate to check every file.", style="Bar.TLabel")
        self.summary.pack(side="left")
        self.show_info = tk.BooleanVar(value=False)
        ttk.Checkbutton(bar, text="Show notes", variable=self.show_info, style="Bar.TCheckbutton",
                        command=self.refresh).pack(side="right")
        cols = ("sev", "file", "entry", "field", "message")
        tf = ttk.Frame(self)
        tf.pack(fill="both", expand=True, pady=(4, 0))
        self.tree = ttk.Treeview(tf, columns=cols, show="headings", height=7)
        for c, w, text in [("sev", 70, "Severity"), ("file", 120, "File"), ("entry", 200, "Entry"),
                           ("field", 160, "Field"), ("message", 640, "Problem")]:
            self.tree.heading(c, text=text)
            self.tree.column(c, width=w, stretch=(c == "message"))
        sb = ttk.Scrollbar(tf, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")
        self.tree.tag_configure("error", foreground="#e07a5f")
        self.tree.tag_configure("warning", foreground="#e5c34a")
        self.tree.tag_configure("info", foreground="#a99f90")
        self.tree.bind("<Double-1>", self._open)
        self.tree.bind("<Return>", self._open)
        self._rows: dict = {}

    def set_issues(self, issues: list[Issue], summary: str):
        self.issues = list(issues)
        self.summary.configure(text=summary + "   (double-click a row to jump to it)")
        self.refresh()

    def add_issues(self, issues: list[Issue]):
        self.issues.extend(issues)
        self.issues.sort(key=lambda i: (SEVERITY_ORDER.get(i.severity, 3), i.tab, i.where))
        self.refresh()

    def remove_source(self, source: str):
        self.issues = [i for i in self.issues if i.source != source]

    def refresh(self):
        self.tree.delete(*self.tree.get_children())
        self._rows.clear()
        for i in self.issues:
            if i.severity == "info" and not self.show_info.get():
                continue
            label = i.severity + (" (godot)" if i.source == "godot" else "")
            iid = self.tree.insert("", "end", values=(label, i.tab, i.where, i.field, i.message), tags=(i.severity,))
            self._rows[iid] = i

    def _open(self, _e=None):
        sel = self.tree.selection()
        if not sel:
            return
        issue = self._rows.get(sel[0])
        if issue is None or not issue.tab:
            return
        field = issue.field.split("[")[0].split(".")[0] if issue.field else None
        self.app.go_to(issue.tab, issue.ref, field)
