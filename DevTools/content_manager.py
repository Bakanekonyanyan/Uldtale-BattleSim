import os
import json
from tkinter import Tk, Label, Entry, Button, Scrollbar, Listbox, messagebox, simpledialog, END, Y, RIGHT, LEFT, BOTH, X, TOP
from tkinter.ttk import Frame

class ContentEditor:
    def __init__(self, root):
        self.root = root
        self.root.title("Game Content Editor")
        self.root.geometry("800x600")

        # Update the content directory path
        self.content_directory = r"D:\Uldtale Battlsim\data"
        self.current_file = None
        self.data = {}

        # GUI Components
        self.frame_content_list = Frame(self.root)
        self.frame_content_list.pack(side=LEFT, fill=BOTH, expand=True)

        self.listbox_content = Listbox(self.frame_content_list)
        self.listbox_content.pack(side=LEFT, fill=BOTH, expand=True)
        self.listbox_content.bind("<<ListboxSelect>>", self.on_select_item)

        self.scrollbar_content = Scrollbar(self.frame_content_list, orient="vertical")
        self.scrollbar_content.config(command=self.listbox_content.yview)
        self.scrollbar_content.pack(side=RIGHT, fill=Y)
        self.listbox_content.config(yscrollcommand=self.scrollbar_content.set)

        self.frame_editor = Frame(self.root)
        self.frame_editor.pack(side=LEFT, fill=BOTH, expand=True)

        self.label_name = Label(self.frame_editor, text="Name:")
        self.label_name.grid(row=0, column=0, padx=5, pady=5, sticky="w")

        self.entry_name = Entry(self.frame_editor)
        self.entry_name.grid(row=0, column=1, padx=5, pady=5, sticky="w")

        self.frame_attributes = Frame(self.frame_editor)
        self.frame_attributes.grid(row=1, column=0, columnspan=2, padx=10, pady=10, sticky="nsew")

        self.label_attributes = Label(self.frame_attributes, text="Attributes:")
        self.label_attributes.grid(row=0, column=0, padx=5, pady=5, sticky="w")

        self.attribute_entries = {}

        self.button_save = Button(self.frame_editor, text="Save", command=self.save_changes)
        self.button_save.grid(row=2, column=1, padx=5, pady=10, sticky="e")

        self.button_load_classes = Button(self.root, text="Load Classes", command=lambda: self.load_content_list("classes.json"))
        self.button_load_classes.pack(side=TOP, padx=10, pady=10)

        self.button_load_races = Button(self.root, text="Load Races", command=lambda: self.load_content_list("races.json"))
        self.button_load_races.pack(side=TOP, padx=10, pady=10)

        self.button_load_skills = Button(self.root, text="Load Skills", command=lambda: self.load_content_list("skills.json"))
        self.button_load_skills.pack(side=TOP, padx=10, pady=10)

        self.button_new_class = Button(self.root, text="New Class", command=lambda: self.create_new_item("classes.json"))
        self.button_new_class.pack(side=TOP, padx=10, pady=10)

        self.button_new_race = Button(self.root, text="New Race", command=lambda: self.create_new_item("races.json"))
        self.button_new_race.pack(side=TOP, padx=10, pady=10)

        self.button_new_skill = Button(self.root, text="New Skill", command=lambda: self.create_new_item("skills.json"))
        self.button_new_skill.pack(side=TOP, padx=10, pady=10)

        # Load initial content list (initialize with classes.json)
        self.load_content_list("classes.json")

    def load_content_list(self, filename):
        self.listbox_content.delete(0, END)
        filepath = os.path.join(self.content_directory, filename)
        try:
            with open(filepath, "r") as file:
                self.data = json.load(file)
                self.current_file = filename
                if filename == "classes.json":
                    self.display_classes()
                elif filename == "races.json":
                    self.display_races()
                elif filename == "skills.json":
                    self.display_skills()
        except FileNotFoundError:
            messagebox.showerror("Error", f"File {filename} not found.")
            self.data = {}
            self.current_file = None
            self.update_editor_fields()

    def display_classes(self):
        self.listbox_content.delete(0, END)
        for class_name in self.data["playable"]:
            self.listbox_content.insert(END, f"Playable: {class_name}")
        for class_name in self.data["non_playable"]:
            self.listbox_content.insert(END, f"Non-playable: {class_name}")

    def display_races(self):
        self.listbox_content.delete(0, END)
        for race_name in self.data["playable"]:
            self.listbox_content.insert(END, f"Playable: {race_name}")
        for race_name in self.data["non_playable"]:
            self.listbox_content.insert(END, f"Non-playable: {race_name}")

    def display_skills(self):
        self.listbox_content.delete(0, END)
        for skill_name in self.data["skills"]:
            self.listbox_content.insert(END, skill_name)

    def on_select_item(self, event):
        selected_index = self.listbox_content.curselection()
        if selected_index:
            selected_item = self.listbox_content.get(selected_index)
            self.load_content_data(selected_item)

    def load_content_data(self, selected_item):
        if self.current_file == "skills.json":
            self.load_skill_data(selected_item)
        else:
            self.load_class_or_race_data(selected_item)

    def load_skill_data(self, skill_name):
        if skill_name in self.data["skills"]:
            skill_data = self.data["skills"][skill_name]
            self.entry_name.delete(0, END)
            self.entry_name.insert(END, skill_data["name"])
            self.update_attribute_fields(skill_data)

    def load_class_or_race_data(self, selected_item):
        if selected_item.startswith("Playable: ") or selected_item.startswith("Non-playable: "):
            class_or_race_name = selected_item.split(": ")[1]
            if class_or_race_name in self.data["playable"]:
                class_or_race_data = self.data["playable"][class_or_race_name]
            elif class_or_race_name in self.data["non_playable"]:
                class_or_race_data = self.data["non_playable"][class_or_race_name]
            else:
                messagebox.showerror("Error", f"{class_or_race_name} not found in data.")
                return

            self.entry_name.delete(0, END)
            self.entry_name.insert(END, class_or_race_name)
            self.update_attribute_fields(class_or_race_data)

    def update_attribute_fields(self, data):
        # Clear previous attribute fields
        for entry in self.attribute_entries.values():
            entry.destroy()
        self.attribute_entries = {}

        # Display attributes item by item with editable fields
        row = 1
        for key, value in data.items():
            label = Label(self.frame_attributes, text=key)
            label.grid(row=row, column=0, padx=5, pady=5, sticky="w")
            entry = Entry(self.frame_attributes, width=50)  # Increase width for description fields
            entry.grid(row=row, column=1, padx=5, pady=5, sticky="w")
            entry.insert(END, value)
            self.attribute_entries[key] = entry
            row += 1

    def save_changes(self):
        if self.current_file:
            # Update data with edited values
            if self.current_file == "skills.json":
                self.save_skill_changes()
            else:
                self.save_class_or_race_changes()

    def save_skill_changes(self):
        selected_skill = self.entry_name.get()
        if selected_skill in self.data["skills"]:
            skill_data = self.data["skills"][selected_skill]
            new_name = self.entry_name.get()
            if new_name != skill_data["name"]:
                self.data["skills"][new_name] = self.data["skills"].pop(selected_skill)
                skill_data = self.data["skills"][new_name]
            for key, entry in self.attribute_entries.items():
                skill_data[key] = entry.get()

            # Save changes to JSON file
            filename = os.path.join(self.content_directory, self.current_file)
            with open(filename, "w") as file:
                json.dump(self.data, file, indent=4)
                messagebox.showinfo("Success", f"Changes saved to {self.current_file}.")
                self.display_skills()

    def save_class_or_race_changes(self):
        selected_item = self.entry_name.get()
        if selected_item.startswith("Playable: ") or selected_item.startswith("Non-playable: "):
            class_or_race_name = selected_item.split(": ")[1]
            if class_or_race_name in self.data["playable"]:
                class_or_race_data = self.data["playable"][class_or_race_name]
            elif class_or_race_name in self.data["non_playable"]:
                class_or_race_data = self.data["non_playable"][class_or_race_name]
            else:
                messagebox.showerror("Error", f"{class_or_race_name} not found in data.")
                return

            new_name = self.entry_name.get()
            if new_name != class_or_race_name:
                self.data["playable" if class_or_race_name in self.data["playable"] else "non_playable"][new_name] = self.data["playable" if class_or_race_name in self.data["playable"] else "non_playable"].pop(class_or_race_name)

            for key, entry in self.attribute_entries.items():
                class_or_race_data[key] = entry.get()

            # Save changes to JSON file
            filename = os.path.join(self.content_directory, self.current_file)
            with open(filename, "w") as file:
                json.dump(self.data, file, indent=4)
                messagebox.showinfo("Success", f"Changes saved to {self.current_file}.")
                if self.current_file == "classes.json":
                    self.display_classes()
                elif self.current_file == "races.json":
                    self.display_races()

    def create_new_item(self, filename):
        new_item_name = simpledialog.askstring("New Item", "Enter the name of the new item:")
        if not new_item_name:
            return
        
        if filename == "skills.json":
            self.create_new_skill(new_item_name)
        else:
            self.create_new_class_or_race(new_item_name, filename)

    def create_new_skill(self, new_skill_name):
        if new_skill_name in self.data["skills"]:
            messagebox.showerror("Error", f"{new_skill_name} already exists in skills.")
            return
        
        new_skill_data = {
            "name": new_skill_name,
            "description": "",
            "type": "",
            "target": "",
            "power": 0,
            "mp_cost": 0,
            "cooldown": 0
        }

        self.data["skills"][new_skill_name] = new_skill_data
        self.save_json_to_file("skills.json")
        self.load_content_list("skills.json")
        self.listbox_content.selection_clear(0, END)
        self.listbox_content.select_set(END)
        self.load_content_data(new_skill_name)
    
    def create_new_class_or_race(self, new_name, filename):
        if new_name in self.data["playable"] or new_name in self.data["non_playable"]:
            messagebox.showerror("Error", f"{new_name} already exists in {filename}.")
            return
        
        new_data = {
            "base_vit": 0,
            "base_str": 0,
            "base_dex": 0,
            "base_int": 0,
            "base_fai": 0,
            "base_mnd": 0,
            "base_end": 0,
            "base_arc": 0,
            "base_agi": 0,
            "base_for": 0,
            "attack_power_type": "",
            "spell_power_type": "",
            "skills": []
        }

        self.data["playable" if filename == "classes.json" else "non_playable"][new_name] = new_data
        self.save_json_to_file(filename)
        self.load_content_list(filename)
        self.listbox_content.selection_clear(0, END)
        self.listbox_content.select_set(END)
        self.load_content_data(f"Playable: {new_name}" if filename == "classes.json" else f"Non-playable: {new_name}")

    def save_json_to_file(self, filename):
        filepath = os.path.join(self.content_directory, filename)
        with open(filepath, "w") as file:
            json.dump(self.data, file, indent=4)

    def update_editor_fields(self):
        self.entry_name.delete(0, END)
        for entry in self.attribute_entries.values():
            entry.destroy()
        self.attribute_entries = {}

if __name__ == "__main__":
    root = Tk()
    app = ContentEditor(root)
    root.mainloop()
