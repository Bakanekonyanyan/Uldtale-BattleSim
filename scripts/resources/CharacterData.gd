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
var proficiency_manager: ProficiencyManager
var elemental_resistances: ElementalResistanceManager


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
	proficiency_manager = ProficiencyManager.new(self)
	elemental_resistances = ElementalResistanceManager.new(self)  # ADD THIS LINE

# Add this method (replaces the one I suggested before)
func initialize_racial_elementals(load_from_race_data: bool = true):
	"""Initialize elemental modifiers from race data using RaceElementalData autoload"""
	if not load_from_race_data or race.is_empty():
		return
	
	if not elemental_resistances:
		push_error("CharacterData.initialize_racial_elementals: elemental_resistances manager not initialized!")
		return
	
	# Use the autoload singleton to apply racial data
	RaceElementalData.apply_to_character(self, race, is_player)
	
	print("[ELEMENTAL] Initialized racial elementals for %s (%s)" % [name, race])

func calculate_secondary_attributes():
	"""Recalculate all derived stats"""
	# Get effective stats (with buffs/debuffs)
	var eff = {}
	for stat in ["vitality", "strength", "dexterity", "intelligence", "faith", "mind", "endurance", "arcane", "agility", "fortitude"]:
		var enum_val = Skill.AttributeTarget[stat.to_upper()]
		eff[stat] = buff_manager.get_effective_attribute(enum_val)
	
	#  CRITICAL: Store old max values BEFORE recalculating
	var old_max_hp = max_hp
	var old_max_mp = max_mp
	var old_max_sp = max_sp
	
	# Resource pools
	max_hp = vitality * 8 + strength * 3
	max_mp = mind * 5 + intelligence * 3
	max_sp = endurance * 5 + agility * 3
	
	#  CRITICAL FIX: Only initialize if resources are ZERO (new character)
	# DO NOT reset if they just exceed max (happens with buffs/debuffs)
	# Only initialize HP on first calculation (when max_hp was 0)
	if max_hp > 0 and old_max_hp == 0 and current_hp == 0:
		# First time calculating stats - initialize to full
		current_hp = max_hp
		print("[CHAR] First initialization - HP set to %d" % max_hp)
	elif current_hp > max_hp:
		# Stat debuff reduced max HP below current - clamp down
		current_hp = max_hp
		print("[CHAR] Clamped HP from above to new max: %d" % max_hp)
		# else: Leave current_hp as-is (including 0 for dead characters)

	# Same logic for MP
	if max_mp > 0 and old_max_mp == 0 and current_mp == 0:
		current_mp = max_mp
	elif current_mp > max_mp:
		current_mp = max_mp

	# Same logic for SP
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

#  FIX 2: heal() - Add logging and return actual heal amount
func heal(amount: int) -> int:
	"""Heal the character, returns actual amount healed"""
	var hp_before = current_hp
	var max_heal = max_hp - current_hp
	var actual_heal = min(amount, max_heal)
	
	current_hp += actual_heal
	current_hp = min(current_hp, max_hp)  # Safety clamp
	
	var hp_after = current_hp
	
	print("[HEAL] %s: %d → %d (+%d requested, +%d actual, max: %d)" % [
		name, hp_before, hp_after, amount, actual_heal, max_hp
	])
	
	return actual_heal

#  FIX 3: restore_mp - Add logging
func restore_mp(amount: int) -> int:
	"""Restore MP, returns actual amount restored"""
	var mp_before = current_mp
	var max_restore = max_mp - current_mp
	var actual_restore = min(amount, max_restore)
	
	current_mp += actual_restore
	current_mp = min(current_mp, max_mp)
	
	print("[RESTORE MP] %s: %d → %d (+%d)" % [name, mp_before, current_mp, actual_restore])
	return actual_restore

#  FIX 4: restore_sp - Add logging
func restore_sp(amount: int) -> int:
	"""Restore SP, returns actual amount restored"""
	var sp_before = current_sp
	var max_restore = max_sp - current_sp
	var actual_restore = min(amount, max_restore)
	
	current_sp += actual_restore
	current_sp = min(current_sp, max_sp)
	
	print("[RESTORE SP] %s: %d → %d (+%d)" % [name, sp_before, current_sp, actual_restore])
	return actual_restore
# === COMBAT ===

func defend() -> String:
	is_defending = true
	return "%s takes a defensive stance" % name

func reset_defense():
	is_defending = false

func is_alive() -> bool:
	# Safety: Ensure HP never goes negative
	if current_hp < 0:
		current_hp = 0
	return current_hp > 0

func get_attack_power() -> int:
	var base = attack_power
	if equipment["main_hand"]:
		var weapon = equipment["main_hand"]
		var weapon_damage = weapon.damage
		
		# NEW: Apply proficiency bonus using specific weapon key
		if proficiency_manager:
			var weapon_key = EquipmentKeyHelper.get_equipment_key(weapon)
			if weapon_key != "":
				var prof_mult = proficiency_manager.get_weapon_damage_multiplier(weapon_key)
				weapon_damage = int(weapon_damage * prof_mult)
		
		base += weapon_damage
		if "bonus_damage" in weapon:
			base += weapon.bonus_damage
	
	return int(base)

func get_defense() -> int:
	var total = defense
	
	for slot in equipment:
		if equipment[slot] and equipment[slot].armor_value:
			var armor = equipment[slot]
			var armor_value = armor.armor_value
			
			# NEW: Apply proficiency bonus
			if proficiency_manager and armor.type in ["cloth", "leather", "mail", "plate"]:
				var prof_mult = proficiency_manager.get_armor_effectiveness_multiplier(armor.type)
				armor_value = int(armor_value * prof_mult)
			
			total += armor_value
	
	return total

# === EQUIPMENT ===

func equip_item(item: Equipment) -> Equipment:
	if not item.can_equip(self):
		print("Cannot equip %s - class restriction" % item.display_name)
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
	# ADD THIS LINE - remove stat modifiers too
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
	level = 1

func update_max_floor_cleared(floor: int):
	if floor > max_floor_cleared:
		max_floor_cleared = floor
		print("New max floor: %d" % max_floor_cleared)

# =============================================
# UPDATE ATTACK TO PASS ATTACKER
# =============================================
# Add these methods to CharacterData.gd for complete proficiency tracking

func track_weapon_proficiency():
	"""Track weapon proficiency usage"""
	if not equipment["main_hand"] or not proficiency_manager:
		return
	
	var weapon = equipment["main_hand"]
	if not weapon is Equipment:
		return
	
	var weapon_key = EquipmentKeyHelper.get_equipment_key(weapon)
	if weapon_key != "":
		var msg = proficiency_manager.use_weapon(weapon_key)
		if msg != "":
			print("[PROFICIENCY] %s" % msg)

func track_armor_proficiency():
	"""Track armor proficiency - call this when taking damage"""
	if not proficiency_manager:
		return
	
	# Track each equipped armor piece
	var armor_slots = ["head", "chest", "hands", "legs", "feet"]
	for slot in armor_slots:
		if equipment[slot] and equipment[slot] is Equipment:
			var armor = equipment[slot]
			if armor.type in ["cloth", "leather", "mail", "plate"]:
				var msg = proficiency_manager.use_armor(armor.type)
				if msg != "":
					print("[PROFICIENCY] %s" % msg)
					# Only show one armor level up per damage instance
					break

func take_damage(amount: float, attacker: CharacterData = null):
	"""Take damage with reflection mechanics and armor proficiency tracking"""
	
	#  CRITICAL FIX: Clamp HP to 0 minimum, never allow negative HP
	if current_hp <= 0:
		current_hp = 0
		print("[TAKE_DAMAGE] %s already dead, ignoring damage" % name)
		return
	
	# Track armor proficiency when taking damage
	track_armor_proficiency()
	
	# Store attacker for reflection
	if attacker:
		last_attacker = attacker
	
	# Apply defense reduction
	if is_defending:
		amount *= 0.5
	
	# REFLECTION MECHANIC
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
	
	#  CRITICAL: Always clamp to [0, max_hp] range
	current_hp = clamp(current_hp, 0, max_hp)
	
	print("[TAKE_DAMAGE] %s took %d damage. HP: %d/%d" % [name, int(amount), current_hp, max_hp])

func attack(target: CharacterData) -> String:
	"""Execute basic attack - NOTE: Proficiency tracking happens in CombatEngine"""
	if not target or not is_instance_valid(target):
		return "%s's attack failed - no valid target!" % name
	
	var momentum_mult = MomentumSystem.get_damage_multiplier()
	var base_damage = get_attack_power() * 0.5 * momentum_mult
	var resistance = target.get_defense()
	
	# Combat rolls
	if RandomManager.randf() >= accuracy:
		return "%s's attack missed!" % name
	if RandomManager.randf() < target.dodge:
		return "%s dodged the attack!" % target.name
	
	var is_crit = RandomManager.randf() < critical_hit_rate
	var damage = max(1, base_damage - resistance)
	
	if is_crit:
		damage *= 1.5 + RandomManager.randf() * 0.5
	
	damage = round(damage)
	
	# Apply damage (pass attacker for reflection)
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
	
	# Build message
	var result = "%s attacks %s for %d damage" % [name, target.name, damage]
	
	if momentum_mult > 1.0:
		result += " (+%d%% momentum)" % int((momentum_mult - 1.0) * 100)
	
	result += " and restores %d MP, %d SP%s" % [mp_restore, sp_restore, status_msg]
	
	if is_crit:
		result = "Critical hit! " + result
	
	return result

func debug_proficiency_status():
	"""Print current proficiency status for debugging"""
	if not proficiency_manager:
		print("[PROFICIENCY] ERROR: No proficiency manager!")
		return
	
	print("=== PROFICIENCY DEBUG ===")
	
	# Check weapon
	if equipment["main_hand"]:
		var weapon = equipment["main_hand"]
		print("Main Hand Weapon: %s" % weapon.name)
		print("  - Type: %s" % (weapon.get_class() if weapon.has_method("get_class") else "Unknown"))
		print("  - Key: '%s'" % (weapon.key if "key" in weapon else "NO KEY PROPERTY"))
		
		if weapon is Equipment and weapon.key != "":
			var uses = proficiency_manager.get_weapon_proficiency_uses(weapon.key)
			var level = proficiency_manager.get_weapon_proficiency_level(weapon.key)
			var next = proficiency_manager.get_uses_for_next_level(level)
			print("  - Proficiency: Level %d (%d/%d uses)" % [level, uses, next])
	else:
		print("No weapon equipped")
	
	# Show all tracked proficiencies
	print("\nAll Weapon Proficiencies:")
	var all_profs = proficiency_manager.get_all_weapon_proficiencies()
	if all_profs.is_empty():
		print("  (none tracked yet)")
	else:
		for prof in all_profs:
			print("  - %s" % prof)
	
	print("========================")

# === ELEMENTAL RESISTANCE DELEGATES ===

func get_elemental_resistance(element: ElementalDamage.Element) -> float:
	"""Get total resistance to an element"""
	if not elemental_resistances:
		return 0.0
	return elemental_resistances.get_total_resistance(element)

func get_elemental_weakness(element: ElementalDamage.Element) -> float:
	"""Get total weakness to an element"""
	if not elemental_resistances:
		return 0.0
	return elemental_resistances.get_total_weakness(element)

func get_elemental_damage_bonus(element: ElementalDamage.Element) -> float:
	"""Get damage bonus for an element"""
	if not elemental_resistances:
		return 0.0
	return elemental_resistances.get_total_damage_bonus(element)

func add_temp_elemental_resistance(element: ElementalDamage.Element, value: float):
	"""Add temporary resistance (from buffs/equipment)"""
	if elemental_resistances:
		elemental_resistances.add_temp_resistance(element, value)

func add_temp_elemental_weakness(element: ElementalDamage.Element, value: float):
	"""Add temporary weakness (from debuffs)"""
	if elemental_resistances:
		elemental_resistances.add_temp_weakness(element, value)

func add_temp_elemental_damage_bonus(element: ElementalDamage.Element, value: float):
	"""Add temporary damage bonus (from buffs/equipment)"""
	if elemental_resistances:
		elemental_resistances.add_temp_damage_bonus(element, value)

func clear_temp_elemental_modifiers():
	"""Clear all temporary elemental modifiers"""
	if elemental_resistances:
		elemental_resistances.clear_temp_modifiers()
