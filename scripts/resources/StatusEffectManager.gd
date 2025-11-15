# StatusEffectManager.gd
# Handles ALL status effect logic for a character
# Extracts 150+ lines from CharacterData

class_name StatusEffectManager
extends RefCounted

var character: CharacterData
var active_effects: Dictionary = {}  # StatusEffect enum -> turns remaining

func _init(owner_character: CharacterData):
	character = owner_character

# === APPLY/REMOVE ===

func apply_effect(effect: Skill.StatusEffect, duration: int) -> String:
	"""Apply or refresh a status effect"""
	var effect_name = Skill.StatusEffect.keys()[effect]
	var data = _get_effect_data(effect_name)
	
	if not active_effects.has(effect):
		active_effects[effect] = duration
		_apply_stat_modifiers(effect, true)
		return "%s is now affected by %s for %d turns" % [character.name, effect_name, duration]
	else:
		active_effects[effect] = max(active_effects[effect], duration)
		return "%s's %s effect refreshed for %d turns" % [character.name, effect_name, duration]

func remove_effect(effect: Skill.StatusEffect) -> String:
	"""Remove a status effect"""
	if active_effects.has(effect):
		_apply_stat_modifiers(effect, false)
		active_effects.erase(effect)
		return "%s is no longer affected by %s" % [character.name, Skill.StatusEffect.keys()[effect]]
	return ""

func clear_all_effects():
	"""Remove all status effects"""
	for effect in active_effects.keys():
		_apply_stat_modifiers(effect, false)
	active_effects.clear()

# === UPDATE TICK ===

func update_effects() -> String:
	"""Process all effects for this turn. Returns combat log message."""
	var message = ""
	var effects_to_remove = []
	
	for effect in active_effects.keys():
		active_effects[effect] -= 1
		
		if active_effects[effect] <= 0:
			effects_to_remove.append(effect)
		else:
			message += _process_effect_damage(effect)
	
	for effect in effects_to_remove:
		message += remove_effect(effect)
	
	return message

# === PRIVATE HELPERS ===

func _process_effect_damage(effect: Skill.StatusEffect) -> String:
	"""Handle per-turn damage/healing/effects for a status"""
	var message = ""
	var effect_name = Skill.StatusEffect.keys()[effect]
	var data = _get_effect_data(effect_name)
	
	if data.is_empty():
		return _fallback_damage(effect)
	
	# ✅ REGENERATION (Healing over time)
	if effect == Skill.StatusEffect.REGENERATION:
		var heal_amount = 0
		if data.damage_type == "heal_percent":
			heal_amount = int(character.max_hp * float(data.damage_value))
		
		if heal_amount > 0:
			character.heal(heal_amount)
			message += "%s regenerated %d HP\n" % [character.name, heal_amount]
		
		return message
	
	# ✅ ENRAGED (No damage, just stat boost + reflection)
	if effect == Skill.StatusEffect.ENRAGED:
		# Reflection is handled in take_damage()
		message += "%s is ENRAGED (reflecting damage)!\n" % character.name
		return message
	
	# ✅ REFLECT (Passive, no per-turn effect)
	if effect == Skill.StatusEffect.REFLECT:
		message += "%s has a damage reflection barrier\n" % character.name
		return message
	
	# Standard damage effects
	if data.has("damage_type") and data.damage_type != "none":
		var dmg = 0
		if data.damage_type == "hp_percent":
			dmg = int(character.max_hp * float(data.damage_value))
		elif data.damage_type == "flat":
			dmg = int(data.damage_value)
		
		if dmg > 0:
			character.take_damage(dmg)
			message += "%s took %d %s damage\n" % [character.name, dmg, effect_name.to_lower()]
	
	# Stun chance
	if data.has("stun_chance"):
		if randf() < float(data.stun_chance):
			character.is_stunned = true
			message += "%s is stunned!\n" % character.name
	
	return message

func _apply_stat_modifiers(effect: Skill.StatusEffect, apply: bool):
	"""Apply or remove stat modifiers for an effect"""
	var effect_name = Skill.StatusEffect.keys()[effect]
	var data = _get_effect_data(effect_name)
	
	if data.has("stat_modifiers"):
		for stat_name in data.stat_modifiers.keys():
			var value = int(data.stat_modifiers[stat_name])
			if Skill.AttributeTarget.has(stat_name.to_upper()):
				var attr = Skill.AttributeTarget[stat_name.to_upper()]
				_modify_attribute(attr, value, apply, active_effects.get(effect, 1))
	else:
		_fallback_modifiers(effect, apply)

func _modify_attribute(attribute: Skill.AttributeTarget, value: int, apply: bool, duration: int):
	"""Helper to apply attribute debuff"""
	if apply:
		character.debuffs[attribute] = {"value": value, "duration": duration}
	else:
		if attribute in character.debuffs:
			character.debuffs.erase(attribute)

func _get_effect_data(effect_name: String) -> Dictionary:
	"""Get data from StatusEffects autoload"""
	if Engine.has_singleton("StatusEffects"):
		return StatusEffects.get_effect_data(effect_name)
	return {}

# === FALLBACK (original hardcoded logic) ===

func _fallback_damage(effect: Skill.StatusEffect) -> String:
	var message = ""
	match effect:
		Skill.StatusEffect.POISON:
			var dmg = character.max_hp / 10
			character.take_damage(dmg)
			message = "%s took %d poison damage\n" % [character.name, dmg]
		Skill.StatusEffect.BURN:
			var dmg = character.max_hp / 20
			character.take_damage(dmg)
			message = "%s took %d burn damage\n" % [character.name, dmg]
		Skill.StatusEffect.SHOCK:
			var dmg = character.max_hp / 15
			character.take_damage(dmg)
			message = "%s took %d shock damage\n" % [character.name, dmg]
			if randf() < 0.2:
				character.is_stunned = true
				message += "%s is stunned!\n" % character.name
		Skill.StatusEffect.FREEZE:
			message = "%s is frozen\n" % character.name
	return message

func _fallback_modifiers(effect: Skill.StatusEffect, apply: bool):
	match effect:
		Skill.StatusEffect.BURN:
			_modify_attribute(Skill.AttributeTarget.STRENGTH, -2, apply, active_effects.get(effect, 1))
		Skill.StatusEffect.FREEZE:
			_modify_attribute(Skill.AttributeTarget.VITALITY, -2, apply, active_effects.get(effect, 1))
			_modify_attribute(Skill.AttributeTarget.AGILITY, -2, apply, active_effects.get(effect, 1))
			_modify_attribute(Skill.AttributeTarget.ARCANE, -2, apply, active_effects.get(effect, 1))

# === QUERY ===

func has_effect(effect: Skill.StatusEffect) -> bool:
	return active_effects.has(effect)

func get_effects_string() -> String:
	"""Get display string of active effects"""
	var effects = []
	for effect in active_effects:
		effects.append("%s (%d)" % [Skill.StatusEffect.keys()[effect], active_effects[effect]])
	return ", ".join(effects) if not effects.is_empty() else "None"

func get_active_effects() -> Dictionary:
	return active_effects.duplicate()

# =============================================
# GET REFLECTION AMOUNT (for damage calc)
# =============================================

func get_total_reflection() -> float:
	"""Calculate total damage reflection from all status effects"""
	var total_reflection = 0.0
	
	for effect in active_effects:
		var effect_name = Skill.StatusEffect.keys()[effect]
		var data = _get_effect_data(effect_name)
		
		if data.has("reflect_damage"):
			total_reflection += float(data.reflect_damage)
	
	return total_reflection
