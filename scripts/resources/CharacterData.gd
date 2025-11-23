# CharacterData.gd - FINAL REFACTORED VERSION
# Managers that store state: Instances (status, buff, skill, proficiency, elemental)
# Managers that are stateless: Static utilities (resource, progression, combat)

extends Resource
class_name CharacterData

# === STATEFUL MANAGERS (need instance, store character reference) ===
var status_manager: StatusEffectManager
var buff_manager: BuffDebuffManager
var skill_manager: SkillProgressionManager
var proficiency_manager: ProficiencyManager
var elemental_resistances: ElementalResistanceManager
# Note: ResourceManager and ProgressionManager are NOT here - they're static utilities

# === BASIC INFO ===
@export var name: String
@export var race: String
@export var character_class: String
@export var level: int = 1
@export var is_player: bool = false

# === PRIMARY ATTRIBUTES ===
@export var vitality: int
@export var strength: int
@export var dexterity: int
@export var intelligence: int
@export var faith: int
@export var mind: int
@export var endurance: int
@export var arcane: int
@export var agility: int
@export var fortitude: int

# === SECONDARY ATTRIBUTES ===
@export var max_hp: int
@export var current_hp: int
@export var max_mp: int
@export var current_mp: int
@export var max_sp: int
@export var current_sp: int
@export var toughness: float
@export var dodge: float
@export var spell_ward: float
@export var accuracy: float
@export var attack_power: float
@export var spell_power: float
@export var critical_hit_rate: float
@export var defense: int
@export var armor_penetration: float = 0

# === POWER TYPES ===
var attack_power_type: String = "strength"
var spell_power_type: String = "intelligence"

# === COMBAT STATE ===
var is_defending: bool = false
var is_stunned: bool = false
var last_attacker: CharacterData = null

# === PROGRESSION ===
@export var xp: int = 0
@export var attribute_points: int = 0
@export var current_floor: int = 0
@export var max_floor_cleared: int = 0

# === EQUIPMENT BONUSES (separate from base attributes) ===
var equipment_bonuses: Dictionary = {}

# === INVENTORY & EQUIPMENT ===
@export var inventory: Inventory
@export var currency: Currency
@export var stash: Stash
var equipment = {
	"main_hand": null,
	"off_hand": null,
	"head": null,
	"chest": null,
	"hands": null,
	"legs": null,
	"feet": null
}

# === LEGACY ACCESSORS ===
var skills: Array:
	get: return skill_manager.get_all_skills() if skill_manager else []
var status_effects: Dictionary:
	get: return status_manager.get_active_effects() if status_manager else {}
var buffs: Dictionary:
	get: return buff_manager.buffs if buff_manager else {}
var debuffs: Dictionary:
	get: return buff_manager.debuffs if buff_manager else {}
var skill_cooldowns: Dictionary:
	get: return skill_manager.skill_cooldowns if skill_manager else {}
var skill_levels: Dictionary:
	get: return skill_manager.skill_levels if skill_manager else {}

func _init(p_name: String = "", p_race: String = "", p_class: String = ""):
	name = p_name
	race = p_race
	character_class = p_class
	inventory = Inventory.new()
	currency = Currency.new()
	stash = Stash.new()
	
	# Initialize ONLY stateful managers
	status_manager = StatusEffectManager.new(self)
	buff_manager = BuffDebuffManager.new(self)
	skill_manager = SkillProgressionManager.new(self)
	proficiency_manager = ProficiencyManager.new(self)
	elemental_resistances = ElementalResistanceManager.new(self)

func initialize_racial_elementals(load_from_race_data: bool = true):
	if not load_from_race_data or race.is_empty():
		return
	
	if not elemental_resistances:
		push_error("CharacterData.initialize_racial_elementals: elemental_resistances manager not initialized!")
		return
	
	RaceElementalData.apply_to_character(self, race, is_player)
	print("[ELEMENTAL] Initialized racial elementals for %s (%s)" % [name, race])

func calculate_secondary_attributes():
	# Calculate effective attributes: base + equipment + buffs/debuffs
	var eff = {}
	for stat in ["vitality", "strength", "dexterity", "intelligence", "faith", "mind", "endurance", "arcane", "agility", "fortitude"]:
		var base_value = get(stat)
		var equipment_bonus = equipment_bonuses.get(stat, 0)
		var enum_val = Skill.AttributeTarget[stat.to_upper()]
		
		# Get buff/debuff modifier (this should NOT include equipment)
		var buff_modifier = 0
		if buff_manager:
			var buffed = buff_manager.get_effective_attribute(enum_val)
			buff_modifier = buffed - base_value
		
		eff[stat] = base_value + equipment_bonus + buff_modifier
	
	var old_max_hp = max_hp
	var old_max_mp = max_mp
	var old_max_sp = max_sp
	
	# Resource pools - use BASE attributes only (no equipment/buffs)
	max_hp = vitality * 8 + strength * 3
	max_mp = mind * 5 + intelligence * 3
	max_sp = endurance * 5 + agility * 3
	
	# Initialize resources on first calculation
	if max_hp > 0 and old_max_hp == 0 and current_hp == 0:
		current_hp = max_hp
	elif current_hp > max_hp:
		current_hp = max_hp
	
	if max_mp > 0 and old_max_mp == 0 and current_mp == 0:
		current_mp = max_mp
	elif current_mp > max_mp:
		current_mp = max_mp
	
	if max_sp > 0 and old_max_sp == 0 and current_sp == 0:
		current_sp = max_sp
	elif current_sp > max_sp:
		current_sp = max_sp
	
	# Defensive
	toughness = (eff.vitality * 0.45 + eff.strength * 0.25 + eff.endurance * 0.15 + eff.fortitude * 0.15) / 10.0
	dodge = 0.05 + (eff.agility * 0.55 + eff.dexterity * 0.35 + eff.fortitude * 0.10) / 200.0
	spell_ward = (eff.fortitude * 0.5) * (0.6 * eff.arcane + 0.3 * eff.mind + 0.1 * eff.faith) / 10.0
	
	# Offensive
	accuracy = 0.75 + (eff.dexterity * 0.35 + eff.agility * 0.25 + eff.mind * 0.25 + eff.fortitude * 0.15) / 200.0
	critical_hit_rate = 0.05 + (eff.dexterity * 0.4 + eff.agility * 0.25 + eff.intelligence * 0.2 + eff.fortitude * 0.15) / 200.0
	
	# Attack power
	match attack_power_type:
		"strength":
			attack_power = eff.strength * 2 + eff.dexterity * 0.5 + eff.vitality * 0.5
		"dexterity":
			attack_power = eff.dexterity * 2 + eff.strength * 0.5 + eff.agility * 0.5
	
	# Spell power
	match spell_power_type:
		"balanced":
			spell_power = (eff.intelligence * 1.5 + eff.faith * 1.5 + eff.arcane * 1.5) / 2
		"intelligence":
			spell_power = eff.intelligence * 2 + eff.faith + eff.arcane
		"arcane":
			spell_power = eff.arcane * 2 + eff.intelligence + eff.faith

# === RESOURCE MANAGEMENT (delegates to static utility) ===
func heal(amount: int) -> int:
	var hp_before = current_hp
	var max_heal = max_hp - current_hp
	var actual_heal = min(amount, max_heal)
	
	current_hp += actual_heal
	current_hp = min(current_hp, max_hp)
	
	print("[HEAL] %s: %d → %d (+%d)" % [name, hp_before, current_hp, actual_heal])
	return actual_heal

func restore_mp(amount: int) -> int:
	var mp_before = current_mp
	var actual = min(amount, max_mp - current_mp)
	current_mp += actual
	current_mp = min(current_mp, max_mp)
	print("[MP] %s: %d → %d (+%d)" % [name, mp_before, current_mp, actual])
	return actual

func restore_sp(amount: int) -> int:
	var sp_before = current_sp
	var actual = min(amount, max_sp - current_sp)
	current_sp += actual
	current_sp = min(current_sp, max_sp)
	print("[SP] %s: %d → %d (+%d)" % [name, sp_before, current_sp, actual])
	return actual

# === COMBAT ===
func defend() -> String:
	is_defending = true
	return "%s takes a defensive stance" % name

func reset_defense():
	is_defending = false

func is_alive() -> bool:
	return current_hp > 0

func get_defense() -> float:
	return toughness

func get_attack_power() -> float:
	return attack_power

func get_spell_power() -> float:
	return spell_power

func attack(target: CharacterData) -> String:
	# Use CombatActions if available, otherwise inline
	if ClassDB.class_exists("CombatActions"):
		return CombatActions.execute_basic_attack(self, target)
	else:
		# Fallback inline implementation
		return _basic_attack_inline(target)

func _basic_attack_inline(target: CharacterData) -> String:
	var momentum_mult = MomentumSystem.get_damage_multiplier()
	var base_damage = get_attack_power() * 0.5 * momentum_mult
	var resistance = target.get_defense()
	
	if RandomManager.randf() >= accuracy:
		return "%s's attack missed!" % name
	if RandomManager.randf() < target.dodge:
		return "%s dodged the attack!" % target.name
	
	var is_crit = RandomManager.randf() < critical_hit_rate
	var damage = max(1, base_damage - resistance)
	
	if is_crit:
		damage *= 1.5 + RandomManager.randf() * 0.5
	
	damage = round(damage)
	target.take_damage(damage, self)
	
	var mp_restore = int(max_mp * 0.08)
	var sp_restore = int(max_sp * 0.08)
	restore_mp(mp_restore)
	restore_sp(sp_restore)
	
	var result = "%s attacks %s for %d damage and restores %d MP, %d SP" % [
		name, target.name, damage, mp_restore, sp_restore
	]
	
	if is_crit:
		result = "Critical hit! " + result
	
	return result

func take_damage(amount: float, attacker: CharacterData = null):
	if current_hp <= 0:
		current_hp = 0
		return
	
	# Track armor proficiency
	track_armor_proficiency()
	
	if attacker:
		last_attacker = attacker
	
	if is_defending:
		amount *= 0.5
	
	# Reflection
	if last_attacker and last_attacker != self:
		var reflection = status_manager.get_total_reflection() if status_manager else 0.0
		if reflection > 0.0:
			var reflected = int(amount * reflection)
			if reflected > 0:
				print("%s reflected %d damage back to %s!" % [name, reflected, last_attacker.name])
				last_attacker.take_damage(reflected, null)
	
	current_hp -= int(amount)
	current_hp = clamp(current_hp, 0, max_hp)
	print("[DAMAGE] %s took %d damage. HP: %d/%d" % [name, int(amount), current_hp, max_hp])

# === EQUIPMENT ===
func equip_item(item: Equipment) -> Equipment:
	if not item.can_equip(self):
		print("Cannot equip %s - class restriction" % item.display_name)
		return null
	
	var target_slot = item.slot
	
	# === DUAL WIELD LOGIC ===
	if item.dual_wieldable and item.can_dual_wield(self):
		# Dual wieldable weapon - check preferred slot first
		if equipment[item.preferred_slot] == null:
			target_slot = item.preferred_slot
		elif item.preferred_slot == "main_hand" and equipment["off_hand"] == null:
			target_slot = "off_hand"
		elif item.preferred_slot == "off_hand" and equipment["main_hand"] == null:
			target_slot = "main_hand"
		else:
			# Both slots occupied, use preferred slot
			target_slot = item.preferred_slot
	
	# === TWO-HANDED BLOCKING ===
	if target_slot == "main_hand" and equipment["main_hand"]:
		var main_hand = equipment["main_hand"]
		if main_hand.blocks_offhand and equipment["off_hand"]:
			# Check if offhand is allowed
			if not main_hand.allows_offhand(self, equipment["off_hand"]):
				# Unequip offhand before equipping new main hand
				unequip_item("off_hand")
	
	# Check if equipping item blocks offhand
	if item.blocks_offhand and equipment["off_hand"]:
		if not item.allows_offhand(self, equipment["off_hand"]):
			unequip_item("off_hand")
	
	# Check if equipping offhand is blocked by main hand
	if target_slot == "off_hand" and equipment["main_hand"]:
		var main_hand = equipment["main_hand"]
		if main_hand.blocks_offhand:
			if not main_hand.allows_offhand(self, item):
				print("Cannot equip %s: blocked by %s" % [item.display_name, main_hand.display_name])
				return null
	
	var old_item = equipment[target_slot]
	
	if old_item:
		unequip_item(target_slot)
	
	equipment[target_slot] = item
	item.apply_effects(self)
	
	if item.has_method("apply_stat_modifiers"):
		item.apply_stat_modifiers(self)
	
	if inventory.items.has(item.inventory_key if item.inventory_key != "" else item.id):
		inventory.remove_item(item.inventory_key if item.inventory_key != "" else item.id, 1)
	
	calculate_secondary_attributes()
	return old_item

func unequip_item(slot: String) -> Equipment:
	var item = equipment[slot]
	if item:
		item.remove_effects(self)
		if item.has_method("remove_stat_modifiers"):
			item.remove_stat_modifiers(self)
		
		equipment[slot] = null
		inventory.add_item(item, 1)
		calculate_secondary_attributes()
	return item

func swap_hands() -> bool:
	"""Swap main_hand and off_hand equipment"""
	var main = equipment["main_hand"]
	var off = equipment["off_hand"]
	
	# Can't swap if either is null
	if not main or not off:
		return false
	
	# Can't swap if main hand blocks offhand
	if main.blocks_offhand and not main.allows_offhand(self, off):
		return false
	
	# Check if both are dual wieldable or compatible
	var main_can_go_off = main.dual_wieldable and main.can_dual_wield(self)
	var off_can_go_main = off.slot == "main_hand" or (off.dual_wieldable and off.can_dual_wield(self))
	
	if not (main_can_go_off and off_can_go_main):
		return false
	
	# Temporarily remove effects
	main.remove_effects(self)
	off.remove_effects(self)
	if main.has_method("remove_stat_modifiers"):
		main.remove_stat_modifiers(self)
	if off.has_method("remove_stat_modifiers"):
		off.remove_stat_modifiers(self)
	
	# Swap
	equipment["main_hand"] = off
	equipment["off_hand"] = main
	
	# Reapply effects
	off.apply_effects(self)
	main.apply_effects(self)
	if off.has_method("apply_stat_modifiers"):
		off.apply_stat_modifiers(self)
	if main.has_method("apply_stat_modifiers"):
		main.apply_stat_modifiers(self)
	
	calculate_secondary_attributes()
	return true

# === SKILL DELEGATES ===
func add_skills(skill_names: Array):
	if skill_manager:
		skill_manager.add_skills(skill_names)

func use_skill(skill_name: String) -> String:
	return skill_manager.use_skill(skill_name) if skill_manager else ""

func get_skill_instance(skill_name: String) -> Skill:
	return skill_manager.get_skill_instance(skill_name) if skill_manager else null

func use_skill_cooldown(skill_name: String, turns: int):
	if skill_manager:
		skill_manager.set_cooldown(skill_name, turns)

func is_skill_ready(skill_name: String) -> bool:
	return skill_manager.is_skill_ready(skill_name) if skill_manager else false

func get_skill_cooldown(skill_name: String) -> int:
	return skill_manager.get_cooldown(skill_name) if skill_manager else 0

func reduce_cooldowns():
	if skill_manager:
		skill_manager.reduce_cooldowns()

# === STATUS EFFECT DELEGATES ===
func apply_status_effect(effect: Skill.StatusEffect, duration: int) -> String:
	return status_manager.apply_effect(effect, duration) if status_manager else ""

func remove_status_effect(effect: Skill.StatusEffect) -> String:
	return status_manager.remove_effect(effect) if status_manager else ""

func has_status_effect(effect: Skill.StatusEffect) -> bool:
	return status_manager.has_effect(effect) if status_manager else false

func update_status_effects() -> String:
	var msg = ""
	if status_manager:
		msg = status_manager.update_effects()
	if buff_manager:
		buff_manager.update_buffs_and_debuffs()
	return msg

func get_status_effects_string() -> String:
	var effects = []
	
	if status_manager:
		var status_str = status_manager.get_effects_string()
		if status_str != "None":
			effects.append(status_str)
	
	if buff_manager:
		if buff_manager.has_buffs():
			effects.append("Buffs: " + buff_manager.get_buffs_string())
		if buff_manager.has_debuffs():
			effects.append("Debuffs: " + buff_manager.get_debuffs_string())
	
	return " | ".join(effects) if not effects.is_empty() else "None"

func check_confusion_self_harm() -> Dictionary:
	if status_manager:
		return status_manager.check_confusion_self_harm()
	return {"success": false, "damage": 0, "message": ""}

func get_total_reflection() -> float:
	if status_manager:
		return status_manager.get_total_reflection()
	return 0.0

func get_bleed_stacks() -> int:
	if status_manager:
		return status_manager.get_bleed_stacks()
	return 0

# === BUFF/DEBUFF DELEGATES ===
func apply_buff(attr: Skill.AttributeTarget, value: int, duration: int):
	if buff_manager:
		buff_manager.apply_buff(attr, value, duration)

func apply_debuff(attr: Skill.AttributeTarget, value: int, duration: int):
	if buff_manager:
		buff_manager.apply_debuff(attr, value, duration)

func get_attribute_with_buffs_and_debuffs(attr: Skill.AttributeTarget) -> int:
	return buff_manager.get_effective_attribute(attr) if buff_manager else get(Skill.AttributeTarget.keys()[attr].to_lower())

func get_effective_attribute(attr: Skill.AttributeTarget) -> int:
	"""Get attribute value including base + equipment + buffs/debuffs"""
	var stat_name = Skill.AttributeTarget.keys()[attr].to_lower()
	var base = get(stat_name)
	var equipment_bonus = equipment_bonuses.get(stat_name, 0)
	var buff_modifier = 0
	
	if buff_manager:
		buff_modifier = buff_manager.get_effective_attribute(attr) - base
	
	return base + equipment_bonus + buff_modifier

# === DISPLAY HELPERS ===
func get_attribute_display(attribute_name: String) -> String:
	"""Returns formatted string: 'Mind: 21 (+7)' or 'Mind: 21' if no bonus"""
	var base = get(attribute_name)
	var bonus = equipment_bonuses.get(attribute_name, 0)
	
	if bonus > 0:
		return "%s: %d (+%d)" % [attribute_name.capitalize(), base, bonus]
	elif bonus < 0:
		return "%s: %d (%d)" % [attribute_name.capitalize(), base, bonus]
	else:
		return "%s: %d" % [attribute_name.capitalize(), base]

func get_attribute_display_compact(attribute_name: String) -> String:
	"""Returns compact format: '21 (+7)' or just '21'"""
	var base = get(attribute_name)
	var bonus = equipment_bonuses.get(attribute_name, 0)
	
	if bonus > 0:
		return "%d (+%d)" % [base, bonus]
	elif bonus < 0:
		return "%d (%d)" % [base, bonus]
	else:
		return "%d" % base

func get_attribute_breakdown(attribute_name: String) -> Dictionary:
	"""
	Get detailed breakdown of attribute sources
	Returns: {base: int, equipment: int, buffs: int, total: int}
	"""
	var base = get(attribute_name)
	var equipment_bonus = equipment_bonuses.get(attribute_name, 0)
	
	var buff_modifier = 0
	if buff_manager and attribute_name.to_upper() in Skill.AttributeTarget:
		var enum_val = Skill.AttributeTarget[attribute_name.to_upper()]
		var buffed = buff_manager.get_effective_attribute(enum_val)
		buff_modifier = buffed - base
	
	return {
		"base": base,
		"equipment": equipment_bonus,
		"buffs": buff_modifier,
		"total": base + equipment_bonus + buff_modifier
	}

# === PROGRESSION (keep existing implementation) ===
func gain_xp(amount: int):
	xp += amount
	print("[XP] %s gained %d XP. Total: %d/%d" % [name, amount, xp, LevelSystem.calculate_xp_for_level(level)])
	check_level_up()

func check_level_up():
	var xp_required = LevelSystem.calculate_xp_for_level(level)
	while xp >= xp_required:
		level_up()
		xp -= xp_required
		xp_required = LevelSystem.calculate_xp_for_level(level)

func level_up():
	level += 1
	vitality += 1
	strength += 1
	dexterity += 1
	intelligence += 1
	faith += 1
	mind += 1
	endurance += 1
	arcane += 1
	agility += 1
	fortitude += 1
	
	if is_player:
		attribute_points += 3
	else:
		distribute_enemy_points()
	
	calculate_secondary_attributes()

func distribute_enemy_points():
	for _i in range(3):
		var attr = RandomManager.randi() % 10
		match attr:
			0: vitality += 1
			1: strength += 1
			2: dexterity += 1
			3: intelligence += 1
			4: faith += 1
			5: mind += 1
			6: endurance += 1
			7: arcane += 1
			8: agility += 1
			9: fortitude += 1

func spend_attribute_point(attribute: String) -> bool:
	if attribute_points > 0 and attribute in self:
		set(attribute, get(attribute) + 1)
		attribute_points -= 1
		calculate_secondary_attributes()
		return true
	return false

func update_max_floor_cleared(floor: int):
	if floor > max_floor_cleared:
		max_floor_cleared = floor
		print("New max floor: %d" % max_floor_cleared)

# === PROFICIENCY ===
func track_weapon_proficiency():
	if equipment["main_hand"] and proficiency_manager:
		var weapon = equipment["main_hand"]
		if weapon is Equipment:
			var key = EquipmentKeyHelper.get_equipment_key(weapon)
			if key != "":
				proficiency_manager.use_weapon(key)

func track_armor_proficiency():
	if not proficiency_manager:
		return
	var armor_slots = ["head", "chest", "hands", "legs", "feet"]
	for slot in armor_slots:
		if equipment[slot] and equipment[slot] is Equipment:
			var armor = equipment[slot]
			if armor.type in ["cloth", "leather", "mail", "plate"]:
				proficiency_manager.use_armor(armor.type)
				break

func debug_proficiency_status():
	if not proficiency_manager:
		print("[PROFICIENCY] ERROR: No proficiency manager!")
		return
	print("=== PROFICIENCY DEBUG ===")
	if equipment["main_hand"]:
		var weapon = equipment["main_hand"]
		print("Main Hand: %s" % weapon.name)
		if weapon is Equipment and weapon.key != "":
			var uses = proficiency_manager.get_weapon_proficiency_uses(weapon.key)
			var level = proficiency_manager.get_weapon_proficiency_level(weapon.key)
			var next = proficiency_manager.get_uses_for_next_level(level)
			print("  Proficiency: Level %d (%d/%d uses)" % [level, uses, next])
	print("========================")

# === ELEMENTAL DELEGATES ===
func get_elemental_resistance(element: ElementalDamage.Element) -> float:
	return elemental_resistances.get_total_resistance(element) if elemental_resistances else 0.0

func get_elemental_weakness(element: ElementalDamage.Element) -> float:
	return elemental_resistances.get_total_weakness(element) if elemental_resistances else 0.0

func get_elemental_damage_bonus(element: ElementalDamage.Element) -> float:
	return elemental_resistances.get_total_damage_bonus(element) if elemental_resistances else 0.0

func add_temp_elemental_resistance(element: ElementalDamage.Element, value: float):
	if elemental_resistances:
		elemental_resistances.add_temp_resistance(element, value)

func add_temp_elemental_weakness(element: ElementalDamage.Element, value: float):
	if elemental_resistances:
		elemental_resistances.add_temp_weakness(element, value)

func add_temp_elemental_damage_bonus(element: ElementalDamage.Element, value: float):
	if elemental_resistances:
		elemental_resistances.add_temp_damage_bonus(element, value)

func clear_temp_elemental_modifiers():
	if elemental_resistances:
		elemental_resistances.clear_temp_modifiers()

# === RESET ===
func reset_for_new_battle():
	current_hp = max_hp
	current_mp = max_mp
	current_sp = max_sp
	status_manager.clear_all_effects()
	skill_manager.clear_cooldowns()
	buff_manager.clear_all()
	is_stunned = false
	is_defending = false

func reset_for_new_game():
	calculate_secondary_attributes()
	current_hp = max_hp
	current_mp = max_mp
	current_sp = max_sp
	inventory.clear()
	currency.copper = 500
	for slot in equipment:
		equipment[slot] = null
	equipment_bonuses.clear()
	level = 1
