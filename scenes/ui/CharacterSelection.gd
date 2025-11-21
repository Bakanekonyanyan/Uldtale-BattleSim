# CharacterSelection.gd - UPDATED with equipment and detailed stats preview
extends Control

var character_list = []
var selected_character: CharacterData = null

@onready var character_container = $MainContainer/ScrollContainer/CharacterContainer
@onready var character_preview = $CharacterPreview  # RichTextLabel for detailed preview
@onready var create_new_button = $CreateNewButton
@onready var load_saved_game_button = $LoadSavedGameButton
@onready var start_new_game_button = $StartNewGameButton
@onready var quit_button = $QuitButton

func _ready():
	load_characters()
	setup_ui()
	
	# Connect signals
	if create_new_button.is_connected("pressed", Callable(self, "_on_create_new_pressed")):
		create_new_button.disconnect("pressed", Callable(self, "_on_create_new_pressed"))
	if load_saved_game_button.is_connected("pressed", Callable(self, "_on_load_saved_game_pressed")):
		load_saved_game_button.disconnect("pressed", Callable(self, "_on_load_saved_game_pressed"))
	if start_new_game_button.is_connected("pressed", Callable(self, "_on_start_new_game_pressed")):
		start_new_game_button.disconnect("pressed", Callable(self, "_on_start_new_game_pressed"))
	if quit_button.is_connected("pressed", Callable(self, "_on_quit_button_pressed")):
		quit_button.disconnect("pressed", Callable(self, "_on_quit_button_pressed"))
	
	create_new_button.connect("pressed", Callable(self, "_on_create_new_pressed"))
	load_saved_game_button.connect("pressed", Callable(self, "_on_load_saved_game_pressed"))
	start_new_game_button.connect("pressed", Callable(self, "_on_start_new_game_pressed"))
	quit_button.connect("pressed", Callable(self, "_on_quit_button_pressed"))
	
	# Initially disable buttons
	load_saved_game_button.disabled = true
	start_new_game_button.disabled = true
	
	# Auto-select first character if list is not empty
	if not character_list.is_empty():
		_on_character_selected(character_list[0])
		update_character_preview()

func _on_quit_button_pressed():
	get_tree().quit()

func _on_character_selected(character):
	selected_character = character
	CharacterManager.set_current_character(character)
	print("Selected character: ", character.name)
	
	# Enable start new game button
	start_new_game_button.disabled = false
	
	# Check if a save exists
	if SaveManager.save_exists(character.name):
		load_saved_game_button.disabled = false
	else:
		load_saved_game_button.disabled = true
	
	_highlight_selected_character()
	update_character_preview()

func _highlight_selected_character():
	"""Visual feedback for selected character"""
	var index = 0
	for child in character_container.get_children():
		if child is HBoxContainer:
			var select_button = child.get_child(0)
			if index < character_list.size() and character_list[index] == selected_character:
				select_button.modulate = Color(2.5, 2.8, 2.2)
			else:
				select_button.modulate = Color(1, 1, 1)
			index += 1

func update_character_preview():
	"""Show detailed character information including equipment"""
	if not selected_character or not character_preview:
		return
	
	var char = selected_character
	var preview_text = ""
	
	# === HEADER ===
	preview_text += "[center][b][color=gold]%s[/color][/b]\n" % char.name
	preview_text += "[color=cyan]Level %d %s %s[/color][/center]\n\n" % [char.level, char.race, char.character_class]
	
	# === STATS SUMMARY ===
	preview_text += "[b][color=cyan]Stats:[/color][/b]\n"
	preview_text += "HP: %d/%d | MP: %d/%d | SP: %d/%d\n" % [
		char.current_hp, char.max_hp,
		char.current_mp, char.max_mp,
		char.current_sp, char.max_sp
	]
	preview_text += "Attack: %d | Spell: %d | Defense: %d\n\n" % [
		char.get_attack_power(), char.spell_power, char.get_defense()
	]
	
	# === EQUIPMENT ===
	preview_text += "[b][color=cyan]Equipment:[/color][/b]\n"
	var has_equipment = false
	
	for slot in ["main_hand", "off_hand", "head", "chest", "hands", "legs", "feet"]:
		var item = char.equipment[slot]
		if item:
			has_equipment = true
			var color = item.get_rarity_color()
			var slot_name = slot.capitalize().replace("_", " ")
			
			var item_line = "%s: [color=%s]%s[/color]" % [slot_name, color, item.display_name]
			
			# Add key stats
			if item.damage > 0:
				item_line += " ([color=yellow]%d dmg[/color])" % item.damage
			if item.armor_value > 0:
				item_line += " ([color=cyan]%d armor[/color])" % item.armor_value
			
			# Show item level and rarity
			if item.get("item_level"):
				item_line += " [color=gray]iLvl %d[/color]" % item.item_level
			
			preview_text += item_line + "\n"
	
	if not has_equipment:
		preview_text += "[color=gray]No equipment[/color]\n"
	
	preview_text += "\n"
	
	# === ELEMENTAL AFFINITIES (if initialized) ===
	if char.get("elemental_resistances") != null:
		preview_text += "[b][color=orange]Elemental Affinities:[/color][/b]\n\n"
		
		# DAMAGE BONUSES LIST
		preview_text += "[b][color=yellow]Damage Bonuses:[/color][/b]\n"
		for element in ElementalDamage.Element.values():
			if element == ElementalDamage.Element.NONE:
				continue
			
			var elem_name = ElementalDamage.get_element_name(element)
			var elem_color = ElementalDamage.get_element_color(element)
			var bonus = char.get_elemental_damage_bonus(element)
			
			var line = "  [color=%s]%s:[/color] " % [elem_color, elem_name]
			
			if bonus > 0.0:
				line += "[color=lime]+%d%% damage[/color]" % int(bonus * 100)
			else:
				line += "[color=gray]Normal[/color]"
			
			preview_text += line + "\n"
		
		preview_text += "\n"
		
		# RESISTANCES & WEAKNESSES LIST
		preview_text += "[b][color=cyan]Resistances & Weaknesses:[/color][/b]\n"
		for element in ElementalDamage.Element.values():
			if element == ElementalDamage.Element.NONE:
				continue
			
			var elem_name = ElementalDamage.get_element_name(element)
			var elem_color = ElementalDamage.get_element_color(element)
			var resist = char.get_elemental_resistance(element)
			var weak = char.get_elemental_weakness(element)
			
			var line = "  [color=%s]%s:[/color] " % [elem_color, elem_name]
			
			if resist > 0.0:
				line += "[color=cyan]-%d%% damage taken[/color]" % int(resist * 100)
			elif weak > 0.0:
				line += "[color=orange]+%d%% damage taken[/color]" % int(weak * 100)
			else:
				line += "[color=gray]Normal[/color]"
			
			preview_text += line + "\n"
		
		preview_text += "\n"
	
	# === PROGRESS ===
	if char.get("current_floor"):
		preview_text += "[b][color=cyan]Progress:[/color][/b]\n"
		preview_text += "Floor: %d | Max Cleared: %d\n" % [char.current_floor, char.max_floor_cleared]
		preview_text += "XP: %d / %d\n\n" % [char.xp, LevelSystem.calculate_xp_for_level(char.level)]
	
	# === CURRENCY ===
	if char.currency:
		preview_text += "[b][color=gold]Currency:[/color][/b] %s\n\n" % char.currency.get_formatted()
	
	# === SKILLS ===
	if char.skills and char.skills.size() > 0:
		preview_text += "[b][color=cyan]Skills:[/color][/b] "
		var skill_names = []
		for skill_name in char.skills:
			skill_names.append(skill_name)
		preview_text += ", ".join(skill_names) + "\n"
	
	# Display preview
	if character_preview is RichTextLabel:
		character_preview.bbcode_enabled = true
		character_preview.text = preview_text
	elif character_preview:
		character_preview.text = preview_text

func _on_start_new_game_pressed():
	if selected_character:
		if SaveManager.save_exists(selected_character.name):
			show_new_game_warning()
		else:
			start_new_game()
	else:
		print("No character selected")

func show_new_game_warning():
	var dialog = ConfirmationDialog.new()
	dialog.title = "Overwrite Save?"
	dialog.dialog_text = "Starting a new game will DELETE your existing save for %s!\n\nAre you sure?" % selected_character.name
	dialog.ok_button_text = "Yes, Delete Save"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func(): start_new_game(); dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())

func start_new_game():
	print("Starting new game with character: ", selected_character.name)
	selected_character.reset_for_new_game()
	SaveManager.save_game(selected_character)
	SceneManager.change_to_town(selected_character)

func _on_load_saved_game_pressed():
	if selected_character:
		var loaded_character = SaveManager.load_game(selected_character.name)
		if loaded_character:
			CharacterManager.set_current_character(loaded_character)
			print("Loaded saved game for character: ", loaded_character.name)
			SceneManager.change_to_town(loaded_character)
		else:
			print("No saved game found for selected character.")
	else:
		print("No character selected.")

func _on_create_new_pressed():
	print("Creating new character")
	SceneManager.change_scene("res://scenes/ui/CharacterCreation.tscn")

func load_characters():
	character_list = SaveManager.get_all_characters()

func setup_ui():
	# Clear existing children
	for child in character_container.get_children():
		child.queue_free()
	
	for character in character_list:
		var character_panel = HBoxContainer.new()
		
		var select_button = Button.new()
		select_button.text = "%s - Level %d %s %s" % [character.name, character.level, character.race, character.character_class]
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.connect("pressed", Callable(self, "_on_character_selected").bind(character))
		character_panel.add_child(select_button)
		
		var delete_button = Button.new()
		delete_button.text = "Delete"
		delete_button.connect("pressed", Callable(self, "_on_delete_pressed").bind(character))
		character_panel.add_child(delete_button)
		
		character_container.add_child(character_panel)

func _on_delete_pressed(character):
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Are you sure you want to delete %s?" % character.name
	dialog.connect("confirmed", Callable(self, "_delete_character").bind(character))
	add_child(dialog)
	dialog.popup_centered()

func _delete_character(character):
	SaveManager.delete_character(character.name)
	load_characters()
	setup_ui()
	
	# If deleted character was selected, clear selection
	if selected_character == character:
		selected_character = null
		start_new_game_button.disabled = true
		load_saved_game_button.disabled = true
		
		# Clear preview
		if character_preview:
			if character_preview is RichTextLabel:
				character_preview.bbcode_enabled = true
			character_preview.text = "[center][color=gray]No character selected[/color][/center]"
		
		# Auto-select first character if any remain
		if not character_list.is_empty():
			_on_character_selected(character_list[0])
