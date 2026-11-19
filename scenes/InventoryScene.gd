# scenes/InventoryScene.gd - ENHANCED UX/UI
extends Control

enum ItemCategory { ALL, CONSUMABLES, WEAPONS, ARMOR, MATERIALS }

var player_character: CharacterData
var current_category: ItemCategory = ItemCategory.ALL

@onready var item_list = $UI/ItemList
@onready var use_button = $UI/UseButton
@onready var back_button = $UI/BackButton
@onready var capacity_label = $UI/CapacityLabel
@onready var item_info_label = $UI/ItemInfoLabel

# Category tab buttons
@onready var tab_container = $UI/TabContainer
@onready var all_tab = $UI/TabContainer/AllTab
@onready var consumables_tab = $UI/TabContainer/ConsumablesTab
@onready var weapons_tab = $UI/TabContainer/WeaponsTab
@onready var armor_tab = $UI/TabContainer/ArmorTab
@onready var materials_tab = $UI/TabContainer/MaterialsTab

func _ready():
	player_character = CharacterManager.get_current_character()
	if not player_character:
		Log.debug("inventory", "Oops! No character loaded.")
		return
	
	_apply_chrome()
	setup_tabs()
	refresh_inventory()
	
	use_button.pressed.connect(_on_use_pressed)
	back_button.pressed.connect(_on_back_pressed)
	item_list.item_selected.connect(_on_item_selected)
	
	clear_item_info()

var chrome: ScreenChrome

func _apply_chrome():
	chrome = ScreenChrome.attach(self, "Inventory", _on_back_pressed, "Back")
	back_button.visible = false
	ScreenChrome.tab_row(tab_container, Rect2(32, 72, 440, 36))
	ScreenChrome.place(item_list, ScreenChrome.LIST_RECT)
	ScreenChrome.place(item_info_label, ScreenChrome.DETAIL_RECT)
	ScreenChrome.place(capacity_label, Rect2(32, 650, 440, 32))
	ScreenChrome.place(use_button, Rect2(496, 640, 160, 48))
	item_info_label.bbcode_enabled = true
	chrome.set_info(ScreenChrome.money_text(player_character))

func setup_tabs():
	"""Setup category filter tabs with enhanced visuals"""
	if all_tab:
		all_tab.pressed.connect(_on_category_changed.bind(ItemCategory.ALL))
	if consumables_tab:
		consumables_tab.pressed.connect(_on_category_changed.bind(ItemCategory.CONSUMABLES))
	if weapons_tab:
		weapons_tab.pressed.connect(_on_category_changed.bind(ItemCategory.WEAPONS))
	if armor_tab:
		armor_tab.pressed.connect(_on_category_changed.bind(ItemCategory.ARMOR))
	if materials_tab:
		materials_tab.pressed.connect(_on_category_changed.bind(ItemCategory.MATERIALS))
	
	_update_tab_visuals()

func _on_category_changed(category: ItemCategory):
	"""Switch to different category"""
	current_category = category
	_update_tab_visuals()
	refresh_inventory()
	clear_item_info()

func _update_tab_visuals():
	"""Enhanced tab highlighting with background colors"""
	ScreenChrome.set_active_tab([all_tab, consumables_tab, weapons_tab, armor_tab, materials_tab], current_category)

func refresh_inventory():
	"""Refresh item list with enhanced formatting"""
	item_list.clear()
	var index = 0
	
	for item_id in player_character.inventory.items:
		var item_data = player_character.inventory.items[item_id]
		var item = item_data.item
		
		# Filter by category
		if not _matches_category(item):
			continue
		
		# Enhanced display text with better formatting
		var display_text = _format_item_display(item, item_data.quantity)
		
		# Add to list
		ScreenChrome.add_item_row(item_list, item, item_data.quantity)
		
		index += 1
	
	update_capacity_display()
	clear_item_info()

func _format_item_display(item: Item, quantity: int) -> String:
	"""Format item display text for better readability"""
	return ScreenChrome.item_row(item, quantity)

func _matches_category(item: Item) -> bool:
	"""Check if item matches current category filter"""
	match current_category:
		ItemCategory.ALL:
			return true
		ItemCategory.CONSUMABLES:
			return item.item_type == Item.ItemType.CONSUMABLE
		ItemCategory.WEAPONS:
			if item is Equipment:
				return item.slot in ["main_hand", "off_hand"]
			return false
		ItemCategory.ARMOR:
			if item is Equipment:
				return item.slot in ["head", "chest", "hands", "legs", "feet"]
			return false
		ItemCategory.MATERIALS:
			return item.item_type == Item.ItemType.MATERIAL
	return false

func update_capacity_display():
	"""Enhanced capacity display with color-coded fullness"""
	if capacity_label:
		var current = player_character.inventory.items.size()
		var max_cap = player_character.inventory.capacity
		
		# Calculate fullness percentage
		var fullness = float(current) / float(max_cap)
		var color = "#FFFFFF"
		var status_icon = ""
		
		if fullness >= 0.95:
			color = "#FF4444"  # Red - Critical
			status_icon = ""
		elif fullness >= 0.8:
			color = "#FF8800"  # Orange - Warning
			status_icon = ""
		elif fullness >= 0.6:
			color = "#FFDD44"  # Yellow - Caution
		else:
			color = "#88FF88"  # Green - Good
		
		# Show category count
		var filtered_count = item_list.get_item_count()
		if current_category == ItemCategory.ALL:
			capacity_label.text = "%s[color=%s]Inventory: %d/%d[/color]" % [
				status_icon, color, current, max_cap
			]
		else:
			var category_name = _get_category_name()
			capacity_label.text = "[color=%s]%s: %d  |  Total: %s%d/%d[/color]" % [
				color, category_name, filtered_count, status_icon, current, max_cap
			]

func _get_category_name() -> String:
	match current_category:
		ItemCategory.CONSUMABLES: return "Consumables"
		ItemCategory.WEAPONS: return "Weapons"
		ItemCategory.ARMOR: return "Armor"
		ItemCategory.MATERIALS: return "Materials"
	return "All Items"

func _on_item_selected(index):
	use_button.disabled = false
	
	# Get the selected item from filtered list
	var filtered_items = _get_filtered_items()
	
	if index >= 0 and index < filtered_items.size():
		display_item_info(filtered_items[index])

func _get_filtered_items() -> Array:
	"""Get items matching current filter"""
	var filtered = []
	for item_id in player_character.inventory.items:
		var item = player_character.inventory.items[item_id].item
		if _matches_category(item):
			filtered.append(item)
	return filtered

func display_item_info(item: Item):
	"""Enhanced item info display with better formatting"""
	if not item_info_label:
		return
	
	var info_text = ""
	
	if item_info_label is RichTextLabel:
		item_info_label.bbcode_enabled = true
		
		# Show full equipment description or item description
		if item is Equipment:
			info_text = item.get_full_description()
		else:
			# Enhanced non-equipment display
			info_text = "[center][b][color=#FFD700]%s[/color][/b][/center]\n" % item.display_name
			info_text += "[color=#CCCCCC]%s[/color]\n\n" % item.description
			
			if item.item_type == Item.ItemType.CONSUMABLE:
				info_text += "[color=#00DDFF][b]EFFECT [/b][/color]\n"
				
				match item.consumable_type:
					Item.ConsumableType.DAMAGE:
						info_text += "[color=#FF6666]Deals %d damage[/color]\n" % item.effect_power
						if item.status_effect != Skill.StatusEffect.NONE:
							var effect_name = Skill.StatusEffect.keys()[item.status_effect]
							info_text += "[color=#BB88FF]Inflicts %s for %d turns[/color]\n" % [effect_name, item.effect_duration]
					Item.ConsumableType.HEAL:
						info_text += "[color=#66FF66]Restores %d HP[/color]\n" % item.effect_power
					Item.ConsumableType.RESTORE:
						info_text += "[color=#6666FF]Restores %d MP/SP[/color]\n" % item.effect_power
					Item.ConsumableType.BUFF:
						info_text += "[color=#FFDD66]Increases %s by %d for %d turns[/color]\n" % [item.buff_type, item.effect_power, item.effect_duration]
					Item.ConsumableType.CURE:
						info_text += "[color=#66FFDD]Cures all status effects[/color]\n"
						if item.effect_power > 0:
							info_text += "[color=#66FF66]Restores %d HP[/color]\n" % item.effect_power
			
			# Show value
			if item.value > 0:
				info_text += "\n[color=#FFD700]Value: %d copper[/color]" % item.value
		
		item_info_label.text = info_text
	else:
		info_text = "%s\n\n%s" % [item.display_name, item.description]
		item_info_label.text = info_text

func clear_item_info():
	"""Enhanced empty state message"""
	if item_info_label:
		var empty_message = "[center][color=#888888][i]"
		
		match current_category:
			ItemCategory.ALL:
				empty_message += "Select an item to view details"
			ItemCategory.CONSUMABLES:
				empty_message += "Select a consumable to view its effects"
			ItemCategory.WEAPONS:
				empty_message += "Select a weapon to view its stats"
			ItemCategory.ARMOR:
				empty_message += "Select armor to view its protection"
			ItemCategory.MATERIALS:
				empty_message += "Select a material to view its properties"
		
		empty_message += "[/i][/color][/center]"
		item_info_label.text = empty_message

func _on_use_pressed():
	var selected_items = item_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		
		# Get filtered items
		var filtered_items = _get_filtered_items()
		if item_index >= filtered_items.size():
			Log.debug("inventory", "Invalid item selection")
			return
		
		var item = filtered_items[item_index]
		var item_id = item.id if not (item is Equipment) else item.inventory_key
		
		# Check if item is consumable
		if item.item_type != Item.ItemType.CONSUMABLE:
			Log.debug("inventory", "Can only use consumable items outside combat")
			return
		
		# Check quantity
		if not player_character.inventory.items.has(item_id):
			Log.debug("inventory", "Item not found in inventory")
			refresh_inventory()
			return
		
		var item_data = player_character.inventory.items[item_id]
		if item_data.quantity <= 0:
			Log.debug("inventory", "No quantity remaining")
			refresh_inventory()
			return
		
		Log.debug("inventory", "Using item outside combat: %s (Quantity: %d)" % [item.display_name, item_data.quantity])
		
		# Use the item
		var result = item.use(player_character, [player_character])
		
		# Remove one from inventory
		var removed = player_character.inventory.remove_item(item_id, 1)
		if removed:
			Log.debug("inventory", "Item used successfully: ", result)
		else:
			Log.debug("inventory", "ERROR: Failed to remove item!")
		
		refresh_inventory()

func _on_back_pressed():
	CharacterManager.save_character(player_character)
	SceneManager.return_to_previous_scene()
