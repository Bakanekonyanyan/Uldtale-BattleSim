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
	if current_character.max_floor_cleared == null:
		current_character.max_floor_cleared = 1;
		print(current_character.max_floor_cleared)
	else:
		print(current_character.max_floor_cleared)
	
	show_floor_selection_dialog()

# In TownScene.gd, REPLACE the show_floor_selection_dialog function:

# In TownScene.gd, REPLACE the show_floor_selection_dialog function:

func show_floor_selection_dialog():
	"""Show a dialog to select which floor to start from"""
	
	# CRITICAL: Log current max_floor_cleared
	print("TownScene: Opening floor selection - max_floor_cleared: %d" % current_character.max_floor_cleared)
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "Select Starting Floor"
	dialog.ok_button_text = "Start Dungeon"
	dialog.cancel_button_text = "Cancel"
	
	# Create container for floor selection
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 200)
	
	# Add info label
	var info_label = Label.new()
	info_label.text = "Choose which floor to start from:"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info_label)
	
	# Add spacing
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	# Create floor selection buttons in a grid
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	
	var max_selectable = max(1, current_character.max_floor_cleared + 1)
	var selected_floor = 1  # Default to floor 1
	var floor_buttons = []
	
	# Create floor buttons
	for floor in range(1, 26):  # Floors 1-25
		var btn = Button.new()
		btn.text = str(floor)
		btn.custom_minimum_size = Vector2(50, 40)
		btn.toggle_mode = true
		btn.disabled = floor > max_selectable
		
		if floor == 1:
			btn.button_pressed = true
		
		# Store floor number in button
		btn.set_meta("floor", floor)
		floor_buttons.append(btn)
		
		# Connect button press
		btn.pressed.connect(func():
			# Unpress all other buttons
			for other_btn in floor_buttons:
				if other_btn != btn:
					other_btn.button_pressed = false
			btn.button_pressed = true
			selected_floor = btn.get_meta("floor")
			# CRITICAL FIX: Update character's floor immediately when selected
			current_character.current_floor = selected_floor
			print("TownScene: Selected floor %d, set current_character.current_floor to %d" % [
				selected_floor,
				current_character.current_floor
			])
		)
		
		grid.add_child(btn)
	
	vbox.add_child(grid)
	
	# Add info about max cleared floor
	var progress_label = Label.new()
	if current_character.max_floor_cleared > 0:
		progress_label.text = "\nHighest Cleared: Floor %d\nYou can start from floors 1-%d" % [
			current_character.max_floor_cleared,
			max_selectable
		]
	else:
		progress_label.text = "\nYou haven't cleared any floors yet.\nStart from Floor 1!"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(progress_label)
	
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	
	# Handle confirmation
	dialog.confirmed.connect(func():
		# CRITICAL FIX: Use current_character.current_floor instead of selected_floor
		# because selected_floor is captured by closure and may be stale
		var final_floor = current_character.current_floor
		print("TownScene: Confirmed floor selection - final_floor=%d, character.current_floor=%d" % [
			final_floor,
			current_character.current_floor
		])
		SceneManager.start_dungeon_from_floor(current_character, final_floor)
		dialog.queue_free()
	)
	
	# Handle cancellation
	dialog.canceled.connect(func():
		print("Dungeon entry cancelled")
		dialog.queue_free()
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
