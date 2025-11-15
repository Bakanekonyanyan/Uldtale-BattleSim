# SceneManager.gd - FIXED: Proper reward scene initialization

extends Node

var current_scene: Node = null
var scene_stack: Array[Dictionary] = []

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
	player.current_hp = player.max_hp
	player.current_mp = player.max_mp
	player.current_sp = player.max_sp
	player.status_effects.clear()
	player.skill_cooldowns.clear()
	
	DungeonStateManager.start_dungeon(player, floor)
	change_scene_with_character("res://scenes/DungeonScene.tscn", player)
	
	await get_tree().process_frame
	if current_scene.has_method("start_dungeon"):
		var battle_data = DungeonStateManager.advance_wave()
		current_scene.start_dungeon(battle_data)

func start_battle(battle_data: Dictionary) -> void:
	"""Transition to battle scene"""
	print("SceneManager: Starting battle - Floor %d, Wave %d" % [
		battle_data["current_floor"],
		battle_data["current_wave"]
	])
	
	if current_scene:
		print("SceneManager: Cleaning up previous scene: ", current_scene.name)
		current_scene.queue_free()
		current_scene = null
	
	change_scene("res://scenes/battle/Battle.tscn")
	
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	if not current_scene:
		push_error("SceneManager: Battle scene failed to load!")
		return
	
	print("SceneManager: Battle scene loaded, setting up...")
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
		battle_data["is_boss_fight"],
		battle_data["current_wave"],
		battle_data["current_floor"],
		battle_data["max_floor"],
		battle_data.get("description", "")
	)

func _on_battle_completed(player_won: bool, xp_gained: int):
	"""Handle battle outcome"""
	print("SceneManager: Battle completed - Won: %s, XP: %d, Wave: %d" % [
		player_won, 
		xp_gained,
		DungeonStateManager.current_wave
	])
	
	if not player_won:
		MomentumSystem.reset_momentum()
		DungeonStateManager.end_dungeon()
		change_to_character_selection()
		return
	
	if DungeonStateManager.is_boss_fight:
		var cleared_floor = DungeonStateManager.current_floor
		var player = DungeonStateManager.active_player
		
		if cleared_floor >= player.max_floor_cleared:
			player.max_floor_cleared = cleared_floor + 1
			print("SceneManager: Boss defeated! Max floor cleared: %d" % player.max_floor_cleared)
			SaveManager.save_game(player)
	
	if xp_gained == -1:
		_continue_with_momentum()
	else:
		_show_rewards(xp_gained)

func _continue_with_momentum():
	"""Player pressed on - skip rewards, continue immediately"""
	print("=== SceneManager: Press On - Floor %d, Wave %d, Boss: %s ===" % [
		DungeonStateManager.current_floor,
		DungeonStateManager.current_wave,
		DungeonStateManager.is_boss_fight
	])
	
	var player = DungeonStateManager.active_player
	MomentumSystem.apply_momentum_effects(player)
	
	if DungeonStateManager.is_boss_fight:
		print("SceneManager: Boss defeated via Press On - advancing floor")
		
		if not DungeonStateManager.advance_floor():
			print("SceneManager: Max floor reached, returning to town")
			change_to_town(player)
			return
		
		print("SceneManager: Advanced to floor %d, loading DungeonScene" % DungeonStateManager.current_floor)
		
		change_scene_with_character("res://scenes/DungeonScene.tscn", player)
		await get_tree().process_frame
		await get_tree().process_frame
		
		print("SceneManager: DungeonScene loaded, calling advance_wave")
		var battle_data = DungeonStateManager.advance_wave()
		
		print("SceneManager: Battle data - Floor %d, Wave %d, Enemy: %s" % [
			battle_data["current_floor"],
			battle_data["current_wave"],
			battle_data["enemy"].name if battle_data["enemy"] else "NULL"
		])
		
		if current_scene.has_method("start_dungeon"):
			print("SceneManager: Calling start_dungeon on DungeonScene")
			current_scene.start_dungeon(battle_data)
		else:
			push_error("SceneManager: Current scene doesn't have start_dungeon method!")
	else:
		print("SceneManager: Regular wave - advancing to next wave")
		var battle_data = DungeonStateManager.advance_wave()
		
		print("SceneManager: Battle data - Floor %d, Wave %d" % [
			battle_data["current_floor"],
			battle_data["current_wave"]
		])
		
		start_battle(battle_data)

func _on_rewards_accepted():
	"""Player collected rewards and wants to continue"""
	print("SceneManager: Rewards accepted - Floor %d, Wave %d" % [
		DungeonStateManager.current_floor,
		DungeonStateManager.current_wave
	])
	
	reward_scene_active = false
	
	var player = DungeonStateManager.active_player
	player.current_hp = player.max_hp
	player.current_mp = player.max_mp
	player.current_sp = player.max_sp
	player.status_effects.clear()
	
	if DungeonStateManager.is_boss_fight:
		print("SceneManager: Boss defeated via rewards - advancing floor")
		
		if not DungeonStateManager.advance_floor():
			change_to_town(player)
			return
		
		change_scene_with_character("res://scenes/DungeonScene.tscn", player)
		await get_tree().process_frame
		
		if current_scene.has_method("start_dungeon"):
			var battle_data = DungeonStateManager.advance_wave()
			current_scene.start_dungeon(battle_data)
	else:
		var battle_data = DungeonStateManager.advance_wave()
		start_battle(battle_data)

func _on_next_floor():
	"""Advance to next floor (from reward screen)"""
	print("SceneManager: Next floor requested")
	
	reward_scene_active = false
	
	if not DungeonStateManager.advance_floor():
		change_to_town(DungeonStateManager.active_player)
		return
	
	change_scene_with_character("res://scenes/DungeonScene.tscn", DungeonStateManager.active_player)
	await get_tree().process_frame
	
	if current_scene.has_method("start_dungeon"): 
		var battle_data = DungeonStateManager.advance_wave()
		current_scene.start_dungeon(battle_data)

func save_reward_state(rewards: Dictionary, xp_gained: int, rewards_collected: bool, collected_items: Dictionary, auto_rewards_given: bool = false):
	"""Save reward state before navigating away from RewardScene"""
	saved_reward_data = {
		"rewards": rewards.duplicate(true),
		"xp_gained": xp_gained,
		"rewards_collected": rewards_collected,
		"collected_items": collected_items.duplicate(),
		"auto_rewards_given": auto_rewards_given,
		"is_boss_fight": DungeonStateManager.is_boss_fight,
		"current_floor": DungeonStateManager.current_floor,
		"current_wave": DungeonStateManager.current_wave,
		"max_floor": DungeonStateManager.max_floor
	}
	print("SceneManager: Saved reward state - Wave %d, Boss: %s" % [
		DungeonStateManager.current_wave,
		DungeonStateManager.is_boss_fight
	])

func get_saved_reward_state():
	"""Get saved reward state when returning to RewardScene"""
	if saved_reward_data.is_empty():
		return null
	return saved_reward_data

func clear_saved_reward_state():
	"""Clear saved reward state when actually leaving rewards"""
	saved_reward_data.clear()
	print("SceneManager: Cleared saved reward state")

func _connect_reward_scene_signals():
	"""Ensure reward scene signals are connected to SceneManager"""
	print("SceneManager: Connecting reward scene signals")
	
	if not current_scene:
		push_error("SceneManager: No current_scene when connecting signals!")
		return
	
	if current_scene.is_connected("rewards_accepted", Callable(self, "_on_rewards_accepted")):
		current_scene.disconnect("rewards_accepted", Callable(self, "_on_rewards_accepted"))
	if current_scene.is_connected("next_floor", Callable(self, "_on_next_floor")):
		current_scene.disconnect("next_floor", Callable(self, "_on_next_floor"))
	
	if not current_scene.is_connected("rewards_accepted", Callable(self, "_on_rewards_accepted")):
		current_scene.connect("rewards_accepted", Callable(self, "_on_rewards_accepted"))
	
	if not current_scene.is_connected("next_floor", Callable(self, "_on_next_floor")):
		current_scene.connect("next_floor", Callable(self, "_on_next_floor"))

func setup_reward_scene(data: Dictionary):
	"""Configure reward scene - MUST be called on the actual reward scene instance"""
	if not current_scene:
		push_error("SceneManager: No current_scene in setup_reward_scene!")
		return
	
	print("SceneManager: Setting up reward scene: ", current_scene.name)
	
	# Set all data FIRST
	if current_scene.has_method("set_player_character"):
		print("SceneManager: Setting player character")
		current_scene.set_player_character(data["player_character"])
	else:
		push_error("SceneManager: Reward scene missing set_player_character method!")
		return
	
	if current_scene.has_method("set_rewards"):
		print("SceneManager: Setting rewards")
		current_scene.set_rewards(data["rewards"])
	
	if current_scene.has_method("set_xp_gained"):
		print("SceneManager: Setting XP gained: %d" % data["xp_gained"])
		current_scene.set_xp_gained(data["xp_gained"])
	
	if current_scene.has_method("set_dungeon_info"):
		print("SceneManager: Setting dungeon info")
		current_scene.set_dungeon_info(
			data["is_boss_fight"],
			data["current_wave"],
			data["current_floor"],
			data["max_floor"],
			data["description"]
		)
	
	# Connect signals
	_connect_reward_scene_signals()
	
	# NOW initialize the display - this is called AFTER all data is set
	if current_scene.has_method("initialize_display"):
		print("SceneManager: Calling initialize_display")
		current_scene.initialize_display()
	else:
		push_error("SceneManager: Reward scene missing initialize_display method!")
	
	print("SceneManager: Reward scene setup complete")

func _show_rewards(xp_gained: int):
	"""Show reward scene - FIXED: Proper async scene loading"""
	print("SceneManager: Showing rewards - Floor %d, Wave %d" % [
		DungeonStateManager.current_floor,
		DungeonStateManager.current_wave
	])
	
	# Calculate rewards
	var battle_data = DungeonStateManager.get_battle_data()
	battle_data["xp_gained"] = xp_gained
	battle_data["enemy"] = DungeonStateManager.active_enemy
	
	var rewards = RewardsManager.calculate_battle_rewards(battle_data)
	
	# Prepare reward scene data
	var reward_data = {
		"rewards": rewards,
		"xp_gained": xp_gained,
		"player_character": DungeonStateManager.active_player,
		"is_boss_fight": DungeonStateManager.is_boss_fight,
		"current_floor": DungeonStateManager.current_floor,
		"current_wave": DungeonStateManager.current_wave,
		"max_floor": DungeonStateManager.max_floor,
		"description": DungeonStateManager.get_dungeon_description()
	}
	
	reward_scene_active = true
	rewards_accepted = false
	
	# Clean up old scene
	if current_scene:
		current_scene.queue_free()
		current_scene = null
	
	# Load new scene
	change_scene("res://scenes/RewardScene.tscn")
	
	# Wait for scene to be fully loaded and ready
	print("SceneManager: Waiting for RewardScene to load...")
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Verify scene loaded
	if not current_scene:
		push_error("SceneManager: RewardScene failed to load!")
		return
	
	print("SceneManager: RewardScene loaded successfully")
	
	# Wait one more frame to ensure @onready variables are initialized
	await get_tree().process_frame
	
	# Now setup the scene
	setup_reward_scene(reward_data)
