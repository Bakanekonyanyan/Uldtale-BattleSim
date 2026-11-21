# scenes/mechanics/Skill.gd
class_name Skill
extends Resource


enum SkillType { DAMAGE, HEAL, BUFF, DEBUFF, RESTORE, INFLICT_STATUS, DRAIN, REVIVE }
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
	REFLECT,      # Buff effect
	EVASIVE,      # Buff effect: flat dodge bonus (append new effects at the end - saves store the number)
	SOAKED,       # Water element: drenched (combos: Conduction, Flash Freeze)
	STAGGERED,    # off balance (shield bashes, heavy kicks): combo set-up
	MARKED,       # hunted / studied (marks, pins): combo set-up
	SEALED        # spirit bound by a seal (Kannagi): combo set-up
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
	PHYSICAL,
	WATER       # appended last: saves store the number
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
## Physical damage type (DamageTypes.Type); FROM_WEAPON (-1) = use the attacker's weapon
@export var damage_type: int = -1
## Bonus when wielding certain gear: {weapon id or type: multiplier}, e.g.
## {"two_handed": 1.25} (Berserker Cleave) or {"shield": 1.2} (Paladin Holy Strike).
## Matches the main hand's or off hand's id or type; the best match applies.
@export var weapon_bonus: Dictionary = {}
## BASIC / ADVANCED / LINK / ULTIMATE... (docs/lore/ABILITY_TYPES.md); talents can key off it
@export var category: String = ""
## Turn order (BattleRules): > 0 pushes enemy targets back that many places,
## < 0 pulls an ally target forward to act next.
@export var turn_delay: int = 0
## Fraction of the user's max HP paid on use (Necromancer blood magic). Never kills.
@export var hp_cost: float = 0.0
## Talent upgrades {power, cooldown, duration, mp_cost, sp_cost} (set by SkillProgressionManager)
var talent_mods: Dictionary = {}

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
	skill.damage_type = DamageTypes.parse(String(data.get("damage_type", "")))
	skill.weapon_bonus = data.get("weapon_bonus", {})
	skill.category = String(data.get("category", "")).to_upper()
	skill.turn_delay = int(data.get("turn_delay", 0))
	skill.hp_cost = float(data.get("hp_cost", 0.0))
	
	# Parse elements
	skill.elements = []
	if data.has("elements") and data.elements is Array:
		for elem_str in data.elements:
			if elem_str != "" and elem_str != "NONE" and ElementType.has(elem_str.to_upper()):
				skill.elements.append(ElementType[elem_str.to_upper()])
	elif data.has("element"):
		# "element" may be one string or (e.g. Blazing Ice Spear) a list - both
		# count. Lists were silently ignored before, leaving such skills elementless.
		var elem_list = data.element if data.element is Array else [data.element]
		for elem_data in elem_list:
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

## Costs: a skill charges every cost it lists (MP and SP, plus hp_cost).
func can_afford(user: CharacterData) -> bool:
	return user.current_mp >= mp_cost and user.current_sp >= sp_cost

func pay_costs(user: CharacterData) -> void:
	user.current_mp -= mp_cost
	user.current_sp -= sp_cost
	if hp_cost > 0.0:   # blood magic, never lethal
		user.current_hp = max(1, user.current_hp - int(round(user.max_hp * hp_cost)))

## "20 MP, 10 SP" style cost text for UI ("Free" if none).
func cost_text() -> String:
	var parts: Array = []
	if mp_cost > 0: parts.append("%d MP" % mp_cost)
	if sp_cost > 0: parts.append("%d SP" % sp_cost)
	if hp_cost > 0.0: parts.append("%d%% HP" % int(round(hp_cost * 100)))
	return ", ".join(parts) if not parts.is_empty() else "Free"

## Damage multiplier from weapon_bonus for what `user` is wielding (1.0 = none).
func weapon_multiplier(user: CharacterData) -> float:
	if weapon_bonus.is_empty() or user == null:
		return 1.0
	var best := 1.0
	for slot in ["main_hand", "off_hand"]:
		var item = user.equipment.get(slot)
		if item is Equipment:
			for k in [item.key, item.type]:
				if weapon_bonus.has(k):
					best = max(best, float(weapon_bonus[k]))
	return best

## e.g. "x1.25 with two-handed" for UI text ("" when no bonus).
func weapon_bonus_text() -> String:
	var parts: Array = []
	for k in weapon_bonus:
		parts.append("x%.2f with %s" % [float(weapon_bonus[k]), String(k).replace("_", " ")])
	return ", ".join(parts)

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
	
	# Only floor at 1 when the skill actually costs that resource; a 0-cost
	# resource must stay 0 (otherwise every skill showed "MP: 1 | SP: 1").
	mp_cost = max(1, int(base_mp_cost * cost_multipliers[level_index])) if base_mp_cost > 0 else 0
	sp_cost = max(1, int(base_sp_cost * cost_multipliers[level_index])) if base_sp_cost > 0 else 0
	cooldown = max(0, base_cooldown - cooldown_reductions[level_index])
	
	# Talent upgrades on top (TalentManager "skill" effects)
	if not talent_mods.is_empty():
		power = max(0, power + int(talent_mods.get("power", 0)))
		duration = max(0, duration + int(talent_mods.get("duration", 0)))
		cooldown = max(0, cooldown + int(talent_mods.get("cooldown", 0)))
		if mp_cost > 0:
			mp_cost = max(1, mp_cost + int(talent_mods.get("mp_cost", 0)))
		if sp_cost > 0:
			sp_cost = max(1, sp_cost + int(talent_mods.get("sp_cost", 0)))

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
		SkillType.REVIVE:
			return revive(user, targets)
	
	return {"message": "Unknown skill type", "damage": 0, "healing": 0}

## Bring knocked-out allies back with `power`% of their max HP (+ any listed
## status, e.g. Regeneration). The battle loop puts them back in the turn order.
func revive(_user: CharacterData, targets: Array) -> Dictionary:
	var raised: Array = []
	var total := 0
	for t in targets:
		if t == null or t.current_hp > 0:
			continue
		if t.status_manager:
			t.status_manager.clear_all_effects()
		t.current_hp = max(1, int(t.max_hp * power / 100.0))
		total += t.current_hp
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				t.apply_status_effect(effect, max(1, duration))
		raised.append(t.name)
	if raised.is_empty():
		return {"message": "%s finds no one to raise." % name, "damage": 0, "healing": 0}
	return {"message": "%s raises %s! (%d HP)" % [name, ", ".join(raised), total], "damage": 0, "healing": total}

# ===== UPDATE ALL SKILL METHODS TO RETURN DICTIONARY =====

func deal_damage(user: CharacterData, targets: Array) -> Dictionary:
	var total_damage = 0
	var target_results = []  #  Track per-target outcomes
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
				ElementType.WATER: elemental_types.append(ElementalDamage.Element.WATER)
	
	var applied_effects := {}  # names of status effects that actually landed
	
	#  PROCESS EACH TARGET (don't early return)
	for t in targets:
		var accuracy_check = RandomManager.randf() < user.accuracy
		var dodge_check = RandomManager.randf() < t.dodge
		
		#  Handle miss/dodge per target
		if not accuracy_check:
			target_results.append({"target": t.name, "missed": true})
			continue
		
		if dodge_check:
			target_results.append({"target": t.name, "dodged": true})
			continue
		
		# Basic-attack math boosted by skill power (see BattleFormulas)
		var damage = BattleFormulas.hit_damage(user, t, ability_type == AbilityType.PHYSICAL, power, damage_type, self) * weapon_multiplier(user)
		# Set-up / payoff combo (data/combos.json): checked before this hit's own statuses land
		var combo = Combos.find(t, Combos.hit_from_skill(user, self))
		if not combo.is_empty():
			damage *= combo.multiplier
		var type_tag = ""
		if ability_type == AbilityType.PHYSICAL:
			var dt = DamageTypes.attack_type(user, damage_type)
			type_tag = DamageTypes.log_tag(DamageTypes.multiplier(t, dt), dt)
		
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
		var crit_mult = BattleFormulas.roll_crit(user)
		var crit_check = crit_mult > 1.0
		damage = BattleFormulas.finalize(damage * crit_mult)
		
		# Reflection
		var reflection_info = _track_reflection_damage(user, t, damage)
		
		# Apply damage
		t.take_damage(damage, user)
		total_damage += damage
		Combos.consume(t, combo)
		BattleFormulas.apply_lifesteal(user, t, damage, ability_type == AbilityType.PHYSICAL, self, damage_type)
		
		# Status riders on damage skills only proc some of the time
		for effect in status_effects:
			if effect != StatusEffect.NONE and t.is_alive() and BattleFormulas.status_procs(true, user):
				t.apply_status_effect(effect, duration)
				applied_effects[StatusEffect.keys()[effect]] = true
		
		#  Record successful hit
		target_results.append({
			"target": t.name,
			"damage": int(damage),
			"crit": crit_check,
			"type_tag": type_tag,
			"combo_msg": Combos.log_line(t, combo) if not combo.is_empty() else "",
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
		
		# Combos
		for res in target_results:
			if res.get("combo_msg", "") != "":
				result_msg += "\n  " + res.combo_msg
		
		# Weak spots / resisted damage types
		for res in target_results:
			if res.get("type_tag", "") != "":
				result_msg += "\n  %s%s" % [res.target, res.type_tag]
		
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
	if not applied_effects.is_empty():
		result_msg += "\nApplied: " + ", ".join(PackedStringArray(applied_effects.keys()))
	
	return {"message": result_msg, "damage": int(total_damage), "healing": 0}

# ===== UPDATE ALL OTHER SKILL METHODS =====

func heal(user: CharacterData, targets: Array) -> Dictionary:
	var total_heal = 0
	for t in targets:
		var heal_amount = BattleFormulas.heal_amount(user, power)
		total_heal += t.heal(heal_amount)  # count actual HP restored, not overheal
	
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
					t.apply_status_effect(effect, BattleFormulas.effect_duration(duration))
	
	# Then apply attribute buffs
	if not attribute_targets.is_empty():
		for t in targets:
			for attribute in attribute_targets:
				if attribute != AttributeTarget.NONE:
					t.apply_buff(attribute, BattleFormulas.buff_amount(t, attribute, power), BattleFormulas.effect_duration(duration))
	
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
			result_parts.append("buffed " + ", ".join(attr_names) + " by +%d%%" % power)
	
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

func apply_debuff(user: CharacterData, targets: Array) -> Dictionary:
	# Debuffs also land a weaker hit so casting one is never a wasted turn
	var total_damage := 0
	var combo_lines: Array = []
	for t in targets:
		if t.is_alive() and BattleFormulas.DEBUFF_HIT_SCALE > 0.0:
			var raw = BattleFormulas.hit_damage(user, t, ability_type == AbilityType.PHYSICAL, 0.0, damage_type, self) * BattleFormulas.DEBUFF_HIT_SCALE * weapon_multiplier(user)
			var combo = Combos.find(t, Combos.hit_from_skill(user, self))
			if not combo.is_empty():
				raw *= combo.multiplier
				combo_lines.append(Combos.log_line(t, combo))
			var hit = BattleFormulas.finalize(raw)
			t.take_damage(hit, user)
			total_damage += hit
			Combos.consume(t, combo)
			BattleFormulas.apply_lifesteal(user, t, hit, ability_type == AbilityType.PHYSICAL, self, damage_type)
		
		for effect in status_effects:
			if effect != StatusEffect.NONE:
				t.apply_status_effect(effect, BattleFormulas.effect_duration(duration))
		
		for attribute in attribute_targets:
			if attribute != AttributeTarget.NONE:
				t.apply_debuff(attribute, BattleFormulas.buff_amount(t, attribute, power), BattleFormulas.effect_duration(duration))
	
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
			result_parts.append("debuffed " + ", ".join(attr_names) + " by -%d%%" % power)
	
	if result_parts.is_empty():
		return {"message": "%s had no effect!" % name, "damage": 0, "healing": 0}
	
	var msg = "%s %s on %d target(s) for %d turns" % [
		name,
		" and ".join(result_parts),
		targets.size(),
		duration
	]
	if total_damage > 0:
		msg = "%s dealt %d damage and %s" % [name, total_damage, msg.trim_prefix(name + " ")]
	for line in combo_lines:
		msg += "\n  " + line
	return {"message": msg, "damage": total_damage, "healing": 0}

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
	var drain_combo_lines: Array = []
	
	for t in targets:
		var drain_amount = 0
		
		match drain_source:
			DrainTarget.HP:
				var raw_drain = BattleFormulas.hit_damage(user, t, ability_type == AbilityType.PHYSICAL, power, damage_type, self) * weapon_multiplier(user)
				var combo = Combos.find(t, Combos.hit_from_skill(user, self))
				if not combo.is_empty():
					raw_drain *= combo.multiplier
					drain_combo_lines.append(Combos.log_line(t, combo))
				drain_amount = BattleFormulas.finalize(raw_drain)
				drain_amount = min(drain_amount, t.current_hp)
				t.take_damage(drain_amount, user)
				Combos.consume(t, combo)
			
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
	
	for line in drain_combo_lines:
		result += "\n  " + line
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

func _track_reflection_damage(user: CharacterData, target: CharacterData, damage: float) -> Dictionary:
	"""Predict reflection for the log. take_damage() applies it (applying it here too doubled it)."""
	return ReflectionInfo.predict(user, target, damage)
