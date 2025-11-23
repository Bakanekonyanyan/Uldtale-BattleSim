# res://scripts/systems/ProgressionManager.gd
class_name ProgressionManager
extends RefCounted

# No character reference stored - passed as parameter to methods

func add_xp(character, amount: int):
	character.xp += amount
	print("%s gained %d XP (Total: %d)" % [character.name, amount, character.xp])
	_check_level_up(character)

func _check_level_up(character):
	var xp_for_next = _xp_required_for_level(character.level + 1)
	while character.xp >= xp_for_next:
		character.xp -= xp_for_next
		_level_up(character)
		xp_for_next = _xp_required_for_level(character.level + 1)

func _xp_required_for_level(level: int) -> int:
	return int(100 * pow(level, 1.5))

func _level_up(character):
	character.level += 1
	character.attribute_points += 5
	print("%s leveled up to %d!" % [character.name, character.level])
	_random_stat_increase(character)
	character.calculate_secondary_attributes()

func _random_stat_increase(character):
	var stat_roll = RandomManager.randi_range(0, 9)
	match stat_roll:
		0: character.vitality += 1
		1: character.strength += 1
		2: character.dexterity += 1
		3: character.intelligence += 1
		4: character.faith += 1
		5: character.mind += 1
		6: character.endurance += 1
		7: character.arcane += 1
		8: character.agility += 1
		9: character.fortitude += 1

func spend_attribute_point(character, attribute: String) -> bool:
	if character.attribute_points > 0 and attribute in character:
		character.set(attribute, character.get(attribute) + 1)
		character.attribute_points -= 1
		character.calculate_secondary_attributes()
		return true
	return false

func update_max_floor(character, floor: int):
	if floor > character.max_floor_cleared:
		character.max_floor_cleared = floor
		print("New max floor: %d" % character.max_floor_cleared)
