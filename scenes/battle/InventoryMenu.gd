# res://scenes/battle/InventoryMenu.gd
#  FIXED: Proper unlock on cancel + correct currency access

extends Control

signal item_selected(item: Item, target: CharacterData)

var player: CharacterData
var enemies: Array[CharacterData] = []
var selected_item: Item = null

@onready var panel: Panel = $Panel
@onready var item_list: ItemList = $Panel/VBoxContainer/ItemList
@onready var use_button: Button = $Panel/VBoxContainer/ButtonContainer/UseButton
@onready var cancel_button: Button = $Panel/VBoxContainer/ButtonContainer/CancelButton
@onready var currency_label: Label = $CurrencyLabel

func _ready():
	if panel:
		panel.hide()
	
	if use_button:
		use_button.pressed.connect(_on_use_pressed)
	
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed)
	
	if item_list:
		item_list.item_selected.connect(_on_item_list_selected)

func show_inventory(p_player: CharacterData, p_enemies: Array[CharacterData] = []):
	"""Display inventory for item selection"""
	player = p_player
	enemies = p_enemies
	selected_item = null
	
	_populate_item_list()
	
	if panel:
		panel.show()
	
	if use_button:
		use_button.disabled = true

func hide_inventory():
	"""Hide inventory panel"""
	if panel:
		panel.hide()

func _populate_item_list():
	"""Fill item list with player's consumable items"""
	if not item_list:
		return
	
	item_list.clear()
	
	if not player or not player.inventory:
		return
	
	#  FIX: Access currency correctly from CharacterData
	if currency_label and currency_label.visible and player.currency:
		currency_label.text = "Gold: %d" % player.currency.copper
	
	# Add consumable items
	for item_id in player.inventory.items:
		var item_data = player.inventory.items[item_id]
		var item = item_data.item if item_data.has("item") else item_data
		var quantity = item_data.quantity if item_data.has("quantity") else player.inventory.items[item_id]
		
		if not item:
			continue
		
		# Only show consumable items in battle
		var item_type = _get_item_type(item)
		if item_type != Item.ItemType.CONSUMABLE:
			continue
		
		var item_name = _get_item_name(item)
		var display_text = str(item_name) + " x" + str(quantity)
		item_list.add_item(display_text)
		item_list.set_item_metadata(item_list.item_count - 1, item)

func _get_item_type(item) -> int:
	"""Safely get item type with multiple fallback methods"""
	if not item:
		return -1
	
	if "item_type" in item:
		return item.item_type
	
	if item.has_method("get"):
		var type_val = item.get("item_type")
		if type_val != null:
			return type_val
	
	if item is Item:
		return item.item_type
	
	var script = item.get_script()
	if script and script.has_script_property_default_value("item_type"):
		return item.item_type
	
	print("Warning: Could not determine item_type for item: %s" % item.name)
	return -1

func _get_item_name(item) -> String:
	"""Get item display name"""
	if not item:
		return "Unknown Item"
	
	if "display_name" in item:
		var name_val = item.display_name
		if name_val != null and name_val != "":
			return name_val
	
	if "id" in item:
		var id_val = item.id
		if id_val != null and id_val != "":
			return id_val
	
	print("Warning: Could not get display_name or id for item: %s" % str(item))
	return "Unknown Item"

func _on_item_list_selected(index: int):
	"""Item selected from list"""
	if index < 0 or index >= item_list.item_count:
		return
	
	selected_item = item_list.get_item_metadata(index)
	
	if use_button:
		use_button.disabled = (selected_item == null)

func _on_use_pressed():
	"""Check target_type and show target selector if needed"""
	if not selected_item:
		return
	
	print("InventoryMenu: Using item: %s (target_type: %s)" % [
		selected_item.display_name, 
		Item.TargetType.keys()[selected_item.target_type]
	])
	
	# Check item's target type
	match selected_item.target_type:
		Item.TargetType.SELF:
			hide_inventory()
			emit_signal("item_selected", selected_item, player)
		
		Item.TargetType.ALLY:
			hide_inventory()
			emit_signal("item_selected", selected_item, player)
		
		Item.TargetType.ENEMY:
			_show_enemy_target_selection()
		
		Item.TargetType.ALL_ENEMIES:
			hide_inventory()
			emit_signal("item_selected", selected_item, null)
		
		Item.TargetType.ALL_ALLIES:
			hide_inventory()
			emit_signal("item_selected", selected_item, player)

func _show_enemy_target_selection():
	"""Show target selector for enemy-targeted items"""
	var ui_controller = get_parent()
	
	if not ui_controller or not ui_controller.has_method("show_target_selection"):
		push_error("InventoryMenu: Cannot access target selector!")
		hide_inventory()
		#  FIX: Unlock UI on error
		_unlock_ui_controller()
		return
	
	# Get living enemies
	var living_enemies: Array[CharacterData] = []
	for enemy in enemies:
		if enemy.is_alive():
			living_enemies.append(enemy)
	
	if living_enemies.is_empty():
		print("InventoryMenu: No valid enemy targets!")
		hide_inventory()
		if ui_controller.has_method("add_combat_log"):
			ui_controller.add_combat_log("No valid targets for this item!", "red")
		#  FIX: Unlock UI when no targets
		_unlock_ui_controller()
		return
	
	# Hide inventory before showing target selector
	hide_inventory()
	
	# Show target selector
	ui_controller.show_target_selection(
		living_enemies,
		func(target: CharacterData):
			print("InventoryMenu: Enemy target selected: %s" % target.name)
			emit_signal("item_selected", selected_item, target),
		func():
			print("InventoryMenu: Target selection cancelled")
			# Re-show inventory if cancelled
			show_inventory(player, enemies)
	)

func _on_cancel_pressed():
	"""Cancel button pressed"""
	hide_inventory()
	
	#  FIX: Always unlock UI when cancelled
	_unlock_ui_controller()

func _unlock_ui_controller():
	"""Helper to unlock parent UI controller"""
	var ui_controller = get_parent()
	if ui_controller and ui_controller.has_method("unlock_ui"):
		ui_controller.unlock_ui()
		ui_controller.enable_actions()
