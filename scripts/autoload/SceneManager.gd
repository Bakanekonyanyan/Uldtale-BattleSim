# SceneManager.gd - REFACTORED
# Responsibility: Scene transitions ONLY
# Dungeon logic → DungeonStateManager
# Rewards logic → RewardsManager
# Momentum logic → MomentumSystem

extends Node

var current_scene: Node = null
var scene_stack: Array[Dictionary] = []

# Temporary reward state (only for navigation)
var reward_scene_active: bool = false
var rewards_accepted: bool = false
var town_scene_active = false
var saved_reward_data: Dictionary = {}

func _ready() -> void:
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)

# === CORE SCENE TRANSITIONS ===

func change_scene(path: String) -> void:
	call_deferred("_deferred_change_scene", path)

func _deferred_change_scene(path: String) -> void:
	print("SceneManager: Changing to: ", path)
	
	if current_scene:
		current_scene.queue_free()
	
	var scene_resource = load(path)
	if not scene_resource:
		printerr("Failed to load: ", path)
		return
	
	current_scene = scene_resource.instantiate()
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene

func change_scene_with_character(path: String, character: CharacterData) -> void:
	"""Change scene and set character on arrival"""
	call_deferred("_change_with_character", path, character)

func _change_with_character(path: String, character: CharacterData) -> void:
	_deferred_change_scene(path)
	await get_tree().process_frame
	
	if current_scene.has_method("set_player"):
		current_scene.set_player(character)
	elif current_scene.has_method("set_player_character"):
		current_scene.set_player_character(character)

# === NAVIGATION WITH STACK ===

func push_scene(path: String, character: CharacterData = null) -> void:
	"""Save current scene and navigate to new one"""
	var state = {
		"path": current_scene.scene_file_path,
		"player_character": character
	}
	
	# CRITICAL: Preserve reward state if in rewards
	if reward_scene_active:
		state["reward_scene_active"] = true
		state["rewards_collected"] = rewards_accepted
		print("SceneManager: Saving reward state - collected: %s" % rewards_accepted)
	
	scene_stack.push_back(state)
	change_scene_with_character(path, character)
	
func pop_scene() -> void:
	"""Return to previous scene"""
	if scene_stack.is_empty():
		print("Warning: Scene stack empty")
		return
	
	var previous = scene_stack.pop_back()
	
	# Restore reward state if needed
	if previous.has("reward_scene_active"):
		reward_scene_active = true
		rewards_accepted = previous.get("rewards_collected", false)
	
	change_scene_with_character(previous["path"], previous["player_character"])

# === TOWN & NAVIGATION ===

func change_to_town(character: CharacterData) -> void:
	MomentumSystem.reset_momentum()
	DungeonStateManager.end_dungeon()
	reward_scene_active = false
	change_scene_with_character("res://scenes/TownScene.tscn", character)

func change_to_shop(character: CharacterData) -> void:
	push_scene("res://scenes/ShopScene.tscn", character)

func change_to_equipment(character: CharacterData) -> void:
	push_scene("res://scenes/EquipmentScene.tscn", character)

func change_to_status(character: CharacterData) -> void:
	push_scene("res://scenes/StatusScene.tscn", character)

func change_to_inventory(character: CharacterData) -> void:
	push_scene("res://scenes/InventoryScene.tscn", character)

func change_to_stash(character: CharacterData) -> void:
	push_scene("res://scenes/StashScene.tscn", character)

func change_to_main_menu() -> void:
	MomentumSystem.reset_momentum()
	DungeonStateManager.end_dungeon()
	change_scene("res://scenes/ui/MainMenu.tscn")

func change_to_character_selection() -> void:
	change_scene("res://scenes/ui/CharacterSelection.tscn")

func return_to_previous_scene() -> void:
	pop_scene()

# === DUNGEON FLOW ===

func start_dungeon_from_floor(player: CharacterData, floor: int) -> void:
	"""Start a new dungeon run"""
	DungeonStateManager.start_dungeon(player, floor)
	change_scene_with_character("res://scenes/DungeonScene.tscn", player)
	
	await get_tree().process_frame
	if current_scene.has_method("start_dungeon"):
		var dungeon_data = DungeonStateManager.get_battle_data()
		current_scene.start_dungeon(dungeon_data)

func start_battle(battle_data: Dictionary) -> void:
	"""Transition to battle scene"""
	print("SceneManager: Starting battle")
	change_scene("res://scenes/battle/Battle.tscn")
	
	await get_tree().process_frame
	setup_battle_scene(battle_data)

func setup_battle_scene(battle_data: Dictionary):
	"""Configure battle scene with data"""
	if not current_scene or not current_scene.has_method("set_player"):
		push_error("Battle scene not ready")
		return
	
	current_scene.set_player(battle_data["player_character"])
	current_scene.set_enemy(battle_data["enemy"])
	
	if not current_scene.is_connected("battle_completed", Callable(self, "_on_battle_completed")):
		current_scene.connect("battle_completed", Callable(self, "_on_battle_completed"))
	
	current_scene.set_dungeon_info(
		battle_data["current_wave"],
		battle_data["current_floor"],
		battle_data.get("description", "")
	)

func _on_battle_completed(player_won: bool, xp_gained: int):
	"""Handle battle outcome"""
	print("SceneManager: Battle completed - Won: %s, XP: %d" % [player_won, xp_gained])
	
	if not player_won:
		MomentumSystem.reset_momentum()
		DungeonStateManager.end_dungeon()
		change_to_character_selection()
		return
	
	# ✅ FIX: Update max_floor_cleared IMMEDIATELY after boss victory
	if DungeonStateManager.is_boss_fight:
		var cleared_floor = DungeonStateManager.current_floor
		var player = DungeonStateManager.active_player
		
		if cleared_floor >= player.max_floor_cleared:
			player.max_floor_cleared = cleared_floor
			player.max_floor_cleared += 1
			
			print("SceneManager: Boss defeated! Max floor cleared updated to %d" % player.max_floor_cleared)
			
			# ✅ CRITICAL: Save immediately so it persists regardless of player choice
			SaveManager.save_game(player)
			print("SceneManager: Progress saved after boss victory")
	
	# Check if "Press On" (xp = -1) or "Take Breather" (xp >= 0)
	if xp_gained == -1:
		_continue_with_momentum()
	else:
		_show_rewards(xp_gained)

func _continue_with_momentum():
	"""Player pressed on - skip rewards"""
	print("SceneManager: Momentum active, continuing")
	
	var player = DungeonStateManager.active_player
	MomentumSystem.apply_momentum_effects(player)
	
	# Advance wave
	var battle_data = DungeonStateManager.advance_wave()
	start_battle(battle_data)

func _on_rewards_accepted():
	"""Player collected rewards and wants to continue"""
	print("SceneManager: Rewards accepted")
	
	reward_scene_active = false
	
	var player = DungeonStateManager.active_player
	player.current_hp = player.max_hp
	player.current_mp = player.max_mp
	player.current_sp = player.max_sp
	player.status_effects.clear()
	player.skill_cooldowns.clear()
	
	# Continue dungeon
	var battle_data = DungeonStateManager.advance_wave()
	start_battle(battle_data)

func _on_next_floor():
	"""Advance to next floor"""
	print("SceneManager: Next floor requested")
	
	reward_scene_active = false
	
	if not DungeonStateManager.advance_floor():
		# Max floor reached
		change_to_town(DungeonStateManager.active_player)
		return
	
	# Start next floor
	change_scene_with_character("res://scenes/DungeonScene.tscn", DungeonStateManager.active_player)
	await get_tree().process_frame
	
	if current_scene.has_method("start_dungeon"): 
		var dungeon_data = DungeonStateManager.get_battle_data()
		current_scene.start_dungeon(dungeon_data)

func save_reward_state(rewards: Dictionary, xp_gained: int, rewards_collected: bool, collected_items: Dictionary):
	"""Save reward state before navigating away from RewardScene"""
	saved_reward_data = {
		"rewards": rewards.duplicate(true),  # Deep copy
		"xp_gained": xp_gained,
		"rewards_collected": rewards_collected,
		# Also save dungeon context
		"is_boss_fight": DungeonStateManager.is_boss_fight,
		"current_floor": DungeonStateManager.current_floor,
		"max_floor": DungeonStateManager.max_floor
	}
	print("SceneManager: Saved reward state - collected: %s, xp: %d" % [rewards_collected, xp_gained])

func get_saved_reward_state():
	"""Get saved reward state when returning to RewardScene"""
	if saved_reward_data.is_empty():
		return null
	print("SceneManager: Restoring reward state - collected: %s" % saved_reward_data.get("rewards_collected", false))
	return saved_reward_data

func clear_saved_reward_state():
	"""Clear saved reward state when actually leaving rewards"""
	saved_reward_data.clear()
	print("SceneManager: Cleared saved reward state")

func setup_reward_scene(data: Dictionary):
	"""Configure reward scene"""
	if current_scene.has_method("set_player_character"):
		current_scene.set_player_character(data["player_character"])
	
	if current_scene.has_method("set_rewards"):
		current_scene.set_rewards(data["rewards"])
	
	if current_scene.has_method("set_xp_gained"):
		current_scene.set_xp_gained(data["xp_gained"])
	
	if current_scene.has_method("set_dungeon_info"):
		current_scene.set_dungeon_info(
			data["is_boss_fight"],
			data["current_floor"],
			data["max_floor"]
		)
	
	# CRITICAL FIX: Always ensure signals are connected
	_connect_reward_scene_signals()

func _connect_reward_scene_signals():
	"""Ensure reward scene signals are connected to SceneManager"""
	print("SceneManager: Connecting reward scene signals")
	
	# Disconnect existing connections first
	if current_scene.is_connected("rewards_accepted", Callable(self, "_on_rewards_accepted")):
		current_scene.disconnect("rewards_accepted", Callable(self, "_on_rewards_accepted"))
	if current_scene.is_connected("next_floor", Callable(self, "_on_next_floor")):
		current_scene.disconnect("next_floor", Callable(self, "_on_next_floor"))
	
	# Connect signals
	if not current_scene.is_connected("rewards_accepted", Callable(self, "_on_rewards_accepted")):
		current_scene.connect("rewards_accepted", Callable(self, "_on_rewards_accepted"))
		print("SceneManager: Connected rewards_accepted")
	
	if not current_scene.is_connected("next_floor", Callable(self, "_on_next_floor")):
		current_scene.connect("next_floor", Callable(self, "_on_next_floor"))
		print("SceneManager: Connected next_floor")

func _show_rewards(xp_gained: int):
	"""Show reward scene"""
	print("SceneManager: Showing rewards")
	
	# Calculate rewards
	var battle_data = DungeonStateManager.get_battle_data()
	battle_data["xp_gained"] = xp_gained
	battle_data["enemy"] = DungeonStateManager.active_enemy
	
	var rewards = RewardsManager.calculate_battle_rewards(battle_data)
	
	# ✅ REMOVED: Don't update max_floor_cleared here - already done in _on_battle_completed
	
	# Prepare reward scene data
	var reward_data = {
		"rewards": rewards,
		"xp_gained": xp_gained,
		"player_character": DungeonStateManager.active_player,
		"is_boss_fight": DungeonStateManager.is_boss_fight,
		"current_floor": DungeonStateManager.current_floor,
		"max_floor": DungeonStateManager.max_floor
	}
	
	reward_scene_active = true
	rewards_accepted = false
	
	change_scene("res://scenes/RewardScene.tscn")
	await get_tree().process_frame
	setup_reward_scene(reward_data)
