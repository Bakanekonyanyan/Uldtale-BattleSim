# SceneManager.gd - REFACTORED
# Unified navigation system with consistent patterns

extends Node

# ===== NAVIGATION TYPES =====
enum TransitionType {
	REPLACE,  # Replace current scene
	PUSH,     # Save current, navigate to new
	POP       # Return to previous
}

enum ScenePath {
	MAIN_MENU,
	CHARACTER_SELECT,
	TOWN,
	SHOP,
	EQUIPMENT,
	STATUS,
	INVENTORY,
	STASH,
	ARENA_LOBBY,
	DUNGEON,
	BATTLE,
	REWARDS
}

# Scene path lookup
const SCENE_PATHS = {
	ScenePath.MAIN_MENU: "res://scenes/ui/MainMenu.tscn",
	ScenePath.CHARACTER_SELECT: "res://scenes/ui/CharacterSelection.tscn",
	ScenePath.TOWN: "res://scenes/TownScene.tscn",
	ScenePath.SHOP: "res://scenes/ShopScene.tscn",
	ScenePath.EQUIPMENT: "res://scenes/EquipmentScene.tscn",
	ScenePath.STATUS: "res://scenes/StatusScene.tscn",
	ScenePath.INVENTORY: "res://scenes/InventoryScene.tscn",
	ScenePath.STASH: "res://scenes/StashScene.tscn",
	ScenePath.ARENA_LOBBY: "res://scenes/arena/ArenaLobby.tscn",
	ScenePath.DUNGEON: "res://scenes/DungeonScene.tscn",
	ScenePath.BATTLE: "res://scenes/battle/Battle.tscn",
	ScenePath.REWARDS: "res://scenes/RewardScene.tscn"
}

# ===== STATE =====
var current_scene: Node = null
var scene_stack: Array[Dictionary] = []

# ===== INIT =====
func _ready() -> void:
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)
	print("SceneManager: Initialized with scene: %s" % current_scene.name)

# ===== CORE NAVIGATION API =====

func navigate(scene: ScenePath, transition: TransitionType = TransitionType.REPLACE, character: CharacterData = null, data: Dictionary = {}) -> void:
	"""
	Unified navigation method
	
	Examples:
	  navigate(ScenePath.TOWN, TransitionType.REPLACE, player)
	  navigate(ScenePath.SHOP, TransitionType.PUSH, player)
	  navigate(ScenePath.MAIN_MENU, TransitionType.POP)
	"""
	var path = SCENE_PATHS.get(scene, "")
	if path.is_empty():
		push_error("SceneManager: Invalid scene enum: %d" % scene)
		return
	
	match transition:
		TransitionType.REPLACE:
			_navigate_replace(path, character, data)
		TransitionType.PUSH:
			_navigate_push(path, character, data)
		TransitionType.POP:
			_navigate_pop()

# ===== INTERNAL TRANSITION LOGIC =====

func _navigate_replace(path: String, character: CharacterData, data: Dictionary) -> void:
	"""Replace current scene"""
	if character:
		SaveManager.save_game(character)
	
	call_deferred("_deferred_load", path, character, data)

func _navigate_push(path: String, character: CharacterData, data: Dictionary) -> void:
	"""Push current scene to stack, navigate to new"""
	if character:
		SaveManager.save_game(character)
	
	# Save current state
	var state = {
		"path": current_scene.scene_file_path if current_scene else "",
		"character": character,
		"data": data.duplicate()
	}
	
	scene_stack.push_back(state)
	print("SceneManager: Pushed to stack (depth: %d)" % scene_stack.size())
	
	call_deferred("_deferred_load", path, character, data)

func _navigate_pop() -> void:
	"""Return to previous scene"""
	if scene_stack.is_empty():
		push_warning("SceneManager: Cannot pop - stack is empty")
		return
	
	var state = scene_stack.pop_back()
	print("SceneManager: Popped from stack (depth: %d)" % scene_stack.size())
	
	var path = state.get("path", "")
	var character = state.get("character", null)
	var data = state.get("data", {})
	
	call_deferred("_deferred_load", path, character, data)

# ===== SCENE LOADING =====

func _deferred_load(path: String, character: CharacterData, data: Dictionary) -> void:
	"""Load and instantiate scene"""
	print("SceneManager: Loading scene: %s" % path)
	
	# Cleanup current
	if current_scene:
		current_scene.queue_free()
		current_scene = null
	
	# Load new
	var scene_resource = load(path)
	if not scene_resource:
		push_error("SceneManager: Failed to load: %s" % path)
		return
	
	current_scene = scene_resource.instantiate()
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene
	
	# Wait for scene to stabilize
	await get_tree().process_frame
	
	# Apply character if provided
	if character:
		_apply_character_to_scene(character)
	
	# Apply custom data
	if not data.is_empty():
		_apply_data_to_scene(data)
	
	print("SceneManager: Scene loaded successfully")

func _apply_character_to_scene(character: CharacterData) -> void:
	"""Set character on scene if it has the method"""
	if current_scene.has_method("set_player"):
		current_scene.set_player(character)
	elif current_scene.has_method("set_player_character"):
		current_scene.set_player_character(character)

func _apply_data_to_scene(data: Dictionary) -> void:
	"""Apply custom data to scene"""
	# Example: Battle data, dungeon info, etc.
	if data.has("battle_data") and current_scene.has_method("setup_battle"):
		current_scene.setup_battle(data["battle_data"])

# ===== HIGH-LEVEL NAVIGATION (Backwards Compatibility) =====

func change_to_town(character: CharacterData) -> void:
	MomentumSystem.reset_momentum()
	DungeonStateManager.end_dungeon()
	RewardsManager.clear_saved_state()  # Managed by RewardsManager now
	navigate(ScenePath.TOWN, TransitionType.REPLACE, character)

func change_to_shop(character: CharacterData) -> void:
	navigate(ScenePath.SHOP, TransitionType.PUSH, character)

func change_to_equipment(character: CharacterData) -> void:
	navigate(ScenePath.EQUIPMENT, TransitionType.PUSH, character)

func change_to_status(character: CharacterData) -> void:
	navigate(ScenePath.STATUS, TransitionType.PUSH, character)

func change_to_inventory(character: CharacterData) -> void:
	navigate(ScenePath.INVENTORY, TransitionType.PUSH, character)

func change_to_stash(character: CharacterData) -> void:
	navigate(ScenePath.STASH, TransitionType.PUSH, character)

func change_to_arena(character: CharacterData) -> void:
	navigate(ScenePath.ARENA_LOBBY, TransitionType.PUSH, character)

func change_to_main_menu() -> void:
	MomentumSystem.reset_momentum()
	DungeonStateManager.end_dungeon()
	navigate(ScenePath.MAIN_MENU, TransitionType.REPLACE)

func change_to_character_selection() -> void:
	navigate(ScenePath.CHARACTER_SELECT, TransitionType.REPLACE)

func return_to_previous_scene() -> void:
	navigate(ScenePath.MAIN_MENU, TransitionType.POP)  # Enum ignored for POP

# ===== DUNGEON FLOW =====

func start_dungeon_from_floor(player: CharacterData, floor: int) -> void:
	"""Initialize dungeon and transition to dungeon scene"""
	# Reset player state
	player.current_hp = player.max_hp
	player.current_mp = player.max_mp
	player.current_sp = player.max_sp
	player.status_manager.clear_all_effects()
	player.skill_manager.clear_cooldowns()
	
	# Initialize dungeon
	DungeonStateManager.start_dungeon(player, floor)
	
	# Navigate
	navigate(ScenePath.DUNGEON, TransitionType.REPLACE, player)
	
	await get_tree().process_frame
	
	# Start first wave
	if current_scene.has_method("start_dungeon"):
		var battle_data = DungeonStateManager.advance_wave()
		current_scene.start_dungeon(battle_data)

func start_battle(battle_data: Dictionary) -> void:
	"""Transition to battle with data"""
	print("SceneManager: Starting battle - Floor %d, Wave %d" % [
		battle_data["current_floor"],
		battle_data["current_wave"]
	])
	
	navigate(ScenePath.BATTLE, TransitionType.REPLACE, battle_data["player_character"], {
		"battle_data": battle_data
	})
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	_setup_battle_scene(battle_data)

func _setup_battle_scene(battle_data: Dictionary) -> void:
	"""Configure battle scene after load"""
	if not current_scene or not current_scene.has_method("set_player"):
		push_error("SceneManager: Battle scene not ready")
		return
	
	current_scene.set_player(battle_data["player_character"])
	
	# Handle enemies (multi or single)
	if battle_data.has("enemies") and not battle_data["enemies"].is_empty():
		current_scene.set_enemies(battle_data["enemies"])
	elif battle_data.has("enemy") and battle_data["enemy"]:
		current_scene.set_enemies([battle_data["enemy"]])
	else:
		push_error("SceneManager: No enemies in battle_data!")
		return
	
	# Set dungeon info
	current_scene.set_dungeon_info(
		battle_data["is_boss_fight"],
		battle_data["current_wave"],
		battle_data["current_floor"],
		battle_data["max_floor"],
		battle_data.get("description", "")
	)
	
	# Connect battle completion
	if not current_scene.is_connected("battle_completed", _on_battle_completed):
		current_scene.battle_completed.connect(_on_battle_completed)


# ===== BATTLE COMPLETION =====

func _on_battle_completed(player_won: bool, xp_gained: int) -> void:
	print("SceneManager: Battle completed - Won: %s, XP: %d" % [player_won, xp_gained])
	
	if not player_won:
		MomentumSystem.reset_momentum()
		DungeonStateManager.end_dungeon()
		change_to_character_selection()
		return
	
	# Update max floor if boss
	if DungeonStateManager.is_boss_fight:
		var cleared_floor = DungeonStateManager.current_floor
		var player = DungeonStateManager.active_player
		
		if cleared_floor >= player.max_floor_cleared:
			player.max_floor_cleared = cleared_floor + 1
			SaveManager.save_game(player)
	
	# Press on (-1) or take breather (xp)
	if xp_gained == -1:
		_continue_with_momentum()
	else:
		_show_rewards(xp_gained)

func _continue_with_momentum() -> void:
	"""Player pressed on - apply momentum and advance"""
	var player = DungeonStateManager.active_player
	MomentumSystem.apply_momentum_effects(player)
	
	if DungeonStateManager.is_boss_fight:
		# Boss defeated - advance floor
		if not DungeonStateManager.advance_floor():
			change_to_town(player)
			return
		
		navigate(ScenePath.DUNGEON, TransitionType.REPLACE, player)
		await get_tree().process_frame
		
		var battle_data = DungeonStateManager.advance_wave()
		if current_scene.has_method("start_dungeon"):
			current_scene.start_dungeon(battle_data)
	else:
		# Regular wave - next wave
		var battle_data = DungeonStateManager.advance_wave()
		start_battle(battle_data)

func _show_rewards(xp_gained: int) -> void:
	"""Show reward scene"""
	var battle_data = DungeonStateManager.get_battle_data()
	battle_data["xp_gained"] = xp_gained
	
	var rewards = RewardsManager.calculate_battle_rewards(battle_data)
	
	var reward_data = {
		"rewards": rewards,
		"xp_gained": xp_gained,
		"player_character": DungeonStateManager.active_player,
		"is_boss_fight": DungeonStateManager.is_boss_fight,
		"current_floor": DungeonStateManager.current_floor,
		"current_wave": DungeonStateManager.current_wave,
		"max_floor": DungeonStateManager.max_floor,
		"description": DungeonStateManager.get_dungeon_description() if DungeonStateManager.has_method("get_dungeon_description") else ""
	}
	
	# Save state in RewardsManager (not SceneManager)
	RewardsManager.save_state(rewards, xp_gained, false, {}, false)
	
	navigate(ScenePath.REWARDS, TransitionType.REPLACE, DungeonStateManager.active_player, {
		"reward_data": reward_data
	})
	
	# Wait for scene to load, then setup
	await get_tree().process_frame
	await get_tree().process_frame
	
	if not current_scene:
		push_error("SceneManager: Reward scene failed to load")
		return
	
	# Set all data on reward scene
	if current_scene.has_method("set_player_character"):
		current_scene.set_player_character(reward_data["player_character"])
	
	if current_scene.has_method("set_rewards"):
		current_scene.set_rewards(reward_data["rewards"])
	
	if current_scene.has_method("set_xp_gained"):
		current_scene.set_xp_gained(reward_data["xp_gained"])
	
	if current_scene.has_method("set_dungeon_info"):
		current_scene.set_dungeon_info(
			reward_data["is_boss_fight"],
			reward_data["current_wave"],
			reward_data["current_floor"],
			reward_data["max_floor"],
			reward_data["description"]
		)
	
	# NOW trigger display
	if current_scene.has_method("initialize_display"):
		current_scene.initialize_display()
		print("SceneManager: Reward scene display initialized")
	else:
		push_warning("SceneManager: Reward scene missing initialize_display() - display may not work")

# ===== LEGACY METHODS (DEPRECATED) =====

func change_scene(path: String) -> void:
	push_warning("SceneManager.change_scene() is deprecated - use navigate()")
	call_deferred("_deferred_load", path, null, {})

func push_scene(path: String, character: CharacterData = null) -> void:
	push_warning("SceneManager.push_scene() is deprecated - use navigate()")
	_navigate_push(path, character, {})

func pop_scene() -> void:
	push_warning("SceneManager.pop_scene() is deprecated - use navigate()")
	_navigate_pop()
