# scenes/mechanics/Skill.gd
class_name Skill
extends Resource


enum SkillType { DAMAGE, HEAL, BUFF, DEBUFF, RESTORE, INFLICT_STATUS, DRAIN }
enum TargetType { SELF, ALLY, ENEMY, ALL_ALLIES, ALL_ENEMIES }
enum AttributeTarget { 
	NONE, 
	VITALITY, 
	STRENGTH, 
	DEXTERITY, 
	INTELLIGENCE, 
	FAITH, 
	MIND, 
	ENDURANCE, 
	ARCANE, 
	AGILITY, 
	FORTITUDE 
}
enum StatusEffect { 
	NONE, 
	POISON,       # Earth element
	BURN,         # Fire element
	FREEZE,       # Ice element
	BLEED,        # Wind element
	SHOCK,        # Lightning element
	CONFUSED,     # Holy element
	BLIND,        # Holy/Dark element
	SLEEP,        # Dark element
	REGENERATION, # Buff effect
	ENRAGED,      # Buff effect
	REFLECT       # Buff effect
}
enum AbilityType { PHYSICAL, MAGICAL }
enum DrainTarget { HP, MP, SP }
enum ElementType {
	NONE,
	EARTH,
	FIRE,
	ICE,
	WIND,
	LIGHTNING,
	HOLY,
	DARK,
	PHYSICAL
}

@export var element: ElementType = ElementType.NONE
@export var elements: Array = []

@export var ability_type: AbilityType
@export var name: String
@export var description: String
@export var type: SkillType
@export var target: TargetType

@export var attribute_targets: Array = []
@export var status_effects: Array = []

# === DRAIN SYSTEM (Enhanced) ===
@export var drain_source: DrainTarget = DrainTarget.HP  # What to drain FROM target
@export var drain_restore: DrainTarget = DrainTarget.HP  # What to restore TO user
@export var drain_efficiency: float = 0.5  # Conversion rate (0.0 to 1.0+)

@export var power: int
@export var duration: int
@export var mp_cost: int
@export var sp_cost: int
@export var cooldown: int

# Skill leveling
@export var level: int = 1
@export var uses: int = 0
@export var base_power: int
@export var base_mp_cost: int
@export var base_sp_cost: int
@export var base_cooldown: int
@export var base_duration: int

const LEVEL_THRESHOLDS = [5, 15, 30, 60, 120]

static func create_from_dict(data: Dictionary) -> Skill:
	var skill = Skill.new()
	skill.name = data.name
	skill.description = data.description
	skill.ability_type = AbilityType[data.ability_type.to_upper()]
	skill.type = SkillType[data.type.to_upper()]
	skill.target = TargetType[data.target.to_upper()]
	
	# Parse elements
	skill.elements = []
	if data.has("elements") and data.elements is Array:
		for elem_str in data.elements:
			if elem_str != "" and elem_str != "NONE" and ElementType.has(elem_str.to_upper()):
				skill.elements.append(ElementType[elem_str.to_upper()])
	elif data.has("element"):
		var elem_data = data.element
		if elem_data is String and elem_data != "" and elem_data != "NONE":
			if ElementType.has(elem_data.to_upper()):
				skill.elements.append(ElementType[elem_data.to_upper()])
	
	# Parse attribute_targets
	skill.attribute_targets = []
	if data.has("attribute_targets") and data.attribute_targets is Array:
		for attr_str in data.attribute_targets:
			if attr_str != "" and AttributeTarget.has(attr_str.to_upper()):
				skill.attribute_targets.append(AttributeTarget[attr_str.to_upper()])
	elif data.has("attribute_target"):
		var attr_data = data.attribute_target
		if attr_data is Array:
			for attr_str in attr_data:
				if attr_str != "" and attr_str != "NONE" and AttributeTarget.has(attr_str.to_upper()):
					skill.attribute_targets.append(AttributeTarget[attr_str.to_upper()])
		elif attr_data is String:
			if attr_data != "" and attr_data != "NONE" and AttributeTarget.has(attr_data.to_upper()):
				skill.attribute_targets.append(AttributeTarget[attr_data.to_upper()])
	
	# Parse status_effects
	skill.status_effects = []
	if data.has("status_effects") and data.status_effects is Array:
		for effect_str in data.status_effects:
			if effect_str != "" and StatusEffect.has(effect_str.to_upper()):
				skill.status_effects.append(StatusEffect[effect_str.to_upper()])
	elif data.has("status_effect"):
		var effect_data = data.status_effect
		if effect_data is Array:
			for effect_str in effect_data:
				if effect_str != "" and effect_str != "NONE" and StatusEffect.has(effect_str.to_upper()):
					skill.status_effects.append(StatusEffect[effect_str.to_upper()])
		elif effect_data is String:
			if effect_data != "" and effect_data != "NONE" and StatusEffect.has(effect_data.to_upper()):
				skill.status_effects.append(StatusEffect[effect_data.to_upper()])
	
	# === NEW: Parse drain system properties ===
	if data.has("drain_source"):
		skill.drain_source = DrainTarget[data.drain_source.to_upper()]
	else:
		skill.drain_source = DrainTarget.HP  # Default
	
	if data.has("drain_restore"):
		skill.drain_restore = DrainTarget[data.drain_restore.to_upper()]
	else:
		skill.drain_restore = DrainTarget.HP  # Default
	
	if data.has("drain_efficiency"):
		skill.drain_efficiency = data.drain_efficiency
	
	skill.base_power = data.power
	skill.base_mp_cost = data.get("mp_cost", 0)
	skill.base_sp_cost = data.get("sp_cost", 0)
	skill.base_cooldown = data.cooldown
	skill.base_duration = data.duration
	
	skill.level = 1
	skill.uses = 0
	
	skill.power = skill.base_power
	skill.mp_cost = skill.base_mp_cost
	skill.sp_cost = skill.base_sp_cost
	skill.cooldown = skill.base_cooldown
	skill.duration = skill.base_duration
	
	return skill

func get_level_string() -> String:
	return "Max" if level >= 6 else str(level)

func get_uses_for_next_level() -> int:
	return LEVEL_THRESHOLDS[level - 1] if level <= 5 else -1

func check_level_up() -> bool:
	if level >= 6:
		return false
	
	var threshold_index = level - 1
	if uses >= LEVEL_THRESHOLDS[threshold_index]:
		level_up()
		return true
	return false

func level_up():
	level += 1
	calculate_level_bonuses()
	
func calculate_level_bonuses():
	var power_multipliers = [1.0, 1.1, 1.25, 1.45, 1.7, 2.0]
	var cost_multipliers = [1.0, 0.95, 0.9, 0.85, 0.75, 0.6]
	var cooldown_reductions = [0, 0, 1, 1, 2, 3]
	var duration_bonuses = [0, 1, 1, 2, 2, 3]
	
	var level_index = min(level - 1, 5)
	
	if type in [SkillType.DAMAGE, SkillType.HEAL, SkillType.RESTORE, SkillType.DRAIN]:
		power = int(base_power * power_multipliers[level_index])
	elif type in [SkillType.BUFF, SkillType.DEBUFF]:
		power = int(base_power * power_multipliers[level_index])
		duration = base_duration + duration_bonuses[level_index]
	elif type == SkillType.INFLICT_STATUS:
		duration = base_duration + duration_bonuses[level_index]
	
	mp_cost = max(1, int(base_mp_cost * cost_multipliers[level_index]))
	sp_cost = max(1, int(base_sp_cost * cost_multipliers[level_index]))
	cooldown = max(0, base_cooldown - cooldown_reductions[level_index])

func on_skill_used():
	uses += 1
	if check_level_up():
		return "Skill leveled up to " + get_level_string() + "!"
	return ""

func use(user: CharacterData, targets: Array) -> Dictionary:
	"""
	Returns a dictionary with:
	- message: String (display text)
	- damage: int (total damage dealt)
	- healing: int (total healing done)
	- mp_restored: int
	- sp_restored: int
	"""
	match type:
		SkillType.DAMAGE:
			return deal_damage(user, targets)
		SkillType.HEAL:
			return heal(user, targets)
		SkillType.BUFF:
			return apply_buff(user, targets)
		SkillType.DEBUFF:
			return apply_debuff(user, targets)
		SkillType.RESTORE:
			return restore(user, targets)
		SkillType.INFLICT_STATUS:
			return inflict_status(user, targets)
		SkillType.DRAIN:
			return drain(user, targets)
	
	return {"message": "Unknown skill type", "damage": 0, "healing": 0}

# ===== UPDATE ALL SKILL METHODS TO RETURN DICTIONARY =====

func deal_damage(user: CharacterData, targets: Array) -> Dictionary:
	var total_damage = 0
	var target_results = []  #  Track per-target outcomes
	var momentum_multiplier = MomentumSystem.get_damage_multiplier()
	
	# Convert elements (keep existing code)
	var elemental_types = []
	for elem in elements:
		if elem != ElementType.NONE and elem != ElementType.PHYSICAL:
			match elem:
				ElementType.EARTH: elemental_types.append(ElementalDamage.Element.EARTH)
				ElementType.FIRE: elemental_types.append(ElementalDamage.Element.FIRE)
				ElementType.ICE: elemental_types.append(ElementalDamage.Element.ICE)
				ElementType.WIND: elemental_types.append(ElementalDamage.Element.WIND)
				ElementType.LIGHTNING: elemental_types.append(ElementalDamage.Element.LIGHTNING)
				ElementType.HOLY: elemental_types.append(ElementalDamage.Element.HOLY)
				ElementType.DARK: elemental_types.append(ElementalDamage.Element.DARK)
	
	#  PROCESS EACH TARGET (don't early return)
	for t in targets:
		var base_damage = power + (user.attack_power if ability_type == AbilityType.PHYSICAL else user.spell_power)
		base_damage *= momentum_multiplier
		var resistance = (t.toughness if ability_type == AbilityType.PHYSICAL else t.spell_ward)
		
		var accuracy_check = RandomManager.randf() < user.accuracy
		var dodge_check = RandomManager.randf() < t.dodge
		
		#  Handle miss/dodge per target
		if not accuracy_check:
			target_results.append({"target": t.name, "missed": true})
			continue
		
		if dodge_check:
			target_results.append({"target": t.name, "dodged": true})
			continue
		
		var damage = max(1, base_damage - resistance)
		
		# Apply elemental (keep existing code)
		if not elemental_types.is_empty() and t.elemental_resistances:
			var total_multiplier = 1.0
			for elemental_type in elemental_types:
				var attacker_bonus = user.get_elemental_damage_bonus(elemental_type)
				var target_resistance = t.get_elemental_resistance(elemental_type)
				var target_weakness = t.get_elemental_weakness(elemental_type)
				var elem_result = ElementalDamage.calculate_elemental_damage(1.0, elemental_type, attacker_bonus, target_resistance, target_weakness)
				total_multiplier *= elem_result.multiplier
			damage *= total_multiplier
		
		# Crit check
		var crit_check = RandomManager.randf() < user.critical_hit_rate
		if crit_check:
			damage *= 1.5 + RandomManager.randf() * 0.5
		
		# Reflection
		var reflection_info = _track_reflection_damage(user, t, damage)
		
		# Apply damage
		t.take_damage(damage, user)
		total_damage += damage
		
		# Apply status
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				t.apply_status_effect(effect, duration)
		
		#  Record successful hit
		target_results.append({
			"target": t.name,
			"damage": int(damage),
			"crit": crit_check,
			"reflected": reflection_info.reflected,
			"reflection_msg": ("[color=cyan]%s's barrier reflects %d damage back![/color]" % [t.name, reflection_info.amount]) if reflection_info.reflected else ""
		})
	
	#  BUILD MESSAGE FROM RESULTS
	var result_msg = ""
	var hit_count = 0
	var miss_count = 0
	var dodge_count = 0
	
	for res in target_results:
		if res.has("missed"):
			miss_count += 1
		elif res.has("dodged"):
			dodge_count += 1
		else:
			hit_count += 1
	
	# Show hits first
	if hit_count > 0:
		result_msg = "%s dealt %d damage to %d target(s)" % [name, total_damage, hit_count]
		
		# Show individual crits
		for res in target_results:
			if res.has("crit") and res.crit:
				result_msg += "\n  CRITICAL on %s!" % res.target
		
		# Show reflections
		for res in target_results:
			if res.has("reflected") and res.reflected:
				result_msg += "\n  " + res.reflection_msg
	
	# Show misses/dodges
	if miss_count > 0:
		for res in target_results:
			if res.has("missed"):
				result_msg += ("\n" if result_msg else "") + "%s missed %s!" % [user.name, res.target]
	
	if dodge_count > 0:
		for res in target_results:
			if res.has("dodged"):
				result_msg += ("\n" if result_msg else "") + "%s dodged!" % res.target
	
	# Show status effects
	if not status_effects.is_empty() and hit_count > 0:
		var effect_names = []
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				effect_names.append(StatusEffect.keys()[effect])
		if not effect_names.is_empty():
			result_msg += "\nApplied: " + ", ".join(effect_names)
	
	return {"message": result_msg, "damage": int(total_damage), "healing": 0}

# ===== UPDATE ALL OTHER SKILL METHODS =====

func heal(user: CharacterData, targets: Array) -> Dictionary:
	var total_heal = 0
	for t in targets:
		var heal_amount = power + user.spell_power
		t.heal(heal_amount)
		total_heal += heal_amount
	
	return {
		"message": "%s healed %d HP to %d target(s)" % [name, total_heal, targets.size()],
		"damage": 0,
		"healing": total_heal
	}

func apply_buff(_user: CharacterData, targets: Array) -> Dictionary:
	# Apply status effects FIRST
	if not status_effects.is_empty():
		for t in targets:
			for effect in status_effects:
				if effect != StatusEffect.NONE:
					t.apply_status_effect(effect, duration)
	
	# Then apply attribute buffs
	if not attribute_targets.is_empty():
		for t in targets:
			for attribute in attribute_targets:
				if attribute != AttributeTarget.NONE:
					t.apply_buff(attribute, power, duration)
	
	# Build message
	var result_parts = []
	
	if not status_effects.is_empty():
		var effect_names = []
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				effect_names.append(StatusEffect.keys()[effect])
		if not effect_names.is_empty():
			result_parts.append("granted " + ", ".join(effect_names))
	
	if not attribute_targets.is_empty():
		var attr_names = []
		for attr in attribute_targets:
			if attr != AttributeTarget.NONE:
				attr_names.append(AttributeTarget.keys()[attr])
		if not attr_names.is_empty():
			result_parts.append("buffed " + ", ".join(attr_names) + " by +" + str(power))
	
	if result_parts.is_empty():
		return {"message": "%s had no effect!" % name, "damage": 0, "healing": 0}
	
	return {
		"message": "%s %s on %s for %d turns" % [
			name,
			" and ".join(result_parts),
			targets[0].name if targets.size() == 1 else "%d target(s)" % targets.size(),
			duration
		],
		"damage": 0,
		"healing": 0
	}

func apply_debuff(_user: CharacterData, targets: Array) -> Dictionary:
	for t in targets:
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				t.apply_status_effect(effect, duration)
		
		for attribute in attribute_targets:
			if attribute != AttributeTarget.NONE:
				t.apply_debuff(attribute, power, duration)
	
	var result_parts = []
	
	if not status_effects.is_empty():
		var effect_names = []
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				effect_names.append(StatusEffect.keys()[effect])
		if not effect_names.is_empty():
			result_parts.append("inflicted " + ", ".join(effect_names))
	
	if not attribute_targets.is_empty():
		var attr_names = []
		for attr in attribute_targets:
			if attr != AttributeTarget.NONE:
				attr_names.append(AttributeTarget.keys()[attr])
		if not attr_names.is_empty():
			result_parts.append("debuffed " + ", ".join(attr_names) + " by " + str(power))
	
	if result_parts.is_empty():
		return {"message": "%s had no effect!" % name, "damage": 0, "healing": 0}
	
	return {
		"message": "%s %s on %d target(s) for %d turns" % [
			name,
			" and ".join(result_parts),
			targets.size(),
			duration
		],
		"damage": 0,
		"healing": 0
	}

func restore(user: CharacterData, targets: Array) -> Dictionary:
	var total_restore = 0
	for t in targets:
		var restore_amount = power + user.spell_power
		t.restore_mp(restore_amount)
		total_restore += restore_amount
	
	return {
		"message": "%s restored %d MP to %d target(s)" % [name, total_restore, targets.size()],
		"damage": 0,
		"healing": 0,
		"mp_restored": total_restore
	}

func inflict_status(_user: CharacterData, targets: Array) -> Dictionary:
	for t in targets:
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				t.apply_status_effect(effect, duration)
	
	var effect_names = []
	for effect in status_effects:
		if effect != StatusEffect.NONE:
			effect_names.append(StatusEffect.keys()[effect])
	
	if effect_names.is_empty():
		return {"message": "%s had no effect!" % name, "damage": 0, "healing": 0}
	
	return {
		"message": "%s inflicted %s on %d target(s) for %d turns" % [
			name, 
			", ".join(effect_names), 
			targets.size(),
			duration
		],
		"damage": 0,
		"healing": 0
	}

func drain(user: CharacterData, targets: Array) -> Dictionary:
	var total_drained = 0
	var total_restored = 0
	
	for t in targets:
		var drain_amount = 0
		
		match drain_source:
			DrainTarget.HP:
				var base_damage = power + (user.attack_power if ability_type == AbilityType.PHYSICAL else user.spell_power)
				var resistance = (t.toughness if ability_type == AbilityType.PHYSICAL else t.spell_ward)
				drain_amount = max(1, base_damage - resistance)
				t.take_damage(drain_amount)
			
			DrainTarget.MP:
				drain_amount = min(power, t.current_mp)
				t.current_mp = max(0, t.current_mp - drain_amount)
			
			DrainTarget.SP:
				drain_amount = min(power, t.current_sp)
				t.current_sp = max(0, t.current_sp - drain_amount)
		
		total_drained += drain_amount
		
		var restore_amount = int(drain_amount * drain_efficiency)
		
		match drain_restore:
			DrainTarget.HP:
				user.heal(restore_amount)
			DrainTarget.MP:
				user.restore_mp(restore_amount)
			DrainTarget.SP:
				user.restore_sp(restore_amount)
		
		total_restored += restore_amount
	
	var source_name = DrainTarget.keys()[drain_source]
	var restore_name = DrainTarget.keys()[drain_restore]
	var source_color = _get_resource_color(drain_source)
	var restore_color = _get_resource_color(drain_restore)
	
	var result = "%s drained [color=%s]%d %s[/color] from %s" % [
		name,
		source_color,
		total_drained,
		source_name,
		targets[0].name if targets.size() == 1 else "%d target(s)" % targets.size()
	]
	
	if drain_source != drain_restore or drain_efficiency != 1.0:
		result += " and restored [color=%s]%d %s[/color] to %s" % [
			restore_color,
			total_restored,
			restore_name,
			user.name
		]
		
		if drain_efficiency != 1.0:
			result += " (%.0f%% efficiency)" % (drain_efficiency * 100)
	else:
		result += " and restored [color=%s]%d %s[/color] to %s" % [
			restore_color,
			total_restored,
			restore_name,
			user.name
		]
	
	return {
		"message": result,
		"damage": total_drained if drain_source == DrainTarget.HP else 0,
		"healing": total_restored if drain_restore == DrainTarget.HP else 0
	}

func _get_resource_color(resource: DrainTarget) -> String:
	"""Get color for resource type"""
	match resource:
		DrainTarget.HP:
			return "red"
		DrainTarget.MP:
			return "cyan"
		DrainTarget.SP:
			return "yellow"
		_:
			return "white"

# ADD this helper method to Skill.gd
# Place it near the other helper methods at the bottom

func _track_reflection_damage(user: CharacterData, target: CharacterData, damage: float) -> Dictionary:
	"""Track reflection damage during skill use"""
	var result = {
		"reflected": false,
		"amount": 0,
		"percent": 0.0,
		"target_name": ""
	}
	
	if not target.status_manager:
		return result
	
	var reflection = target.status_manager.get_total_reflection()
	
	if reflection > 0.0:
		var reflected_damage = int(damage * reflection)
		
		if reflected_damage > 0:
			result.reflected = true
			result.amount = reflected_damage
			result.percent = reflection * 100
			result.target_name = user.name
			
			# Apply reflected damage (pass null to prevent chain)
			user.take_damage(reflected_damage, null)
	
	return result
