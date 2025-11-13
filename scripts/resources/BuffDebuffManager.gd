# BuffDebuffManager.gd
# Handles ALL buff/debuff logic for a character
# Extracts ~100 lines from CharacterData

class_name BuffDebuffManager
extends RefCounted

var character: CharacterData
var buffs: Dictionary = {}  # AttributeTarget -> {value: int, duration: int}
var debuffs: Dictionary = {}

func _init(owner_character: CharacterData):
	character = owner_character

# === APPLY ===

func apply_buff(attribute: Skill.AttributeTarget, value: int, duration: int):
	"""Apply or refresh a buff"""
	if not buffs.has(attribute):
		buffs[attribute] = {"value": value, "duration": duration}
	else:
		# Take stronger buff
		if value > buffs[attribute].value:
			buffs[attribute] = {"value": value, "duration": duration}
		elif value == buffs[attribute].value:
			buffs[attribute].duration = max(buffs[attribute].duration, duration)
	
	print("%s received buff to %s: +%d for %d turns" % [
		character.name,
		Skill.AttributeTarget.keys()[attribute],
		value,
		duration
	])
	
	character.calculate_secondary_attributes()

func apply_debuff(attribute: Skill.AttributeTarget, value: int, duration: int):
	"""Apply or refresh a debuff"""
	if not debuffs.has(attribute):
		debuffs[attribute] = {"value": value, "duration": duration}
	else:
		# Take stronger debuff
		if value > debuffs[attribute].value:
			debuffs[attribute] = {"value": value, "duration": duration}
		elif value == debuffs[attribute].value:
			debuffs[attribute].duration = max(debuffs[attribute].duration, duration)
	
	print("%s received debuff to %s: -%d for %d turns" % [
		character.name,
		Skill.AttributeTarget.keys()[attribute],
		value,
		duration
	])
	
	character.calculate_secondary_attributes()

# === UPDATE TICK ===

func update_buffs_and_debuffs():
	"""Decrease durations and remove expired effects"""
	var stats_changed = false
	
	# Update buffs
	for attribute in buffs.keys():
		buffs[attribute].duration -= 1
		if buffs[attribute].duration <= 0:
			print("%s's buff to %s expired" % [
				character.name,
				Skill.AttributeTarget.keys()[attribute]
			])
			buffs.erase(attribute)
			stats_changed = true
	
	# Update debuffs
	for attribute in debuffs.keys():
		debuffs[attribute].duration -= 1
		if debuffs[attribute].duration <= 0:
			print("%s's debuff to %s expired" % [
				character.name,
				Skill.AttributeTarget.keys()[attribute]
			])
			debuffs.erase(attribute)
			stats_changed = true
	
	if stats_changed:
		character.calculate_secondary_attributes()

# === QUERY ===

func get_buff_value(attribute: Skill.AttributeTarget) -> int:
	"""Get current buff value for an attribute"""
	return buffs.get(attribute, {"value": 0})["value"]

func get_debuff_value(attribute: Skill.AttributeTarget) -> int:
	"""Get current debuff value for an attribute"""
	return debuffs.get(attribute, {"value": 0})["value"]

func get_effective_attribute(attribute: Skill.AttributeTarget) -> int:
	"""Get attribute value with buffs/debuffs applied"""
	var attr_name = Skill.AttributeTarget.keys()[attribute].to_lower()
	
	if not (attr_name in character):
		push_error("Character missing attribute: %s" % attr_name)
		return 0
	
	var base = character.get(attr_name)
	var buff = get_buff_value(attribute)
	var debuff = get_debuff_value(attribute)
	
	return base + buff - debuff

func has_buffs() -> bool:
	return not buffs.is_empty()

func has_debuffs() -> bool:
	return not debuffs.is_empty()

func clear_all():
	"""Remove all buffs and debuffs"""
	buffs.clear()
	debuffs.clear()
	character.calculate_secondary_attributes()

func get_buffs_string() -> String:
	"""Get display string of active buffs"""
	var list = []
	for attr in buffs:
		list.append("%s +%d (%d)" % [
			Skill.AttributeTarget.keys()[attr],
			buffs[attr].value,
			buffs[attr].duration
		])
	return ", ".join(list) if not list.is_empty() else "None"

func get_debuffs_string() -> String:
	"""Get display string of active debuffs"""
	var list = []
	for attr in debuffs:
		list.append("%s -%d (%d)" % [
			Skill.AttributeTarget.keys()[attr],
			debuffs[attr].value,
			debuffs[attr].duration
		])
	return ", ".join(list) if not list.is_empty() else "None"
