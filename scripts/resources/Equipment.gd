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
	
	# Check if rarity is already set in the data
	if data.has("rarity") and data["rarity"] != "":
		rarity = data["rarity"]
	else:
		assign_random_rarity()
	
	# Only apply rarity multiplier if it hasn't been applied before
	if not data.get("rarity_applied", false):
		apply_rarity_multiplier()
		
func assign_random_rarity():
	var rarity_roll = randf()
	if rarity_roll < 0.60:
		rarity = "common"
	elif rarity_roll < 0.85:
		rarity = "uncommon"
	elif rarity_roll < 0.95:
		rarity = "magic"
	elif rarity_roll < 0.99:
		rarity = "epic"
	else:
		rarity = "legendary"

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
				# You might need to add this property to CharacterData
				character.armor_penetration += effects[effect]
			"spell_power":
				character.spell_power += effects[effect]
			# Add more effects as needed

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
			# Add more effects as needed
