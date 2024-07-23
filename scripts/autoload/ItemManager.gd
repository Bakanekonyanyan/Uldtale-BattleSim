# res://scripts/autoload/ItemManager.gd
# ItemManager.gd
extends Node

var items = {}
var weapons = {}
var armors = {}
var consumables = {}
var materials = {}

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
				if weapon_id != "rarity":  # Skip the rarity field if it's at this level
					var weapon_data = json[hand_type][weapon_category][weapon_id]
					if typeof(weapon_data) == TYPE_DICTIONARY:
						weapon_data["id"] = weapon_id  # Add the id to the weapon data
						var weapon = Equipment.new(weapon_data)
						weapons[weapon_id] = weapon
						items[weapon_id] = weapon
					else:
						print("Warning: Invalid weapon data for ", weapon_id)

	print("Loaded weapons: ", weapons.keys())

func load_armors():
	var file = FileAccess.open("res://data/items/armors.json", FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	
	for armor_type in json:
		for slot in json[armor_type]:
			for armor_id in json[armor_type][slot]:
				var armor_data = json[armor_type][slot][armor_id]
				armor_data["id"] = armor_id  # Make sure this line is here
				var armor = Equipment.new(armor_data)
				armor.id = armor_id  # Explicitly set the id
				armors[armor_id] = armor
				items[armor_id] = armor
				
func update_items():
	items.clear()
	items.merge(consumables)
	items.merge(materials)
	items.merge(weapons)
	items.merge(armors)

func get_item(item_id: String) -> Item:
	print("Attempting to get item: ", item_id)
	var item = items.get(item_id)
	if item:
		print("Item found: ", item_id)
		return item
	else:
		print("Item not found: ", item_id)
		return null

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
