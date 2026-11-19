"""Tk editors for each schema field type.

Every editor is a ttk.Frame with:
    set_value(value)   show a value from the data
    value()            -> (ok, value); ok=False while the input is invalid
and calls `on_change()` whenever the user changes something.
"""
from __future__ import annotations

import json
import tkinter as tk
from tkinter import ttk

from .schema import Field

PALETTE = {
    "dark": {"bg": "#1d1c21", "panel": "#26242b", "field": "#2f2c35", "fg": "#e6dccb", "muted": "#a99f90",
             "accent": "#e5c34a", "error": "#6b2a2a", "select": "#4a3f1a", "border": "#3d3944"},
    "light": {"bg": "#f3f1ec", "panel": "#ffffff", "field": "#ffffff", "fg": "#1d1c21", "muted": "#6b645a",
              "accent": "#9a7a12", "error": "#f3c6c6", "select": "#efe2b0", "border": "#c9c3b8"},
}
COLORS = dict(PALETTE["dark"])


def set_palette(name: str) -> None:
    COLORS.clear()
    COLORS.update(PALETTE[name])


def _num(field: Field, text: str):
    text = text.strip()
    if text == "":
        return False, None
    try:
        v = int(text) if field.type == "int" else float(text)
    except ValueError:
        return False, None
    if field.type == "int" and isinstance(v, float):
        return False, None
    if field.min is not None and v < field.min:
        return False, None
    if field.max is not None and v > field.max:
        return False, None
    return True, v


class Editor(ttk.Frame):
    def __init__(self, master, field: Field, choices, on_change):
        super().__init__(master, style="Form.TFrame")
        self.field = field
        self.choices = choices          # callable(field) -> list
        self.on_change = on_change
        self._loading = False

    def changed(self, *_):
        if not self._loading:
            self.on_change()

    def set_error(self, widget, bad: bool):
        try:
            widget.configure(style="Bad.TEntry" if bad else "TEntry")
        except tk.TclError:
            pass


class ScalarEditor(Editor):
    """str / int / float in a one-line entry."""

    def __init__(self, master, field, choices, on_change, width=18):
        super().__init__(master, field, choices, on_change)
        self.var = tk.StringVar()
        wide = field.type == "str" and width >= 18      # compact cells (map keys, table columns) stay small
        self.entry = ttk.Entry(self, textvariable=self.var, width=48 if wide else width)
        self.entry.pack(side="left", fill="x", expand=wide)
        self.var.trace_add("write", self._edited)
        if field.type in ("int", "float") and (field.min is not None or field.max is not None):
            rng = f"{'' if field.min is None else field.min} .. {'' if field.max is None else field.max}"
            ttk.Label(self, text=rng, style="Muted.TLabel").pack(side="left", padx=6)

    def _edited(self, *_):
        ok, _v = self.value()
        self.set_error(self.entry, not ok)
        self.changed()

    def set_value(self, value):
        self._loading = True
        self.var.set("" if value is None else (json.dumps(value) if isinstance(value, bool) else str(value)))
        self._loading = False
        self.set_error(self.entry, not self.value()[0])

    def value(self):
        if self.field.type == "str":
            return True, self.var.get()
        return _num(self.field, self.var.get())


class TextEditor(Editor):
    def __init__(self, master, field, choices, on_change):
        super().__init__(master, field, choices, on_change)
        self.text = tk.Text(self, height=3, width=60, wrap="word", undo=True, relief="flat",
                            bg=COLORS["field"], fg=COLORS["fg"], insertbackground=COLORS["fg"],
                            highlightthickness=1, highlightbackground=COLORS["border"])
        self.text.pack(fill="x", expand=True)
        self.text.bind("<<Modified>>", self._modified)

    def _modified(self, _e=None):
        if self.text.edit_modified():
            self.text.edit_modified(False)
            self.changed()

    def set_value(self, value):
        self._loading = True
        self.text.delete("1.0", "end")
        self.text.insert("1.0", "" if value is None else str(value))
        self.text.edit_modified(False)
        self._loading = False

    def value(self):
        return True, self.text.get("1.0", "end-1c")


class BoolEditor(Editor):
    def __init__(self, master, field, choices, on_change):
        super().__init__(master, field, choices, on_change)
        self.var = tk.BooleanVar()
        ttk.Checkbutton(self, variable=self.var, command=self.changed).pack(side="left")

    def set_value(self, value):
        self.var.set(bool(value))

    def value(self):
        return True, bool(self.var.get())


class EnumEditor(Editor):
    """One value from a list (combobox). Unknown current values are kept and flagged."""

    def __init__(self, master, field, choices, on_change, width=26):
        super().__init__(master, field, choices, on_change)
        self.var = tk.StringVar()
        self.box = ttk.Combobox(self, textvariable=self.var, width=width,
                                state="normal" if field.allow_custom or field.type == "str" else "readonly")
        self.box._cm_state = self.box.cget("state")
        self.box.pack(side="left")
        self.box.bind("<<ComboboxSelected>>", self.changed)
        self.var.trace_add("write", lambda *_: self._check())
        self.note = ttk.Label(self, text="", style="Error.TLabel")
        self.note.pack(side="left", padx=6)

    def _values(self):
        vals = list(self.choices(self.field))
        cur = self.var.get()
        if cur and cur not in vals:
            vals.append(cur)
        return vals

    def _check(self):
        cur = self.var.get()
        known = cur == "" or cur in self.choices(self.field)
        self.note.configure(text="" if known or self.field.allow_custom else "not a known value")
        if self.box.cget("state") == "normal":
            self.changed()

    def set_value(self, value):
        self._loading = True
        self.var.set("" if value is None else str(value))
        self.box.configure(values=self._values())
        self._loading = False
        self._check()

    def value(self):
        return True, self.var.get()


class ListEditor(Editor):
    """A list of values picked from a combobox (enum_list / ref_list / enum_multi)."""

    def __init__(self, master, field, choices, on_change):
        super().__init__(master, field, choices, on_change)
        self.items: list = []
        self.shape_str = False          # enum_multi: data was a single string
        top = ttk.Frame(self, style="Form.TFrame")
        top.pack(fill="x")
        self.lb = tk.Listbox(top, height=4, width=34, activestyle="none", relief="flat",
                             bg=COLORS["field"], fg=COLORS["fg"], selectbackground=COLORS["select"],
                             highlightthickness=1, highlightbackground=COLORS["border"], exportselection=False)
        self.lb.pack(side="left")
        btns = ttk.Frame(top, style="Form.TFrame")
        btns.pack(side="left", padx=4, fill="y")
        ttk.Button(btns, text="Remove", width=8, command=self._remove).pack(fill="x")
        ttk.Button(btns, text="Up", width=8, command=lambda: self._move(-1)).pack(fill="x", pady=2)
        ttk.Button(btns, text="Down", width=8, command=lambda: self._move(1)).pack(fill="x")
        add = ttk.Frame(self, style="Form.TFrame")
        add.pack(fill="x", pady=(3, 0))
        self.pick = tk.StringVar()
        self.box = ttk.Combobox(add, textvariable=self.pick, width=30,
                                state="normal" if field.allow_custom else "readonly")
        self.box._cm_state = self.box.cget("state")
        self.box.pack(side="left")
        self.box.bind("<Return>", lambda e: self._add())
        self.box.bind("<<ComboboxSelected>>", lambda e: self._add())
        ttk.Button(add, text="Add", command=self._add).pack(side="left", padx=4)
        self.note = ttk.Label(add, text="", style="Error.TLabel")
        self.note.pack(side="left", padx=4)

    def _refresh(self):
        self.lb.delete(0, "end")
        known = set(self.choices(self.field))
        for it in self.items:
            self.lb.insert("end", it if it in known or self.field.allow_custom else f"{it}   (unknown)")
        self.lb.configure(height=max(2, min(8, len(self.items))))
        self.box.configure(values=[c for c in self.choices(self.field) if c not in self.items])
        unknown = [i for i in self.items if i not in known] if not self.field.allow_custom else []
        self.note.configure(text=f"unknown: {', '.join(map(str, unknown))}" if unknown else "")

    def _add(self):
        v = self.pick.get().strip()
        if v and v not in self.items:
            self.items.append(v)
            self.pick.set("")
            self._refresh()
            self.changed()

    def _remove(self):
        for i in reversed(self.lb.curselection()):
            del self.items[i]
        self._refresh()
        self.changed()

    def _move(self, d):
        sel = self.lb.curselection()
        if not sel:
            return
        i = sel[0]
        j = i + d
        if 0 <= j < len(self.items):
            self.items[i], self.items[j] = self.items[j], self.items[i]
            self._refresh()
            self.lb.selection_set(j)
            self.changed()

    def set_value(self, value):
        self.shape_str = isinstance(value, str)
        if value is None or value == "":
            self.items = []
        elif isinstance(value, list):
            self.items = list(value)
        else:
            self.items = [value]
        if self.field.type == "enum_multi" and self.items in (["NONE"],):
            self.items = []
            self._none_marker = True
        else:
            self._none_marker = False
        self._refresh()

    def value(self):
        if self.field.type != "enum_multi":
            return True, list(self.items)
        if not self.items:
            return True, ("NONE" if self._none_marker or "NONE" in self.choices(self.field) else "") if self.shape_str else []
        if self.shape_str and len(self.items) == 1:
            return True, self.items[0]
        return True, list(self.items)


class JsonEditor(Editor):
    def __init__(self, master, field, choices, on_change, height=5):
        super().__init__(master, field, choices, on_change)
        self.text = tk.Text(self, height=height, width=70, wrap="none", undo=True, relief="flat",
                            font=("TkFixedFont", 10), bg=COLORS["field"], fg=COLORS["fg"],
                            insertbackground=COLORS["fg"], highlightthickness=1,
                            highlightbackground=COLORS["border"])
        self.text.pack(fill="x", expand=True)
        self.note = ttk.Label(self, text="", style="Error.TLabel")
        self.note.pack(anchor="w")
        self.text.bind("<<Modified>>", self._modified)

    def _modified(self, _e=None):
        if self.text.edit_modified():
            self.text.edit_modified(False)
            ok, _ = self.value()
            self.text.configure(bg=COLORS["field"] if ok else COLORS["error"])
            self.note.configure(text="" if ok else "not valid JSON yet")
            self.changed()

    def set_value(self, value):
        self._loading = True
        self.text.delete("1.0", "end")
        txt = json.dumps(value, indent=2, ensure_ascii=False)
        self.text.insert("1.0", txt)
        self.text.configure(height=max(2, min(14, txt.count("\n") + 1)))
        self.text.edit_modified(False)
        self._loading = False

    def value(self):
        try:
            return True, json.loads(self.text.get("1.0", "end-1c"))
        except ValueError:
            return False, None


class RowsEditor(Editor):
    """Base for map (key -> value) and table (list of rows)."""

    def __init__(self, master, field, choices, on_change):
        super().__init__(master, field, choices, on_change)
        self.rows: list = []
        self.body = ttk.Frame(self, style="Form.TFrame")
        self.body.pack(fill="x")
        bar = ttk.Frame(self, style="Form.TFrame")
        bar.pack(fill="x", pady=(2, 0))
        ttk.Button(bar, text="+ Add row", command=self._add_row).pack(side="left")

    def _cell(self, parent, spec: Field, value):
        ed = make_editor(parent, spec, self.choices, self.changed, compact=True)
        ed.set_value(value)
        return ed

    def _remove_row(self, row):
        row["frame"].destroy()
        self.rows.remove(row)
        self.changed()


class MapEditor(RowsEditor):
    def _add_row(self, key="", value=None, notify=True):
        f = ttk.Frame(self.body, style="Form.TFrame")
        f.pack(fill="x", pady=1)
        k = self._cell(f, self.field.key, key)
        k.pack(side="left")
        ttk.Label(f, text="  ->  ", style="Muted.TLabel").pack(side="left")
        v = self._cell(f, self.field.value, self.field.value.default_value() if value is None else value)
        v.pack(side="left")
        row = {"frame": f, "key": k, "value": v}
        ttk.Button(f, text="x", width=2, command=lambda: self._remove_row(row)).pack(side="left", padx=4)
        self.rows.append(row)
        if notify:
            self.changed()

    def set_value(self, value):
        self._loading = True
        for r in self.rows:
            r["frame"].destroy()
        self.rows = []
        for k, v in (value or {}).items():
            self._add_row(k, v, notify=False)
        self._loading = False

    def value(self):
        out = {}
        for r in self.rows:
            okk, k = r["key"].value()
            okv, v = r["value"].value()
            if not okk or not okv:
                return False, None
            if k == "":
                continue
            if k in out:
                return False, None
            out[k] = v
        return True, out


class TableEditor(RowsEditor):
    def __init__(self, master, field, choices, on_change):
        super().__init__(master, field, choices, on_change)
        head = ttk.Frame(self, style="Form.TFrame")
        head.pack(before=self.body, fill="x")
        for c in field.columns:
            ttk.Label(head, text=c.label, style="Muted.TLabel", width=22).pack(side="left")

    def _add_row(self, value=None, notify=True):
        value = value or {c.name: c.default_value() for c in self.field.columns}
        f = ttk.Frame(self.body, style="Form.TFrame")
        f.pack(fill="x", pady=1)
        cells = {}
        for c in self.field.columns:
            ed = self._cell(f, c, value.get(c.name, c.default_value()))
            ed.pack(side="left", padx=(0, 6))
            cells[c.name] = ed
        row = {"frame": f, "cells": cells, "extra": {k: v for k, v in value.items() if k not in cells}}
        ttk.Button(f, text="x", width=2, command=lambda: self._remove_row(row)).pack(side="left")
        self.rows.append(row)
        if notify:
            self.changed()

    def set_value(self, value):
        self._loading = True
        for r in self.rows:
            r["frame"].destroy()
        self.rows = []
        for v in value or []:
            self._add_row(v if isinstance(v, dict) else {}, notify=False)
        self._loading = False

    def value(self):
        out = []
        for r in self.rows:
            d = {}
            for name, ed in r["cells"].items():
                ok, v = ed.value()
                if not ok:
                    return False, None
                d[name] = v
            d.update(r["extra"])
            out.append(d)
        return True, out


class ObjectEditor(Editor):
    """Nested dict with its own fields (e.g. a recipe's unlock rule)."""

    def __init__(self, master, field, choices, on_change):
        super().__init__(master, field, choices, on_change)
        self.form = Form(self, field.fields, choices, self.changed)
        self.form.pack(fill="x")
        self.extra: dict = {}

    def set_value(self, value):
        value = value if isinstance(value, dict) else {}
        self.extra = {k: v for k, v in value.items() if k not in {f.name for f in self.field.fields}}
        self.form.load(value)

    def value(self):
        ok, d = self.form.collect()
        if not ok:
            return False, None
        d.update(self.extra)
        return True, d


def make_editor(master, field: Field, choices, on_change, compact=False) -> Editor:
    t = field.type
    if t in ("str",) and (field.options or field.source):
        return EnumEditor(master, field, choices, on_change)
    if t in ("str", "int", "float"):
        return ScalarEditor(master, field, choices, on_change, width=10 if compact else 18)
    if t == "text":
        return TextEditor(master, field, choices, on_change)
    if t == "bool":
        return BoolEditor(master, field, choices, on_change)
    if t in ("enum", "ref"):
        return EnumEditor(master, field, choices, on_change, width=22 if compact else 28)
    if t in ("enum_list", "ref_list", "enum_multi"):
        return ListEditor(master, field, choices, on_change)
    if t == "map":
        return MapEditor(master, field, choices, on_change)
    if t == "table":
        return TableEditor(master, field, choices, on_change)
    if t == "object":
        return ObjectEditor(master, field, choices, on_change)
    return JsonEditor(master, field, choices, on_change)


class Form(ttk.Frame):
    """Label + editor rows for a list of fields. Optional fields get an
    'include' checkbox; unticking removes the key from the data."""

    def __init__(self, master, fields, choices, on_change, on_field_change=None):
        super().__init__(master, style="Form.TFrame")
        self.fields = fields
        self.choices = choices
        self.on_change = on_change
        self.on_field_change = on_field_change     # (name, ok, value, present) for live writes
        self.rows: dict = {}
        self.columnconfigure(1, weight=1)
        for i, f in enumerate(fields):
            self._row(i, f)

    def _row(self, i, f: Field):
        lab = ttk.Frame(self, style="Form.TFrame")
        lab.grid(row=i * 2, column=0, sticky="nw", padx=(0, 10), pady=(6, 0))
        present = tk.BooleanVar(value=True)
        if f.optional:
            ttk.Checkbutton(lab, variable=present, command=lambda n=f.name: self._toggle(n)).pack(side="left")
        ttk.Label(lab, text=f.label, style="Field.TLabel").pack(side="left")
        ed = make_editor(self, f, self.choices, lambda n=f.name: self._edited(n))
        ed.grid(row=i * 2, column=1, sticky="w", pady=(6, 0))
        if f.help:
            ttk.Label(self, text=f.help, style="Help.TLabel", wraplength=560, justify="left").grid(
                row=i * 2 + 1, column=1, sticky="w")
        self.rows[f.name] = {"field": f, "editor": ed, "present": present}

    def _set_enabled(self, widget, enabled):
        for child in widget.winfo_children():
            try:
                if enabled:
                    child.configure(state=getattr(child, "_cm_state", "normal"))
                else:
                    child.configure(state="disabled")
            except tk.TclError:
                pass
            self._set_enabled(child, enabled)

    def _toggle(self, name):
        row = self.rows[name]
        on = row["present"].get()
        self._set_enabled(row["editor"], on)
        if on:
            ok, v = row["editor"].value()
            if not ok or v in (None, "", [], {}):
                row["editor"].set_value(row["field"].default_value())
        self._edited(name)

    def _edited(self, name):
        if self.on_field_change:
            row = self.rows[name]
            ok, v = row["editor"].value()
            self.on_field_change(name, ok, v, row["present"].get())
        self.on_change()

    def load(self, data: dict):
        for name, row in self.rows.items():
            f = row["field"]
            has = name in data
            row["present"].set(has or not f.optional)
            # enable first: Tk ignores inserts into disabled Listbox/Text widgets
            self._set_enabled(row["editor"], True)
            row["editor"].set_value(data[name] if has else f.default_value())
            if not (has or not f.optional):
                self._set_enabled(row["editor"], False)

    def collect(self):
        out = {}
        for name, row in self.rows.items():
            if not row["present"].get():
                continue
            ok, v = row["editor"].value()
            if not ok:
                return False, None
            out[name] = v
        return True, out
