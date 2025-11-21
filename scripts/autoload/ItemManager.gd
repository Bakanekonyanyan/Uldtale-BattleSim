# ItemManager.gd - FIXED: Optional min_rarity_tier parameter

extends Node

var items = {}
var weapons = {}
var armors = {}
var consumables = {}
var materials = {}
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
						weapon_data["key"] = weapon_id  # NEW: Add proficiency key
						equipment_templates[weapon_id] = weapon_data
						weapons[weapon_id] = weapon_data
						print("ItemManager: Loaded weapon '%s' with key '%s'" % [weapon_data.get("name", ""), weapon_id])

func load_armors():
	var file = FileAccess.open("res://data/items/armors.json", FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	
	for armor_type in json:
		for slot in json[armor_type]:
			for armor_id in json[armor_type][slot]:
				var armor_data = json[armor_type][slot][armor_id]
				armor_data["id"] = armor_id
				armor_data["key"] = armor_id  # NEW: Add proficiency key
				equipment_templates[armor_id] = armor_data
				armors[armor_id] = armor_data
				print("ItemManager: Loaded armor '%s' with key '%s'" % [armor_data.get("name", ""), armor_id])

func create_equipment_instance(item_id: String) -> Equipment:
	"""Creates a NEW equipment instance with fresh random rolls"""
	if not equipment_templates.has(item_id):
		print("ItemManager: Template not found for: ", item_id)
		return null
	
	# Create NEW instance from template data
	var template_data = equipment_templates[item_id].duplicate(true)
	
	# IMPORTANT: Keep the key during duplication
	if not template_data.has("key"):
		template_data["key"] = item_id
	
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
		return consumables.keys()[RandomManager.randi() % consumables.size()]
	return ""

func get_random_material() -> String:
	if materials.size() > 0:
		return materials.keys()[RandomManager.randi() % materials.size()]
	return ""
	
func get_random_weapon(category: String = "") -> String:
	if weapons.size() > 0:
		var available_weapons = weapons.keys()
		if category != "":
			available_weapons = available_weapons.filter(func(weapon_id): return weapons[weapon_id].type == category)
		
		if available_weapons.size() > 0:
			return available_weapons[RandomManager.randi() % available_weapons.size()]
	return ""

func get_random_armor(type: String = "", slot: String = "") -> String:
	if armors.size() > 0:
		var available_armors = armors.keys()
		if type != "":
			available_armors = available_armors.filter(func(armor_id): return armors[armor_id].type == type)
		if slot != "":
			available_armors = available_armors.filter(func(armor_id): return armors[armor_id].slot == slot)
		
		if available_armors.size() > 0:
			return available_armors[RandomManager.randi() % available_armors.size()]
	return ""

func get_random_equipment() -> String:
	var all_equipment = weapons.keys() + armors.keys()
	if all_equipment.size() > 0:
		return all_equipment[RandomManager.randi() % all_equipment.size()]
	return ""

func filter_array(arr: Array, condition: Callable) -> Array:
	var result = []
	for item in arr:
		if condition.call(item):
			result.append(item)
	return result

func print_consumables():
	print("Available consumables: ", consumables.keys())

func print_materials():
	print("Available materials: ", materials.keys())

#  FIXED: Make min_rarity_tier OPTIONAL with default value of 0
func create_equipment_for_floor(item_id: String, floor: int, min_rarity_tier: int = 0) -> Equipment:
	"""
	Creates equipment instance scaled to a specific floor
	
	Parameters:
	- item_id: Equipment template ID
	- floor: Current floor number (affects item level)
	- min_rarity_tier: OPTIONAL minimum rarity tier (0 = no minimum, uses random roll)
	"""
	if not equipment_templates.has(item_id):
		print("ItemManager: Template not found for: ", item_id)
		return null
	
	var template_data = equipment_templates[item_id].duplicate(true)
	
	# IMPORTANT: Preserve the proficiency key
	if not template_data.has("key"):
		template_data["key"] = item_id
	
	# CRITICAL: Add floor context
	template_data["floor_number"] = floor
	
	# NEW: Add minimum rarity tier if specified
	if min_rarity_tier > 0:
		template_data["min_rarity_tier"] = min_rarity_tier
		print("ItemManager: Creating equipment with min rarity tier %d" % min_rarity_tier)
	
	# Clear any pre-existing rarity data to force fresh generation
	template_data.erase("rarity")
	template_data.erase("rarity_applied")
	template_data.erase("stat_modifiers")
	
	print("ItemManager: Creating equipment for floor %d: %s (key: %s)" % [floor, item_id, template_data["key"]])
	
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
	
# ADD: Class-biased random weapon selection
func get_random_weapon_biased(character_class: String = "") -> String:
	"""Get random weapon with optional class bias"""
	if character_class == "" or not ClassEquipmentBias.CLASS_EQUIPMENT_BIAS.has(character_class):
		return get_random_weapon()  # Fallback to existing random
	
	return ClassEquipmentBias.get_biased_equipment_id(character_class, "weapons")

# ADD: Class-biased random armor selection
func get_random_armor_biased(character_class: String = "", slot: String = "") -> String:
	"""Get random armor with optional class bias and slot filter"""
	if character_class == "" or not ClassEquipmentBias.CLASS_EQUIPMENT_BIAS.has(character_class):
		return get_random_armor("", slot)  # Fallback to existing random
	
	var armor_id = ClassEquipmentBias.get_biased_equipment_id(character_class, "armors")
	
	# Apply slot filter if specified
	if slot != "" and armor_id != "":
		var template = get_equipment_template(armor_id)
		if template.get("slot", "") != slot:
			# Re-roll with slot filter
			var prefs = ClassEquipmentBias.CLASS_EQUIPMENT_BIAS[character_class]
			var armor_types = prefs.get("armor_types", [])
			var filtered = _get_armors_by_type_and_slot(armor_types, slot)
			if not filtered.is_empty():
				return filtered[RandomManager.randi() % filtered.size()]
	
	return armor_id

# ADD: Helper for slot filtering
func _get_armors_by_type_and_slot(armor_types: Array, slot: String) -> Array:
	"""Get armor IDs matching both type and slot"""
	var result = []
	for armor_id in armors.keys():
		var template = get_equipment_template(armor_id)
		if template.get("type", "") in armor_types and template.get("slot", "") == slot:
			result.append(armor_id)
	return result

# ADD: Class-biased random equipment
func get_random_equipment_biased(character_class: String = "") -> String:
	"""Get random equipment (weapon or armor) with class bias"""
	if character_class == "" or not ClassEquipmentBias.CLASS_EQUIPMENT_BIAS.has(character_class):
		return get_random_equipment()
	
	# 50/50 weapon vs armor
	if RandomManager.randf() < 0.5:
		return get_random_weapon_biased(character_class)
	else:
		return get_random_armor_biased(character_class)
