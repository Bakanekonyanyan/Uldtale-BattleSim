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
## Scales max HP. Regular enemies use < 1.0 so a lone hero can beat a group
## (set by EnemyFactory; players and PvP opponents keep 1.0).
var hp_multiplier: float = 1.0
## Scales damage this character deals (see BattleFormulas.hit_damage).
## Set by EnemyFactory; players and PvP opponents keep 1.0.
var damage_multiplier: float = 1.0
var is_stunned: bool = false
var last_attacker: CharacterData = null

# === PROGRESSION ===
@export var xp: int = 0
@export var attribute_points: int = 0
@export var current_floor: int = 0
## Highest floor unlocked in ANY location (kept for display / old saves).
## Real progress is per location: see location_progress.
@export var max_floor_cleared: int = 0
## location_id -> highest floor unlocked there (floors start unlocked at 1)
@export var location_progress: Dictionary = {}
@export var last_location: String = "the_dungeon"
## Max copies of each consumable carried in the pack; the rest goes to the stash.
## Raised later by purchases / Adventurer rank in steps of CARRY_LIMIT_STEP.
@export var carry_limit: int = 5
## Saved town-service state ({"alchemy": {...}, "blacksmith": {...}, "guild": {...}})
@export var town_state: Dictionary = {}
const CARRY_LIMIT_STEP := 5
const CARRY_LIMIT_MAX := 20

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
	talents = TalentManager.new(self)

func initialize_racial_elementals(load_from_race_data: bool = true):
	if not load_from_race_data or race.is_empty():
		return
	
	if not elemental_resistances:
		push_error("CharacterData.initialize_racial_elementals: elemental_resistances manager not initialized!")
		return
	
	RaceElementalData.apply_to_character(self, race, is_player)
	print("[ELEMENTAL] Initialized racial elementals for %s (%s)" % [name, race])

## Flat bonuses from everything currently equipped (Equipment.get_flat_bonuses):
## primary attributes (intelligence...) and secondary stats (dodge, spell_ward...).
## Talent trees (data/talents.json) and the battle loadout (max 6 equipped skills).
var talents: TalentManager
var equipped_skills: Array = []

## Equipment + talent flat bonuses ({stat: amount}); attributes, secondary stats
## (dodge, spell_power...) and "max_hp_pct" are all read by calculate_secondary_attributes.
func get_all_flat_bonuses() -> Dictionary:
	var total = get_equipment_flat_bonuses()
	if talents:
		var t = talents.stat_bonuses()
		for stat in t:
			total[stat] = total.get(stat, 0.0) + t[stat]
	return total

## Skills usable in battle: the equipped loadout (or the first N known if none chosen).
func get_battle_skills() -> Array:
	var known = skills
	var picked = equipped_skills.filter(func(s): return s in known)
	if picked.is_empty():
		picked = known.slice(0, TalentManager.loadout_size())
	return picked

func set_equipped_skills(names: Array) -> void:
	equipped_skills = names.filter(func(s): return s in skills).slice(0, TalentManager.loadout_size())

func remove_skill(skill_name: String) -> void:
	if skill_manager:
		skill_manager.remove_skill(skill_name)

func refresh_talent_skill_mods() -> void:
	if skill_manager:
		skill_manager.refresh_talent_mods()

func get_equipment_flat_bonuses() -> Dictionary:
	var total := {}
	for slot in equipment:
		var item = equipment[slot]
		if item is Equipment:
			var b = item.get_flat_bonuses()
			for stat in b:
				total[stat] = total.get(stat, 0.0) + b[stat]
	return total

func calculate_secondary_attributes():
	# Calculate effective attributes: base + equipment + talents + buffs/debuffs
	var flat = get_all_flat_bonuses()
	var eff = {}
	for stat in ["vitality", "strength", "dexterity", "intelligence", "faith", "mind", "endurance", "arcane", "agility", "fortitude"]:
		var base_value = get(stat)
		var equipment_bonus = equipment_bonuses.get(stat, 0) + int(round(flat.get(stat, 0.0)))
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
	max_hp = int((vitality * 8 + strength * 3) * hp_multiplier * (1.0 + flat.get("max_hp_pct", 0.0)))
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
	# Defense ratings feed BattleFormulas.mitigation(): 100 defense = half damage.
	# (Toughness used to be divided by 10, making it ~1 at level 1 - i.e. useless.
	# Spell ward was a product of two stats, so it grew quadratically.)
	toughness = eff.vitality * 0.45 + eff.strength * 0.25 + eff.endurance * 0.15 + eff.fortitude * 0.15
	dodge = 0.05 + (eff.agility * 0.55 + eff.dexterity * 0.35 + eff.fortitude * 0.10) / 200.0
	spell_ward = eff.mind * 0.45 + eff.faith * 0.25 + eff.arcane * 0.15 + eff.fortitude * 0.15
	
	# Offensive
	# Base 85%: at 75% a third of attacks missed once dodge was factored in
	accuracy = 0.85 + (eff.dexterity * 0.35 + eff.agility * 0.25 + eff.mind * 0.25 + eff.fortitude * 0.15) / 200.0
	# Status effects: Blind/Confused accuracy & dodge penalties, Evasive bonus
	if status_manager:
		var mods = status_manager.get_combat_modifiers()
		accuracy *= mods.accuracy_mult
		dodge = clamp(dodge * mods.dodge_mult + mods.dodge_bonus, 0.0, 0.75)
	
	critical_hit_rate = 0.05 + (eff.dexterity * 0.4 + eff.agility * 0.25 + eff.intelligence * 0.2 + eff.fortitude * 0.15) / 200.0
	
	# Armor penetration only comes from gear: reset, then add (so it never stacks
	# across recalculations). Used by BattleFormulas.hit_damage on physical hits.
	armor_penetration = 0.0
	
	# Equipment bonuses to secondary stats (e.g. Talisman dodge, source spell_ward)
	for stat in ["toughness", "dodge", "spell_ward", "accuracy", "critical_hit_rate", "armor_penetration"]:
		if flat.has(stat):
			set(stat, get(stat) + flat[stat])
	
	# Attack power
	match attack_power_type:
		"strength":
			attack_power = eff.strength * 2 + eff.dexterity * 0.5 + eff.vitality * 0.5
		"dexterity":
			attack_power = eff.dexterity * 2 + eff.strength * 0.5 + eff.agility * 0.5
		"arcane":  # Druid - previously unhandled, so attack_power stayed 0
			attack_power = eff.arcane * 2 + eff.strength * 0.5 + eff.dexterity * 0.5
		_:
			push_warning("%s: unknown attack_power_type '%s'" % [name, attack_power_type])
			attack_power = eff.strength * 2 + eff.dexterity * 0.5 + eff.vitality * 0.5
	
	# Spell power - same shape as attack power: primary x2 + two secondaries x0.5
	# (the old formulas weighted 4 stats vs attack power's 3, so magic out-scaled physical)
	match spell_power_type:
		"balanced":
			spell_power = eff.intelligence + eff.faith + eff.arcane
		"intelligence":
			spell_power = eff.intelligence * 2 + eff.faith * 0.5 + eff.arcane * 0.5
		"arcane":
			spell_power = eff.arcane * 2 + eff.intelligence * 0.5 + eff.faith * 0.5
		"faith":  # Paladin/Cleric/Druid/Shaman - previously unhandled, so spell_power stayed 0
			spell_power = eff.faith * 2 + eff.intelligence * 0.5 + eff.arcane * 0.5
		_:
			push_warning("%s: unknown spell_power_type '%s'" % [name, spell_power_type])
			spell_power = eff.intelligence + eff.faith + eff.arcane
	
	# Flat gear bonuses to the powers (e.g. cloth armor "spell_power": 1). These are
	# computed after the loop above, so they must be added here or they are lost.
	attack_power += flat.get("attack_power", 0.0)
	spell_power += flat.get("spell_power", 0.0)

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
	
	# Reflection - the ONLY place reflected damage is applied.
	# Only reflect when a live attacker hit us directly; status ticks, confusion
	# self-harm and reflected damage itself pass no attacker. (Previously this used
	# the stale `last_attacker`, so e.g. poison damage was reflected too.)
	if attacker and attacker != self:
		var reflection = status_manager.get_total_reflection() if status_manager else 0.0
		if reflection > 0.0:
			var reflected = int(amount * reflection)
			if reflected > 0:
				print("%s reflected %d damage back to %s!" % [name, reflected, attacker.name])
				attacker.take_damage(reflected, null)
	
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
	var equipment_bonus = equipment_bonuses.get(attribute_name, 0) + int(round(get_all_flat_bonuses().get(attribute_name, 0.0)))
	
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

# === CARRY LIMIT (pack vs stash) ===
## Consumables are limited to `carry_limit` copies of each in the pack.
func is_carry_limited(item: Item) -> bool:
	return item != null and not (item is Equipment) and item.item_type == Item.ItemType.CONSUMABLE

## How many more of this item fit in the pack (huge for unlimited items).
func pack_room_for(item: Item) -> int:
	if not is_carry_limited(item):
		return 1 << 30
	return max(0, carry_limit - inventory.get_quantity(item.id))

## Add items to the pack; anything over the carry limit goes to the stash.
## Returns {"pack": n, "stash": m}.
func add_to_pack(item: Item, quantity: int = 1) -> Dictionary:
	var to_pack = min(quantity, pack_room_for(item))
	var to_stash = quantity - to_pack
	if to_pack > 0 and not inventory.add_item(item, to_pack):
		to_stash += to_pack  # pack full (capacity) -> stash
		to_pack = 0
	if to_stash > 0:
		stash.add_item(item, to_stash)
		print("%d x %s sent to stash (carry limit %d)" % [to_stash, item.display_name, carry_limit])
	return {"pack": to_pack, "stash": to_stash}

## Move up to `quantity` of a stash entry into the pack, respecting the carry
## limit. Returns how many were moved.
func withdraw_from_stash(stash_key: String, quantity: int = 1) -> int:
	if not stash.items.has(stash_key):
		return 0
	var item: Item = stash.items[stash_key].item
	var amount = min(quantity, stash.items[stash_key].quantity, pack_room_for(item))
	if amount <= 0:
		return 0
	stash.remove_item(stash_key, amount)
	if not inventory.add_item(item, amount):
		stash.add_item(item, amount)  # pack full: put it back
		return 0
	return amount

## Move any consumables above the carry limit from the pack to the stash
## (save migration, or after carry_limit changes). Returns the number moved.
func enforce_carry_limit() -> int:
	var moved := 0
	for key in inventory.items.keys():
		var entry = inventory.items[key]
		var item: Item = entry.item
		if is_carry_limited(item) and entry.quantity > carry_limit:
			var excess = entry.quantity - carry_limit
			inventory.remove_item(key, excess)
			stash.add_item(item, excess)
			moved += excess
	return moved

## Quantity owned across pack + stash (town crafting/upgrading can use both).
func count_owned(item_id: String) -> int:
	return inventory.get_quantity(item_id) + stash.get_quantity(item_id)

## Remove `amount` of an item, pack first then stash. Caller checks count_owned first.
func take_owned(item_id: String, amount: int) -> void:
	var from_pack = min(amount, inventory.get_quantity(item_id))
	if from_pack > 0:
		inventory.remove_item(item_id, from_pack)
	if amount - from_pack > 0:
		stash.remove_item(item_id, amount - from_pack)

# === LOCATION PROGRESS ===
## Highest floor the player may start from at this location (at least 1).
func get_max_floor(location_id: String) -> int:
	return max(1, int(location_progress.get(location_id, 1)))

## Unlock floors up to `floor_num` at a location (never lowers progress).
func unlock_floor(location_id: String, floor_num: int) -> void:
	if floor_num > get_max_floor(location_id):
		location_progress[location_id] = floor_num
		print("%s: unlocked floor %d" % [location_id, floor_num])
	update_max_floor_cleared(floor_num)

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
