# CharacterSelection.gd
extends Control

var character_list = []
var selected_character: CharacterData = null

@onready var character_container = $MainContainer/ScrollContainer/CharacterContainer
@onready var create_new_button = $MainContainer/CreateNewButton
@onready var load_saved_game_button = $LoadSavedGameButton
@onready var start_new_game_button = $StartNewGameButton

func _ready():
	load_characters()
	setup_ui()
	
	# Disconnect existing connections if any
	if create_new_button.is_connected("pressed", Callable(self, "_on_create_new_pressed")):
		create_new_button.disconnect("pressed", Callable(self, "_on_create_new_pressed"))
	if load_saved_game_button.is_connected("pressed", Callable(self, "_on_load_saved_game_pressed")):
		load_saved_game_button.disconnect("pressed", Callable(self, "_on_load_saved_game_pressed"))
	if start_new_game_button.is_connected("pressed", Callable(self, "_on_start_new_game_pressed")):
		start_new_game_button.disconnect("pressed", Callable(self, "_on_start_new_game_pressed"))
	
	# Connect signals
	create_new_button.connect("pressed", Callable(self, "_on_create_new_pressed"))
	load_saved_game_button.connect("pressed", Callable(self, "_on_load_saved_game_pressed"))
	start_new_game_button.connect("pressed", Callable(self, "_on_start_new_game_pressed"))
	
	# Initially disable buttons
	load_saved_game_button.disabled = true
	start_new_game_button.disabled = true

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

func _on_start_new_game_pressed():
	if selected_character:
		print("Starting new game with character: ", selected_character.name)
		# Reset character to initial state if needed
		selected_character.reset_for_new_game()
		# FIXED: Use SaveManager.save_game() instead of CharacterManager.save_character()
		SaveManager.save_game(selected_character)
		SceneManager.change_to_town(selected_character)
	else:
		print("No character selected")

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
	# FIXED: Use SaveManager.get_all_characters() instead of CharacterManager.get_all_characters()
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
	# FIXED: Use SaveManager.delete_character() instead of CharacterManager.delete_character()
	SaveManager.delete_character(character.name)
	load_characters()
	setup_ui()
