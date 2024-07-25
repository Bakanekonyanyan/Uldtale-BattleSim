# DungeonScene.gd
extends Node

var player_character: CharacterData
var current_wave: int = 0
var current_floor: int = 1
var waves_per_floor: int = 5
var is_boss_fight: bool = false
var current_battle: Node = null
var current_reward_scene = null
var max_floor: int = 3
var continue_delving: bool = false
var xp_gained: int

@onready var wave_label = $WaveLabel
@onready var floor_label = $FloorLabel
@onready var dungeon_description_label = $DungeonDescriptionLabel

func _ready():
	player_character = CharacterManager.get_current_character()
	if player_character == null:
		print("Error: No character selected")
		SceneManager.change_to_character_selection()
		return
	
	reset_player_stats()
	start_dungeon()

# Reset player's HP and MP to max
func reset_player_stats():
	player_character.current_hp = player_character.max_hp
	player_character.current_mp = player_character.max_mp

# Set the player character and update UI
func set_player(character: CharacterData):
	player_character = character
	update_labels()

# Initialize dungeon parameters and start the first wave
func start_dungeon(info: Dictionary = {}):
	print("DungeonScene: start_dungeon called with info: ", info)
	if not info.is_empty():
		# Restoring state when returning from RewardScene
		current_wave = info["current_wave"]
		current_floor = info["current_floor"]
		is_boss_fight = info["is_boss_fight"]
		max_floor = info["max_floor"]
		print("DungeonScene: Restoring dungeon state - Wave: ", current_wave, ", Floor: ", current_floor)
	else:
		# Initial dungeon setup
		current_wave = 0
		current_floor = 1
		is_boss_fight = false
		max_floor = 3  # Or whatever your default max_floor is
		print("DungeonScene: Starting new dungeon")

	EnemyFactory.set_dungeon_race()
	update_labels()
	if not info.is_empty():
		print("DungeonScene: Continuing from previous state")
		continue_dungeon()
	else:
		print("DungeonScene: Starting first wave")
		next_wave()

# Start a regular battle
func start_battle():
	if current_battle:
		current_battle.queue_free()
	
	current_battle = preload("res://scenes/battle/Battle.tscn").instantiate()
	EnemyFactory.get_dungeon_race()
	setup_battle(EnemyFactory.create_enemy())

# Start a boss battle
func start_boss_battle():
	if current_battle:
		current_battle.queue_free()
	
	current_battle = preload("res://scenes/battle/Battle.tscn").instantiate()
	setup_battle(EnemyFactory.create_boss(), true)

# Set up the battle scene
func setup_battle(enemy: CharacterData, is_boss: bool = false):
	current_battle.set_player(player_character)
	current_battle.set_enemy(enemy)
	current_battle.set_dungeon_info(current_wave, current_floor, get_dungeon_description() + (" BOSS BATTLE!" if is_boss else ""))
	current_battle.connect("battle_completed", Callable(self, "_on_battle_completed"))
	add_child(current_battle)

# Get the description of the current dungeon
func get_dungeon_description() -> String:
	match EnemyFactory.current_dungeon_race:
		"Goblin": return "You're in a dark, dank cave. The air is thick with the stench of goblins."
		"Troll": return "The ground trembles beneath your feet. You've stumbled into troll territory."
		"Fairy": return "Glowing lights dance in the air. You've wandered into an enchanted fairy glade."
	return "You're in a mysterious dungeon."

# Handle quitting the dungeon
func _on_quit_dungeon():
	SaveManager.save_game(player_character)
	if current_reward_scene:
		current_reward_scene.queue_free()
		current_reward_scene = null
	SceneManager.change_to_town(player_character) 
	
# Calculate rewards for the current battle
func calculate_rewards() -> Dictionary:
	var rewards = {"currency": (50 + (current_wave * 10)) * current_floor, "xp": xp_gained}
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

# Handle choosing to proceed to the next floor
func _on_next_floor():
	continue_delving = true
	_on_rewards_accepted()

# Show the level up scene
func show_level_up_scene():
	var level_up_scene = preload("res://scenes/LevelUpScene.tscn").instantiate()
	add_child(level_up_scene)
	
	var viewport_size = get_viewport().get_visible_rect().size
	var scene_size = level_up_scene.get_node("Background").size
	level_up_scene.position = (viewport_size - scene_size) / 2
	
	level_up_scene.visible = true
	level_up_scene.show()
	level_up_scene.move_to_front()
	
	level_up_scene.setup(player_character)
	
	await level_up_scene.level_up_complete
	
	level_up_scene.queue_free()

# Update UI labels
func update_labels():
	if wave_label:
		wave_label.text = "Boss Battle" if is_boss_fight else "Wave: %d / %d" % [current_wave, waves_per_floor]
	if floor_label:
		floor_label.text = "Floor: %d" % current_floor

# Add a random item to the rewards
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

# Calculate XP reward based on enemy level and current floor
func calculate_xp_reward(enemy: CharacterData) -> int:
	return enemy.level * 10 * current_floor

# Get a random item from all available items
func get_random_item() -> String:
	var items = ItemManager.get_all_items()
	var item_keys = items.keys()
	return item_keys[randi() % item_keys.size()] if item_keys.size() > 0 else ""

func _on_battle_completed(player_won: bool) -> void:
	if player_won:
		var xp_gained = calculate_xp_reward(current_battle.enemy_character)
		var old_level = player_character.level
		player_character.gain_xp(xp_gained)
		
		if player_character.level > old_level:
			await show_level_up_scene()
		
		show_reward_scene(xp_gained)
	else:
		reset_player_stats()
		SceneManager.change_to_character_selection()
	
	update_labels()

func continue_dungeon():
	print("DungeonScene: Continuing dungeon - Current wave: ", current_wave)
	if is_boss_fight and current_floor < max_floor:
		current_floor += 1
		current_wave = 0
		is_boss_fight = false
		print("DungeonScene: Moving to next floor: ", current_floor)
	next_wave()

func next_wave():
	print("DungeonScene: Starting next wave")
	current_wave += 1
	print("DungeonScene: Current wave is now ", current_wave)
	update_labels()
	
	if current_wave > waves_per_floor:
		is_boss_fight = true
		start_boss_battle()
	else:
		is_boss_fight = false
		start_battle()

func show_reward_scene(xp_gained: int):
	var rewards = calculate_rewards()
	var reward_data = {
		"rewards": rewards,
		"xp_gained": xp_gained,
		"player_character": player_character,
		"is_boss_fight": is_boss_fight,
		"current_floor": current_floor,
		"current_wave": current_wave,
		"max_floor": max_floor
	}
	print("DungeonScene: Showing reward scene - Current wave: ", current_wave)
	SceneManager.show_reward_scene(self, reward_data)

func _on_rewards_accepted():
	print("DungeonScene: Rewards accepted")
	if is_boss_fight and current_floor < max_floor:
		current_floor += 1
		current_wave = 0
		is_boss_fight = false
	print("DungeonScene: Before next_wave, current_wave is ", current_wave)
	next_wave()
	print("DungeonScene: After next_wave, current_wave is ", current_wave)
