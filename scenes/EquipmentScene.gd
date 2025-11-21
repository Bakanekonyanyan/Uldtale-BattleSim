# EquipmentScene.gd
extends Control
class_name EquipmentScene

var current_character: CharacterData
var selected_item: Equipment = null

@onready var inventory_list = $InventoryList
@onready var equipment_list = $EquipmentList
@onready var item_info = $ItemInfo
@onready var equip_button = $EquipButton
@onready var unequip_button = $UnequipButton
@onready var exit_button = $ExitButton

func _ready():
	current_character = CharacterManager.get_current_character()
	if not current_character:
		print("Error: No character loaded")
		return
	
	refresh_lists()
	equip_button.connect("pressed", Callable(self, "_on_equip_pressed"))
	unequip_button.connect("pressed", Callable(self, "_on_unequip_pressed"))
	inventory_list.connect("item_selected", Callable(self, "_on_inventory_item_selected"))
	equipment_list.connect("item_selected", Callable(self, "_on_equipment_item_selected"))
	exit_button.connect("pressed", Callable(self, "_on_exit_pressed"))

func set_player(character: CharacterData):
	current_character = character

func refresh_lists():
	inventory_list.clear()
	equipment_list.clear()
	
	var index = 0
	for item_id in current_character.inventory.items:
		var item_data = current_character.inventory.items[item_id]
		var item = item_data.item
		if item is Equipment:
			# Add the item with its name and rarity
			var display_name = "%s [%s]" % [item.display_name, item.rarity.capitalize()]
			inventory_list.add_item(display_name)
			
			# Set the color based on rarity
			var rarity_color = item.get_rarity_color()
			if rarity_color != "":
				inventory_list.set_item_custom_fg_color(index, Color(rarity_color))
			index += 1
	
	index = 0
	for slot in current_character.equipment:
		var item = current_character.equipment[slot]
		if item:
			equipment_list.add_item("%s: %s [%s]" % [slot, item.display_name, item.rarity.capitalize()])
			# Set the color based on rarity
			var rarity_color = item.get_rarity_color()
			if rarity_color != "":
				equipment_list.set_item_custom_fg_color(index, Color(rarity_color))
		else:
			equipment_list.add_item("%s: Empty" % slot)
		index += 1

func update_item_info(item: Equipment):
	if not item_info:
		print("Error: item_info node not found")
		return
	
	# First, let's clear out all the existing children of ItemInfo
	for child in item_info.get_children():
		child.queue_free()
	
	# Clear the text
	item_info.text = ""

	if item:
		# Use the get_full_description() method which includes all modifiers
		var full_desc = item.get_full_description()
		
		# If ItemInfo is a RichTextLabel, we can use BBCode directly
		if item_info is RichTextLabel:
			item_info.bbcode_enabled = true
			item_info.text = full_desc
			item_info.fit_content = true
			# Make sure it's visible
			item_info.visible = true
		else:
			# If it's a regular Label, we need to strip BBCode tags
			# But ideally, ItemInfo should be a RichTextLabel to show colors and formatting
			var stripped_desc = full_desc
			# Basic BBCode stripping regex (simplified)
			var regex = RegEx.new()
			regex.compile("\\[.*?\\]")
			stripped_desc = regex.sub(stripped_desc, "", true)
			item_info.text = stripped_desc
			item_info.visible = true
	else:
		item_info.text = "No equipment selected"
		item_info.visible = true

func _on_inventory_item_selected(index):
	var equipment_items = []
	for item_id in current_character.inventory.items:
		var item = current_character.inventory.items[item_id].item
		if item is Equipment:
			equipment_items.append(item)
	
	if index >= 0 and index < equipment_items.size():
		selected_item = equipment_items[index]
		update_item_info(selected_item)
		equip_button.disabled = false
		unequip_button.disabled = true
	else:
		selected_item = null
		update_item_info(null)
		equip_button.disabled = true
		unequip_button.disabled = true

func _on_equipment_item_selected(index):
	var slot = current_character.equipment.keys()[index]
	selected_item = current_character.equipment[slot]
	update_item_info(selected_item)
	equip_button.disabled = true
	unequip_button.disabled = false if selected_item else true

func _on_equip_pressed():
	if selected_item:
		current_character.equip_item(selected_item)
		refresh_lists()
		selected_item = null
		update_item_info(null)
		equip_button.disabled = true

func _on_unequip_pressed():
	if selected_item:
		current_character.unequip_item(selected_item.slot)
		refresh_lists()
		selected_item = null
		update_item_info(null)
		unequip_button.disabled = true
		
func _on_exit_pressed():
	# Save the character's updated inventory and currency
	print(SceneManager.town_scene_active)
	CharacterManager.save_character(current_character)
	# Return to the previous scene (which should be the RewardScene)
	SceneManager.return_to_previous_scene()
	
func get_equipment_from_inventory() -> Array:
	var equipment_items = []
	for item_id in current_character.inventory.items:
		var item = current_character.inventory.items[item_id].item
		if item is Equipment:
			equipment_items.append(item)
	return equipment_items
