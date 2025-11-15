# res://scenes/ShopScene.gd
extends Control

enum ItemCategory { ALL, CONSUMABLES, WEAPONS, ARMOR }

var player_character: CharacterData
var current_category: ItemCategory = ItemCategory.ALL

@onready var item_list = $UI/ItemList
@onready var sell_item_list = $UI/SellItemList
@onready var buy_button = $UI/BuyButton
@onready var sell_button = $UI/SellButton
@onready var sell_all_button = $UI/SellAllButton
@onready var exit_button = $UI/ExitButton
@onready var player_currency_label = $UI/PlayerCurrencyLabel
@onready var item_info_label = $UI/ItemInfoLabel

# Category tabs
var tab_container: HBoxContainer
var all_tab: Button
var consumables_tab: Button
var weapons_tab: Button
var armor_tab: Button

func _ready():
	print("ShopScene: _ready called")
	
	setup_tabs()
	
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
	
	player_character = CharacterManager.get_current_character()
	if player_character == null:
		print("Error: No character selected")
		SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")
		return
	
	refresh_shop_display()
	refresh_sell_items()
	clear_item_info()

func setup_tabs():
	"""Setup category filter tabs"""
	tab_container = HBoxContainer.new()
	tab_container.position = Vector2(32, 8)
	
	all_tab = Button.new()
	all_tab.text = "All"
	all_tab.custom_minimum_size = Vector2(80, 32)
	all_tab.pressed.connect(func(): _on_category_changed(ItemCategory.ALL))
	tab_container.add_child(all_tab)
	
	consumables_tab = Button.new()
	consumables_tab.text = "Consumables"
	consumables_tab.custom_minimum_size = Vector2(100, 32)
	consumables_tab.pressed.connect(func(): _on_category_changed(ItemCategory.CONSUMABLES))
	tab_container.add_child(consumables_tab)
	
	weapons_tab = Button.new()
	weapons_tab.text = "Weapons"
	weapons_tab.custom_minimum_size = Vector2(90, 32)
	weapons_tab.pressed.connect(func(): _on_category_changed(ItemCategory.WEAPONS))
	tab_container.add_child(weapons_tab)
	
	armor_tab = Button.new()
	armor_tab.text = "Armor"
	armor_tab.custom_minimum_size = Vector2(80, 32)
	armor_tab.pressed.connect(func(): _on_category_changed(ItemCategory.ARMOR))
	tab_container.add_child(armor_tab)
	
	add_child(tab_container)
	
	_update_tab_visuals()

func _on_category_changed(category: ItemCategory):
	"""Switch to different category"""
	current_category = category
	_update_tab_visuals()
	refresh_shop_display()
	clear_item_info()

func _update_tab_visuals():
	"""Highlight active tab"""
	var tabs = [all_tab, consumables_tab, weapons_tab, armor_tab]
	for i in range(tabs.size()):
		if tabs[i]:
			if i == current_category:
				tabs[i].modulate = Color(1.2, 1.2, 0.8)  # Highlighted
			else:
				tabs[i].modulate = Color(1, 1, 1)  # Normal

func refresh_shop_display():
	if item_list:
		item_list.clear()
		
		var index = 0
		
		# Add consumables if showing ALL or CONSUMABLES
		if current_category == ItemCategory.ALL or current_category == ItemCategory.CONSUMABLES:
			for item_id in ShopManager.consumable_inventory:
				var item = ShopManager.get_consumable_item(item_id)
				if item:
					var price = ShopManager.get_consumable_price(item_id)
					item_list.add_item("%s - %d copper" % [item.name, price])
					# Store item data in metadata
					item_list.set_item_metadata(index, {
						"type": "consumable",
						"id": item_id,
						"item": item,
						"price": price
					})
					index += 1
		
		# Add equipment if showing ALL, WEAPONS, or ARMOR
		if current_category in [ItemCategory.ALL, ItemCategory.WEAPONS, ItemCategory.ARMOR]:
			var equipment_list = ShopManager.get_equipment_list()
			for equip_data in equipment_list:
				var equipment = equip_data["equipment"]
				var price = equip_data["price"]
				var key = equip_data["key"]
				
				# Filter by weapon/armor if specific category selected
				var should_show = false
				if current_category == ItemCategory.ALL:
					should_show = true
				elif current_category == ItemCategory.WEAPONS:
					# Weapons are main_hand or off_hand slots
					should_show = equipment.slot in ["main_hand", "off_hand"]
				elif current_category == ItemCategory.ARMOR:
					# Armor is head, chest, hands, legs, feet slots
					should_show = equipment.slot in ["head", "chest", "hands", "legs", "feet"]
				
				if should_show:
					var display_text = "%s [%s] - %d copper" % [
						equipment.name,
						equipment.rarity.capitalize(),
						price
					]
					
					item_list.add_item(display_text)
					
					# Color by rarity
					var rarity_color = Color(equipment.get_rarity_color())
					item_list.set_item_custom_fg_color(index, rarity_color)
					
					# Store equipment data in metadata
					item_list.set_item_metadata(index, {
						"type": "equipment",
						"key": key,
						"item": equipment,
						"price": price
					})
					index += 1
	
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
	var metadata = item_list.get_item_metadata(index)
	if not metadata:
		return
	
	var item = metadata["item"]
	var price = metadata["price"]
	
	print("Shop item selected: %s" % item.name)
	display_item_info(item, price, true)

func _on_sell_item_selected(index: int):
	var item_id = player_character.inventory.items.keys()[index]
	var item = player_character.inventory.items[item_id].item
	
	display_item_info(item, item.value / 2, false)

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
			# Show consumable details
			info_text = "[b]%s[/b]\n\n%s\n\n" % [item.name, item.description]
			
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
		var metadata = item_list.get_item_metadata(item_index)
		
		if not metadata:
			print("ShopScene: No metadata for selected item")
			return
		
		var price = metadata["price"]
		
		# Check if player can afford
		if player_character.currency.copper < price:
			print("Not enough gold!")
			var dialog = AcceptDialog.new()
			dialog.dialog_text = "Not enough gold!"
			dialog.title = "Cannot Purchase"
			add_child(dialog)
			dialog.popup_centered()
			return
		
		# Handle purchase based on type
		if metadata["type"] == "consumable":
			# Consumable purchase (unlimited stock)
			var item = metadata["item"]
			player_character.currency.subtract(price)
			player_character.inventory.add_item(item)
			print("ShopScene: Purchased consumable: %s" % item.name)
		
		elif metadata["type"] == "equipment":
			# Equipment purchase (one-time)
			var equipment = metadata["item"]
			var key = metadata["key"]
			
			# Deduct currency
			player_character.currency.subtract(price)
			
			# Add to inventory
			player_character.inventory.add_item(equipment, 1)
			
			# Remove from shop
			ShopManager.purchase_equipment(key)
			
			print("ShopScene: Purchased equipment: %s" % equipment.name)
		
		# Refresh displays
		refresh_shop_display()
		refresh_sell_items()
		clear_item_info()

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
