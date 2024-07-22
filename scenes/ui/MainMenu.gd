extends Control

func _ready():
	$VBoxContainer/StartButton.connect("pressed", Callable(self, "_on_start_pressed"))
	$VBoxContainer/QuitButton.connect("pressed", Callable(self, "_on_quit_pressed"))

func _on_start_pressed():
	SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")

func _on_quit_pressed():
	get_tree().quit()
