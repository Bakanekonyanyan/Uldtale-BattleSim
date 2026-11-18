# res://scripts/BattleManager.gd
extends Node

signal wave_completed(wave_number)
signal all_waves_completed

var current_wave: int = 0
var waves_before_boss: int = 3
var total_waves: int

var player_character: CharacterData
var current_enemy: CharacterData

func start_battle(p_character: CharacterData, num_waves: int = 3):
	print("BattleManager: start_battle called with ", num_waves, " waves")
	player_character = p_character
	waves_before_boss = num_waves
	total_waves = waves_before_boss + 1  # +1 for the boss wave
	current_wave = 0
	SceneManager.change_scene("res://scenes/battle/Battle.tscn")

func start_next_wave():
	print("BattleManager: Starting next wave: ", current_wave + 1)
	current_wave += 1
	if current_wave <= waves_before_boss:
		current_enemy = EnemyFactory.create_random_enemy()
		print("BattleManager: Created random enemy: ", current_enemy.name)
	elif current_wave == total_waves:
		current_enemy = BossFactory.create_boss()
		print("BattleManager: Created boss enemy: ", current_enemy.name)
	else:
		print("BattleManager: All waves completed")
		emit_signal("all_waves_completed")
		return

	print("BattleManager: Creating battle scene")
	var battle_scene = load("res://scenes/battle/Battle.tscn").instantiate()
	print("BattleManager: Setting up battle")
	battle_scene.setup_battle(player_character, current_enemy)
	battle_scene.connect("battle_completed", Callable(self, "_on_battle_completed"))
	print("BattleManager: Adding battle scene to tree")
	get_tree().root.add_child(battle_scene)
	print("Battle scene added to tree. Current scene: ", get_tree().current_scene.name)

func _on_battle_completed(player_won: bool):
	print("BattleManager: Battle completed. Player won: ", player_won)
	if player_won:
		emit_signal("wave_completed", current_wave)
		if current_wave < total_waves:
			print("BattleManager: Starting next wave")
			start_next_wave()
		else:
			print("BattleManager: All waves completed")
			emit_signal("all_waves_completed")
	else:
		# Handle player defeat
		print("BattleManager: Player was defeated. Game Over.")
		# You might want to show a game over screen here
