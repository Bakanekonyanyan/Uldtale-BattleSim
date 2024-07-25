# SceneManager.gd
extends Node

var current_scene: Node = null
var scene_stack: Array[Dictionary] = []
var dungeon_info: Dictionary = {}
var reward_data: Dictionary = {}
var reward_scene_active = false
var town_scene_active = false


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
	
	if current_scene.has_method("setup_dungeon"):
		current_scene.setup_dungeon()
	
	print("Scene changed to: ", current_scene.name)
	
func _on_quit_dungeon():
	print("SceneManager: Quitting dungeon")
	var player_character = dungeon_info["player_character"]
	change_to_town(player_character)
	
func change_to_shop(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/ShopScene.tscn", player_character)

func change_to_dungeon(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/DungeonScene.tscn", player_character)
	town_scene_active = false

func change_to_status(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/StatusScene.tscn", player_character)

func change_to_town(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/TownScene.tscn", player_character)
	town_scene_active = true

func change_to_stash(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/StashScene.tscn", player_character)

func change_to_main_menu() -> void:
	change_scene("res://scenes/ui/MainMenu.tscn")

func change_to_character_selection() -> void:
	change_scene("res://scenes/ui/CharacterSelection.tscn")

func change_to_rewards(player_character: CharacterData) -> void:
	change_scene_with_return("res://scenes/RewardScene.tscn", player_character)

# Add this new method
func change_scene_with_return_to_reward(path: String, player_character: CharacterData = null) -> void:
	scene_stack.push_back({
		"path": "res://scenes/RewardScene.tscn",
		"player_character": player_character
	})
	_change_scene_internal(path, player_character)

func change_scene_with_return_to_town(path: String, player_character: CharacterData = null) -> void:
	scene_stack.push_back({
		"path": "res://scenes/TownScene.tscn",
		"player_character": player_character
	})
	_change_scene_internal(path, player_character)

# Update these methods
func change_to_equipment(player_character: CharacterData) -> void:
	if town_scene_active:
		change_scene_with_return_to_town("res://scenes/EquipmentScene.tscn", player_character)
	if reward_scene_active:
		change_scene_with_return_to_reward("res://scenes/EquipmentScene.tscn", player_character)	

func change_to_inventory(player_character: CharacterData) -> void:
	if town_scene_active:
		change_scene_with_return_to_town("res://scenes/InventoryScene.tscn", player_character)
	if reward_scene_active:
		change_scene_with_return_to_reward("res://scenes/EquipmentScene.tscn", player_character)


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
	
	if reward_scene_active and previous_scene_data["path"] == "res://scenes/RewardScene.tscn":
		_change_scene_internal(previous_scene_data["path"], previous_scene_data["player_character"])
		setup_reward_scene()
	elif town_scene_active and previous_scene_data["path"] == "res://scenes/TownScene.tscn":
		print("Town scene is active")
		_change_scene_internal(previous_scene_data["path"], previous_scene_data["player_character"])
		setup_reward_scene()
	else:
		_change_scene_internal(previous_scene_data["path"], previous_scene_data["player_character"])

func setup_reward_scene():
	if current_scene.has_method("set_player_character"):
		current_scene.set_player_character(reward_data.get("player_character"))
	if current_scene.has_method("set_rewards"):
		current_scene.set_rewards(reward_data.get("rewards", {}))
	if current_scene.has_method("set_xp_gained"):
		current_scene.set_xp_gained(reward_data.get("xp_gained", 0))
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
	current_scene.connect("rewards_accepted", Callable(self, "_on_rewards_accepted"))

func show_reward_scene(dungeon: Node, new_reward_data: Dictionary) -> void:
	print("SceneManager: Preparing to show reward scene")
	
	dungeon_info = {
		"path": dungeon.scene_file_path,
		"player_character": new_reward_data.get("player_character"),
		"current_wave": dungeon.current_wave,
		"current_floor": dungeon.current_floor,
		"is_boss_fight": dungeon.is_boss_fight,
		"max_floor": dungeon.max_floor
	}
	print("SceneManager: Storing dungeon info - Wave: ", dungeon_info["current_wave"], ", Floor: ", dungeon_info["current_floor"])
	reward_data = new_reward_data
	reward_scene_active = true
	
	_change_scene_internal("res://scenes/RewardScene.tscn", new_reward_data.get("player_character"))
	call_deferred("setup_reward_scene")

func _on_rewards_accepted():
	print("SceneManager: Rewards accepted, returning to dungeon")
	reward_scene_active = false
	if not dungeon_info.is_empty():
		print("SceneManager: Restoring dungeon - Wave: ", dungeon_info["current_wave"], ", Floor: ", dungeon_info["current_floor"])
		_change_scene_internal(dungeon_info["path"], dungeon_info["player_character"])
		if current_scene.has_method("start_dungeon"):
			current_scene.call_deferred("start_dungeon", dungeon_info)
	else:
		print("Error: No dungeon info to return to")
	reward_data.clear()  # Clear reward data after accepting
