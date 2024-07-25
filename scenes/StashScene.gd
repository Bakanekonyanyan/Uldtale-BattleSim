# StashScene.gd
extends Control

var player_character: CharacterData

@onready var inventory_list = $InventoryList
@onready var stash_list = $StashList
@onready var move_to_stash_button = $MoveToStashButton
@onready var move_to_inventory_button = $MoveToInventoryButton
@onready var back_button = $BackButton

func _ready():
	player_character = CharacterManager.get_current_character()
	if not player_character:
		print("Whoops! No character loaded.")
		return
	
	refresh_lists()
	
	move_to_stash_button.connect("pressed", Callable(self, "_on_move_to_stash_pressed"))
	move_to_inventory_button.connect("pressed", Callable(self, "_on_move_to_inventory_pressed"))
	back_button.connect("pressed", Callable(self, "_on_back_pressed"))

func refresh_lists():
	inventory_list.clear()
	stash_list.clear()
	
	for item_id in player_character.inventory.items:
		var item_data = player_character.inventory.items[item_id]
		inventory_list.add_item("%s (x%d)" % [item_data.item.name, item_data.quantity])
	
	for item_id in player_character.stash.items:
		var item_data = player_character.stash.items[item_id]
		stash_list.add_item("%s (x%d)" % [item_data.item.name, item_data.quantity])

func _on_move_to_stash_pressed():
	var selected_items = inventory_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		var item_id = player_character.inventory.items.keys()[item_index]
		var item = player_character.inventory.items[item_id].item
		player_character.inventory.remove_item(item_id, 1)
		player_character.stash.add_item(item, 1)
		refresh_lists()

func _on_move_to_inventory_pressed():
	var selected_items = stash_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		var item_id = player_character.stash.items.keys()[item_index]
		var item = player_character.stash.items[item_id].item
		player_character.stash.remove_item(item_id, 1)
		player_character.inventory.add_item(item, 1)
		refresh_lists()

func _on_back_pressed():
	SaveManager.save_game(player_character)
	SceneManager.change_to_town(player_character)
