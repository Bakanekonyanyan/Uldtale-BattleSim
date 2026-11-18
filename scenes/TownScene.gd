# TownScene.gd
extends Node2D

var current_character: CharacterData

@onready var name_label = $UI/NameLabel
@onready var shop_button = $UI/ShopButton
@onready var dungeon_button = $UI/DungeonButton
@onready var equipment_button = $UI/EquipmentButton
@onready var status_button = $UI/StatusButton
@onready var inventory_button = $UI/InventoryButton
@onready var stash_button = $UI/StashButton
@onready var character_select_button = $UI/CharacterSelectButton
@onready var quit_button = $UI/QuitButton
@onready var arena_button = $UI/ArenaButton
@onready var alchemist_button = $UI/AlchemistButton


func _ready():
	if shop_button:
		shop_button.connect("pressed", Callable(self, "_on_shop_pressed"))
	if dungeon_button:
		dungeon_button.connect("pressed", Callable(self, "_on_dungeon_pressed"))
	if equipment_button:
		equipment_button.connect("pressed", Callable(self, "_on_equipment_pressed"))
	if status_button:
		status_button.connect("pressed", Callable(self, "_on_status_pressed"))
	if inventory_button:
		inventory_button.connect("pressed", Callable(self, "_on_inventory_pressed"))
	if stash_button:
		stash_button.connect("pressed", Callable(self, "_on_stash_pressed"))
	if character_select_button:
		character_select_button.connect("pressed", Callable(self, "_on_charselect_pressed"))
	if quit_button:
		quit_button.connect("pressed", Callable(self, "_on_quit_pressed"))
	if arena_button:
		arena_button.connect("pressed", Callable(self, "_on_arena_pressed"))
	if alchemist_button:
		alchemist_button.pressed.connect(func(): SceneManager.change_to_alchemist(current_character))
		
	update_ui()

func set_player(character: CharacterData):
	current_character = character
	print("TownScene: Character set - ", character.name)
	print("TownScene: Inventory items - ", character.inventory.items)
	update_ui()

func update_ui():
	if name_label:
		if current_character:
			name_label.text = "Character: " + current_character.name
		else:
			name_label.text = "No character loaded"
	else:
		print(current_character.name)
		print("Warning: CharacterNameLabel not found in TownScene")

func _on_shop_pressed():
	SceneManager.change_to_shop(current_character)

# Update the _on_dungeon_pressed function in TownScene.gd:

func _on_dungeon_pressed():
	set_player(current_character)
	current_character.current_floor = 1
	show_location_selection_dialog()

# === EXPEDITION: pick a location, then a floor ===

func show_location_selection_dialog():
	"""Step 1: choose where to go (The Dungeon or a themed location)."""
	var dialog = ConfirmationDialog.new()
	dialog.title = "Choose Expedition"
	dialog.ok_button_text = "Next: Choose Floor"
	dialog.cancel_button_text = "Cancel"
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(460, 320)
	
	var selected = [current_character.last_location if LocationManager.has_location(current_character.last_location) else LocationManager.DEFAULT_LOCATION]
	var buttons: Array[Button] = []
	
	var description = RichTextLabel.new()
	description.bbcode_enabled = true
	description.fit_content = true
	description.custom_minimum_size = Vector2(440, 90)
	
	var update_description = func():
		var loc = LocationManager.get_location(selected[0])
		var races = LocationManager.get_races(selected[0], EnemyFactory.races["non_playable"].keys())
		description.text = "[b]%s[/b]\n%s\n[color=gray]Enemies: %s  |  Highest floor unlocked: %d[/color]" % [
			loc.get("name", selected[0]),
			loc.get("description", ""),
			"Mixed (" + ", ".join(races) + ")" if LocationManager.is_mixed(selected[0]) else ", ".join(races),
			current_character.get_max_floor(selected[0])
		]
	
	for location_id in LocationManager.get_ids():
		var btn = Button.new()
		btn.text = "%s  (Floor %d)" % [LocationManager.get_display_name(location_id), current_character.get_max_floor(location_id)]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(440, 36)
		btn.button_pressed = location_id == selected[0]
		buttons.append(btn)
		btn.pressed.connect(func():
			selected[0] = location_id
			for other in buttons:
				other.button_pressed = other == btn
			update_description.call()
		)
		vbox.add_child(btn)
	
	vbox.add_child(description)
	update_description.call()
	
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		current_character.last_location = selected[0]
		dialog.queue_free()
		show_floor_selection_dialog(selected[0])
	)
	dialog.canceled.connect(func(): dialog.queue_free())

func show_floor_selection_dialog(location_id: String = "the_dungeon"):
	"""Step 2: choose a starting floor. Progress is tracked per location."""
	var max_selectable = current_character.get_max_floor(location_id)
	print("TownScene: Floor selection for %s - max unlocked floor %d" % [location_id, max_selectable])
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "%s - Select Starting Floor" % LocationManager.get_display_name(location_id)
	dialog.ok_button_text = "Start Expedition"
	dialog.cancel_button_text = "Back"
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 200)
	
	var info_label = Label.new()
	info_label.text = "Choose which floor to start from:"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info_label)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	
	var floor_buttons: Array[Button] = []
	current_character.current_floor = 1
	
	for floor_num in range(1, DungeonStateManager.max_floor + 1):
		var btn = Button.new()
		btn.text = str(floor_num)
		btn.custom_minimum_size = Vector2(50, 40)
		btn.toggle_mode = true
		btn.disabled = floor_num > max_selectable
		btn.button_pressed = floor_num == 1
		floor_buttons.append(btn)
		btn.pressed.connect(func():
			for other in floor_buttons:
				other.button_pressed = other == btn
			current_character.current_floor = floor_num
		)
		grid.add_child(btn)
	
	vbox.add_child(grid)
	
	var progress_label = Label.new()
	progress_label.text = "\nYou can start from floors 1-%d here." % max_selectable
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(progress_label)
	
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		var final_floor = current_character.current_floor
		print("TownScene: Starting %s at floor %d" % [location_id, final_floor])
		SceneManager.start_dungeon_from_floor(current_character, final_floor, location_id)
		dialog.queue_free()
	)
	
	# "Back" returns to the location picker
	dialog.canceled.connect(func():
		dialog.queue_free()
		show_location_selection_dialog()
	)

func _on_equipment_pressed():
	SceneManager.change_to_equipment(current_character)

func _on_status_pressed():
	SceneManager.change_to_status(current_character)

func _on_inventory_pressed():
	SceneManager.change_to_inventory(current_character)

func _on_stash_pressed():
	SceneManager.change_to_stash(current_character)
	
func _on_quit_pressed():
	CharacterManager.save_character(current_character)
	get_tree().quit()

func _on_charselect_pressed():
	SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")

func _on_arena_pressed():
	SceneManager.change_to_arena(current_character)
	
