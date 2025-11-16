# res://scenes/WaveBattle.gd
extends Node

@onready var wave_label = $WaveLabel
@onready var battle_manager = BattleManager.new()

var player_character: CharacterData

func _ready():
	battle_manager.connect("wave_completed", Callable(self, "_on_wave_completed"))
	battle_manager.connect("all_waves_completed", Callable(self, "_on_all_waves_completed"))
	
	# For testing purposes, create a player character here.
	# In a full game, you'd probably pass this from a previous scene.
	player_character = CharacterData.new()
	# Set up player_character stats here...

	start_wave_battle()

func start_wave_battle():
	battle_manager.start_battle(player_character, 3)  # 3 waves before boss

func _on_wave_completed(wave_number):
	wave_label.text = "Wave %d completed!" % wave_number
	# You could show rewards here between waves

func _on_all_waves_completed():
	wave_label.text = "All waves completed! You win!"
	# Handle the end of the entire wave battle here
	# Maybe show final rewards, return to a town scene, etc.
