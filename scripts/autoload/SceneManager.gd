# SceneManager.gd - REFACTORED
# Responsibilities: Scene transitions ONLY
# Reward logic moved to RewardsManager
# Momentum logic moved to MomentumSystem
extends Node

var current_scene: Node = null
var player_character: CharacterData
var scene_stack: Array[Dictionary] = []
var dungeon_info: Dictionary = {}
var battle_info: Dictionary = {}
var reward_data_temp: Dictionary = {}
var reward_scene_active = false
var town_scene_active = false
var rewards_accepted = false

func _ready() -> void:
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)

# === SCENE TRANSITION CORE ===
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

# === NAVIGATION SHORTCUTS ===
func change_to_shop(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/ShopScene.tscn", player_character)

func change_to_dungeon(player_character: CharacterData) -> void:
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
	dungeon_info.clear()
	battle_info.clear()
	reward_data_temp.clear()
	reward_scene_active = false
	town_scene_active = true
	
	# Reset momentum when returning to town
	MomentumSystem.reset_momentum()
	
	_change_scene_internal("res://scenes/TownScene.tscn", player_character)

func change_to_main_menu() -> void:
	MomentumSystem.reset_momentum()
	change_scene("res://scenes/ui/MainMenu.tscn")

func change_to_character_selection() -> void:
	MomentumSystem.reset_momentum()
	change_scene("res://scenes/ui/CharacterSelection.tscn")

# === BATTLE FLOW ===
func start_battle(battle_data: Dictionary) -> void:
	print("SceneManager: Starting battle")
	
	# Add momentum level to battle data
	battle_data["momentum_level"] = MomentumSystem.get_momentum()
	
	dungeon_info = {
		"path": "res://scenes/DungeonScene.tscn",
		"player_character": battle_data.get("player_character"),
		"current_wave": battle_data.get("current_wave"),
		"current_floor": battle_data.get("current_floor"),
		"is_boss_fight": battle_data.get("is_boss_fight"),
		"max_floor": battle_data.get("max_floor"),
		"waves_per_floor": battle_data.get("waves_per_floor", 5),
		"momentum_level": battle_data["momentum_level"]
	}
	
	battle_info = battle_data
	_change_scene_internal("res://scenes/battle/Battle.tscn")
	setup_battle_scene()

func setup_battle_scene():
	await get_tree().process_frame
	reward_scene_active = false
	rewards_accepted = false
	
	if not current_scene or not current_scene.has_method("set_player"):
		push_error("SceneManager: Battle scene not ready")
		return
	
	print("SceneManager: Setting up battle scene")
	current_scene.set_player(battle_info.get("player_character"))
	current_scene.set_enemy(battle_info.get("enemy"))
	
	if not current_scene.is_connected("battle_completed", Callable(self, "_on_battle_completed")):
		current_scene.connect("battle_completed", Callable(self, "_on_battle_completed"))
	
	current_scene.set_dungeon_info(
		battle_info.get("current_wave"),
		battle_info.get("current_floor"),
		battle_info.get("description")
	)

# SceneManager.gd - FIXED reward flow

func _on_battle_completed(player_won: bool, xp_gained: int):
	print("SceneManager: Battle completed - Won: ", player_won, " XP: ", xp_gained)
	
	if not player_won:
		MomentumSystem.reset_momentum()
		change_scene("res://scenes/ui/CharacterSelection.tscn")
		return
	
	# CRITICAL FIX: Check XP value to determine flow
	# -1 XP = "Press On" was selected (skip rewards)
	# >= 0 XP = "Take Breather" was selected (show rewards)
	
	if xp_gained == -1:
		# Press On: skip rewards, continue to next wave
		print("SceneManager: Momentum active, skipping rewards")
		_continue_with_momentum()
	else:
		# Take Breather: show rewards
		print("SceneManager: Showing rewards")
		_show_rewards(xp_gained)

func _show_rewards(xp_gained: int):
	# CRITICAL FIX: Store XP BEFORE calculating rewards
	dungeon_info["xp_gained"] = xp_gained
	dungeon_info["enemy"] = battle_info.get("enemy")
	
	# Calculate rewards using RewardsManager
	var rewards = RewardsManager.calculate_battle_rewards(dungeon_info)
	
	print("SceneManager: Calculated rewards: ", rewards)
	
	var reward_data = {
		"rewards": rewards,
		"xp_gained": xp_gained,
		"player_character": dungeon_info["player_character"],
		"is_boss_fight": dungeon_info["is_boss_fight"],
		"current_floor": dungeon_info["current_floor"],
		"current_wave": dungeon_info["current_wave"],
		"max_floor": dungeon_info["max_floor"]
	}
	
	# CRITICAL FIX: Store in temp AND pass to scene
	reward_data_temp = reward_data
	reward_scene_active = true
	rewards_accepted = false  # Reset flag
	
	print("SceneManager: Reward data prepared: ", reward_data)
	
	_change_scene_internal("res://scenes/RewardScene.tscn", dungeon_info["player_character"])
	await get_tree().process_frame
	setup_reward_scene_from_battle()

func setup_reward_scene_from_battle():
	print("SceneManager: Setting up reward scene")
	print("SceneManager: Reward data: ", reward_data_temp)
	
	# CRITICAL FIX: Verify data before passing
	if reward_data_temp.is_empty():
		push_error("SceneManager: Reward data is empty!")
		return
	
	if current_scene.has_method("set_player_character"):
		current_scene.set_player_character(reward_data_temp.get("player_character"))
		print("SceneManager: Set player character")
	
	if current_scene.has_method("set_rewards"):
		var rewards = reward_data_temp.get("rewards", {})
		print("SceneManager: Setting rewards: ", rewards)
		current_scene.set_rewards(rewards)
	
	if current_scene.has_method("set_xp_gained"):
		var xp = reward_data_temp.get("xp_gained", 0)
		print("SceneManager: Setting XP: ", xp)
		current_scene.set_xp_gained(xp)
	
	if current_scene.has_method("set_dungeon_info"):
		current_scene.set_dungeon_info(
			dungeon_info["is_boss_fight"],
			dungeon_info["current_floor"],
			dungeon_info["max_floor"]
		)
		print("SceneManager: Set dungeon info")
	
	# Connect signals
	if not current_scene.is_connected("rewards_accepted", Callable(self, "_on_rewards_accepted")):
		current_scene.connect("rewards_accepted", Callable(self, "_on_rewards_accepted"))
	if not current_scene.is_connected("next_floor", Callable(self, "_on_next_floor")):
		current_scene.connect("next_floor", Callable(self, "_on_next_floor"))
	
	print("SceneManager: Reward scene setup complete")

# CRITICAL FIX: Preserve reward state when navigating to equipment/inventory
func change_scene_with_return(path: String, player_character: CharacterData = null) -> void:
	# Store current scene info INCLUDING reward state
	var scene_state = {
		"path": current_scene.scene_file_path,
		"player_character": player_character
	}
	
	# CRITICAL FIX: If leaving reward scene, preserve its state
	if reward_scene_active and current_scene.has_method("set_rewards_accepted"):
		scene_state["reward_scene_active"] = true
		scene_state["rewards_collected"] = rewards_accepted
		scene_state["reward_data"] = reward_data_temp.duplicate()
		print("SceneManager: Preserving reward scene state - collected: ", rewards_accepted)
	
	scene_stack.push_back(scene_state)
	_change_scene_internal(path, player_character)

func return_to_previous_scene() -> void:
	if scene_stack.is_empty():
		print("Warning: No previous scene to return to")
		return
	
	var previous_scene_data = scene_stack.pop_back()
	
	# CRITICAL FIX: Restore reward scene state if returning to it
	if previous_scene_data.has("reward_scene_active"):
		reward_scene_active = true
		rewards_accepted = previous_scene_data.get("rewards_collected", false)
		reward_data_temp = previous_scene_data.get("reward_data", {})
		print("SceneManager: Restoring reward scene state - collected: ", rewards_accepted)
	
	_change_scene_internal(previous_scene_data["path"], previous_scene_data["player_character"])
	
	# CRITICAL FIX: Restore reward scene display after transition
	if previous_scene_data.has("reward_scene_active"):
		await get_tree().process_frame
		
		if current_scene.has_method("set_rewards_accepted"):
			current_scene.set_rewards_accepted(rewards_accepted)
		
		# Re-setup the scene with preserved data
		if current_scene.has_method("set_rewards"):
			current_scene.set_rewards(reward_data_temp.get("rewards", {}))
		if current_scene.has_method("set_xp_gained"):
			current_scene.set_xp_gained(reward_data_temp.get("xp_gained", 0))
		if current_scene.has_method("set_player_character"):
			current_scene.set_player_character(reward_data_temp.get("player_character"))

func _continue_with_momentum():
	# No reward calculation, straight back to dungeon
	print("SceneManager: Continuing with momentum")
	
	# Apply momentum effects (no recovery)
	MomentumSystem.apply_momentum_effects(dungeon_info["player_character"])
	
	_change_scene_internal(dungeon_info["path"], dungeon_info["player_character"])
	await get_tree().process_frame
	
	if current_scene.has_method("start_dungeon"):
		current_scene.start_dungeon(dungeon_info)

func _continue_without_momentum():
	# No reward calculation, straight back to dungeon
	print("SceneManager: Continuing without momentum")
	
	
	_change_scene_internal(dungeon_info["path"], dungeon_info["player_character"])
	await get_tree().process_frame
	
	if current_scene.has_method("start_dungeon"):
		current_scene.start_dungeon(dungeon_info)

func _on_rewards_accepted():
	print("SceneManager: Rewards accepted, returning to dungeon")
	
	reward_scene_active = false
	reward_data_temp.clear()
	
	# Apply full recovery since momentum was reset
	var player = dungeon_info["player_character"]
	player.current_hp = player.max_hp
	player.current_mp = player.max_mp
	player.current_sp = player.max_sp
	player.status_effects.clear()
	player.skill_cooldowns.clear()
	
	if not dungeon_info.is_empty():
		_change_scene_internal(dungeon_info["path"], dungeon_info["player_character"])
		await get_tree().process_frame
		
		if current_scene.has_method("start_dungeon"):
			current_scene.start_dungeon(dungeon_info)

func _on_next_floor():
	print("SceneManager: Next floor requested")
	reward_scene_active = false
	rewards_accepted = false
	
	if not dungeon_info.is_empty():
		dungeon_info["current_floor"] += 1
		dungeon_info["current_wave"] = 0
		dungeon_info["is_boss_fight"] = false

		_change_scene_internal(dungeon_info["path"], dungeon_info["player_character"])
		await get_tree().process_frame
		
		if current_scene.has_method("start_dungeon"):
			current_scene.start_dungeon(dungeon_info)

func start_dungeon_from_floor(player_character: CharacterData, start_floor: int) -> void:
	"""Start a dungeon run from a specific floor"""
	dungeon_info = {
		"player_character": player_character,
		"current_wave": 0,
		"current_floor": start_floor,
		"is_boss_fight": false,
		"max_floor": 25,
		"waves_per_floor": 5
	}
	
	town_scene_active = false
	_change_scene_internal("res://scenes/DungeonScene.tscn", player_character)
	await get_tree().process_frame
	
	if current_scene.has_method("start_dungeon"):
		current_scene.start_dungeon(dungeon_info)
