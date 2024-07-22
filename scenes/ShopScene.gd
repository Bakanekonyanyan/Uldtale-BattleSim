# res://scenes/ShopScene.gd
extends Control

var player_character: CharacterData
var shop_inventory: Dictionary = {
	"health_potion": {"item": null, "price": 50},
	"mana_potion": {"item": null, "price": 75},
	# Add more items as needed
}

@onready var item_list = $ItemList if has_node("ItemList") else null
@onready var sell_item_list = $SellItemList if has_node("SellItemList") else null
@onready var buy_button = $BuyButton if has_node("BuyButton") else null
@onready var sell_button = $SellButton if has_node("SellButton") else null
@onready var exit_button = $ExitButton if has_node("ExitButton") else null
@onready var player_currency_label = $PlayerCurrencyLabel if has_node("PlayerCurrencyLabel") else null

func _ready():
	print("ShopScene: _ready called")
	
	if not item_list:
		print("Error: ItemList node not found")
	if not sell_item_list:
		print("Error: SellItemList node not found")
	if not buy_button:
		print("Error: BuyButton node not found")
	if not sell_button:
		print("Error: SellButton node not found")
	if not exit_button:
		print("Error: ExitButton node not found")
	if not player_currency_label:
		print("Error: PlayerCurrencyLabel node not found")

	if buy_button:
		buy_button.connect("pressed", Callable(self, "_on_buy_pressed"))
	if exit_button:
		exit_button.connect("pressed", Callable(self, "_on_exit_pressed"))
	if item_list:
		item_list.connect("item_selected", Callable(self, "_on_item_selected"))
	if sell_button:
		sell_button.connect("pressed", Callable(self, "_on_sell_pressed"))
	
	# Load items
	for item_id in shop_inventory:
		shop_inventory[item_id].item = ItemManager.get_item(item_id)
	
	# Get the current character from CharacterManager
	player_character = CharacterManager.get_current_character()
	if player_character == null:
		print("Error: No character selected")
		SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")
		return
	
	refresh_shop_display()
	refresh_sell_items()

func set_player(character: CharacterData):
	player_character = character
	refresh_shop_display()

func refresh_shop_display():
	print("ShopScene: refresh_shop_display called")
	if item_list:
		item_list.clear()
		for item_id in shop_inventory:
			var item_data = shop_inventory[item_id]
			if item_data.item != null:
				item_list.add_item("%s - %d gold" % [item_data.item.name, item_data.price])
			else:
				print("Warning: Item not found in ItemManager: ", item_id)
	else:
		print("Error: ItemList is null in refresh_shop_display")
	
	if player_currency_label and player_character:
		player_currency_label.text = "Your Gold: %s" % player_character.currency.get_formatted()
	else:
		print("Error: player_currency_label or player_character is null")
		
func _on_buy_pressed():
	var selected_items = item_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		var item_id = shop_inventory.keys()[item_index]
		var item_data = shop_inventory[item_id]
		
		if player_character.currency.copper >= item_data.price:
			player_character.currency.subtract(item_data.price)
			player_character.inventory.add_item(item_data.item)
			refresh_shop_display()
			refresh_sell_items()
		else:
			print("Not enough gold!")

func refresh_sell_items():
	if sell_item_list:
		sell_item_list.clear()
		for item_id in player_character.inventory.items:
			var item_data = player_character.inventory.items[item_id]
			var item = item_data.item
			if item:
				sell_item_list.add_item("%s (x%d) - %d gold" % [item.name, item_data.quantity, item.value / 2])
	else:
		print("Error: sell_item_list is null")

func _on_sell_pressed():
	var selected_items = sell_item_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		var item_id = player_character.inventory.items.keys()[item_index]
		var item_data = player_character.inventory.items[item_id]
		var item = item_data.item
		
		player_character.inventory.remove_item(item_id, 1)
		player_character.currency.add(item.value / 2)
		
		refresh_sell_items()
		refresh_shop_display()

func _on_exit_pressed():
	# Save the character's updated inventory and currency
	CharacterManager.save_character(player_character)
	# Return to character selection
	SceneManager.change_scene("res://scenes/TownScene.tscn")

func _on_item_selected(_index):
	buy_button.disabled = false
	

