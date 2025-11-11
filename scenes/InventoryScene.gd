# res://scenes/InventoryScene.gd
extends Control

var player_character: CharacterData

@onready var item_list = $UI/ItemList
@onready var use_button = $UI/UseButton
@onready var back_button = $UI/BackButton
@onready var capacity_label = $UI/CapacityLabel  # Add this to your scene

func _ready():
	player_character = CharacterManager.get_current_character()
	if not player_character:
		print("Oops! No character loaded.")
		return
	
	refresh_inventory()
	
	use_button.connect("pressed", Callable(self, "_on_use_pressed"))
	back_button.connect("pressed", Callable(self, "_on_back_pressed"))
	item_list.connect("item_selected", Callable(self, "_on_item_selected"))

func refresh_inventory():
	item_list.clear()
	var index = 0
	
	for item_id in player_character.inventory.items:
		var item_data = player_character.inventory.items[item_id]
		var item = item_data.item
		
		if item.item_type == Item.ItemType.CONSUMABLE:
			item_list.add_item("%s (x%d)" % [item.name, item_data.quantity])
			index += 1
	
	# Update capacity display
	update_capacity_display()

func update_capacity_display():
	if capacity_label:
		var current = player_character.inventory.items.size()
		var max_cap = player_character.inventory.capacity
		capacity_label.text = "Inventory: %d/%d" % [current, max_cap]

func _on_use_pressed():
	var selected_items = item_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		var item_id = player_character.inventory.items.keys()[item_index]
		var item = player_character.inventory.items[item_id].item
		if item.item_type == Item.ItemType.CONSUMABLE:
			var result = item.use(player_character, [player_character])
			print(result)
			refresh_inventory()

func _on_back_pressed():
	CharacterManager.save_character(player_character)
	SceneManager.return_to_previous_scene()

func _on_item_selected(_index):
	use_button.disabled = false
