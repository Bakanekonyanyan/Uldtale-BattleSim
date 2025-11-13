# res://scripts/autoload/ItemManager.gd
# ItemManager.gd
extends Node

var items = {}
var weapons = {}
var armors = {}
var consumables = {}
var materials = {}
# NEW: Separate templates from instances
var equipment_templates = {}  # Base templates (never modified)

func _ready():
	load_consumables()
	load_materials()
	load_weapons()
	load_armors()
	update_items()
	print("Loaded items: ", items.keys())
	print("Loaded consumables: ", consumables.keys())
	print("Loaded materials: ", materials.keys())
	print("Loaded weapons: ", weapons.keys())
	print("Loaded armors: ", armors.keys())

func load_consumables():
	var file = FileAccess.open("res://data/items/consumables.json", FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	
	for item_id in json:
		consumables[item_id] = Item.create_from_dict(item_id, json[item_id])

func load_materials():
	var file = FileAccess.open("res://data/items/materials.json", FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	
	for item_id in json:
		materials[item_id] = Item.create_from_dict(item_id, json[item_id])

func load_weapons():
	var file = FileAccess.open("res://data/items/weapons.json", FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	
	for hand_type in json:
		for weapon_category in json[hand_type]:
			for weapon_id in json[hand_type][weapon_category]:
				if weapon_id != "rarity":
					var weapon_data = json[hand_type][weapon_category][weapon_id]
					if typeof(weapon_data) == TYPE_DICTIONARY:
						weapon_data["id"] = weapon_id
						# Store as template (never modified)
						equipment_templates[weapon_id] = weapon_data
						# Don't create Equipment instance yet
						weapons[weapon_id] = weapon_data

func load_armors():
	var file = FileAccess.open("res://data/items/armors.json", FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	
	for armor_type in json:
		for slot in json[armor_type]:
			for armor_id in json[armor_type][slot]:
				var armor_data = json[armor_type][slot][armor_id]
				armor_data["id"] = armor_id
				equipment_templates[armor_id] = armor_data
				armors[armor_id] = armor_data

func create_equipment_instance(item_id: String) -> Equipment:
	"""Creates a NEW equipment instance with fresh random rolls"""
	if not equipment_templates.has(item_id):
		return null
	
	# Create NEW instance from template data
	var template_data = equipment_templates[item_id].duplicate(true)
	
	# CRITICAL: Mark as NEW (no rarity pre-assigned)
	template_data.erase("rarity")
	template_data.erase("rarity_applied")
	template_data.erase("stat_modifiers")
	
	# This will trigger full generation in Equipment._init()
	return Equipment.new(template_data)

func get_equipment_template(item_id: String) -> Dictionary:
	"""Get base template data (for display/info only)"""
	return equipment_templates.get(item_id, {})

func update_items():
	items.clear()
	items.merge(consumables)
	items.merge(materials)
	items.merge(weapons)
	items.merge(armors)

func get_all_items() -> Dictionary:
	return items

func get_random_consumable() -> String:
	if consumables.size() > 0:
		return consumables.keys()[randi() % consumables.size()]
	return ""

func get_random_material() -> String:
	if materials.size() > 0:
		return materials.keys()[randi() % materials.size()]
	return ""
	
func get_random_weapon(category: String = "") -> String:
	if weapons.size() > 0:
		var available_weapons = weapons.keys()
		if category != "":
			available_weapons = available_weapons.filter(func(weapon_id): return weapons[weapon_id].type == category)
		
		if available_weapons.size() > 0:
			return available_weapons[randi() % available_weapons.size()]
	return ""

func get_random_armor(type: String = "", slot: String = "") -> String:
	if armors.size() > 0:
		var available_armors = armors.keys()
		if type != "":
			available_armors = available_armors.filter(func(armor_id): return armors[armor_id].type == type)
		if slot != "":
			available_armors = available_armors.filter(func(armor_id): return armors[armor_id].slot == slot)
		
		if available_armors.size() > 0:
			return available_armors[randi() % available_armors.size()]
	return ""

func get_random_equipment() -> String:
	var all_equipment = weapons.keys() + armors.keys()
	if all_equipment.size() > 0:
		return all_equipment[randi() % all_equipment.size()]
	return ""
# Helper function to filter arrays
func filter_array(arr: Array, condition: Callable) -> Array:
	var result = []
	for item in arr:
		if condition.call(item):
			result.append(item)
	return result
# Add these debug functions
func print_consumables():
	print("Available consumables: ", consumables.keys())

func print_materials():
	print("Available materials: ", materials.keys())

func create_equipment_for_floor(item_id: String, floor: int) -> Equipment:
	"""Creates equipment instance scaled to a specific floor"""
	if not equipment_templates.has(item_id):
		print("ItemManager: Template not found for: ", item_id)
		return null
	
	var template_data = equipment_templates[item_id].duplicate(true)
	
	# Add floor context
	template_data["floor_number"] = floor
	
	# Clear any pre-existing rarity data to force fresh generation
	template_data.erase("rarity")
	template_data.erase("rarity_applied")
	template_data.erase("stat_modifiers")
	
	print("ItemManager: Creating equipment for floor %d: %s" % [floor, item_id])
	
	# This will trigger generation in Equipment._init()
	return Equipment.new(template_data)

func get_item(item_id: String) -> Item:
	"""Get an item - for consumables/materials returns singleton, for equipment creates new instance"""
	
	# Consumables/Materials - return singleton
	if consumables.has(item_id):
		return consumables[item_id]
	if materials.has(item_id):
		return materials[item_id]
	
	# Equipment - create NEW instance (defaults to floor 1)
	if equipment_templates.has(item_id):
		print("ItemManager: WARNING - get_item() called for equipment, defaulting to floor 1. Use create_equipment_for_floor() instead.")
		return create_equipment_for_floor(item_id, 1)
	
	print("ItemManager: Item not found: ", item_id)
	return null
