# scenes/ui/MainMenu.gd
extends Control

func _ready():
	$VBoxContainer/StartButton.pressed.connect(_on_start_pressed)
	$VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

func _on_start_pressed():
	# QOL: Check if any characters exist
	var characters = SaveManager.get_all_characters()
	
	if characters.is_empty():
		# No characters exist - go straight to character creation
		Log.debug("main_menu", "MainMenu: No characters found, going to character creation")
		SceneManager.change_to_character_creation()
	else:
		# Characters exist - go to selection screen
		Log.debug("main_menu", "MainMenu: Characters found, going to character selection")
		SceneManager.change_to_character_selection()

func _on_quit_pressed():
	get_tree().quit()
