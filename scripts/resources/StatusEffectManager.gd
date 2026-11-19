# StatusEffectManager.gd - DEBUG VERSION
# This will show us EXACTLY why update_effects isn't working

class_name StatusEffectManager
extends RefCounted

## Weak back-reference: the character owns this manager, so a strong
## reference here would be a cycle and neither would ever be freed.
var _character_ref: WeakRef
var character: CharacterData:
	get: return _character_ref.get_ref() if _character_ref else null
	set(value): _character_ref = weakref(value) if value else null
var active_effects: Dictionary = {}
var effect_stacks: Dictionary = {}

func _init(owner_character: CharacterData):
	character = owner_character

# === APPLY/REMOVE ===

func apply_effect(effect: Skill.StatusEffect, duration: int) -> String:
	"""Apply or refresh a status effect"""
	var effect_name = Skill.StatusEffect.keys()[effect]
	var data = _get_effect_data(effect_name)
	
	Log.debug("status", "[STATUS MGR] apply_effect: %s (enum=%d) for %d turns" % [effect_name, effect, duration])
	
	# BLEED: Stackable logic
	if effect == Skill.StatusEffect.BLEED:
		return _apply_bleed_stack(duration)
	
	# Normal status effects
	if not active_effects.has(effect):
		active_effects[effect] = duration
		_apply_stat_modifiers(effect, true)
		
		Log.debug("status", "[STATUS MGR] Added to active_effects: key=%d, value=%d" % [effect, duration])
		Log.debug("status", "[STATUS MGR] active_effects now has %d entries" % active_effects.size())
		
		# Recalculate derived stats (attack, accuracy/dodge modifiers...)
		character.calculate_secondary_attributes()
		
		if effect == Skill.StatusEffect.REGENERATION:
			Log.debug("status", "[STATUS] %s gained REGENERATION" % character.name)
		
		return "%s is now affected by %s for %d turns" % [character.name, effect_name, duration]
	else:
		active_effects[effect] = max(active_effects[effect], duration)
		return "%s's %s effect refreshed for %d turns" % [character.name, effect_name, duration]

func _apply_bleed_stack(duration: int) -> String:
	var effect = Skill.StatusEffect.BLEED
	var data = _get_effect_data("BLEED")
	var max_stacks = int(data.get("max_stacks", 3))
	
	if not effect_stacks.has(effect):
		effect_stacks[effect] = 1
		active_effects[effect] = duration
		_apply_stat_modifiers(effect, true)
		return "%s is bleeding (1/%d stacks)" % [character.name, max_stacks]
	else:
		var current_stacks = effect_stacks[effect]
		
		if current_stacks >= max_stacks:
			return _trigger_bleed_burst()
		else:
			effect_stacks[effect] += 1
			active_effects[effect] += duration
			current_stacks = effect_stacks[effect]
			
			if current_stacks >= max_stacks:
				return _trigger_bleed_burst()
			
			return "%s's bleed worsens (%d/%d stacks)" % [character.name, current_stacks, max_stacks]

func _trigger_bleed_burst() -> String:
	var data = _get_effect_data("BLEED")
	var burst_percent = float(data.get("burst_damage_percent", 0.30))
	var burst_damage = int(character.max_hp * burst_percent)
	
	character.take_damage(burst_damage)
	
	var effect = Skill.StatusEffect.BLEED
	_apply_stat_modifiers(effect, false)
	active_effects.erase(effect)
	effect_stacks.erase(effect)
	
	return "%s's wounds BURST OPEN for %d damage! (Bleed cleared)" % [character.name, burst_damage]

func remove_effect(effect: Skill.StatusEffect) -> String:
	if active_effects.has(effect):
		_apply_stat_modifiers(effect, false)
		active_effects.erase(effect)
		
		character.calculate_secondary_attributes()
		
		if effect_stacks.has(effect):
			effect_stacks.erase(effect)
		
		return "%s is no longer affected by %s" % [character.name, Skill.StatusEffect.keys()[effect]]
	return ""

func clear_all_effects():
	for effect in active_effects.keys():
		_apply_stat_modifiers(effect, false)
	active_effects.clear()
	effect_stacks.clear()
	character.calculate_secondary_attributes()

# === UPDATE TICK ===

func update_effects() -> String:
	""" CRITICAL DEBUG VERSION"""
	Log.debug("status", "\n[STATUS MGR] ========== update_effects START ==========")
	Log.debug("status", "[STATUS MGR] Character: %s" % character.name)
	Log.debug("status", "[STATUS MGR] active_effects dictionary size: %d" % active_effects.size())
	Log.debug("status", "[STATUS MGR] active_effects keys: %s" % str(active_effects.keys()))
	Log.debug("status", "[STATUS MGR] active_effects values: %s" % str(active_effects.values()))
	
	# Debug: Print each effect in detail
	for effect_key in active_effects.keys():
		var effect_name = Skill.StatusEffect.keys()[effect_key]
		var duration = active_effects[effect_key]
		Log.debug("status", "[STATUS MGR]   - %s (enum=%d): %d turns" % [effect_name, effect_key, duration])
	
	var message = ""
	var effects_to_remove = []
	
	var loop_count = 0
	for effect in active_effects.keys():
		loop_count += 1
		var effect_name = Skill.StatusEffect.keys()[effect]
		Log.debug("status", "[STATUS MGR] Loop iteration %d: Processing %s (enum=%d)" % [loop_count, effect_name, effect])
		
		# Decrement
		var old_duration = active_effects[effect]
		active_effects[effect] -= 1
		var new_duration = active_effects[effect]
		Log.debug("status", "[STATUS MGR]   Duration: %d → %d" % [old_duration, new_duration])
		
		if active_effects[effect] <= 0:
			Log.debug("status", "[STATUS MGR]   Effect expired, marking for removal")
			effects_to_remove.append(effect)
		else:
			Log.debug("status", "[STATUS MGR]   Calling _process_effect_damage...")
			var effect_msg = _process_effect_damage(effect)
			Log.debug("status", "[STATUS MGR]   _process_effect_damage returned: '%s'" % effect_msg)
			message += effect_msg
	
	Log.debug("status", "[STATUS MGR] Loop completed, processed %d effects" % loop_count)
	Log.debug("status", "[STATUS MGR] Effects to remove: %d" % effects_to_remove.size())
	
	for effect in effects_to_remove:
		var removal_msg = remove_effect(effect)
		Log.debug("status", "[STATUS MGR] Removed effect, message: %s" % removal_msg)
		message += removal_msg
	
	Log.debug("status", "[STATUS MGR] Final message: '%s'" % message)
	Log.debug("status", "[STATUS MGR] ========== update_effects END ==========\n")
	
	return message

# === PROCESS EFFECT TICK ===

func _process_effect_damage(effect: Skill.StatusEffect) -> String:
	var message = ""
	var effect_name = Skill.StatusEffect.keys()[effect]
	var data = _get_effect_data(effect_name)
	
	Log.debug("status", "[PROCESS] _process_effect_damage: %s" % effect_name)
	
	if data.is_empty():
		Log.debug("status", "[PROCESS] No data found, using fallback")
		return _fallback_damage(effect)
	
	# BLEED
	if effect == Skill.StatusEffect.BLEED:
		var stacks = effect_stacks.get(effect, 1)
		message += "%s is bleeding (%d/3 stacks)\n" % [character.name, stacks]
		return message
	
	#  REGENERATION
	if effect == Skill.StatusEffect.REGENERATION:
		Log.debug("status", "[REGEN] REGENERATION branch entered!")
		Log.debug("status", "[REGEN] HP before: %d/%d" % [character.current_hp, character.max_hp])
		
		var heal_percent = float(data.get("damage_value", 0.05))
		var heal_amount = int(character.max_hp * heal_percent)
		
		Log.debug("status", "[REGEN] Heal percent: %.2f, heal amount: %d" % [heal_percent, heal_amount])
		
		var hp_before = character.current_hp
		var actual_heal = min(heal_amount, character.max_hp - character.current_hp)
		
		Log.debug("status", "[REGEN] Actual heal (capped): %d" % actual_heal)
		
		if actual_heal > 0:
			Log.debug("status", "[REGEN] Calling character.heal(%d)..." % actual_heal)
			var healed = character.heal(actual_heal)
			Log.debug("status", "[REGEN] character.heal() returned: %d" % healed)
			
			var hp_after = character.current_hp
			Log.debug("status", "[REGEN] HP after: %d/%d" % [hp_after, character.max_hp])
			
			message += "[color=green]%s regenerated %d HP (%d → %d/%d)[/color]\n" % [
				character.name, actual_heal, hp_before, hp_after, character.max_hp
			]
			
			Log.debug("status", "[REGEN] Message created: %s" % message)
		else:
			message += "%s's regeneration has no effect (already at max HP)\n" % character.name
		
		Log.debug("status", "[REGEN] Returning message")
		return message
	
	# ENRAGED
	if effect == Skill.StatusEffect.ENRAGED:
		var data_enraged = _get_effect_data("ENRAGED")
		var str_bonus = int(data_enraged.stat_modifiers.get("strength", 5))
		var int_bonus = int(data_enraged.stat_modifiers.get("intelligence", 3))
		var agi_bonus = int(data_enraged.stat_modifiers.get("agility", 3))
		
		message += "[color=orange]%s is ENRAGED! (+%d STR, +%d INT, +%d AGI, reflects 10%% dmg)[/color]\n" % [
			character.name, str_bonus, int_bonus, agi_bonus
		]
		return message
	
	# REFLECT
	if effect == Skill.StatusEffect.REFLECT:
		message += "[color=cyan]%s has a reflection barrier (30%% damage reflected)[/color]\n" % character.name
		return message
	
	# CONFUSED
	if effect == Skill.StatusEffect.CONFUSED:
		message += "[color=purple]%s is confused and disoriented[/color]\n" % character.name
		return message
	
	# Standard damage effects
	if data.has("damage_type") and data.damage_type != "none":
		var dmg = 0
		if data.damage_type == "hp_percent":
			dmg = int(character.max_hp * float(data.damage_value))
		elif data.damage_type == "flat":
			dmg = int(data.damage_value)
		
		# The status's element (data "element", e.g. Poison = EARTH) applies the
		# target's resistance/weakness, the same way it does for skill hits
		var note = ""
		var elem_name = String(data.get("element", ""))
		if dmg > 0 and ElementalDamage.Element.has(elem_name):
			var elem = ElementalDamage.Element[elem_name]
			var res = character.get_elemental_resistance(elem)
			var weak = character.get_elemental_weakness(elem)
			var mult = max(0.1, (1.0 - res) * (1.0 + weak))
			dmg = max(1, int(round(dmg * mult)))
			note = " (resisted)" if mult < 0.99 else (" (weak!)" if mult > 1.01 else "")
		
		if dmg > 0:
			character.take_damage(dmg)
			message += "[color=red]%s took %d %s damage%s[/color]\n" % [character.name, dmg, effect_name.to_lower(), note]
	
	# Stun chance
	if data.has("stun_chance"):
		if RandomManager.randf() < float(data.stun_chance):
			character.is_stunned = true
			message += "[color=yellow]%s is stunned![/color]\n" % character.name
	
	return message

func _apply_stat_modifiers(effect: Skill.StatusEffect, apply: bool):
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
	if apply:
		if value > 0:
			character.buff_manager.apply_buff(attribute, value, duration)
		else:
			character.buff_manager.apply_debuff(attribute, abs(value), duration)
	else:
		if attribute in character.buff_manager.buffs:
			character.buff_manager.buffs.erase(attribute)
		if attribute in character.buff_manager.debuffs:
			character.buff_manager.debuffs.erase(attribute)

func _get_effect_data(effect_name: String) -> Dictionary:
	#  FIX: Access autoload directly, not via Engine.has_singleton()
	# Script autoloads are NOT engine singletons!
	
	if StatusEffects:  # Direct reference to autoload
		var data = StatusEffects.get_effect_data(effect_name)
		if not data.is_empty():
			Log.debug("status", "[STATUS MGR] Got data for %s: %s" % [effect_name, str(data)])
		return data
	else:
		push_error("StatusEffectManager: StatusEffects autoload not found!")
	
	return {}

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
			if RandomManager.randf() < 0.2:
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

func has_effect(effect: Skill.StatusEffect) -> bool:
	return active_effects.has(effect)

func get_effects_string() -> String:
	var effects = []
	for effect in active_effects:
		var effect_str = Skill.StatusEffect.keys()[effect]
		
		if effect == Skill.StatusEffect.BLEED and effect_stacks.has(effect):
			effect_str += " x%d" % effect_stacks[effect]
		
		effects.append("%s (%d)" % [effect_str, active_effects[effect]])
	return ", ".join(effects) if not effects.is_empty() else "None"

func get_active_effects() -> Dictionary:
	return active_effects.duplicate()

func get_bleed_stacks() -> int:
	return effect_stacks.get(Skill.StatusEffect.BLEED, 0)

func check_confusion_self_harm() -> Dictionary:
	if not has_effect(Skill.StatusEffect.CONFUSED):
		return {"success": false, "damage": 0, "message": ""}
	
	var data = _get_effect_data("CONFUSED")
	var self_harm_chance = float(data.get("self_harm_chance", 0.30))
	
	if RandomManager.randf() < self_harm_chance:
		var self_harm_mult = float(data.get("self_harm_multiplier", 0.70))
		var base_damage = character.get_attack_power() * 0.5
		var self_damage = int(base_damage * self_harm_mult)
		
		character.take_damage(self_damage)
		
		return {
			"success": true,
			"damage": self_damage,
			"message": "%s is confused and hurts themselves for %d damage!" % [character.name, self_damage]
		}
	
	return {"success": false, "damage": 0, "message": ""}

## Accuracy/dodge changes from active effects (status_effects.json keys
## accuracy_reduction, dodge_reduction, dodge_bonus). These keys existed in the
## data (Blind, Confused) but were never applied before.
func get_combat_modifiers() -> Dictionary:
	var mods = {"accuracy_mult": 1.0, "dodge_mult": 1.0, "dodge_bonus": 0.0}
	for effect in active_effects:
		var data = _get_effect_data(Skill.StatusEffect.keys()[effect])
		mods.accuracy_mult *= 1.0 - float(data.get("accuracy_reduction", 0.0))
		mods.dodge_mult *= 1.0 - float(data.get("dodge_reduction", 0.0))
		mods.dodge_bonus += float(data.get("dodge_bonus", 0.0))
	return mods

func get_total_reflection() -> float:
	var total_reflection = 0.0
	
	for effect in active_effects:
		var effect_name = Skill.StatusEffect.keys()[effect]
		var data = _get_effect_data(effect_name)
		
		if data.has("reflect_damage"):
			total_reflection += float(data.reflect_damage)
	
	return total_reflection
