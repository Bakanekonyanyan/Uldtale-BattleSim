# scenes/ui/CharacterSelection.gd
extends Control

var character_list = []
var selected_character: CharacterData = null

@onready var character_container = $MainContainer/ScrollContainer/CharacterContainer
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
	
	# QOL: Auto-select first character if list is not empty
	if not character_list.is_empty():
		_on_character_selected(character_list[0])
		

func _on_quit_button_pressed():
	get_tree().quit()

func _on_character_selected(character):
	selected_character = character
	CharacterManager.set_current_character(character)
	print("Selected character: ", character.name)
	print("Inventory items: ", character.inventory.items)
	
	# Enable start new game button
	start_new_game_button.disabled = false
	
	# Check if a save exists for this character
	if SaveManager.save_exists(character.name):
		load_saved_game_button.disabled = false
	else:
		load_saved_game_button.disabled = true
	
	# QOL: Highlight the selected character button
	_highlight_selected_character()

func _highlight_selected_character():
	"""Visual feedback for selected character"""
	var index = 0
	for child in character_container.get_children():
		if child is HBoxContainer:
			var select_button = child.get_child(0)
			if character_list[index] == selected_character:
				# Highlight selected
				select_button.modulate = Color(2.5, 2.8, 2.2)  # Slight yellow tint
			else:
				# Normal color
				select_button.modulate = Color(1, 1, 1)
			index += 1

func _on_start_new_game_pressed():
	if selected_character:
		# Check if save exists
		if SaveManager.save_exists(selected_character.name):
			show_new_game_warning()
		else:
			start_new_game()
	else:
		print("No character selected")

func show_new_game_warning():
	var dialog = ConfirmationDialog.new()
	dialog.title = "Overwrite Save?"
	dialog.dialog_text = "Starting a new game will DELETE your existing save for %s!\n\nAre you sure you want to continue?" % selected_character.name
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
	
	# QOL: If deleted character was selected, clear selection
	if selected_character == character:
		selected_character = null
		start_new_game_button.disabled = true
		load_saved_game_button.disabled = true
		
		# Auto-select first character if any remain
		if not character_list.is_empty():
			_on_character_selected(character_list[0])
