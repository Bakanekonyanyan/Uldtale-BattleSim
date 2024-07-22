# SceneManager.gd
extends Node

var current_scene = null

func _ready():
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)

func change_scene(path: String):
	call_deferred("_deferred_change_scene", path)

func _deferred_change_scene(path: String):
	print("SceneManager: Changing scene to: ", path)
	
	# Clean up the current scene
	if current_scene != null:
		current_scene.queue_free()
	
	# Load the new scene
	var s = ResourceLoader.load(path)
	if s == null:
		print("SceneManager: Error - Failed to load scene: ", path)
		return
	
	# Instance the new scene
	current_scene = s.instantiate()
	if current_scene == null:
		print("SceneManager: Error - Failed to instantiate scene: ", path)
		return
	
	# Add it to the active scene, as child of root
	get_tree().root.add_child(current_scene)
	# Set the new scene as the active one
	get_tree().current_scene = current_scene
	
	if get_tree().current_scene:
		print("SceneManager: Current scene set to: ", get_tree().current_scene.name)
	else:
		print("SceneManager: Warning - Failed to set current_scene")
	
	print("SceneManager: Scene changed to: ", current_scene.name)

func change_to_shop(player_character: CharacterData):
	var shop_scene = load("res://scenes/ShopScene.tscn").instantiate()
	shop_scene.set_player(player_character)
	change_scene_to(shop_scene)

func change_to_dungeon(player_character: CharacterData):
	var dungeon_scene = load("res://scenes/DungeonScene.tscn").instantiate()
	dungeon_scene.set_player(player_character)
	change_scene_to(dungeon_scene)

func change_to_equipment(player_character: CharacterData):
	var equipment_scene = load("res://scenes/EquipmentScene.tscn").instantiate()
	equipment_scene.set_player(player_character)
	change_scene_to(equipment_scene)

func change_to_status(player_character: CharacterData):
	var status_scene = load("res://scenes/StatusScene.tscn").instantiate()
	status_scene.set_player(player_character)
	change_scene_to(status_scene)

func change_to_town(player_character: CharacterData):
	var town_scene = load("res://scenes/TownScene.tscn").instantiate()
	town_scene.set_player(player_character)
	change_scene_to(town_scene)

func change_scene_to(scene: Node):
	if current_scene:
		current_scene.queue_free()
	current_scene = scene
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene
