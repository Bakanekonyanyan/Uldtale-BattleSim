# res://scripts/autoload/SceneManager.gd
extends Node

var current_scene: Node = null
var scene_stack: Array[Dictionary] = []
var dungeon_info: Dictionary = {}
var battle_info: Dictionary = {}
var reward_data: Dictionary = {}
var reward_data_temp: Dictionary = {}
var reward_scene_active = false
var town_scene_active = false
var rewards_accepted = false


func _ready() -> void:
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)

func change_scene(path: String) -> void:
	call_deferred("_deferred_change_scene", path)

func _deferred_change_scene(path: String) -> void:
	_change_scene_internal(path)

func _change_scene_internal(path: String, player_character: CharacterData = null) -> void:
	print("Changing scene to: ", path)
	
	if current_scene != null:
		current_scene.queue_free()
	
	var scene_resource = load(path)
	if scene_resource == null:
		printerr("Failed to load scene: ", path)
		return
	
	current_scene = scene_resource.instantiate()
	
	# If we're loading a RewardScene, tell it whether rewards were already accepted
	if current_scene.has_method("set_rewards_accepted"):
		current_scene.set_rewards_accepted(rewards_accepted)

	
	if current_scene == null:
		printerr("Failed to instantiate scene: ", path)
		return
	
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene
	
	if player_character != null:
		if current_scene.has_method("set_player"):
			current_scene.set_player(player_character)
		elif current_scene.has_method("set_player_character"):
			current_scene.set_player_character(player_character)
	
	print("Scene changed to: ", current_scene.name)

# === TOWN NAVIGATION ===
func change_to_shop(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/ShopScene.tscn", player_character)

func change_to_dungeon(player_character: CharacterData) -> void:
	# CRITICAL FIX: Clear dungeon_info when starting fresh dungeon
	dungeon_info.clear()
	town_scene_active = false
	_change_scene_internal("res://scenes/DungeonScene.tscn", player_character)

func change_to_equipment(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/EquipmentScene.tscn", player_character)

func change_to_status(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/StatusScene.tscn", player_character)

func change_to_inventory(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/InventoryScene.tscn", player_character)

func change_to_stash(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/StashScene.tscn", player_character)

func change_to_town(player_character: CharacterData) -> void:
	# CRITICAL FIX: Clear dungeon data when returning to town
	dungeon_info.clear()
	battle_info.clear()
	reward_data_temp.clear()
	reward_scene_active = false
	town_scene_active = true
	_change_scene_internal("res://scenes/TownScene.tscn", player_character)

func change_to_main_menu() -> void:
	change_scene("res://scenes/ui/MainMenu.tscn")

func change_to_character_selection() -> void:
	change_scene("res://scenes/ui/CharacterSelection.tscn")

# === BATTLE FLOW ===
func start_battle(battle_data: Dictionary) -> void:
	print("SceneManager: Starting battle")
	
	dungeon_info = {
		"path": "res://scenes/DungeonScene.tscn",
		"player_character": battle_data.get("player_character"),
		"current_wave": battle_data.get("current_wave"),
		"current_floor": battle_data.get("current_floor"),
		"is_boss_fight": battle_data.get("is_boss_fight"),
		"max_floor": battle_data.get("max_floor"),
		"waves_per_floor": battle_data.get("waves_per_floor", 5)
	}
	
	battle_info = battle_data
	_change_scene_internal("res://scenes/battle/Battle.tscn")
	setup_battle_scene()

func setup_battle_scene():
	await get_tree().process_frame
	reward_scene_active = false
	rewards_accepted = false
	
	if not current_scene or not current_scene.has_method("set_player"):
		push_error("SceneManager: Battle scene not ready or missing required methods")
		return
	
	print("SceneManager: Setting up battle scene")
	current_scene.set_player(battle_info.get("player_character"))
	current_scene.set_enemy(battle_info.get("enemy"))
	
	if not current_scene.is_connected("battle_completed", Callable(self, "_on_battle_completed")):
		current_scene.connect("battle_completed", Callable(self, "_on_battle_completed"))
		print("SceneManager: Connected battle_completed signal")
	
	current_scene.set_dungeon_info(
		battle_info.get("current_wave"),
		battle_info.get("current_floor"),
		battle_info.get("description")
	)

func _on_battle_completed(player_won: bool, xp_gained: int):
	print("SceneManager: Battle completed signal received - Won: ", player_won, " XP: ", xp_gained)
	
	if not player_won:
		change_scene("res://scenes/ui/CharacterSelection.tscn")
		return
	
	dungeon_info["xp_gained"] = xp_gained
	
	print("SceneManager: Preparing reward scene after battle")
	
	var reward_data = {
		"rewards": calculate_battle_rewards(dungeon_info),
		"xp_gained": xp_gained,
		"player_character": dungeon_info["player_character"],
		"is_boss_fight": dungeon_info["is_boss_fight"],
		"current_floor": dungeon_info["current_floor"],
		"current_wave": dungeon_info["current_wave"],
		"max_floor": dungeon_info["max_floor"]
	}
	
	reward_data_temp = reward_data
	reward_scene_active = true
	
	_change_scene_internal("res://scenes/RewardScene.tscn", dungeon_info["player_character"])
	await get_tree().process_frame
	setup_reward_scene_from_battle()

func calculate_battle_rewards(battle_info: Dictionary) -> Dictionary:
	var current_wave = battle_info.get("current_wave", 1)
	var current_floor = battle_info.get("current_floor", 1)
	var is_boss = battle_info.get("is_boss_fight", false)
	var xp_gained = battle_info.get("xp_gained", 0)
	
	var rewards = {
		"currency": (50 + (current_wave * 10)) * current_floor,
		"xp": xp_gained
	}
	
	var drop_chance_multiplier = 1 + (current_floor * 0.1)
	
	if is_boss:
		rewards["currency"] *= 2
		add_random_item_to_rewards(rewards, "consumable", 1.0 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "material", 1.0 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "weapon", 0.5 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "armor", 0.5 * drop_chance_multiplier)
	else:
		add_random_item_to_rewards(rewards, "consumable", 0.7 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "material", 0.3 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "equipment", 0.1 * drop_chance_multiplier)
	
	return rewards

func add_random_item_to_rewards(rewards: Dictionary, item_type: String, chance: float):
	if randf() < chance:
		var item_id = ""
		match item_type:
			"consumable": item_id = ItemManager.get_random_consumable()
			"material": item_id = ItemManager.get_random_material()
			"weapon": item_id = ItemManager.get_random_weapon()
			"armor": item_id = ItemManager.get_random_armor()
			"equipment": item_id = ItemManager.get_random_equipment()
		
		if item_id != "":
			# CRITICAL FIX: Store item_id, not quantity initially
			if not rewards.has(item_id):
				rewards[item_id] = 0
			rewards[item_id] += 1

func setup_reward_scene_from_battle():
	print("SceneManager: Setting up reward scene from battle")
	
	if current_scene.has_method("set_player_character"):
		current_scene.set_player_character(reward_data_temp.get("player_character"))
	if current_scene.has_method("set_rewards"):
		current_scene.set_rewards(reward_data_temp.get("rewards", {}))
	if current_scene.has_method("set_xp_gained"):
		current_scene.set_xp_gained(reward_data_temp.get("xp_gained", 0))
	if current_scene.has_method("set_dungeon_info"):
		current_scene.set_dungeon_info(
			dungeon_info["is_boss_fight"],
			dungeon_info["current_floor"],
			dungeon_info["max_floor"]
		)
	if current_scene.has_method("setup_ui"):
		current_scene.setup_ui()
	if current_scene.has_method("display_rewards"):
		current_scene.display_rewards()
	
	if not current_scene.is_connected("rewards_accepted", Callable(self, "_on_rewards_accepted")):
		current_scene.connect("rewards_accepted", Callable(self, "_on_rewards_accepted"))
	if not current_scene.is_connected("next_floor", Callable(self, "_on_next_floor")):
		current_scene.connect("next_floor", Callable(self, "_on_next_floor"))

func change_scene_with_return(path: String, player_character: CharacterData = null) -> void:
	scene_stack.push_back({
		"path": current_scene.scene_file_path,
		"player_character": player_character
	})
	_change_scene_internal(path, player_character)

func return_to_previous_scene() -> void:
	if scene_stack.is_empty():
		print("Warning: No previous scene to return to")
		return
	
	var previous_scene_data = scene_stack.pop_back()
	print("SceneManager: Returning to previous scene: ", previous_scene_data["path"])
	
	# CRITICAL FIX: Restore player character from reward_data_temp if returning to RewardScene
	if reward_scene_active and previous_scene_data["path"] == "res://scenes/RewardScene.tscn":
		if reward_data_temp.has("player_character"):
			previous_scene_data["player_character"] = reward_data_temp["player_character"]
	
	_change_scene_internal(previous_scene_data["path"], previous_scene_data["player_character"])
	
	# CRITICAL FIX: If returning to RewardScene, restore its state
	if reward_scene_active and previous_scene_data["path"] == "res://scenes/RewardScene.tscn":
		await get_tree().process_frame
		setup_reward_scene_from_battle()
	elif town_scene_active and previous_scene_data["path"] == "res://scenes/TownScene.tscn":
		# Returning to town, nothing special needed
		pass

func _on_rewards_accepted():
	print("SceneManager: Rewards accepted, returning to dungeon")
	print("SceneManager: Current dungeon_info - Wave: ", dungeon_info.get("current_wave"), ", Floor: ", dungeon_info.get("current_floor"), ", Boss: ", dungeon_info.get("is_boss_fight"))
	
	reward_scene_active = false
	reward_data_temp.clear()
	
	if not dungeon_info.is_empty():
		# XP is already applied in RewardScene now, no need to do it here
		
		print("SceneManager: Restoring dungeon - Wave: ", dungeon_info["current_wave"], ", Floor: ", dungeon_info["current_floor"])
		_change_scene_internal(dungeon_info["path"], dungeon_info["player_character"])
		await get_tree().process_frame
		
		if current_scene.has_method("start_dungeon"):
			current_scene.start_dungeon(dungeon_info)
		else:
			push_error("SceneManager: DungeonScene missing start_dungeon method")
	else:
		push_error("SceneManager: No dungeon info to return to")

func _on_next_floor():
	print("SceneManager: Next floor requested")
	reward_scene_active = false
	rewards_accepted = false

	if not dungeon_info.is_empty():
		dungeon_info["current_floor"] += 1
		dungeon_info["current_wave"] = 0
		dungeon_info["is_boss_fight"] = false
		
		print("SceneManager: Advancing to floor ", dungeon_info["current_floor"])
		
		# XP is already applied in RewardScene, no need to do it here
		
		_change_scene_internal(dungeon_info["path"], dungeon_info["player_character"])
		await get_tree().process_frame
		
		if current_scene.has_method("start_dungeon"):
			current_scene.start_dungeon(dungeon_info)
		else:
			push_error("SceneManager: DungeonScene missing start_dungeon method")
	else:
		push_error("SceneManager: No dungeon info available for next floor")

# REMOVE show_level_up_scene function entirely
func show_level_up_scene(player: CharacterData):
	print("SceneManager: Showing level-up scene")
	
	# Load and add level-up scene as overlay on current scene
	var level_up_scene = load("res://scenes/LevelUpScene.tscn").instantiate()
	current_scene.add_child(level_up_scene)
	
	# Center it on screen
	var viewport_size = get_tree().root.get_visible_rect().size
	if level_up_scene.has_node("Background"):
		var background = level_up_scene.get_node("Background")
		var scene_size = background.size
		level_up_scene.position = (viewport_size - scene_size) / 2
	
	level_up_scene.visible = true
	level_up_scene.show()
	
	# Setup the level-up scene with player data
	level_up_scene.setup(player)
	
	# Wait for player to finish allocating points
	await level_up_scene.level_up_complete
	
	print("SceneManager: Level-up complete")
	level_up_scene.queue_free()
