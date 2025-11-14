# scenes/ui/MainMenu.gd
extends Control

func _ready():
	$VBoxContainer/StartButton.connect("pressed", Callable(self, "_on_start_pressed"))
	$VBoxContainer/QuitButton.connect("pressed", Callable(self, "_on_quit_pressed"))

func _on_start_pressed():
	# QOL: Check if any characters exist
	var characters = SaveManager.get_all_characters()
	
	if characters.is_empty():
		# No characters exist - go straight to character creation
		print("MainMenu: No characters found, going to character creation")
		SceneManager.change_scene("res://scenes/ui/CharacterCreation.tscn")
	else:
		# Characters exist - go to selection screen
		print("MainMenu: Characters found, going to character selection")
		SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")

func _on_quit_pressed():
	get_tree().quit()
