"""Main window: one tab per data file (from DevTools/schemas), an entry list on
the left and a form on the right. Edits go straight into the in-memory data;
Save writes only the files that changed (minimal diffs, see cm/splice.py)."""
from __future__ import annotations

import json
import os
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from . import widgets
from .config import Config, is_project_root
from .project import EntryRef, Project
from .widgets import COLORS, Form, JsonEditor

APP_TITLE = "Uldtale Content Manager"


def apply_theme(root: tk.Tk, dark: bool) -> None:
    widgets.set_palette("dark" if dark else "light")
    c = COLORS
    st = ttk.Style(root)
    st.theme_use("clam")
    root.configure(bg=c["bg"])
    st.configure(".", background=c["bg"], foreground=c["fg"], fieldbackground=c["field"],
                 bordercolor=c["border"], lightcolor=c["panel"], darkcolor=c["bg"],
                 troughcolor=c["panel"], selectbackground=c["select"], selectforeground=c["fg"],
                 insertcolor=c["fg"], font=("TkDefaultFont", 10))
    st.configure("TFrame", background=c["bg"])
    st.configure("Form.TFrame", background=c["panel"])
    st.configure("Panel.TFrame", background=c["panel"])
    st.configure("TLabel", background=c["bg"], foreground=c["fg"])
    for name, fg, font in [("Field", c["fg"], ("TkDefaultFont", 10, "bold")),
                           ("Help", c["muted"], ("TkDefaultFont", 9)),
                           ("Muted", c["muted"], ("TkDefaultFont", 9)),
                           ("Error", "#e07a5f", ("TkDefaultFont", 9)),
                           ("Section", c["accent"], ("TkDefaultFont", 10, "bold"))]:
        st.configure(f"{name}.TLabel", background=c["panel"], foreground=fg, font=font)
    st.configure("Title.TLabel", background=c["panel"], foreground=c["accent"], font=("TkDefaultFont", 15, "bold"))
    st.configure("Sub.TLabel", background=c["panel"], foreground=c["muted"])
    st.configure("Bar.TLabel", background=c["bg"], foreground=c["muted"])
    st.configure("TButton", background=c["field"], foreground=c["fg"], padding=(8, 3), bordercolor=c["border"])
    st.map("TButton", background=[("active", c["select"]), ("disabled", c["bg"])],
           foreground=[("disabled", c["muted"])])
    st.configure("Accent.TButton", background=c["accent"], foreground="#111111")
    st.map("Accent.TButton", background=[("active", c["accent"])])
    st.configure("TCheckbutton", background=c["panel"], foreground=c["fg"])
    st.configure("Bar.TCheckbutton", background=c["bg"], foreground=c["fg"])
    st.map("TCheckbutton", background=[("active", c["panel"])])
    st.configure("TEntry", fieldbackground=c["field"], foreground=c["fg"])
    st.configure("Bad.TEntry", fieldbackground=c["error"], foreground=c["fg"])
    st.configure("TCombobox", fieldbackground=c["field"], foreground=c["fg"], background=c["field"])
    st.map("TCombobox", fieldbackground=[("readonly", c["field"]), ("disabled", c["bg"])],
           foreground=[("disabled", c["muted"])])
    root.option_add("*TCombobox*Listbox.background", c["field"])
    root.option_add("*TCombobox*Listbox.foreground", c["fg"])
    root.option_add("*TCombobox*Listbox.selectBackground", c["select"])
    st.configure("Treeview", background=c["panel"], fieldbackground=c["panel"], foreground=c["fg"], rowheight=22)
    st.map("Treeview", background=[("selected", c["select"])], foreground=[("selected", c["fg"])])
    st.configure("Treeview.Heading", background=c["bg"], foreground=c["muted"])
    st.configure("TNotebook", background=c["bg"], borderwidth=0)
    st.configure("TNotebook.Tab", background=c["bg"], foreground=c["muted"], padding=(8, 4), font=("TkDefaultFont", 10))
    st.map("TNotebook.Tab", background=[("selected", c["panel"])], foreground=[("selected", c["accent"])])
    st.configure("TPanedwindow", background=c["bg"])


class ScrollFrame(ttk.Frame):
    """A vertically scrollable frame (canvas + inner frame)."""

    def __init__(self, master):
        super().__init__(master, style="Panel.TFrame")
        self.canvas = tk.Canvas(self, bg=COLORS["panel"], highlightthickness=0)
        sb = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.inner = ttk.Frame(self.canvas, style="Form.TFrame", padding=(14, 10))
        self.inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self._win = self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfigure(self._win, width=e.width))
        self.canvas.configure(yscrollcommand=sb.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")
        for w in (self.canvas, self.inner):
            w.bind("<Enter>", lambda e: self._wheel(True))
            w.bind("<Leave>", lambda e: self._wheel(False))

    def _wheel(self, on):
        if on:
            self.bind_all("<MouseWheel>", lambda e: self.canvas.yview_scroll(int(-e.delta / 120), "units"))
            self.bind_all("<Button-4>", lambda e: self.canvas.yview_scroll(-3, "units"))
            self.bind_all("<Button-5>", lambda e: self.canvas.yview_scroll(3, "units"))
        else:
            self.unbind_all("<MouseWheel>")
            self.unbind_all("<Button-4>")
            self.unbind_all("<Button-5>")

    def to_top(self):
        self.canvas.yview_moveto(0)


class NewEntryDialog(tk.Toplevel):
    """Ask for group (levels), display name and id for a new entry."""

    def __init__(self, app, tab: str, section_index: int, copy_from: EntryRef | None = None):
        super().__init__(app)
        self.app, self.tab, self.si, self.copy_from = app, tab, section_index, copy_from
        self.p = app.project
        self.section = self.p.by_tab[tab].sections[section_index]
        self.result: EntryRef | None = None
        self.title(("Duplicate " if copy_from else "New ") + self.section.label.rstrip("s").lower())
        self.configure(bg=COLORS["panel"])
        self.transient(app)
        body = ttk.Frame(self, style="Form.TFrame", padding=16)
        body.pack(fill="both", expand=True)
        row = 0
        self.group_vars = []
        for li, lvl in enumerate(self.section.levels):
            ttk.Label(body, text=lvl["name"].capitalize(), style="Field.TLabel").grid(row=row, column=0, sticky="w", pady=4)
            v = tk.StringVar(value=(copy_from.groups[li] if copy_from else ""))
            cb = ttk.Combobox(body, textvariable=v, width=28)
            cb.grid(row=row, column=1, sticky="w", pady=4)
            cb.bind("<Button-1>", lambda e, i=li, box=cb: box.configure(values=self._group_opts(i)))
            cb.configure(values=self._group_opts(li))
            if not v.get() and cb.cget("values"):
                v.set(cb.cget("values")[0])
            if lvl.get("help"):
                ttk.Label(body, text=lvl["help"], style="Help.TLabel").grid(row=row + 1, column=1, sticky="w")
                row += 1
            self.group_vars.append(v)
            row += 1
        has_name = "name" in self.section.field_map
        self.name_var = tk.StringVar()
        if has_name:
            ttk.Label(body, text="Name", style="Field.TLabel").grid(row=row, column=0, sticky="w", pady=4)
            e = ttk.Entry(body, textvariable=self.name_var, width=32)
            e.grid(row=row, column=1, sticky="w", pady=4)
            e.focus_set()
            row += 1
        ttk.Label(body, text=self.section.key_label, style="Field.TLabel").grid(row=row, column=0, sticky="w", pady=4)
        self.key_var = tk.StringVar()
        ke = ttk.Entry(body, textvariable=self.key_var, width=32)
        ke.grid(row=row, column=1, sticky="w", pady=4)
        if not has_name:
            ke.focus_set()
        row += 1
        if self.section.key_help:
            ttk.Label(body, text=self.section.key_help, style="Help.TLabel", wraplength=360).grid(row=row, column=1, sticky="w")
            row += 1
        self._auto_key = True
        self.name_var.trace_add("write", self._name_changed)
        self.key_var.trace_add("write", lambda *_: self._key_edited())
        if copy_from:
            src = self.p.get(copy_from) or {}
            nm = src.get("name", "") if isinstance(src, dict) else ""
            self.name_var.set(f"{nm} Copy" if nm else "")
            if not has_name:
                self.key_var.set(f"{copy_from.key}_copy")
        self.err = ttk.Label(body, text="", style="Error.TLabel")
        self.err.grid(row=row, column=0, columnspan=2, sticky="w", pady=(6, 0))
        row += 1
        btns = ttk.Frame(body, style="Form.TFrame")
        btns.grid(row=row, column=0, columnspan=2, sticky="e", pady=(10, 0))
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right")
        ttk.Button(btns, text="Create", style="Accent.TButton", command=self._ok).pack(side="right", padx=6)
        self.bind("<Return>", lambda e: self._ok())
        self.bind("<Escape>", lambda e: self.destroy())
        self.grab_set()

    def _group_opts(self, level):
        parents = tuple(v.get() for v in self.group_vars[:level])
        return self.p.group_options(self.tab, self.si, level, parents)

    def _name_changed(self, *_):
        if self._auto_key:
            self._setting = True
            self.key_var.set(self.p.suggest_key(self.section, self.name_var.get()))
            self._setting = False

    def _key_edited(self):
        if not getattr(self, "_setting", False):
            self._auto_key = False

    def _ok(self):
        key = self.key_var.get().strip()
        groups = tuple(v.get().strip() for v in self.group_vars)
        if any(not g for g in groups):
            self.err.configure(text="Pick a value for every group.")
            return
        problem = self.p.key_problem(self.section, key)
        if problem:
            self.err.configure(text=problem)
            return
        if key in [r.key for r in self.p.entries(self.tab, self.si) if r.groups == groups]:
            self.err.configure(text=f"'{key}' already exists here.")
            return
        if self.copy_from:
            entry = json.loads(json.dumps(self.p.get(self.copy_from)))
        else:
            entry = self.p.template_for(self.section)
            # fill group-mirroring fields like an armor's type/slot
            for lvl, g in zip(self.section.levels, groups):
                for fname in lvl.get("sets", []):
                    entry[fname] = g
        if "name" in self.section.field_map and self.name_var.get().strip():
            entry["name"] = self.name_var.get().strip()
        self.result = self.p.add_entry(self.tab, self.si, groups, key, entry)
        self.destroy()


class TabView(ttk.Frame):
    """One data file: entry tree on the left, form on the right."""

    def __init__(self, app, tab: str):
        super().__init__(app.notebook)
        self.app, self.tab = app, tab
        self.p: Project = app.project
        self.schema = self.p.by_tab[tab]
        self.current: EntryRef | None = None
        self.iid_to_ref: dict = {}
        self.forms: dict = {}

        pw = ttk.PanedWindow(self, orient="horizontal")
        pw.pack(fill="both", expand=True)
        left = ttk.Frame(pw, padding=(6, 6, 2, 6))
        right = ttk.Frame(pw, style="Panel.TFrame")
        pw.add(left, weight=0)
        pw.add(right, weight=1)
        self.after(50, lambda: pw.sashpos(0, 300))

        bar = ttk.Frame(left)
        bar.pack(fill="x")
        for text, cmd in [("New", self.new), ("Duplicate", self.duplicate), ("Rename", self.rename), ("Delete", self.delete)]:
            ttk.Button(bar, text=text, command=cmd).pack(side="left", padx=(0, 3))
        srow = ttk.Frame(left)
        srow.pack(fill="x", pady=6)
        ttk.Label(srow, text="Search", style="Bar.TLabel").pack(side="left", padx=(0, 6))
        self.search = tk.StringVar()
        se = ttk.Entry(srow, textvariable=self.search)
        se.pack(side="left", fill="x", expand=True)
        self.search.trace_add("write", lambda *_: self.refresh_tree())
        self.search_entry = se
        tf = ttk.Frame(left)
        tf.pack(fill="both", expand=True)
        self.tree = ttk.Treeview(tf, show="tree", selectmode="browse")
        sb = ttk.Scrollbar(tf, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")
        self.tree.bind("<<TreeviewSelect>>", self._selected)
        self.tree.tag_configure("group", foreground=COLORS["muted"])
        self.tree.tag_configure("section", foreground=COLORS["accent"])

        head = ttk.Frame(right, style="Panel.TFrame", padding=(14, 10, 14, 4))
        head.pack(fill="x")
        self.title_lbl = ttk.Label(head, text=tab, style="Title.TLabel")
        self.title_lbl.pack(anchor="w")
        self.sub_lbl = ttk.Label(head, text=self.schema.description or self.schema.file, style="Sub.TLabel", wraplength=760, justify="left")
        self.sub_lbl.pack(anchor="w")
        self.scroll = ScrollFrame(right)
        self.scroll.pack(fill="both", expand=True)
        self.other_frame = None
        self.refresh_tree()

    # ------------------------------------------------------------- tree

    def refresh_tree(self, select: EntryRef | None = None):
        q = self.search.get().strip().lower()
        self.tree.delete(*self.tree.get_children())
        self.iid_to_ref.clear()
        multi = len(self.schema.sections) > 1
        first = None
        for si, sec in enumerate(self.schema.sections):
            parent = ""
            if multi:
                parent = self.tree.insert("", "end", text=sec.label, open=True, tags=("section",))
                if sec.kind == "settings":
                    ref = EntryRef(self.tab, si)
                    self.iid_to_ref[parent] = ref
                    first = first or parent
                    continue
            if sec.kind == "settings":
                iid = self.tree.insert(parent, "end", text=sec.label)
                self.iid_to_ref[iid] = EntryRef(self.tab, si)
                first = first or iid
                continue
            groups = {}
            for ref in self.p.entries(self.tab, si):
                label = self.p.display_name(ref)
                if q and q not in label.lower() and q not in "/".join(map(str, ref.groups)).lower():
                    continue
                gparent = parent
                for depth in range(len(ref.groups)):
                    gk = ref.groups[: depth + 1]
                    if gk not in groups:
                        groups[gk] = self.tree.insert(gparent, "end", text=str(gk[-1]), open=bool(q) or depth == 0, tags=("group",))
                    gparent = groups[gk]
                iid = self.tree.insert(gparent, "end", text=label)
                self.iid_to_ref[iid] = ref
                first = first or iid
                if select is not None and ref == select:
                    self.tree.see(iid)
                    self.tree.selection_set(iid)
        if select is None and self.current is not None:
            for iid, r in self.iid_to_ref.items():
                if r == self.current:
                    self.tree.selection_set(iid)
                    self.tree.see(iid)
                    return
        if select is None and self.current is None and first:
            self.tree.selection_set(first)

    def _selected(self, _e=None):
        sel = self.tree.selection()
        if not sel or sel[0] not in self.iid_to_ref:
            return
        self.show(self.iid_to_ref[sel[0]])

    # ------------------------------------------------------------- form

    def _form_for(self, si: int) -> Form:
        if si not in self.forms:
            sec = self.schema.sections[si]
            frame = ttk.Frame(self.scroll.inner, style="Form.TFrame")
            form = Form(frame, sec.fields, self.p.choices, lambda: None, self._field_changed)
            form.pack(fill="x")
            self.forms[si] = (frame, form)
        return self.forms[si]

    def show(self, ref: EntryRef, focus_field: str | None = None):
        self.current = ref
        sec = self.p.section(ref)
        data = self.p.get(ref)
        for si, (frame, _f) in self.forms.items():
            frame.pack_forget()
        if self.other_frame is not None:
            self.other_frame.destroy()
            self.other_frame = None
        if not isinstance(data, dict):
            self.title_lbl.configure(text=f"{ref.label()} (missing)")
            return
        frame, form = self._form_for(ref.section)
        form.load(data)
        frame.pack(fill="x")
        title = ref.key if ref.key is not None else sec.label
        self.title_lbl.configure(text=str(title))
        sub = " / ".join(map(str, ref.groups))
        if sec.name_field and data.get(sec.name_field) and data.get(sec.name_field) != ref.key:
            sub = (sub + "   " if sub else "") + str(data.get(sec.name_field))
        if sec.summary:
            try:
                sub = (sub + "   " if sub else "") + sec.summary.format(**{k: v for k, v in data.items()})
            except (KeyError, IndexError, ValueError):
                pass
        self.sub_lbl.configure(text=sub or (self.schema.description or self.schema.file))
        others = [k for k in self.p.other_fields(ref)]
        if others:
            self.other_frame = ttk.Frame(self.scroll.inner, style="Form.TFrame")
            self.other_frame.pack(fill="x", pady=(16, 0))
            ttk.Label(self.other_frame, text="Other fields (not in the schema, kept as-is)", style="Section.TLabel").pack(anchor="w")
            for k in others:
                row = ttk.Frame(self.other_frame, style="Form.TFrame")
                row.pack(fill="x", pady=3)
                ttk.Label(row, text=k, style="Field.TLabel", width=22).pack(side="left", anchor="n")
                from .schema import Field
                ed = JsonEditor(row, Field({"name": k, "type": "json"}), self.p.choices,
                                lambda name=k, e=None: None, height=2)
                ed.on_change = lambda name=k, editor=ed: self._other_changed(name, editor)
                ed.set_value(data[k])
                ed.pack(side="left", fill="x", expand=True)
        self.scroll.to_top()
        if focus_field and focus_field in form.rows:
            w = form.rows[focus_field]["editor"]
            self.after(50, lambda: self._reveal(w))

    def _reveal(self, widget):
        try:
            y = widget.winfo_rooty() - self.scroll.inner.winfo_rooty()
            h = max(1, self.scroll.inner.winfo_height())
            self.scroll.canvas.yview_moveto(max(0.0, (y - 40) / h))
            widget.focus_set()
        except tk.TclError:
            pass

    def _field_changed(self, name, ok, value, present):
        if self.current is None:
            return
        if not ok:
            self.app.status(f"{name}: invalid value - not applied yet")
            return
        self.p.set_field(self.current, name, value, remove=not present)
        self.app.mark_changed(self.tab)
        if name == self.p.section(self.current).name_field:
            self._relabel()

    def _other_changed(self, name, editor):
        ok, v = editor.value()
        if ok and self.current is not None:
            self.p.set_field(self.current, name, v)
            self.app.mark_changed(self.tab)

    def _relabel(self):
        for iid, r in self.iid_to_ref.items():
            if r == self.current:
                self.tree.item(iid, text=self.p.display_name(r))

    # ------------------------------------------------------------- actions

    def _collection_index(self) -> int | None:
        if self.current is not None and self.p.section(self.current).kind == "collection":
            return self.current.section
        cols = [i for i, s in enumerate(self.schema.sections) if s.kind == "collection"]
        return cols[0] if len(cols) == 1 else (cols[0] if cols else None)

    def new(self):
        si = self._collection_index()
        if si is None:
            return
        d = NewEntryDialog(self.app, self.tab, si)
        self.wait_window(d)
        self._after_add(d.result)

    def duplicate(self):
        if self.current is None or self.current.key is None:
            return
        d = NewEntryDialog(self.app, self.tab, self.current.section, copy_from=self.current)
        self.wait_window(d)
        self._after_add(d.result)

    def _after_add(self, ref):
        if ref is None:
            return
        self.search.set("")
        self.current = ref
        self.refresh_tree(select=ref)
        self.show(ref)
        self.app.mark_changed(self.tab)
        self.app.status(f"Created {ref.label()} - not saved yet")

    def rename(self):
        ref = self.current
        if ref is None or ref.key is None:
            return
        sec = self.p.section(ref)
        new = _ask_string(self.app, "Rename", f"New {sec.key_label.lower()} for '{ref.key}':", ref.key)
        if not new or new == ref.key:
            return
        problem = self.p.key_problem(sec, new)
        if problem:
            messagebox.showerror("Rename", problem, parent=self.app)
            return
        try:
            ref2 = self.p.rename_entry(ref, new)
        except KeyError as e:
            messagebox.showerror("Rename", str(e), parent=self.app)
            return
        self.current = ref2
        self.refresh_tree(select=ref2)
        self.show(ref2)
        self.app.mark_changed(self.tab)
        self.app.status(f"Renamed to {new}. Other files that refer to '{ref.key}' are not changed - run Validate to find them.")

    def delete(self):
        ref = self.current
        if ref is None or ref.key is None:
            return
        if not messagebox.askyesno("Delete", f"Delete '{ref.label()}'?\n\nYou can undo by closing without saving.", parent=self.app):
            return
        self.p.delete_entry(ref)
        self.current = None
        self.refresh_tree()
        self._selected()
        self.app.mark_changed(self.tab)
        self.app.status(f"Deleted {ref.label()} - not saved yet")


def _ask_string(parent, title, prompt, initial=""):
    from tkinter import simpledialog
    return simpledialog.askstring(title, prompt, initialvalue=initial, parent=parent)


class App(tk.Tk):
    def __init__(self, config: Config | None = None):
        super().__init__()
        self.cfg = config or Config()
        apply_theme(self, self.cfg.get("dark_mode", True))
        self.title(APP_TITLE)
        self.geometry("1280x820")
        self.minsize(900, 600)
        self.project = Project(self.cfg.root)
        self.views: dict = {}
        self._build()
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.bind_all("<Control-s>", lambda e: self.save_all())
        self.bind_all("<Control-f>", lambda e: self.current_view() and self.current_view().search_entry.focus_set())
        if self.project.load_errors:
            messagebox.showwarning(APP_TITLE, "Some files could not be read:\n\n" + "\n".join(
                f"{t}: {e}" for t, e in self.project.load_errors.items()), parent=self)

    # ------------------------------------------------------------- layout

    def _build(self):
        self.toolbar = ttk.Frame(self, padding=(8, 6))
        self.toolbar.pack(fill="x")
        self.save_btn = ttk.Button(self.toolbar, text="Save all", style="Accent.TButton", command=self.save_all)
        self.save_btn.pack(side="left")
        ttk.Button(self.toolbar, text="Reload", command=self.reload).pack(side="left", padx=4)
        self.tools = ttk.Frame(self.toolbar)       # Validate / tests go here
        self.tools.pack(side="left", padx=12)
        self.dark_var = tk.BooleanVar(value=self.cfg.get("dark_mode", True))
        ttk.Checkbutton(self.toolbar, text="Dark", variable=self.dark_var, style="Bar.TCheckbutton",
                        command=self._toggle_dark).pack(side="right")
        ttk.Button(self.toolbar, text="Change...", command=self.change_root).pack(side="right", padx=6)
        self.root_lbl = ttk.Label(self.toolbar, text=self.project.root, style="Bar.TLabel")
        self.root_lbl.pack(side="right")

        self.vpane = ttk.PanedWindow(self, orient="vertical")
        self.vpane.pack(fill="both", expand=True)
        self.notebook = ttk.Notebook(self.vpane)
        self.vpane.add(self.notebook, weight=5)
        for s in self.project.schemas:
            v = TabView(self, s.tab)
            self.views[s.tab] = v
            self.notebook.add(v, text=s.tab)
        self.dock = ttk.Notebook(self.vpane)       # Problems / Godot output (added later)
        self._dock_shown = False

        self.status_var = tk.StringVar(value="Ready. Ctrl+S saves all changed files; Ctrl+F searches the current tab.")
        ttk.Label(self, textvariable=self.status_var, style="Bar.TLabel", padding=(8, 3)).pack(fill="x", side="bottom")

    def show_dock(self, page=None):
        if not self._dock_shown:
            self.vpane.add(self.dock, weight=2)
            self._dock_shown = True
        if page is not None:
            self.dock.select(page)

    def current_view(self) -> TabView | None:
        try:
            return self.views[self.notebook.tab(self.notebook.select(), "text").rstrip(" *")]
        except (KeyError, tk.TclError):
            return None

    def go_to(self, tab: str, ref: EntryRef | None, field: str | None = None):
        view = self.views.get(tab)
        if view is None:
            return
        self.notebook.select(view)
        if ref is not None and view.p.get(ref) is not None:
            view.search.set("")
            view.current = ref
            view.refresh_tree(select=ref)
            view.show(ref, focus_field=field)

    # ------------------------------------------------------------ status

    def status(self, text: str):
        self.status_var.set(text)

    def mark_changed(self, tab: str | None = None):
        dirty = self.project.dirty_tabs()
        for t, v in self.views.items():
            self.notebook.tab(v, text=t + (" *" if t in dirty else ""))
        self.save_btn.configure(text=f"Save all ({len(dirty)})" if dirty else "Save all")
        self.title(APP_TITLE + (" *" if dirty else ""))

    # ------------------------------------------------------------ actions

    def save_all(self) -> list:
        try:
            saved = self.project.save_all()
        except OSError as e:
            messagebox.showerror("Save", str(e), parent=self)
            return []
        self.mark_changed()
        self.status(("Saved: " + ", ".join(saved)) if saved else "Nothing to save.")
        return saved

    def reload(self):
        if self.project.dirty_tabs() and not messagebox.askyesno(
                "Reload", "Discard unsaved changes and reload all files from disk?", parent=self):
            return
        self.project.load()
        for v in self.views.values():
            v.current = None
            v.refresh_tree()
            v._selected()
        self.mark_changed()
        self.status("Reloaded from disk.")

    def change_root(self):
        d = filedialog.askdirectory(title="Select the Uldtale-BattleSim folder (contains project.godot)", parent=self)
        if not d:
            return
        if not is_project_root(d):
            messagebox.showerror("Project folder", "That folder has no project.godot and data/ folder.", parent=self)
            return
        self.cfg["root_directory"] = d
        self.cfg.save()
        messagebox.showinfo("Project folder", "Restart the content manager to load the new folder.", parent=self)

    def _toggle_dark(self):
        self.cfg["dark_mode"] = bool(self.dark_var.get())
        self.cfg.save()
        apply_theme(self, self.cfg["dark_mode"])
        self.status("Theme changed - restart to recolour every text box.")

    def on_close(self):
        dirty = self.project.dirty_tabs()
        if dirty:
            ans = messagebox.askyesnocancel(APP_TITLE, "Save changes to " + ", ".join(dirty) + " before closing?", parent=self)
            if ans is None:
                return
            if ans:
                self.save_all()
        self.destroy()


def main():
    app = App()
    app.mainloop()
