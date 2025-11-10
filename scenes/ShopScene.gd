# res://scenes/ShopScene.gd
extends Control

var player_character: CharacterData
var shop_inventory: Dictionary = {
	"health_potion": {"item": null, "price": 25},
	"mana_potion": {"item": null, "price": 30},
	"stamina_potion": {"item": null, "price": 30},
	"flame_flask": {"item": null, "price": 50},
	"frost_crystal": {"item": null, "price": 50},
	"thunder_orb": {"item": null, "price": 50},
	"venom_vial": {"item": null, "price": 50},
	"stone_shard": {"item": null, "price": 10},
	"rotten_dung": {"item": null, "price": 10},
	"smoke_bomb": {"item": null, "price": 15},
	"berserker_brew": {"item": null, "price": 30},
	"holy_water": {"item": null, "price": 50},
	# Add more items as needed
}

@onready var item_list = $UI/ItemList if has_node("ItemList") else null
@onready var sell_item_list = $UI/SellItemList if has_node("SellItemList") else null
@onready var buy_button = $UI/BuyButton if has_node("BuyButton") else null
@onready var sell_button = $UI/SellButton if has_node("SellButton") else null
@onready var exit_button = $UI/ExitButton if has_node("ExitButton") else null
@onready var player_currency_label = $UI/PlayerCurrencyLabel if has_node("PlayerCurrencyLabel") else null

func _ready():
	print("ShopScene: _ready called")
	
	if not $UI/ItemList:
		print("Error: ItemList node not found")
	if not $UI/SellItemList:
		print("Error: SellItemList node not found")
	if not $UI/BuyButton:
		print("Error: BuyButton node not found")
	if not $UI/SellButton:
		print("Error: SellButton node not found")
	if not $UI/ExitButton:
		print("Error: ExitButton node not found")
	if not $UI/PlayerCurrencyLabel:
		print("Error: PlayerCurrencyLabel node not found")

	if $UI/BuyButton:
		$UI/BuyButton.connect("pressed", Callable(self, "_on_buy_pressed"))
	if $UI/ExitButton:
		$UI/ExitButton.connect("pressed", Callable(self, "_on_exit_pressed"))
	if $UI/ItemList:
		$UI/ItemList.connect("item_selected", Callable(self, "_on_item_selected"))
	if $UI/SellButton:
		$UI/SellButton.connect("pressed", Callable(self, "_on_sell_pressed"))
	
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
	if $UI/ItemList:
		$UI/ItemList.clear()
		for item_id in shop_inventory:
			var item_data = shop_inventory[item_id]
			if item_data.item != null:
				$UI/ItemList.add_item("%s - %d copper" % [item_data.item.name, item_data.price])
			else:
				print("Warning: Item not found in ItemManager: ", item_id)
	else:
		print("Error: ItemList is null in refresh_shop_display")
	
	if $UI/PlayerCurrencyLabel and player_character:
		$UI/PlayerCurrencyLabel.text = "Your Gold: %s" % player_character.currency.get_formatted()
	else:
		print("Error: player_currency_label or player_character is null")
		
func _on_buy_pressed():
	var selected_items = $UI/ItemList.get_selected_items()
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
	if $UI/SellItemList:
		$UI/SellItemList.clear()
		for item_id in player_character.inventory.items:
			var item_data = player_character.inventory.items[item_id]
			var item = item_data.item
			
			if item:
				$UI/SellItemList.add_item("%s (x%d) - %d gold" % [item.name, item_data.quantity, item.value / 2])

	else:
		print("Error: sell_item_list is null")

func _on_sell_pressed():
	var selected_items = $UI/SellItemList.get_selected_items()
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
	$UI/BuyButton.disabled = false
	
