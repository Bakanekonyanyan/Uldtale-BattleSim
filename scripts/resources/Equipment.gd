# Equipment.gd
extends Item
class_name Equipment

var damage: int = 0
var armor_value: int = 0
var attribute_target: Variant
var attribute_increase: Variant
var type: String
var slot: String
var class_restriction: Array
var effects: Dictionary
var rarity: String = "common"
var rarity_applied: bool = false
var inventory_key: String = ""  # Stores the unique inventory key for this instance

var rarities: Dictionary = {
	"common": {"multiplier": 1, "color": "white"},
	"uncommon": {"multiplier": 2, "color": "blue"},
	"magic": {"multiplier": 2.5, "color": "yellow"},
	"epic": {"multiplier": 3, "color": "purple"},
	"legendary": {"multiplier": 5, "color": "orange"}
}

func _init(data: Dictionary):
	load_rarities()
	id = data.get("id", "")
	name = data.get("name", "")
	description = data.get("description", "")
	value = data.get("value", 0)
	damage = data.get("damage", 0)
	armor_value = data.get("armor_value", 0)
	attribute_target = data.get("attribute_target", "")
	attribute_increase = data.get("attribute_increase", 0)
	type = data.get("type", "")
	slot = data.get("slot", "")
	class_restriction = data.get("class_restriction", [])
	effects = data.get("effects", {})
	
	# Set the proper item_type based on whether it's a weapon or armor
	if type == "weapon":
		item_type = Item.ItemType.WEAPON
	elif type == "armor":
		item_type = Item.ItemType.ARMOR
	else:
		item_type = Item.ItemType.WEAPON
	
	# Check if rarity is already set in the data (for loading saves)
	if data.has("rarity") and data["rarity"] != "":
		rarity = data["rarity"]
		rarity_applied = data.get("rarity_applied", false)
		print("Equipment loaded with existing rarity: %s (%s)" % [name, rarity])
	else:
		# Only assign and apply rarity for NEW items
		assign_random_rarity()
		apply_rarity_multiplier()
		print("New equipment created: %s with rarity %s (damage: %d, armor: %d)" % [name, rarity, damage, armor_value])

# Update assign_random_rarity with better distribution:
func assign_random_rarity():
	var rarity_roll = randf()
	if rarity_roll < 0.50:  # 50% common
		rarity = "common"
	elif rarity_roll < 0.75:  # 25% uncommon
		rarity = "uncommon"
	elif rarity_roll < 0.90:  # 15% magic
		rarity = "magic"
	elif rarity_roll < 0.97:  # 7% epic
		rarity = "epic"
	else:  # 3% legendary
		rarity = "legendary"
	print("Assigned rarity: %s (roll: %.3f)" % [rarity, rarity_roll])

func apply_rarity_multiplier():
	var multiplier = rarities[rarity]["multiplier"]
	if damage > 0:
		damage = int(damage * multiplier)
	if armor_value > 0:
		armor_value = int(armor_value * multiplier)
	value = int(value * multiplier)
	# Mark that rarity has been applied
	rarity_applied = true

func get_rarity_color() -> String:
	return rarities[rarity]["color"]
	
func load_rarities():
	var file = FileAccess.open("res://data/rarities.json", FileAccess.READ)
	rarities = JSON.parse_string(file.get_as_text())
	file.close()

func is_equippable() -> bool:
	return true

func can_equip(character: CharacterData) -> bool:
	if class_restriction.is_empty():
		return true
	return character.character_class in class_restriction

func apply_effects(character: CharacterData):
	if attribute_target is String:
		character.set(attribute_target, character.get(attribute_target) + attribute_increase)
	elif attribute_target is Array:
		for i in range(attribute_target.size()):
			character.set(attribute_target[i], character.get(attribute_target[i]) + attribute_increase[i])
	
	for effect in effects:
		match effect:
			"dodge":
				character.dodge += effects[effect]
			"crit":
				character.critical_hit_rate += effects[effect]
			"armor_penetration":
				character.armor_penetration += effects[effect]
			"spell_power":
				character.spell_power += effects[effect]

func remove_effects(character: CharacterData):
	if attribute_target is String:
		character.set(attribute_target, character.get(attribute_target) - attribute_increase)
	elif attribute_target is Array:
		for i in range(attribute_target.size()):
			character.set(attribute_target[i], character.get(attribute_target[i]) - attribute_increase[i])
	
	for effect in effects:
		match effect:
			"dodge":
				character.dodge -= effects[effect]
			"crit":
				character.critical_hit_rate -= effects[effect]
			"armor_penetration":
				character.armor_penetration -= effects[effect]
			"spell_power":
				character.spell_power -= effects[effect]

func apply_rarity(rarity_name: String) -> void:
	# Prevent duplicate application
	if rarity_applied:
		return

	# Validate rarity exists
	if not rarities.has(rarity_name):
		push_warning("Invalid rarity '%s' for equipment: %s" % [rarity_name, name])
		return

	rarity = rarity_name
	apply_rarity_multiplier()
