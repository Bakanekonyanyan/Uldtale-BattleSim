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
}

@onready var item_list = $UI/ItemList
@onready var sell_item_list = $UI/SellItemList
@onready var buy_button = $UI/BuyButton
@onready var sell_button = $UI/SellButton
@onready var sell_all_button = $UI/SellAllButton  # Add to scene
@onready var exit_button = $UI/ExitButton
@onready var player_currency_label = $UI/PlayerCurrencyLabel
@onready var item_info_label = $UI/ItemInfoLabel  # Add to scene (RichTextLabel preferred)

func _ready():
	print("ShopScene: _ready called")
	
	if buy_button:
		buy_button.connect("pressed", Callable(self, "_on_buy_pressed"))
	if exit_button:
		exit_button.connect("pressed", Callable(self, "_on_exit_pressed"))
	if item_list:
		item_list.connect("item_selected", Callable(self, "_on_shop_item_selected"))
	if sell_button:
		sell_button.connect("pressed", Callable(self, "_on_sell_pressed"))
	if sell_all_button:
		sell_all_button.connect("pressed", Callable(self, "_on_sell_all_pressed"))
	if sell_item_list:
		sell_item_list.connect("item_selected", Callable(self, "_on_sell_item_selected"))
	
	# Load items
	for item_id in shop_inventory:
		shop_inventory[item_id].item = ItemManager.get_item(item_id)
	
	player_character = CharacterManager.get_current_character()
	if player_character == null:
		print("Error: No character selected")
		SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")
		return
	
	refresh_shop_display()
	refresh_sell_items()
	clear_item_info()

func refresh_shop_display():
	if item_list:
		item_list.clear()
		for item_id in shop_inventory:
			var item_data = shop_inventory[item_id]
			if item_data.item != null:
				item_list.add_item("%s - %d copper" % [item_data.item.name, item_data.price])
	
	if player_currency_label and player_character:
		player_currency_label.text = "Your Gold: %s" % player_character.currency.get_formatted()

func refresh_sell_items():
	if sell_item_list:
		sell_item_list.clear()
		var index = 0
		
		for item_id in player_character.inventory.items:
			var item_data = player_character.inventory.items[item_id]
			var item = item_data.item
			
			if item:
				var sell_value = item.value / 2
				var display_text = "%s (x%d) - %d copper" % [item.name, item_data.quantity, sell_value]
				sell_item_list.add_item(display_text)
				
				# Color equipment by rarity
				if item is Equipment:
					var rarity_color = Color(item.get_rarity_color())
					sell_item_list.set_item_custom_fg_color(index, rarity_color)
				
				index += 1

func _on_shop_item_selected(index: int):
	var item_id = shop_inventory.keys()[index]
	var item_data = shop_inventory[item_id]
	var item = item_data.item
	print("shop item selected")
	display_item_info(item, item_data.price, true)

func _on_sell_item_selected(index: int):
	var item_id = player_character.inventory.items.keys()[index]
	var item = player_character.inventory.items[item_id].item
	
	display_item_info(item, item.value / 2, false)

# In ShopScene.gd, update the display_item_info function:

func display_item_info(item: Item, price: int, is_buying: bool):
	if not item_info_label:
		return
	
	var info_text = ""
	
	if item_info_label is RichTextLabel:
		item_info_label.bbcode_enabled = true
		
		# For equipment, show full description
		if item is Equipment:
			info_text = item.get_full_description()
			info_text += "\n\n"
		else:
			# FIXED: Show consumable details properly
			info_text = "[b]%s[/b]\n\n%s\n\n" % [item.name, item.description]
			
			# Show consumable-specific info
			if item.item_type == Item.ItemType.CONSUMABLE:
				info_text += "[color=cyan][b]Consumable Effect:[/b][/color]\n"
				
				match item.consumable_type:
					Item.ConsumableType.DAMAGE:
						info_text += "  Deals %d damage\n" % item.effect_power
						if item.status_effect != Skill.StatusEffect.NONE:
							var effect_name = Skill.StatusEffect.keys()[item.status_effect]
							info_text += "  Inflicts [color=purple]%s[/color] for %d turns\n" % [effect_name, item.effect_duration]
					Item.ConsumableType.HEAL:
						info_text += "  Restores %d HP\n" % item.effect_power
					Item.ConsumableType.RESTORE:
						info_text += "  Restores %d MP/SP\n" % item.effect_power
					Item.ConsumableType.BUFF:
						info_text += "  Increases %s by %d for %d turns\n" % [item.buff_type, item.effect_power, item.effect_duration]
					Item.ConsumableType.CURE:
						info_text += "  Cures all status effects\n"
						if item.effect_power > 0:
							info_text += "  Restores %d HP\n" % item.effect_power
				
				info_text += "\n"
		
		if is_buying:
			info_text += "[color=yellow]Buy Price: %d copper[/color]" % price
		else:
			info_text += "[color=yellow]Sell Price: %d copper[/color]" % price
		
		item_info_label.text = info_text
	else:
		# Fallback for regular Label
		info_text = "%s\n\n%s\n\n" % [item.name, item.description]
		if is_buying:
			info_text += "Buy Price: %d copper" % price
		else:
			info_text += "Sell Price: %d copper" % price
		item_info_label.text = info_text
		
func clear_item_info():
	if item_info_label:
		item_info_label.text = "Select an item to view details"

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
		clear_item_info()

func _on_sell_all_pressed():
	var selected_items = sell_item_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		var item_id = player_character.inventory.items.keys()[item_index]
		var item_data = player_character.inventory.items[item_id]
		var item = item_data.item
		var quantity = item_data.quantity
		
		player_character.inventory.remove_item(item_id, quantity)
		player_character.currency.add((item.value / 2) * quantity)
		
		refresh_sell_items()
		refresh_shop_display()
		clear_item_info()

func _on_exit_pressed():
	CharacterManager.save_character(player_character)
	SceneManager.change_to_town(player_character)

func _on_item_selected(_index):
	if buy_button:
		buy_button.disabled = false
