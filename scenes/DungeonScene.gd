# DungeonScene.gd
extends Node

var player_character: CharacterData
var current_wave: int = 0
var current_floor: int = 1
var waves_per_floor: int = 5
var is_boss_fight: bool = false
var current_battle: Node = null
var current_reward_scene = null
var dungeon_description: String
var max_floor_reached: int = 1
var max_floor: int = 3  # Set the max number of floors
var continue_delving: bool = false


@onready var wave_label = $WaveLabel
@onready var floor_label = $FloorLabel
@onready var dungeon_description_label = $DungeonDescriptionLabel

func _ready():
	player_character = CharacterManager.get_current_character()
	if player_character == null:
		print("Error: No character selected")
		SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")
		return
	
	reset_player_stats()
	start_dungeon()

func reset_player_stats():
	player_character.current_hp = player_character.max_hp
	player_character.current_mp = player_character.max_mp

func set_player(character: CharacterData):
	player_character = character
	update_labels()

func start_dungeon():
	current_wave = 0
	current_floor = 1
	is_boss_fight = false
	EnemyFactory.set_dungeon_race()
	update_labels()
	next_wave()

func next_wave():
	current_wave += 1
	update_labels()
	
	if current_wave > waves_per_floor:
		is_boss_fight = true
		start_boss_battle()
	else:
		is_boss_fight = false
		start_battle()

func start_battle():
	if current_battle:
		current_battle.queue_free()
	
	current_battle = preload("res://scenes/battle/Battle.tscn").instantiate()
	current_battle.set_player(player_character)
	current_battle.set_enemy(EnemyFactory.create_enemy())
	current_battle.set_dungeon_info(current_wave, current_floor, get_dungeon_description())
	current_battle.connect("battle_completed", Callable(self, "_on_battle_completed"))
	add_child(current_battle)

func start_boss_battle():
	if current_battle:
		current_battle.queue_free()
	
	current_battle = preload("res://scenes/battle/Battle.tscn").instantiate()
	current_battle.set_player(player_character)
	current_battle.set_enemy(EnemyFactory.create_boss())
	current_battle.set_dungeon_info(current_wave, current_floor, get_dungeon_description() + " BOSS BATTLE!")
	current_battle.connect("battle_completed", Callable(self, "_on_battle_completed"))
	add_child(current_battle)

func get_dungeon_description() -> String:
	var race = EnemyFactory.current_dungeon_race
	match race:
		"Goblin":
			return "You're in a dark, dank cave. The air is thick with the stench of goblins."
		"Troll":
			return "The ground trembles beneath your feet. You've stumbled into troll territory."
		"Fairy":
			return "Glowing lights dance in the air. You've wandered into an enchanted fairy glade."
	return "You're in a mysterious dungeon."
	
func _on_quit_dungeon():
	print("Quitting dungeon")
	SaveManager.save_game(player_character)
	if current_reward_scene:
		current_reward_scene.queue_free()
		current_reward_scene = null
	SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")

func calculate_rewards() -> Dictionary:
	var rewards = {}
	rewards["currency"] = (50 + (current_wave * 10)) * current_floor
	
	var drop_chance_multiplier = 1 + (current_floor * 0.1)
	
	if is_boss_fight:
		rewards["currency"] *= 2
		add_random_item(rewards, "consumable", 1.0 * drop_chance_multiplier)
		add_random_item(rewards, "material", 1.0 * drop_chance_multiplier)
		add_random_item(rewards, "weapon", 0.5 * drop_chance_multiplier)
		add_random_item(rewards, "armor", 0.5 * drop_chance_multiplier)
	else:
		add_random_item(rewards, "consumable", 0.7 * drop_chance_multiplier)
		add_random_item(rewards, "material", 0.3 * drop_chance_multiplier)
		add_random_item(rewards, "equipment", 0.1 * drop_chance_multiplier)
	
	return rewards

func _on_rewards_accepted():
	print("Rewards accepted")
	SaveManager.save_game(player_character)
	if current_reward_scene:
		current_reward_scene.queue_free()
		current_reward_scene = null
	
	if is_boss_fight:
		if current_floor < max_floor and continue_delving:
			print("Moving to next floor")
			current_floor += 1
			current_wave = 0
			is_boss_fight = false
			EnemyFactory.set_dungeon_race()
			next_wave()
		else:
			print("Dungeon completed or player chose to quit")
			SceneManager.change_scene("res://scenes/TownScene.tscn")
	else:
		next_wave()

func show_reward_scene(xp_gained: int):
	print("Showing reward scene")
	var reward_scene = preload("res://scenes/RewardScene.tscn").instantiate()
	var rewards = calculate_rewards()
	print("Rewards calculated: ", rewards)
	reward_scene.set_rewards(rewards)
	reward_scene.set_xp_gained(xp_gained)
	reward_scene.set_player_character(player_character)
	reward_scene.set_dungeon_info(is_boss_fight, current_floor, max_floor)
	reward_scene.connect("rewards_accepted", Callable(self, "_on_rewards_accepted"))
	reward_scene.connect("quit_dungeon", Callable(self, "_on_quit_dungeon"))
	reward_scene.connect("next_floor", Callable(self, "_on_next_floor"))
	add_child(reward_scene)
	current_reward_scene = reward_scene

func _on_next_floor():
	continue_delving = true
	_on_rewards_accepted()

func _on_battle_completed(player_won: bool) -> void:
	if player_won:
		var xp_gained = calculate_xp_reward(current_battle.enemy_character)
		var old_level = player_character.level
		player_character.gain_xp(xp_gained)
		print("Player won the battle. XP gained: ", xp_gained)
		print("Old level: ", old_level, " New level: ", player_character.level)
		
		if player_character.level > old_level:
			print("Level up detected. Showing level up scene.")
			await show_level_up_scene()
			print("Level up scene completed")
		
		show_reward_scene(xp_gained)
	else:
		print("Game Over!")
		reset_player_stats()
		SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")
	
	update_labels()

func show_level_up_scene():
	print("Showing level up scene")
	var level_up_scene = preload("res://scenes/LevelUpScene.tscn").instantiate()
	add_child(level_up_scene)
	
	# Center the level up scene
	var viewport_size = get_viewport().get_visible_rect().size
	var scene_size = level_up_scene.get_node("Background").size  # Assuming Background is sized correctly
	level_up_scene.position = (viewport_size - scene_size) / 2
	
	# Ensure it's visible and on top
	level_up_scene.visible = true
	level_up_scene.show()
	level_up_scene.move_to_front()
	
	# Setup the level up scene
	level_up_scene.setup(player_character)
	
	# Wait for the level up scene to complete
	await level_up_scene.level_up_complete
	
	# Remove the level up scene
	level_up_scene.queue_free()

func _setup_level_up_scene(level_up_scene):
	if level_up_scene.has_method("setup"):
		level_up_scene.setup(player_character)
	else:
		print("Error: LevelUpScene doesn't have a setup method")
	level_up_scene.connect("level_up_complete", Callable(self, "_on_level_up_complete"))
	print("Level up scene setup completed")

func _on_level_up_complete():
	print("Level up complete!")

func update_labels():
	if wave_label:
		if is_boss_fight:
			wave_label.text = "Boss Battle"
		else:
			wave_label.text = "Wave: %d / %d" % [current_wave, waves_per_floor]
	else:
		print("Warning: wave_label not found")

	if floor_label:
		floor_label.text = "Floor: %d" % current_floor
	else:
		print("Warning: floor_label not found")

	print("Labels updated - Wave: %d, Floor: %d" % [current_wave, current_floor])

func add_random_item(rewards: Dictionary, item_type: String, chance: float):
	if randf() < chance:
		var item_id = ""
		match item_type:
			"consumable": item_id = ItemManager.get_random_consumable()
			"material": item_id = ItemManager.get_random_material()
			"weapon": item_id = ItemManager.get_random_weapon()
			"armor": item_id = ItemManager.get_random_armor()
			"equipment": item_id = ItemManager.get_random_equipment()
		
		if item_id != "":
			rewards[item_id] = rewards.get(item_id, 0) + 1

func calculate_xp_reward(enemy: CharacterData) -> int:
	return enemy.level * 10 * current_floor  # Increase XP based on floor

func get_random_item() -> String:
	var items = ItemManager.get_all_items()
	var item_keys = items.keys()
	if item_keys.size() > 0:
		return item_keys[randi() % item_keys.size()]
	return ""
