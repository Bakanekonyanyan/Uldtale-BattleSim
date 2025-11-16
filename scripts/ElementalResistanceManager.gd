# res://scripts/managers/ElementalResistanceManager.gd
# Manages elemental resistances, weaknesses, and damage bonuses for a character
# Integrates with ElementalDamage system and racial modifiers

class_name ElementalResistanceManager
extends RefCounted

var character: CharacterData

# Base values from race
var base_resistances: Dictionary = {}  # Element -> float
var base_weaknesses: Dictionary = {}   # Element -> float
var damage_bonuses: Dictionary = {}    # Element -> float

# Temporary modifiers (from buffs, equipment, etc.)
var temp_resistances: Dictionary = {}
var temp_weaknesses: Dictionary = {}
var temp_damage_bonuses: Dictionary = {}

func _init(p_character: CharacterData):
	character = p_character
	_initialize_defaults()

func _initialize_defaults():
	"""Initialize all elements to 0"""
	for element in ElementalDamage.Element.values():
		if element == ElementalDamage.Element.NONE:
			continue
		base_resistances[element] = 0.0
		base_weaknesses[element] = 0.0
		damage_bonuses[element] = 0.0
		temp_resistances[element] = 0.0
		temp_weaknesses[element] = 0.0
		temp_damage_bonuses[element] = 0.0

# === SETTERS (called by RaceElementalData) ===

func set_base_resistance(element: ElementalDamage.Element, value: float):
	"""Set base resistance from race data"""
	base_resistances[element] = clamp(value, 0.0, 0.9)  # Max 90% resistance

func set_base_weakness(element: ElementalDamage.Element, value: float):
	"""Set base weakness from race data"""
	base_weaknesses[element] = clamp(value, 0.0, 2.0)  # Max 200% extra damage

func set_damage_bonus(element: ElementalDamage.Element, value: float):
	"""Set damage bonus from race data"""
	damage_bonuses[element] = clamp(value, 0.0, 2.0)  # Max 200% bonus

# === TEMPORARY MODIFIERS (from buffs/equipment) ===

func add_temp_resistance(element: ElementalDamage.Element, value: float):
	"""Add temporary resistance (stacks with base)"""
	temp_resistances[element] += value

func add_temp_weakness(element: ElementalDamage.Element, value: float):
	"""Add temporary weakness (stacks with base)"""
	temp_weaknesses[element] += value

func add_temp_damage_bonus(element: ElementalDamage.Element, value: float):
	"""Add temporary damage bonus (stacks with base)"""
	temp_damage_bonuses[element] += value

func clear_temp_modifiers():
	"""Clear all temporary modifiers (call on combat end)"""
	for element in ElementalDamage.Element.values():
		if element == ElementalDamage.Element.NONE:
			continue
		temp_resistances[element] = 0.0
		temp_weaknesses[element] = 0.0
		temp_damage_bonuses[element] = 0.0

# === GETTERS (used in combat calculations) ===

func get_total_resistance(element: ElementalDamage.Element) -> float:
	"""Get total resistance (base + temp), capped at 90%"""
	var total = base_resistances.get(element, 0.0) + temp_resistances.get(element, 0.0)
	return clamp(total, 0.0, 0.9)

func get_total_weakness(element: ElementalDamage.Element) -> float:
	"""Get total weakness (base + temp)"""
	var total = base_weaknesses.get(element, 0.0) + temp_weaknesses.get(element, 0.0)
	return max(0.0, total)

func get_total_damage_bonus(element: ElementalDamage.Element) -> float:
	"""Get total damage bonus (base + temp)"""
	var total = damage_bonuses.get(element, 0.0) + temp_damage_bonuses.get(element, 0.0)
	return max(0.0, total)

# === COMBAT INTEGRATION ===

func calculate_incoming_damage(base_damage: float, element: ElementalDamage.Element) -> Dictionary:
	"""Calculate damage taken with elemental modifiers"""
	if element == ElementalDamage.Element.NONE:
		return {"damage": base_damage, "multiplier": 1.0, "is_resistant": false, "is_weak": false}
	
	var resistance = get_total_resistance(element)
	var weakness = get_total_weakness(element)
	
	return ElementalDamage.calculate_elemental_damage(
		base_damage,
		element,
		0.0,  # No attacker bonus here (that's on the attacker's side)
		resistance,
		weakness
	)

func get_outgoing_damage_bonus(element: ElementalDamage.Element) -> float:
	"""Get damage bonus for attacks this character makes"""
	if element == ElementalDamage.Element.NONE:
		return 0.0
	return get_total_damage_bonus(element)

# === DEBUG / UI ===

func get_resistance_string(element: ElementalDamage.Element) -> String:
	"""Get formatted string for UI display"""
	var resist = get_total_resistance(element)
	var weak = get_total_weakness(element)
	var bonus = get_total_damage_bonus(element)
	
	var parts = []
	if resist > 0.0:
		parts.append("-%d%% taken" % int(resist * 100))
	if weak > 0.0:
		parts.append("+%d%% taken" % int(weak * 100))
	if bonus > 0.0:
		parts.append("+%d%% dealt" % int(bonus * 100))
	
	if parts.is_empty():
		return "Normal"
	return ", ".join(parts)

func print_all_resistances():
	"""Debug: Print all elemental modifiers"""
	print("=== Elemental Resistances for %s ===" % character.name)
	for element in ElementalDamage.Element.values():
		if element == ElementalDamage.Element.NONE:
			continue
		var name = ElementalDamage.get_element_name(element)
		var info = get_resistance_string(element)
		print("  %s: %s" % [name, info])

# === BACKWARD COMPATIBILITY ===
# These methods provide simpler access for external code

func get_resistance(element: ElementalDamage.Element) -> float:
	"""Alias for get_total_resistance"""
	return get_total_resistance(element)

func get_weakness(element: ElementalDamage.Element) -> float:
	"""Alias for get_total_weakness"""
	return get_total_weakness(element)

func get_damage_bonus(element: ElementalDamage.Element) -> float:
	"""Alias for get_total_damage_bonus"""
	return get_total_damage_bonus(element)
