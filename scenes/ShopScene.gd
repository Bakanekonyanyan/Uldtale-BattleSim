# res://scenes/ShopScene.gd
extends Control

enum ItemCategory { ALL, CONSUMABLES, WEAPONS, ARMOR, BUYBACK }

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
var buyback_tab: Button  # NEW

func _ready():
	print("ShopScene: _ready called")
	
	# ✅ ENABLE MULTI-SELECT
	if item_list:
		item_list.select_mode = ItemList.SELECT_MULTI
	if sell_item_list:
		sell_item_list.select_mode = ItemList.SELECT_MULTI
	
	setup_tabs()
	
	if buy_button:
		buy_button.text = "Buy Selected"  # Updated text
		buy_button.connect("pressed", Callable(self, "_on_buy_pressed"))
	if exit_button:
		exit_button.connect("pressed", Callable(self, "_on_exit_pressed"))
	if item_list:
		item_list.connect("item_selected", Callable(self, "_on_shop_item_selected"))
	if sell_button:
		sell_button.text = "Sell Selected"  # Updated text
		sell_button.connect("pressed", Callable(self, "_on_sell_pressed"))
	if sell_all_button:
		sell_all_button.text = "Sell All Selected (Full Stack)"  # Updated text
		sell_all_button.connect("pressed", Callable(self, "_on_sell_all_pressed"))
	if sell_item_list:
		sell_item_list.connect("item_selected", Callable(self, "_on_sell_item_selected"))
	
	player_character = CharacterManager.get_current_character()
	if player_character == null:
		print("Error: No character selected")
		SceneManager.change_scene("res://scenes/ui/CharacterSelection.tscn")
		return
	
	# NEW: Update buyback based on current floor
	ShopManager.clear_buyback_on_floor_change(player_character.current_floor)
	
	refresh_shop_display()
	refresh_sell_items()
	clear_item_info()
	
	print("ShopScene: Multi-select enabled")

func setup_tabs():
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
	
	# NEW: Buyback tab
	buyback_tab = Button.new()
	buyback_tab.text = "Buyback"
	buyback_tab.custom_minimum_size = Vector2(80, 32)
	buyback_tab.pressed.connect(func(): _on_category_changed(ItemCategory.BUYBACK))
	tab_container.add_child(buyback_tab)
	
	add_child(tab_container)
	
	_update_tab_visuals()

func _on_category_changed(category: ItemCategory):
	current_category = category
	_update_tab_visuals()
	refresh_shop_display()
	clear_item_info()

func _update_tab_visuals():
	var tabs = [all_tab, consumables_tab, weapons_tab, armor_tab, buyback_tab]
	for i in range(tabs.size()):
		if tabs[i]:
			if i == current_category:
				tabs[i].modulate = Color(1.2, 1.2, 0.8)
			else:
				tabs[i].modulate = Color(1, 1, 1)

func refresh_shop_display():
	if item_list:
		item_list.clear()
		
		var index = 0
		
		# NEW: Show buyback items if buyback tab selected
		if current_category == ItemCategory.BUYBACK:
			var buyback_items = ShopManager.get_buyback_list()
			for buyback_data in buyback_items:
				var item = buyback_data["item"]
				var price = buyback_data["price"]
				var quantity = buyback_data["quantity"]
				
				var display_text = ""
				if item is Equipment:
					display_text = "%s [%s] (x%d) - %d copper" % [
						item.name,
						item.rarity.capitalize(),
						quantity,
						price
					]
					
					item_list.add_item(display_text)
					var rarity_color = Color(item.get_rarity_color())
					item_list.set_item_custom_fg_color(index, rarity_color)
				else:
					display_text = "%s (x%d) - %d copper" % [item.name, quantity, price]
					item_list.add_item(display_text)
				
				# Store buyback data in metadata
				item_list.set_item_metadata(index, {
					"type": "buyback",
					"key": buyback_data["key"],
					"item": item,
					"price": price,
					"quantity": quantity
				})
				index += 1
			
			# Update button text for buyback
			if buy_button:
				buy_button.text = "Buyback Selected"
		else:
			# Regular shop items
			if buy_button:
				buy_button.text = "Buy Selected"
			
			# Add consumables if showing ALL or CONSUMABLES
			if current_category == ItemCategory.ALL or current_category == ItemCategory.CONSUMABLES:
				for item_id in ShopManager.consumable_inventory:
					var item = ShopManager.get_consumable_item(item_id)
					if item:
						var price = ShopManager.get_consumable_price(item_id)
						item_list.add_item("%s - %d copper" % [item.name, price])
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
					
					var should_show = false
					if current_category == ItemCategory.ALL:
						should_show = true
					elif current_category == ItemCategory.WEAPONS:
						should_show = equipment.slot in ["main_hand", "off_hand"]
					elif current_category == ItemCategory.ARMOR:
						should_show = equipment.slot in ["head", "chest", "hands", "legs", "feet"]
					
					if should_show:
						var display_text = "%s [%s] - %d copper" % [
							equipment.name,
							equipment.rarity.capitalize(),
							price
						]
						
						item_list.add_item(display_text)
						
						var rarity_color = Color(equipment.get_rarity_color())
						item_list.set_item_custom_fg_color(index, rarity_color)
						
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
		
		if item is Equipment:
			info_text = item.get_full_description()
			info_text += "\n\n"
		else:
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

# NEW: Batch buy selected items
func _on_buy_pressed():
	var selected_items = item_list.get_selected_items()
	if selected_items.is_empty():
		return
	
	# ✅ Cache metadata BEFORE processing
	var items_to_buy = []
	for item_index in selected_items:
		var metadata = item_list.get_item_metadata(item_index)
		if metadata:
			items_to_buy.append(metadata)
	
	# Calculate and validate total
	var total_cost = 0
	for item_data in items_to_buy:
		total_cost += item_data["price"]
	
	if player_character.currency.copper < total_cost:
		# show error dialog
		return
	
	# Calculate total cost
	for item_index in selected_items:
		var metadata = item_list.get_item_metadata(item_index)
		if not metadata:
			continue
		
		var price = metadata["price"]
		total_cost += price
		items_to_buy.append(metadata)
	
	# Check if player can afford
	if player_character.currency.copper < total_cost:
		print("Not enough gold!")
		var dialog = AcceptDialog.new()
		dialog.dialog_text = "Not enough gold! Need %d copper, have %d copper" % [total_cost, player_character.currency.copper]
		dialog.title = "Cannot Purchase"
		add_child(dialog)
		dialog.popup_centered()
		return
	
	# Process purchases
	for item_data in items_to_buy:
		if item_data["type"] == "consumable":
			var item = item_data["item"]
			var price = item_data["price"]
			player_character.currency.subtract(price)
			player_character.inventory.add_item(item)
			print("ShopScene: Purchased consumable: %s" % item.name)
		
		elif item_data["type"] == "equipment":
			var equipment = item_data["item"]
			var key = item_data["key"]
			var price = item_data["price"]
			
			player_character.currency.subtract(price)
			player_character.inventory.add_item(equipment, 1)
			ShopManager.purchase_equipment(key)
			print("ShopScene: Purchased equipment: %s" % equipment.name)
		
		elif item_data["type"] == "buyback":
			var item = item_data["item"]
			var key = item_data["key"]
			var price = item_data["price"]
			
			var result = ShopManager.buyback_item(key, 1)
			if result["success"]:
				player_character.currency.subtract(price)
				player_character.inventory.add_item(result["item"], result["quantity"])
				print("ShopScene: Bought back: %s" % item.name)
	
	refresh_shop_display()
	refresh_sell_items()
	clear_item_info()
	
	print("Purchased %d items for %d copper" % [items_to_buy.size(), total_cost])

# NEW: Batch sell selected items (one of each)
# === FIXED: Batch sell functions ===

func _on_sell_pressed():
	"""Sell selected items (one of each) - FIXED"""
	var selected_items = sell_item_list.get_selected_items()
	if selected_items.is_empty():
		print("No items selected")
		return
	
	# ✅ FIX: Sort indices in DESCENDING order to avoid index shifting
	selected_items.sort()
	selected_items.reverse()
	
	var total_earned = 0
	
	for item_index in selected_items:
		# ✅ FIX: Re-fetch item keys EACH iteration (inventory may have changed)
		var current_keys = player_character.inventory.items.keys()
		
		if item_index >= current_keys.size():
			print("⚠️ Index %d out of range (only %d items), skipping" % [item_index, current_keys.size()])
			continue
		
		var item_id = current_keys[item_index]
		var item_data = player_character.inventory.items[item_id]
		var item = item_data.item
		var sell_value = item.value / 2
		
		# Add to buyback BEFORE removing
		ShopManager.add_to_buyback(item, sell_value, 1)
		
		player_character.inventory.remove_item(item_id, 1)
		player_character.currency.add(sell_value)
		total_earned += sell_value
	
	refresh_sell_items()
	refresh_shop_display()
	clear_item_info()
	
	print("Sold %d items for %d copper" % [selected_items.size(), total_earned])

func _on_sell_all_pressed():
	"""Sell all selected items (full stacks) - FIXED"""
	var selected_items = sell_item_list.get_selected_items()
	if selected_items.is_empty():
		print("No items selected")
		return
	
	# ✅ FIX: Sort indices in DESCENDING order
	selected_items.sort()
	selected_items.reverse()
	
	var total_earned = 0
	
	for item_index in selected_items:
		# ✅ FIX: Re-fetch keys EACH iteration
		var current_keys = player_character.inventory.items.keys()
		
		if item_index >= current_keys.size():
			print("⚠️ Index %d out of range (only %d items), skipping" % [item_index, current_keys.size()])
			continue
		
		var item_id = current_keys[item_index]
		var item_data = player_character.inventory.items[item_id]
		var item = item_data.item
		var quantity = item_data.quantity
		var sell_value = item.value / 2
		
		# Add to buyback BEFORE removing
		ShopManager.add_to_buyback(item, sell_value, quantity)
		
		player_character.inventory.remove_item(item_id, quantity)
		player_character.currency.add(sell_value * quantity)
		total_earned += (sell_value * quantity)
	
	refresh_sell_items()
	refresh_shop_display()
	clear_item_info()
	
	print("Sold all quantities of %d items for %d copper" % [selected_items.size(), total_earned])

func _on_exit_pressed():
	CharacterManager.save_character(player_character)
	SceneManager.change_to_town(player_character)
