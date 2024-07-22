# Equipment.gd
extends Item
class_name Equipment

var damage: int = 0
var armor_value: int = 0
var attribute_target: Variant  # Can be String or Array
var attribute_increase: Variant  # Can be int or Array
var type: String
var slot: String
var class_restriction: Array
var effects: Dictionary

func _init(data: Dictionary):
	super._init()
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
