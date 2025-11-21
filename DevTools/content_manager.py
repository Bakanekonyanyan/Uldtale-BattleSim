#!/usr/bin/env python3
"""
contentmanager.py
Uldtale-Battlesim Content Manager
- Project-root aware (choose Uldtale-Battlesim root)
- Loads files from data/ and data/items/
- Edit JSON entries, add/duplicate/delete
- Dropdowns for rarity/elements where possible
- Auto-backups on save
- Dark mode toggle
"""

import os
import json
import shutil
import datetime
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog, filedialog

CONFIG_FILE = "content_manager_config.json"

# relative paths mapped to tabs
JSON_FILES = {
    "Classes": "data/classes.json",
    "Races": "data/races.json",
    "Skills": "data/skills.json",
    "Rarities": "data/rarities.json",
    "Status Effects": "data/status_effects.json",
    "Armors": "data/items/armors.json",
    "Weapons": "data/items/weapons.json",
    "Consumables": "data/items/consumables.json",
    "Materials": "data/items/materials.json",
}

# -------------------------
# Config utilities
# -------------------------
def load_config():
    if not os.path.exists(CONFIG_FILE):
        return {"root_directory": "", "dark_mode": False}
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"root_directory": "", "dark_mode": False}

def save_config(cfg):
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=4)
    except Exception as e:
        print("Failed saving config:", e)

# -------------------------
# Safe JSON IO + backup
# -------------------------
def safe_load(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"ERROR loading {path}: {e}")
        return {}

def backup_file(path):
    if not os.path.exists(path):
        return None
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    base = os.path.basename(path)
    dirn = os.path.dirname(path)
    backup_name = f"{base}.bak.{ts}"
    backup_path = os.path.join(dirn, backup_name)
    try:
        shutil.copy2(path, backup_path)
        return backup_path
    except Exception as e:
        print("Backup failed:", e)
        return None

def safe_save(path, data):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        # backup existing file
        if os.path.exists(path):
            backup_file(path)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4, ensure_ascii=False)
        return True
    except Exception as e:
        print(f"ERROR saving {path}: {e}")
        return False

# -------------------------
# Helpers
# -------------------------
def make_key_from_name(name):
    return name.strip().lower().replace(" ", "_")

def is_leaf_node(obj):
    # consider dict of only primitive values (no nested dict/list) a leaf
    if not isinstance(obj, dict):
        return True
    for v in obj.values():
        if isinstance(v, dict) or isinstance(v, list):
            return False
    return True

def nested_get(data, path):
    cur = data
    for p in path:
        cur = cur[p]
    return cur

def nested_set(data, path, value):
    cur = data
    for p in path[:-1]:
        cur = cur[p]
    cur[path[-1]] = value

def nested_delete(data, path):
    cur = data
    for p in path[:-1]:
        cur = cur[p]
    del cur[path[-1]]

def parse_value_by_example(orig, raw):
    # Try to parse raw string into int/float/bool/list if orig indicates type
    if isinstance(orig, bool):
        return raw.lower() in ("1", "true", "yes", "y", "on")
    if isinstance(orig, int):
        try:
            return int(raw)
        except:
            try:
                return int(float(raw))
            except:
                return raw
    if isinstance(orig, float):
        try:
            return float(raw)
        except:
            return raw
    if isinstance(orig, list):
        # accept comma-separated values
        pieces = [s.strip() for s in raw.split(",") if s.strip()]
        return pieces
    # fallback
    return raw

# -------------------------
# GUI Application
# -------------------------
class ContentManagerApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Uldtale Battlesim - Content Manager")
        self.geometry("1200x760")

        # config
        self.config_data = load_config()
        self.root_dir = self.config_data.get("root_directory", "")
        self.dark_mode = self.config_data.get("dark_mode", False)

        # state
        self.data = {}  # tab -> loaded JSON
        self.current_tab = None
        self.current_path = None  # list path into JSON for currently selected node
        self.rarity_list = []
        self.elements_list = []

        # widgets storage
        self.listboxes = {}
        self.treeviews = {}
        self.editor_widgets = {}

        self._build_ui()
        # ask for root dir if not set or invalid
        if not self.root_dir or not os.path.isdir(self.root_dir):
            self._prompt_for_root()
        else:
            self._load_all_files()
            self._populate_all()

        # apply dark mode if configured
        if self.dark_mode:
            self.toggle_dark_mode(enable=True)

    # -----------------------
    # UI setup
    # -----------------------
    def _build_ui(self):
        # Toolbar
        toolbar = ttk.Frame(self)
        toolbar.pack(side="top", fill="x", padx=6, pady=4)

        ttk.Label(toolbar, text="Project Root:").pack(side="left")
        self.dir_label = ttk.Label(toolbar, text=self.root_dir or "(not set)")
        self.dir_label.pack(side="left", padx=(4,12))

        ttk.Button(toolbar, text="Change Root", command=self._change_root).pack(side="left")
        ttk.Button(toolbar, text="Reload", command=self._reload_all).pack(side="left", padx=6)
        ttk.Button(toolbar, text="Save All", command=self._save_all).pack(side="left", padx=6)

        ttk.Separator(toolbar, orient="vertical").pack(side="left", fill="y", padx=8)

        # Dark mode toggle
        self.dark_var = tk.BooleanVar(value=self.dark_mode)
        ttk.Checkbutton(toolbar, text="Dark Mode", variable=self.dark_var, command=self._on_toggle_dark).pack(side="left")

        # Main Notebook
        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill="both", expand=True, padx=6, pady=6)
        self.notebook.bind("<<NotebookTabChanged>>", self._on_tab_changed)

        # Build tabs
        for tab_name in JSON_FILES.keys():
            frame = ttk.Frame(self.notebook)
            self.notebook.add(frame, text=tab_name)
            self._build_tab_ui(tab_name, frame)

        # Status bar
        self.status_var = tk.StringVar(value="Ready")
        status = ttk.Label(self, textvariable=self.status_var, relief="sunken", anchor="w")
        status.pack(side="bottom", fill="x")

    def _build_tab_ui(self, tab_name, parent_frame):
        # left pane: controls + list/tree
        left = ttk.Frame(parent_frame, width=360)
        left.pack(side="left", fill="y", padx=(6,2), pady=6)
        left.pack_propagate(False)

        # Buttons: New / Duplicate / Delete / Save (tab)
        btn_frame = ttk.Frame(left)
        btn_frame.pack(fill="x", pady=(0,6))
        ttk.Button(btn_frame, text="New", command=lambda tn=tab_name: self._new_item(tn)).pack(side="left")
        ttk.Button(btn_frame, text="Duplicate", command=lambda tn=tab_name: self._duplicate_item(tn)).pack(side="left", padx=4)
        ttk.Button(btn_frame, text="Delete", command=lambda tn=tab_name: self._delete_item(tn)).pack(side="left")
        ttk.Button(btn_frame, text="Save", command=lambda tn=tab_name: self._save_tab(tn)).pack(side="left", padx=4)

        # Search
        sframe = ttk.Frame(left)
        sframe.pack(fill="x", pady=(4,6))
        ttk.Label(sframe, text="Search:").pack(side="left")
        sv = tk.StringVar()
        ent = ttk.Entry(sframe, textvariable=sv)
        ent.pack(side="left", fill="x", expand=True, padx=6)
        ent.bind("<Return>", lambda e, tn=tab_name, v=sv: self._search_tab(tn, v.get()))

        # For Armors/Weapons, use Treeview; else Listbox
        container = ttk.Frame(left)
        container.pack(fill="both", expand=True)

        if tab_name in ("Armors", "Weapons"):
            tree = ttk.Treeview(container)
            tree.pack(side="left", fill="both", expand=True)
            vsb = ttk.Scrollbar(container, orient="vertical", command=tree.yview)
            vsb.pack(side="right", fill="y")
            tree.configure(yscrollcommand=vsb.set)
            tree.bind("<<TreeviewSelect>>", lambda e, tn=tab_name: self._on_tree_select(tn))
            self.treeviews[tab_name] = tree
        else:
            lb = tk.Listbox(container)
            lb.pack(side="left", fill="both", expand=True)
            vsb = ttk.Scrollbar(container, orient="vertical", command=lb.yview)
            vsb.pack(side="right", fill="y")
            lb.configure(yscrollcommand=vsb.set)
            lb.bind("<<ListboxSelect>>", lambda e, tn=tab_name: self._on_list_select(tn))
            self.listboxes[tab_name] = lb

        # right pane: editor
        right = ttk.Frame(parent_frame)
        right.pack(side="left", fill="both", expand=True, padx=(6,10), pady=6)
        # Selected path label
        header = ttk.Frame(right)
        header.pack(fill="x")
        sel_label = ttk.Label(header, text="Selected: -", font=("TkDefaultFont", 10, "bold"))
        sel_label.pack(side="left")
        self._set_widget_attr(tab_name, "selected_label", sel_label)
        # attributes frame (scrollable)
        canvas_frame = ttk.Frame(right)
        canvas_frame.pack(fill="both", expand=True, pady=(8,0))

        canvas = tk.Canvas(canvas_frame)
        canvas.pack(side="left", fill="both", expand=True)
        vsb2 = ttk.Scrollbar(canvas_frame, orient="vertical", command=canvas.yview)
        vsb2.pack(side="right", fill="y")
        canvas.configure(yscrollcommand=vsb2.set)
        inner = ttk.Frame(canvas)
        # widget creation on canvas
        canvas.create_window((0,0), window=inner, anchor='nw')
        inner.bind("<Configure>", lambda e, c=canvas: c.configure(scrollregion=c.bbox("all")))
        self._set_widget_attr(tab_name, "attrs_frame", inner)

    def _set_widget_attr(self, tab, key, widget):
        if not hasattr(self, "_widgets"):
            self._widgets = {}
        if tab not in self._widgets:
            self._widgets[tab] = {}
        self._widgets[tab][key] = widget

    def _get_widget_attr(self, tab, key):
        return getattr(self, "_widgets", {}).get(tab, {}).get(key)

    # -------------------------
    # Project root / loading
    # -------------------------
    def _prompt_for_root(self):
        messagebox.showinfo("Select Project Root", "Please select the Uldtale-Battlesim project root folder.")
        self._change_root()

    def _change_root(self):
        new = filedialog.askdirectory(title="Select Uldtale-Battlesim root folder")
        if not new:
            return
        self.root_dir = new
        self.dir_label.config(text=new)
        self.config_data["root_directory"] = new
        save_config(self.config_data)
        self._load_all_files()
        self._populate_all()
        self.status("Project root updated.")

    def _load_all_files(self):
        self.data.clear()
        for tab, rel in JSON_FILES.items():
            full = os.path.join(self.root_dir, rel)
            self.data[tab] = safe_load(full)
        # infer enums
        self._load_enums()

    def _load_enums(self):
        # rarities
        rarities = self.data.get("Rarities", {})
        self.rarity_list = list(rarities.keys()) if isinstance(rarities, dict) else []
        # elements: infer from skills (fields 'element' or 'elements')
        elems = set()
        skills = self.data.get("Skills", {})
        sknode = skills.get("skills") if isinstance(skills, dict) and "skills" in skills else skills
        if isinstance(sknode, dict):
            for s, val in sknode.items():
                if isinstance(val, dict):
                    for k in ("element", "elements"):
                        if k in val:
                            v = val[k]
                            if isinstance(v, list):
                                elems.update(v)
                            elif isinstance(v, str) and v.upper() != "NONE":
                                elems.add(v)
        self.elements_list = sorted(elems)

    # -------------------------
    # Populate views
    # -------------------------
    def _populate_all(self):
        for tab in JSON_FILES.keys():
            self._populate_tab(tab)

    def _populate_tab(self, tab):
        # clear editor selection
        self._widgets and self._widgets.get(tab, {}).get("selected_label", ttk.Label()) and \
            self._widgets[tab]["selected_label"].config(text="Selected: -")
        self.current_tab = tab
        # tree vs list
        if tab in ("Armors", "Weapons"):
            tree = self.treeviews.get(tab)
            if not tree:
                return
            tree.delete(*tree.get_children())
            root_node = self.data.get(tab, {})
            self._populate_tree(tree, "", root_node)
        else:
            lb = self.listboxes.get(tab)
            if not lb:
                return
            lb.delete(0, tk.END)
            node = self.data.get(tab, {})
            if tab in ("Classes", "Races"):
                for grp, entries in node.items():
                    for k in entries.keys():
                        lb.insert(tk.END, f"{grp}:{k}")
            elif isinstance(node, dict):
                for k in node.keys():
                    lb.insert(tk.END, k)

    def _populate_tree(self, tree, parent, node):
        # recursively populate keys
        if not isinstance(node, dict):
            return
        for key, val in node.items():
            nid = tree.insert(parent, "end", text=key, open=False)
            if isinstance(val, dict):
                # mark leaf nodes visually by tag if leaf
                if is_leaf_node(val):
                    tree.item(nid, tags=("leaf",))
                self._populate_tree(tree, nid, val)
        # configure tag once
        tree.tag_configure("leaf", background="#f0fff0")

    # -------------------------
    # Selection handlers
    # -------------------------
    def _on_tab_changed(self, event):
        tab = event.widget.tab(event.widget.select(), "text")
        self.current_tab = tab
        self.current_path = None
        self.status(f"Switched to {tab}")

    def _on_list_select(self, tab):
        lb = self.listboxes.get(tab)
        if not lb:
            return
        sel = lb.curselection()
        if not sel:
            return
        value = lb.get(sel)
        path = []
        if tab in ("Classes", "Races"):
            grp, name = value.split(":", 1)
            path = [grp, name]
        else:
            path = [value]
        self.current_tab = tab
        self.current_path = path
        self._widgets[tab]["selected_label"].config(text="Selected: " + "/".join(path))
        node = nested_get(self.data[tab], path)
        if isinstance(node, dict):
            self._show_editor_for_node(tab, path, node)
        else:
            self._clear_editor(tab)
            ttk.Label(self._widgets[tab]["attrs_frame"], text="Not editable").pack(anchor="w", pady=8)

    def _on_tree_select(self, tab):
        tree = self.treeviews.get(tab)
        if not tree:
            return
        sels = tree.selection()
        if not sels:
            return
        iid = sels[0]
        # build path from tree root
        path = []
        cur = iid
        while cur:
            path.insert(0, tree.item(cur, "text"))
            cur = tree.parent(cur)
        self.current_tab = tab
        self.current_path = path
        self._widgets[tab]["selected_label"].config(text="Selected: " + "/".join(path))
        node = nested_get(self.data[tab], path)
        if isinstance(node, dict) and is_leaf_node(node):
            self._show_editor_for_node(tab, path, node)
        else:
            self._clear_editor(tab)
            ttk.Label(self._widgets[tab]["attrs_frame"], text="Select a leaf item to edit attributes.").pack(anchor="w", pady=8)

    # -------------------------
    # Editor generation
    # -------------------------
    def _clear_editor(self, tab):
        frame = self._widgets[tab]["attrs_frame"]
        for w in frame.winfo_children():
            w.destroy()
        self.editor_widgets = {}

    def _show_editor_for_node(self, tab, path, node):
        self._clear_editor(tab)
        frame = self._widgets[tab]["attrs_frame"]
        # show editable fields row-by-row
        row = 0
        for key, val in node.items():
            lbl = ttk.Label(frame, text=key)
            lbl.grid(row=row, column=0, sticky="w", padx=6, pady=4)
            widget = None
            # choose widget type
            # rarity dropdown
            if key.lower() == "rarity":
                cb = ttk.Combobox(frame, values=self.rarity_list)
                cb.set("" if val is None else str(val))
                cb.grid(row=row, column=1, sticky="ew", padx=6, pady=4)
                widget = cb
            # element(s)
            elif key.lower() in ("element", "elements", "elemental", "elements_list"):
                # support multiple via comma-separated entry
                if isinstance(val, list):
                    ent = ttk.Entry(frame)
                    ent.insert(0, ",".join(map(str, val)))
                    ent.grid(row=row, column=1, sticky="ew", padx=6, pady=4)
                    widget = ent
                else:
                    cb = ttk.Combobox(frame, values=self.elements_list)
                    cb.set("" if val is None else str(val))
                    cb.grid(row=row, column=1, sticky="ew", padx=6, pady=4)
                    widget = cb
            elif isinstance(val, bool):
                var = tk.BooleanVar(value=val)
                chk = ttk.Checkbutton(frame, variable=var)
                chk.grid(row=row, column=1, sticky="w", padx=6, pady=4)
                widget = var
            elif isinstance(val, int) or isinstance(val, float):
                ent = ttk.Entry(frame)
                ent.insert(0, str(val))
                ent.grid(row=row, column=1, sticky="ew", padx=6, pady=4)
                widget = ent
            else:
                ent = ttk.Entry(frame, width=80)
                ent.insert(0, str(val))
                ent.grid(row=row, column=1, sticky="ew", padx=6, pady=4)
                widget = ent

            self.editor_widgets[key] = (widget, val)  # store original value for type info
            row += 1

        # action buttons
        btn_frame = ttk.Frame(frame)
        btn_frame.grid(row=row, column=0, columnspan=2, sticky="w", pady=(8,0))
        ttk.Button(btn_frame, text="Apply", command=lambda t=tab, p=path: self._apply_changes(t, p)).pack(side="left")
        ttk.Button(btn_frame, text="Revert", command=lambda t=tab, p=path: self._revert_node(t, p)).pack(side="left", padx=8)

    def _apply_changes(self, tab, path):
        node = nested_get(self.data[tab], path)
        for key, (widget, orig) in self.editor_widgets.items():
            new_val = None
            # resolve widget type
            if isinstance(widget, ttk.Combobox):
                new_val = widget.get()
                if isinstance(orig, list):
                    new_val = [s.strip() for s in new_val.split(",") if s.strip()]
            elif isinstance(widget, tk.BooleanVar):
                new_val = bool(widget.get())
            elif isinstance(widget, ttk.Entry) or isinstance(widget, tk.Entry):
                raw = widget.get()
                new_val = parse_value_by_example(orig, raw)
            else:
                # fallback: read get() if possible
                try:
                    new_val = widget.get()
                except:
                    new_val = str(widget)
            node[key] = new_val

        self.status(f"Applied changes to {'/'.join(path)}")

    def _revert_node(self, tab, path):
        # reload from memory (no disk)
        node = nested_get(self.data[tab], path)
        self._show_editor_for_node(tab, path, node)
        self.status("Reverted changes (unsaved).")

    # -------------------------
    # Add / Duplicate / Delete (Option A for nested)
    # -------------------------
    def _new_item(self, tab):
        # Option A: if Armors/Weapons -> ask category and slot
        if tab in ("Armors", "Weapons"):
            name = simpledialog.askstring("New Item", "Enter display name for new item:")
            if not name:
                return
            key = make_key_from_name(name)
            # ask category (top-level) and slot (sub-level)
            top_existing = list(self.data.get(tab, {}).keys())
            top_choice = simpledialog.askstring("Category", f"Top-level category (existing or new). Existing: {', '.join(top_existing)}", initialvalue=(top_existing[0] if top_existing else "misc"))
            if top_choice is None:
                return
            slot_existing = []
            if top_choice in self.data.get(tab, {}):
                slot_existing = list(self.data[tab][top_choice].keys())
            slot_choice = simpledialog.askstring("Slot", f"Slot (existing or new). Existing: {', '.join(slot_existing)}", initialvalue=(slot_existing[0] if slot_existing else "slot"))
            if slot_choice is None:
                return
            # ensure structure exists
            if tab not in self.data:
                self.data[tab] = {}
            if top_choice not in self.data[tab]:
                self.data[tab][top_choice] = {}
            if slot_choice not in self.data[tab][top_choice]:
                self.data[tab][top_choice][slot_choice] = {}
            # create default template
            template = {"name": name, "description": "", "value": 0, "rarity": ""}
            self.data[tab][top_choice][slot_choice][key] = template
            # refresh tree
            self._populate_tab(tab)
            self.status(f"Created {name} under {top_choice}/{slot_choice}")
        elif tab in ("Classes", "Races"):
            name = simpledialog.askstring("New Entry", "Enter new entry name:")
            if not name:
                return
            group = simpledialog.askstring("Group", "Group (playable or non_playable):", initialvalue="playable")
            if not group:
                return
            if group not in ("playable", "non_playable"):
                messagebox.showerror("Invalid group", "Group must be 'playable' or 'non_playable'")
                return
            key = name
            if group not in self.data[tab]:
                self.data[tab][group] = {}
            self.data[tab][group][key] = {"base_vit":5,"base_str":5,"base_dex":5,"base_int":5,"skills":[]}
            self._populate_tab(tab)
            self.status(f"Created {name} in {group}")
        elif tab == "Skills":
            name = simpledialog.askstring("New Skill", "Enter skill name:")
            if not name:
                return
            key = name
            if "skills" not in self.data["Skills"]:
                self.data["Skills"]["skills"] = {}
            self.data["Skills"]["skills"][key] = {"name": key, "description":"", "ability_type":"MAGICAL", "type":"DAMAGE", "target":"ENEMY", "power":10, "mp_cost":0, "cooldown":0}
            self._populate_tab(tab)
            self.status(f"Created skill {key}")
        else:
            # flat dicts
            name = simpledialog.askstring("New Item", "Enter key for new item:")
            if not name:
                return
            key = make_key_from_name(name)
            self.data.setdefault(tab, {})[key] = {"name": name, "description": ""}
            self._populate_tab(tab)
            self.status(f"Created {key} in {tab}")

    def _duplicate_item(self, tab):
        if not self.current_path:
            messagebox.showwarning("No selection", "Select an item to duplicate")
            return
        # find node and parent
        parent_path = self.current_path[:-1]
        old_key = self.current_path[-1]
        parent_node = nested_get(self.data[tab], parent_path) if parent_path else self.data[tab]
        if old_key not in parent_node:
            messagebox.showerror("Error", "Selected item not found")
            return
        new_name = simpledialog.askstring("Duplicate", "New name for duplicate:")
        if not new_name:
            return
        new_key = make_key_from_name(new_name)
        # deep copy
        parent_node[new_key] = json.loads(json.dumps(parent_node[old_key]))
        # if has name field update
        if isinstance(parent_node[new_key], dict):
            parent_node[new_key]["name"] = new_name
        self._populate_tab(tab)
        self.status(f"Duplicated {old_key} -> {new_key}")

    def _delete_item(self, tab):
        if not self.current_path:
            messagebox.showwarning("No selection", "Select an item to delete")
            return
        full = "/".join(self.current_path)
        if not messagebox.askyesno("Confirm delete", f"Delete {full}?"):
            return
        # delete nested
        try:
            nested_delete(self.data[tab], self.current_path)
        except Exception as e:
            messagebox.showerror("Delete failed", str(e))
            return
        self._populate_tab(tab)
        self._clear_editor(tab)
        self.current_path = None
        self.status(f"Deleted {full}")

    # -------------------------
    # Search
    # -------------------------
    def _search_tab(self, tab, query):
        q = query.strip().lower()
        if not q:
            self._populate_tab(tab)
            return
        matches = []
        if tab in ("Armors", "Weapons"):
            tree = self.treeviews.get(tab)
            # repopulate then expand nodes with matches
            self._populate_tab(tab)
            def match_node(iid):
                text = tree.item(iid, "text").lower()
                matched = q in text
                for ch in tree.get_children(iid):
                    if match_node(ch):
                        matched = True
                tree.item(iid, open=matched)
                return matched
            for root in tree.get_children():
                match_node(root)
            self.status(f"Searched {tab} for '{query}'")
        else:
            lb = self.listboxes.get(tab)
            if not lb:
                return
            lb.delete(0, tk.END)
            node = self.data.get(tab, {})
            items = []
            if tab in ("Classes", "Races"):
                for grp, entries in node.items():
                    for k in entries.keys():
                        items.append(f"{grp}:{k}")
            elif isinstance(node, dict):
                items = list(node.keys())
            for it in items:
                if q in it.lower():
                    lb.insert(tk.END, it)
            self.status(f"Found matches in {tab}")

    # -------------------------
    # Save functions
    # -------------------------
    def _tab_fullpath(self, tab):
        rel = JSON_FILES[tab]
        return os.path.join(self.root_dir, rel)

    def _save_tab(self, tab):
        path = self._tab_fullpath(tab)
        ok = safe_save(path, self.data.get(tab, {}))
        if ok:
            self.status(f"Saved {tab} -> {path}")
            messagebox.showinfo("Saved", f"Saved {tab}")
        else:
            messagebox.showerror("Save failed", f"Could not save {path}")

    def _save_all(self):
        failures = []
        for tab, rel in JSON_FILES.items():
            full = os.path.join(self.root_dir, rel)
            ok = safe_save(full, self.data.get(tab, {}))
            if not ok:
                failures.append(full)
        if failures:
            messagebox.showerror("Save errors", "Failed to save:\n" + "\n".join(failures))
        else:
            messagebox.showinfo("Saved", "All files saved (backups created if file existed).")
            self.status("Saved all files")

    # -------------------------
    # Utilities
    # -------------------------
    def status(self, text):
        self.status_var.set(text)
        # clear after a while
        self.after(6000, lambda: self.status_var.set("Ready"))

    # -------------------------
    # Dark Mode
    # -------------------------
    def _on_toggle_dark(self):
        enable = bool(self.dark_var.get())
        self.toggle_dark_mode(enable)
        self.config_data["dark_mode"] = enable
        save_config(self.config_data)

    def toggle_dark_mode(self, enable=False):
        style = ttk.Style()
        try:
            if enable:
                style.theme_use('clam')
                bg = "#2b2b2b"
                fg = "#e6e6e6"
                entry_bg = "#3c3f41"
                style.configure(".", background=bg, foreground=fg)
                style.configure("TLabel", background=bg, foreground=fg)
                style.configure("TFrame", background=bg)
                style.configure("TButton", background=entry_bg, foreground=fg)
                style.configure("TEntry", fieldbackground=entry_bg, foreground=fg)
                style.configure("Treeview", background="#262626", foreground=fg, fieldbackground="#262626")
                self.configure(bg=bg)
            else:
                style.theme_use('default')
                style.configure(".", background=None, foreground=None)
                self.configure(bg=None)
        except Exception as e:
            print("Dark mode switch error:", e)

    # -------------------------
    # Reload and populate helpers
    # -------------------------
    def _reload_all(self):
        self._load_all_files()
        self._populate_all()
        messagebox.showinfo("Reload", "All files reloaded from disk.")
        self.status("Reloaded files")

# -------------------------
# Main
# -------------------------
if __name__ == "__main__":
    app = ContentManagerApp()
    app.mainloop()
