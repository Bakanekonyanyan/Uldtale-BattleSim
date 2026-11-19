# res://scenes/ShopScene.gd - ENHANCED UX/UI
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
var buyback_tab: Button

func _ready():
	Log.debug("shop", "ShopScene: _ready called")
	
	# Enable multi-select
	if item_list:
		item_list.select_mode = ItemList.SELECT_MULTI
	if sell_item_list:
		sell_item_list.select_mode = ItemList.SELECT_MULTI
	
	setup_tabs()
	
	if not buy_button.pressed.is_connected(_on_buy_pressed):
		buy_button.pressed.connect(_on_buy_pressed)
	if exit_button:
		exit_button.pressed.connect(_on_exit_pressed)
	if item_list:
		item_list.item_clicked.connect(_on_shop_item_clicked)
	if sell_button:
		sell_button.text = "Sell Selected"
		sell_button.pressed.connect(_on_sell_pressed)
	if sell_all_button:
		sell_all_button.text = "Sell Whole Stacks"
		sell_all_button.pressed.connect(_on_sell_all_pressed)
	if sell_item_list:
		sell_item_list.item_clicked.connect(_on_sell_item_clicked)
	
	player_character = CharacterManager.get_current_character()
	if player_character == null:
		Log.debug("shop", "Error: No character selected")
		SceneManager.change_to_character_selection()
		return
	
	# Update buyback based on current floor
	ShopManager.clear_buyback_on_floor_change(player_character.current_floor)
	
	_apply_chrome()
	refresh_shop_display()
	refresh_sell_items()
	clear_item_info()
	
	Log.debug("shop", "ShopScene: Multi-select enabled")

var chrome: ScreenChrome

func _apply_chrome():
	chrome = ScreenChrome.attach(self, "Shop", _on_exit_pressed)
	exit_button.visible = false
	player_currency_label.visible = false
	ScreenChrome.tab_row(tab_container, Rect2(32, 72, 440, 36))
	var for_sale = $UI/ShopLabel
	for_sale.text = "For Sale"
	ScreenChrome.place(for_sale, Rect2(32, 114, 440, 24))
	for_sale.add_theme_color_override("font_color", ScreenChrome.MUTED)
	ScreenChrome.place(item_list, Rect2(32, 140, 440, 220))
	var pack_label = $UI/InventoryLabel
	pack_label.text = "Your Pack (sells for half value)"
	ScreenChrome.place(pack_label, Rect2(32, 372, 440, 24))
	pack_label.add_theme_color_override("font_color", ScreenChrome.MUTED)
	ScreenChrome.place(sell_item_list, Rect2(32, 398, 440, 226))
	ScreenChrome.place(item_info_label, Rect2(496, 72, 672, 488))
	item_info_label.bbcode_enabled = true
	ScreenChrome.place(buy_button, Rect2(496, 576, 200, 44))
	ScreenChrome.place(sell_button, Rect2(712, 576, 200, 44))
	ScreenChrome.place(sell_all_button, Rect2(928, 576, 240, 44))
	chrome.set_info(ScreenChrome.money_text(player_character))

func setup_tabs():
	"""Setup category tabs with enhanced visuals"""
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
	"""Enhanced tab highlighting with background colors and borders"""
	ScreenChrome.set_active_tab([all_tab, consumables_tab, weapons_tab, armor_tab, buyback_tab], current_category)

func refresh_shop_display():
	"""Refresh shop items with enhanced formatting"""
	if item_list:
		item_list.clear()
		
		var index = 0
		
		# Show buyback items if buyback tab selected
		if current_category == ItemCategory.BUYBACK:
			var buyback_items = ShopManager.get_buyback_list()
			
			if buyback_items.is_empty():
				# Add placeholder message
				item_list.add_item("No items to buyback")
				item_list.set_item_disabled(0, true)
				item_list.set_item_custom_fg_color(0, Color(0.5, 0.5, 0.5))
			else:
				for buyback_data in buyback_items:
					var item = buyback_data["item"]
					var price = buyback_data["price"]
					var quantity = buyback_data["quantity"]
					
					var display_text = _format_shop_item(item, price, quantity)
					item_list.add_item(display_text)
					
					if item is Equipment:
						var rarity_color = ScreenChrome.rarity_color(item)
						item_list.set_item_custom_fg_color(index, rarity_color)
					
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
						var display_text = _format_shop_item(item, price)
						item_list.add_item(display_text)
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
						var display_text = _format_shop_item(equipment, price)
						item_list.add_item(display_text)
						
						var rarity_color = ScreenChrome.rarity_color(equipment)
						item_list.set_item_custom_fg_color(index, rarity_color)
						
						item_list.set_item_metadata(index, {
							"type": "equipment",
							"key": key,
							"item": equipment,
							"price": price
						})
						index += 1
	
	if player_currency_label and player_character:
		# Enhanced currency display with icon
		var copper = player_character.currency.copper
		var color = "#FFD700"  # Gold
		
		if copper < 100:
			color = "#FF6666"  # Red if low
		elif copper < 500:
			color = "#FFAA44"  # Orange if medium
		
		if chrome:
			chrome.set_info(ScreenChrome.money_text(player_character))
		player_currency_label.text = "[color=%s] Your Gold: %s[/color]" % [
			color,
			player_character.currency.get_formatted()
		]

func _format_shop_item(item: Item, price: int, quantity: int = 1) -> String:
	"""Format shop item display for better readability"""
	return ScreenChrome.item_row(item, quantity, price)

func refresh_sell_items():
	"""Refresh sell items with enhanced formatting"""
	if sell_item_list:
		sell_item_list.clear()
		var index = 0
		
		if player_character.inventory.items.is_empty():
			# Add placeholder message
			sell_item_list.add_item("Your inventory is empty")
			sell_item_list.set_item_disabled(0, true)
			sell_item_list.set_item_custom_fg_color(0, Color(0.5, 0.5, 0.5))
		else:
			for item_id in player_character.inventory.items:
				var item_data = player_character.inventory.items[item_id]
				var item = item_data.item
				
				if item:
					var sell_value = item.value / 2
					var display_text = _format_sell_item(item, sell_value, item_data.quantity)
					sell_item_list.add_item(display_text)
					
					if item is Equipment:
						var rarity_color = ScreenChrome.rarity_color(item)
						sell_item_list.set_item_custom_fg_color(index, rarity_color)
					
					index += 1

func _format_sell_item(item: Item, sell_value: int, quantity: int) -> String:
	"""Format sell item display for better readability"""
	return ScreenChrome.item_row(item, quantity, sell_value)

func _on_shop_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int):
	var metadata = item_list.get_item_metadata(index)
	if not metadata:
		return
	
	var item = metadata["item"]
	var price = metadata["price"]
	
	Log.debug("shop", "Shop item selected: %s" % item.display_name)
	display_item_info(item, price, true)

func _on_sell_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int):
	var item_id = player_character.inventory.items.keys()[index]
	var item = player_character.inventory.items[item_id].item
	
	display_item_info(item, item.value / 2, false)

func display_item_info(item: Item, price: int, is_buying: bool):
	"""Enhanced item info display"""
	if not item_info_label:
		return
	
	var info_text = ""
	
	if item_info_label is RichTextLabel:
		item_info_label.bbcode_enabled = true
		
		if item is Equipment:
			info_text = item.get_full_description()
			info_text += "\n\n"
		else:
			info_text = "[center][b][color=#FFD700]%s[/color][/b][/center]\n" % item.display_name
			info_text += "[color=#CCCCCC]%s[/color]\n\n" % item.description
			
			if item.item_type == Item.ItemType.CONSUMABLE:
				info_text += "[color=#00DDFF][b]EFFECT [/b][/color]\n"
				
				match item.consumable_type:
					Item.ConsumableType.DAMAGE:
						info_text += "[color=#FF6666] Deals %d damage[/color]\n" % item.effect_power
						if item.status_effect != Skill.StatusEffect.NONE:
							var effect_name = Skill.StatusEffect.keys()[item.status_effect]
							info_text += "[color=#BB88FF]Inflicts %s for %d turns[/color]\n" % [effect_name, item.effect_duration]
					Item.ConsumableType.HEAL:
						info_text += "[color=#66FF66] Restores %d HP[/color]\n" % item.effect_power
					Item.ConsumableType.RESTORE:
						info_text += "[color=#6666FF] Restores %d MP/SP[/color]\n" % item.effect_power
					Item.ConsumableType.BUFF:
						info_text += "[color=#FFDD66] Increases %s by %d for %d turns[/color]\n" % [item.buff_type, item.effect_power, item.effect_duration]
					Item.ConsumableType.CURE:
						info_text += "[color=#66FFDD] Cures all status effects[/color]\n"
						if item.effect_power > 0:
							info_text += "[color=#66FF66] Restores %d HP[/color]\n" % item.effect_power
				
				info_text += "\n"
		
		# Show price with appropriate color
		if is_buying:
			var can_afford = player_character.currency.copper >= price
			var price_color = "#00FF00" if can_afford else "#FF4444"
			info_text += "[color=%s] Buy Price: %d copper[/color]" % [price_color, price]
		else:
			info_text += "[color=#FFD700] Sell Price: %d copper[/color]" % price
		
		item_info_label.text = info_text
	else:
		info_text = "%s\n\n%s\n\n" % [item.display_name, item.description]
		if is_buying:
			info_text += "Buy Price: %d copper" % price
		else:
			info_text += "Sell Price: %d copper" % price
		item_info_label.text = info_text

func clear_item_info():
	"""Enhanced empty state message"""
	if item_info_label:
		var empty_message = "[center][color=#888888][i]"
		
		match current_category:
			ItemCategory.BUYBACK:
				empty_message += "Select an item to buyback\n\n[color=#FFAA44]Tip: Items you sell are added here[/color]"
			_:
				empty_message += "Select an item to view details and pricing"
		
		empty_message += "[/i][/color][/center]"
		item_info_label.text = empty_message

func _on_buy_pressed():
	"""Batch buy selected items"""
	var selected_items = item_list.get_selected_items()
	if selected_items.is_empty():
		return
	
	# Cache metadata BEFORE processing
	var items_to_buy = []
	var total_cost = 0
	
	for item_index in selected_items:
		var metadata = item_list.get_item_metadata(item_index)
		if metadata:
			items_to_buy.append(metadata)
			total_cost += metadata["price"]
	
	# Check if player can afford
	if player_character.currency.copper < total_cost:
		Log.debug("shop", "Not enough gold!")
		var dialog = AcceptDialog.new()
		dialog.dialog_text = "[color=#FF4444]Not enough gold![/color]\n\nNeed: %d copper\nHave: %d copper" % [total_cost, player_character.currency.copper]
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
			player_character.add_to_pack(item, 1)  # over the carry limit -> stash
			Log.debug("shop", "ShopScene: Purchased consumable: %s" % item.display_name)
		
		elif item_data["type"] == "equipment":
			var equipment = item_data["item"]
			var key = item_data["key"]
			var price = item_data["price"]
			
			player_character.currency.subtract(price)
			player_character.inventory.add_item(equipment, 1)
			ShopManager.purchase_equipment(key)
			Log.debug("shop", "ShopScene: Purchased equipment: %s" % equipment.display_name)
		
		elif item_data["type"] == "buyback":
			var item = item_data["item"]
			var key = item_data["key"]
			var price = item_data["price"]
			
			var result = ShopManager.buyback_item(key, 1)
			if result["success"]:
				player_character.currency.subtract(price)
				player_character.add_to_pack(result["item"], result["quantity"])
				Log.debug("shop", "ShopScene: Bought back: %s" % item.display_name)
	
	refresh_shop_display()
	refresh_sell_items()
	clear_item_info()
	
	Log.debug("shop", "Purchased %d items for %d copper" % [items_to_buy.size(), total_cost])

func _on_sell_pressed():
	"""Sell selected items (one of each) - FIXED"""
	var selected_items = sell_item_list.get_selected_items()
	if selected_items.is_empty():
		Log.debug("shop", "No items selected")
		return
	
	# Sort indices in DESCENDING order to avoid index shifting
	selected_items.sort()
	selected_items.reverse()
	
	var total_earned = 0
	
	for item_index in selected_items:
		# Re-fetch item keys EACH iteration
		var current_keys = player_character.inventory.items.keys()
		
		if item_index >= current_keys.size():
			Log.debug("shop", "Index %d out of range, skipping" % item_index)
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
	
	Log.debug("shop", "Sold %d items for %d copper" % [selected_items.size(), total_earned])

func _on_sell_all_pressed():
	"""Sell all selected items (full stacks) - FIXED"""
	var selected_items = sell_item_list.get_selected_items()
	if selected_items.is_empty():
		Log.debug("shop", "No items selected")
		return
	
	# Sort indices in DESCENDING order
	selected_items.sort()
	selected_items.reverse()
	
	var total_earned = 0
	
	for item_index in selected_items:
		# Re-fetch keys EACH iteration
		var current_keys = player_character.inventory.items.keys()
		
		if item_index >= current_keys.size():
			Log.debug("shop", "Index %d out of range, skipping" % item_index)
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
	
	Log.debug("shop", "Sold all quantities of %d items for %d copper" % [selected_items.size(), total_earned])

func _on_exit_pressed():
	CharacterManager.save_character(player_character)
	SceneManager.change_to_town(player_character)
