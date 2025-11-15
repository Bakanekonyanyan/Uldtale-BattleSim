# CharacterData.gd - REFACTORED
# Now focuses on: Core stats, combat calculations, equipment
# Status effects → StatusEffectManager
# Buffs/Debuffs → BuffDebuffManager  
# Skills → SkillProgressionManager

extends Resource
class_name CharacterData

# === MANAGERS (handles complex subsystems) ===
var status_manager: StatusEffectManager
var buff_manager: BuffDebuffManager
var skill_manager: SkillProgressionManager

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

# === LEGACY ACCESSORS (for backward compatibility) ===
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

# === PROGRESSION ===
@export var xp: int = 0
@export var attribute_points: int = 0
@export var current_floor: int = 0
@export var max_floor_cleared: int = 0

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

func _init(p_name: String = "", p_race: String = "", p_class: String = ""):
	name = p_name
	race = p_race
	character_class = p_class
	inventory = Inventory.new()
	currency = Currency.new()
	stash = Stash.new()
	
	# Initialize managers
	status_manager = StatusEffectManager.new(self)
	buff_manager = BuffDebuffManager.new(self)
	skill_manager = SkillProgressionManager.new(self)

# === STATS CALCULATION ===

func calculate_secondary_attributes():
	"""Recalculate all derived stats"""
	# Get effective stats (with buffs/debuffs)
	var eff = {}
	for stat in ["vitality", "strength", "dexterity", "intelligence", "faith", "mind", "endurance", "arcane", "agility", "fortitude"]:
		var enum_val = Skill.AttributeTarget[stat.to_upper()]
		eff[stat] = buff_manager.get_effective_attribute(enum_val)
	
	# Resource pools
	max_hp = vitality * 8 + strength * 3
	max_mp = mind * 5 + intelligence * 3
	max_sp = endurance * 5 + agility * 3
	
	# Initialize if needed
	if current_hp == 0 or current_hp > max_hp:
		current_hp = max_hp
	if current_mp == 0 or current_mp > max_mp:
		current_mp = max_mp
	if current_sp == 0 or current_sp > max_sp:
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

# === COMBAT ===

func defend() -> String:
	is_defending = true
	return "%s takes a defensive stance" % name

func reset_defense():
	is_defending = false

func heal(amount: int):
	current_hp += amount
	current_hp = min(current_hp, max_hp)

func restore_mp(amount: int):
	current_mp += amount
	current_mp = min(current_mp, max_mp)

func restore_sp(amount: int):
	current_sp += amount
	current_sp = min(current_sp, max_sp)

func is_alive() -> bool:
	return current_hp > 0

func get_attack_power() -> int:
	var base = attack_power
	if equipment["main_hand"]:
		base += equipment["main_hand"].damage
		if "bonus_damage" in equipment["main_hand"]:
			base += equipment["main_hand"].bonus_damage
	return int(base)

func get_defense() -> int:
	var total = defense
	for slot in equipment:
		if equipment[slot] and equipment[slot].armor_value:
			total += equipment[slot].armor_value
	return total

# === EQUIPMENT ===

func equip_item(item: Equipment) -> Equipment:
	if not item.can_equip(self):
		print("Cannot equip %s - class restriction" % item.name)
		return null
	
	var old_item = equipment[item.slot]
	
	if old_item:
		unequip_item(item.slot)
	
	equipment[item.slot] = item
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

# === MANAGER DELEGATES ===

func add_skills(skill_names: Array):
	skill_manager.add_skills(skill_names)

func use_skill(skill_name: String) -> String:
	return skill_manager.use_skill(skill_name)

func get_skill_instance(skill_name: String) -> Skill:
	return skill_manager.get_skill_instance(skill_name)

func use_skill_cooldown(skill_name: String, turns: int):
	skill_manager.set_cooldown(skill_name, turns)

func is_skill_ready(skill_name: String) -> bool:
	return skill_manager.is_skill_ready(skill_name)

func get_skill_cooldown(skill_name: String) -> int:
	return skill_manager.get_cooldown(skill_name)

func reduce_cooldowns():
	skill_manager.reduce_cooldowns()

func apply_status_effect(effect: Skill.StatusEffect, duration: int) -> String:
	return status_manager.apply_effect(effect, duration)

func remove_status_effect(effect: Skill.StatusEffect) -> String:
	return status_manager.remove_effect(effect)

func update_status_effects() -> String:
	var msg = status_manager.update_effects()
	buff_manager.update_buffs_and_debuffs()
	return msg

func apply_buff(attr: Skill.AttributeTarget, value: int, duration: int):
	buff_manager.apply_buff(attr, value, duration)

func apply_debuff(attr: Skill.AttributeTarget, value: int, duration: int):
	buff_manager.apply_debuff(attr, value, duration)

func get_attribute_with_buffs_and_debuffs(attr: Skill.AttributeTarget) -> int:
	return buff_manager.get_effective_attribute(attr)

func get_status_effects_string() -> String:
	var effects = []
	effects.append(status_manager.get_effects_string())
	
	if buff_manager.has_buffs():
		effects.append("Buffs: " + buff_manager.get_buffs_string())
	if buff_manager.has_debuffs():
		effects.append("Debuffs: " + buff_manager.get_debuffs_string())
	
	return " | ".join(effects) if not effects.is_empty() else "Normal"

# === LEVELING ===

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
		var attr = randi() % 10
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
	currency.copper = 0
	for slot in equipment:
		equipment[slot] = null
	level = 1

func update_max_floor_cleared(floor: int):
	if floor > max_floor_cleared:
		max_floor_cleared = floor
		print("New max floor: %d" % max_floor_cleared)

func take_damage(amount: float, attacker: CharacterData = null):
	"""Take damage with reflection support"""
	
	# Store attacker for reflection
	if attacker:
		last_attacker = attacker
	
	# Apply defense reduction
	if is_defending:
		amount *= 0.5
	
	# ✅ REFLECTION MECHANIC
	if last_attacker and last_attacker != self:
		var reflection = status_manager.get_total_reflection()
		
		if reflection > 0.0:
			var reflected_damage = int(amount * reflection)
			
			if reflected_damage > 0:
				print("%s reflected %d damage back to %s!" % [name, reflected_damage, last_attacker.name])
				
				# Apply reflected damage (no further reflection chain)
				last_attacker.take_damage(reflected_damage, null)
	
	# Apply damage
	current_hp -= int(amount)
	current_hp = max(0, current_hp)

# =============================================
# UPDATE ATTACK TO PASS ATTACKER
# =============================================

func attack(target: CharacterData) -> String:
	"""Execute basic attack with attacker tracking"""
	if not target or not is_instance_valid(target):
		return "%s's attack failed - no valid target!" % name
	
	var momentum_mult = MomentumSystem.get_damage_multiplier()
	var base_damage = get_attack_power() * 0.5 * momentum_mult
	var resistance = target.get_defense()
	
	# Rolls
	if randf() >= accuracy:
		return "%s's attack missed!" % name
	if randf() < target.dodge:
		return "%s dodged the attack!" % target.name
	
	var is_crit = randf() < critical_hit_rate
	var damage = max(1, base_damage - resistance)
	
	if is_crit:
		damage *= 1.5 + randf() * 0.5
	
	damage = round(damage)
	
	# ✅ PASS ATTACKER TO take_damage()
	target.take_damage(damage, self)
	
	# Status effect from weapon
	var status_msg = ""
	if equipment["main_hand"] and equipment["main_hand"] is Equipment:
		var weapon = equipment["main_hand"]
		if "status_effect_type" in weapon and "status_effect_chance" in weapon:
			if weapon.status_effect_type != Skill.StatusEffect.NONE:
				if weapon.has_method("try_apply_status_effect"):
					if weapon.try_apply_status_effect(target):
						status_msg = " and applied %s" % Skill.StatusEffect.keys()[weapon.status_effect_type]
	
	# Resource regen
	var mp_restore = int(max_mp * 0.08)
	var sp_restore = int(max_sp * 0.08)
	restore_mp(mp_restore)
	restore_sp(sp_restore)
	
	var result = "%s attacks %s for %d damage" % [name, target.name, damage]
	
	if momentum_mult > 1.0:
		result += " (+%d%% momentum)" % int((momentum_mult - 1.0) * 100)
	
	result += " and restores %d MP, %d SP%s" % [mp_restore, sp_restore, status_msg]
	
	if is_crit:
		result = "Critical hit! " + result
	
	return result
