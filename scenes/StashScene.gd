# res://scenes/StashScene.gd
extends Control

enum ItemCategory { ALL, CONSUMABLES, WEAPONS, ARMOR, MATERIALS }

var player_character: CharacterData
var current_category: ItemCategory = ItemCategory.ALL

@onready var inventory_list = $InventoryList
@onready var stash_list = $StashList
@onready var move_to_stash_button = $MoveToStashButton
@onready var move_all_to_stash_button = $MoveAllToStashButton
@onready var move_to_inventory_button = $MoveToInventoryButton
@onready var move_all_to_inventory_button = $MoveAllToInventoryButton
@onready var back_button = $BackButton
@onready var inventory_capacity_label = $InventoryCapacityLabel
@onready var stash_capacity_label = $StashCapacityLabel
@onready var item_info_label = $ItemInfoLabel

# ✅ NEW: Tab buttons (created programmatically)
var tab_container: HBoxContainer
var all_tab: Button
var consumables_tab: Button
var weapons_tab: Button
var armor_tab: Button
var materials_tab: Button

func _ready():
	player_character = CharacterManager.get_current_character()
	if not player_character:
		print("Whoops! No character loaded.")
		return
	
	setup_tabs()
	refresh_lists()
	
	move_to_stash_button.connect("pressed", Callable(self, "_on_move_to_stash_pressed"))
	move_all_to_stash_button.connect("pressed", Callable(self, "_on_move_all_to_stash_pressed"))
	move_to_inventory_button.connect("pressed", Callable(self, "_on_move_to_inventory_pressed"))
	move_all_to_inventory_button.connect("pressed", Callable(self, "_on_move_all_to_inventory_pressed"))
	back_button.connect("pressed", Callable(self, "_on_back_pressed"))

func setup_tabs():
	"""Setup category filter tabs programmatically"""
	tab_container = HBoxContainer.new()
	tab_container.position = Vector2(56, 8)
	
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
	weapons_tab.custom_minimum_size = Vector2(80, 32)
	weapons_tab.pressed.connect(func(): _on_category_changed(ItemCategory.WEAPONS))
	tab_container.add_child(weapons_tab)
	
	armor_tab = Button.new()
	armor_tab.text = "Armor"
	armor_tab.custom_minimum_size = Vector2(80, 32)
	armor_tab.pressed.connect(func(): _on_category_changed(ItemCategory.ARMOR))
	tab_container.add_child(armor_tab)
	
	materials_tab = Button.new()
	materials_tab.text = "Materials"
	materials_tab.custom_minimum_size = Vector2(80, 32)
	materials_tab.pressed.connect(func(): _on_category_changed(ItemCategory.MATERIALS))
	tab_container.add_child(materials_tab)
	
	add_child(tab_container)
	
	_update_tab_visuals()

func _on_category_changed(category: ItemCategory):
	"""Switch to different category"""
	current_category = category
	_update_tab_visuals()
	refresh_lists()

func _update_tab_visuals():
	"""Highlight active tab"""
	var tabs = [all_tab, consumables_tab, weapons_tab, armor_tab, materials_tab]
	for i in range(tabs.size()):
		if tabs[i]:
			if i == current_category:
				tabs[i].modulate = Color(1.2, 1.2, 0.8)  # Highlighted
			else:
				tabs[i].modulate = Color(1, 1, 1)  # Normal

func _matches_category(item: Item) -> bool:
	"""Check if item matches current category filter"""
	match current_category:
		ItemCategory.ALL:
			return true
		ItemCategory.CONSUMABLES:
			return item.item_type == Item.ItemType.CONSUMABLE
		ItemCategory.WEAPONS:
			# ✅ Weapons = main_hand or off_hand slots
			if item is Equipment:
				return item.slot in ["main_hand", "off_hand"]
			return false
		ItemCategory.ARMOR:
			# ✅ Armor = head, chest, hands, legs, feet slots
			if item is Equipment:
				return item.slot in ["head", "chest", "hands", "legs", "feet"]
			return false
		ItemCategory.MATERIALS:
			return item.item_type == Item.ItemType.MATERIAL
	return false

func refresh_lists():
	inventory_list.clear()
	stash_list.clear()
	
	# Build filtered inventory list
	var inv_items = _get_filtered_items_from(player_character.inventory)
	for i in range(inv_items.size()):
		var item = inv_items[i]
		var item_data = player_character.inventory.items[item.get("key")]
		
		if item_data.item is Equipment:
			var equip = item_data.item
			var display_name = "%s (x%d) [%s]" % [equip.name, item_data.quantity, equip.rarity.capitalize()]
			inventory_list.add_item(display_name)
			var rarity_color = Color(equip.get_rarity_color())
			inventory_list.set_item_custom_fg_color(i, rarity_color)
		else:
			inventory_list.add_item("%s (x%d)" % [item_data.item.name, item_data.quantity])
	
	# Build filtered stash list
	var stash_items = _get_filtered_items_from(player_character.stash)
	for i in range(stash_items.size()):
		var item = stash_items[i]
		var item_data = player_character.stash.items[item.get("key")]
		
		if item_data.item is Equipment:
			var equip = item_data.item
			var display_name = "%s (x%d) [%s]" % [equip.name, item_data.quantity, equip.rarity.capitalize()]
			stash_list.add_item(display_name)
			var rarity_color = Color(equip.get_rarity_color())
			stash_list.set_item_custom_fg_color(i, rarity_color)
		else:
			stash_list.add_item("%s (x%d)" % [item_data.item.name, item_data.quantity])
	
	update_capacity_labels()

func _get_filtered_items_from(source: Inventory) -> Array:
	"""Get items matching current filter from inventory/stash"""
	var filtered = []
	for item_id in source.items:
		var item_data = source.items[item_id]
		var item = item_data.item
		
		if _matches_category(item):
			filtered.append({"key": item_id, "item": item})
	
	return filtered

func update_capacity_labels():
	if inventory_capacity_label:
		var inv_size = player_character.inventory.items.size()
		var inv_cap = player_character.inventory.capacity
		inventory_capacity_label.text = "Inventory: %d/%d" % [inv_size, inv_cap]
	
	if stash_capacity_label:
		var stash_size = player_character.stash.items.size()
		var stash_cap = player_character.stash.capacity
		stash_capacity_label.text = "Stash: %d/%d" % [stash_size, stash_cap]

func _on_move_to_stash_pressed():
	var selected_items = inventory_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		
		# Get filtered item list to find correct item_id
		var filtered_items = _get_filtered_items_from(player_character.inventory)
		if item_index >= filtered_items.size():
			return
		
		var item_id = filtered_items[item_index].get("key")
		var item = player_character.inventory.items[item_id].item
		
		player_character.inventory.remove_item(item_id, 1)
		player_character.stash.add_item(item, 1)
		refresh_lists()

func _on_move_all_to_stash_pressed():
	var selected_items = inventory_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		
		var filtered_items = _get_filtered_items_from(player_character.inventory)
		if item_index >= filtered_items.size():
			return
		
		var item_id = filtered_items[item_index].get("key")
		var item_data = player_character.inventory.items[item_id]
		var item = item_data.item
		var quantity = item_data.quantity
		
		player_character.inventory.remove_item(item_id, quantity)
		player_character.stash.add_item(item, quantity)
		refresh_lists()

func _on_move_to_inventory_pressed():
	var selected_items = stash_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		
		var filtered_items = _get_filtered_items_from(player_character.stash)
		if item_index >= filtered_items.size():
			return
		
		var item_id = filtered_items[item_index].get("key")
		var item = player_character.stash.items[item_id].item
		
		player_character.stash.remove_item(item_id, 1)
		player_character.inventory.add_item(item, 1)
		refresh_lists()

func _on_move_all_to_inventory_pressed():
	var selected_items = stash_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		
		var filtered_items = _get_filtered_items_from(player_character.stash)
		if item_index >= filtered_items.size():
			return
		
		var item_id = filtered_items[item_index].get("key")
		var item_data = player_character.stash.items[item_id]
		var item = item_data.item
		var quantity = item_data.quantity
		
		player_character.stash.remove_item(item_id, quantity)
		player_character.inventory.add_item(item, quantity)
		refresh_lists()

func _on_back_pressed():
	SaveManager.save_game(player_character)
	SceneManager.change_to_town(player_character)

func _on_item_selected(index):
	print("Item Slected")
	# Get the selected item from filtered list
	var filtered_items = _get_filtered_items_from(player_character.inventory)
	if index >= 0 and index < filtered_items.size():
		display_item_info(filtered_items[index])
		
func display_item_info(item: Item):
	if not item_info_label:
		return
	
	var info_text = ""
	
	if item_info_label is RichTextLabel:
		item_info_label.bbcode_enabled = true
		
		# Show full equipment description or item description
		if item is Equipment:
			info_text = item.get_full_description()
		else:
			info_text = "[b]%s[/b]\n\n%s\n\n" % [item.name, item.description]
			
			if item.item_type == Item.ItemType.CONSUMABLE:
				info_text += "[color=cyan][b]Effect:[/b][/color]\n"
				
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
		
		item_info_label.text = info_text
	else:
		info_text = "%s\n\n%s" % [item.name, item.description]
		item_info_label.text = info_text
