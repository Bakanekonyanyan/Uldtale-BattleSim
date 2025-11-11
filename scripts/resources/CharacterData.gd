# CharacterData.gd
extends Resource
class_name CharacterData

# Basic Info
@export var name: String
@export var race: String
@export var character_class: String
@export var level: int = 1

# Primary Attributes
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

# Secondary Attributes
@export var max_hp: int
@export var current_hp: int
@export var max_mp: int
@export var current_mp: int
@export var max_sp: int  # Stamina Points
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

# Power types
var attack_power_type: String = "strength"
var spell_power_type: String = "intelligence"

# Skills and Status
@export var skills: Array[String] = []
var skill_cooldowns: Dictionary = {}  # Maps skill_name -> turns_remaining
var skill_levels: Dictionary = {}  # Maps skill_name -> {level: int, uses: int}
var skill_instances: Dictionary = {}  # Maps skill_name -> Skill instance
var status_effects: Dictionary = {}  # Will store {StatusEffect: remaining_duration}
var is_defending: bool = false
var is_stunned: bool = false
var buffs: Dictionary = {}
var debuffs: Dictionary = {}
@export var inventory: Inventory
@export var currency: Currency
@export var stash: Inventory 

@export var xp: int = 0
@export var attribute_points: int = 0
@export var current_floor: int = 0
@export var max_floor_cleared: int = 0  # Highest floor number completed
@export var is_player: bool = false

# Equipment slots
var equipment = {
	"main_hand": null,
	"off_hand": null,
	"head": null,
	"chest": null,
	"hands": null,
	"legs": null,
	"feet": null
}

var previous_level: int = 1

func _init(p_name: String = "", p_race: String = "", p_class: String = ""):
	name = p_name
	race = p_race
	character_class = p_class
	inventory = Inventory.new()
	currency = Currency.new()
	stash = Inventory.new()	

func add_skills(new_skills: Array):
	skills.clear()
	for skill in new_skills:
		if skill is String:
			skills.append(skill)
			# Initialize skill tracking if not exists
			if not skill_levels.has(skill):
				skill_levels[skill] = {"level": 1, "uses": 0}
			# Create and store skill instance
			var skill_data = SkillManager.get_skill(skill)
			if skill_data:
				var skill_instance = skill_data.duplicate()
				skill_instance.level = skill_levels[skill]["level"]
				skill_instance.uses = skill_levels[skill]["uses"]
				skill_instance.calculate_level_bonuses()
				skill_instances[skill] = skill_instance
		else:
			print("Warning: Invalid skill type encountered: ", skill)

func get_skill_instance(skill_name: String) -> Skill:
	if skill_instances.has(skill_name):
		return skill_instances[skill_name]
	# Create instance if not exists
	var skill_data = SkillManager.get_skill(skill_name)
	if skill_data:
		var skill_instance = skill_data.duplicate()
		if skill_levels.has(skill_name):
			skill_instance.level = skill_levels[skill_name]["level"]
			skill_instance.uses = skill_levels[skill_name]["uses"]
			skill_instance.calculate_level_bonuses()
		skill_instances[skill_name] = skill_instance
		return skill_instance
	return null

func use_skill(skill_name: String):
	# Track skill usage
	if not skill_levels.has(skill_name):
		skill_levels[skill_name] = {"level": 1, "uses": 0}
	
	skill_levels[skill_name]["uses"] += 1
	
	# Update skill instance
	var skill_instance = get_skill_instance(skill_name)
	if skill_instance:
		skill_instance.uses = skill_levels[skill_name]["uses"]
		var level_up_msg = skill_instance.on_skill_used()
		if level_up_msg != "":
			skill_levels[skill_name]["level"] = skill_instance.level
			return level_up_msg
	return ""

func remove_skill(skill_name: String):
	skills.erase(skill_name)

# Update calculate_secondary_attributes to use buffed/debuffed stats:
func calculate_secondary_attributes():
	# Get buffed/debuffed primary attributes
	var effective_vit = get_attribute_with_buffs_and_debuffs(Skill.AttributeTarget.VITALITY) if Skill.AttributeTarget.has("VITALITY") else vitality
	var effective_str = get_attribute_with_buffs_and_debuffs(Skill.AttributeTarget.STRENGTH) if Skill.AttributeTarget.has("STRENGTH") else strength
	var effective_dex = get_attribute_with_buffs_and_debuffs(Skill.AttributeTarget.DEXTERITY) if Skill.AttributeTarget.has("DEXTERITY") else dexterity
	var effective_int = get_attribute_with_buffs_and_debuffs(Skill.AttributeTarget.INTELLIGENCE) if Skill.AttributeTarget.has("INTELLIGENCE") else intelligence
	var effective_fai = get_attribute_with_buffs_and_debuffs(Skill.AttributeTarget.FAITH) if Skill.AttributeTarget.has("FAITH") else faith
	var effective_mnd = get_attribute_with_buffs_and_debuffs(Skill.AttributeTarget.MIND) if Skill.AttributeTarget.has("MIND") else mind
	var effective_end = get_attribute_with_buffs_and_debuffs(Skill.AttributeTarget.ENDURANCE) if Skill.AttributeTarget.has("ENDURANCE") else endurance
	var effective_arc = get_attribute_with_buffs_and_debuffs(Skill.AttributeTarget.ARCANE) if Skill.AttributeTarget.has("ARCANE") else arcane
	var effective_agi = get_attribute_with_buffs_and_debuffs(Skill.AttributeTarget.AGILITY) if Skill.AttributeTarget.has("AGILITY") else agility
	var effective_for = get_attribute_with_buffs_and_debuffs(Skill.AttributeTarget.FORTITUDE) if Skill.AttributeTarget.has("FORTITUDE") else fortitude

	# Health and Resource Pools - use base stats (don't want max HP/MP changing mid-combat)
	max_hp = vitality * 10 + strength * 5
	max_mp = mind * 8 + intelligence * 4
	max_sp = endurance * 8 + agility * 4
	# CRITICAL FIX: Initialize current values if they're 0 or unset
	if current_hp == 0 or current_hp > max_hp:
		current_hp = max_hp
	if current_mp == 0 or current_mp > max_mp:
		current_mp = max_mp
	if current_sp == 0 or current_sp > max_sp:
		current_sp = max_sp
	# Defensive Stats - use effective stats
	toughness = (effective_vit * 0.45 + effective_str * 0.25 + effective_end * 0.15 + effective_for * 0.15) / 10.0
	dodge = 0.05 + (effective_agi * 0.55 + effective_dex * 0.35 + effective_for * 0.10) / 200.0
	spell_ward = (effective_for * 0.5) * (0.6 * effective_arc + 0.3 * effective_mnd + 0.1 * effective_fai) / 10.0

	# Offensive Stats - use effective stats
	accuracy = 0.75 + (effective_dex * 0.35 + effective_agi * 0.25 + effective_mnd * 0.25 + effective_for * 0.15) / 200.0
	critical_hit_rate = 0.05 + (effective_dex * 0.4 + effective_agi * 0.25 + effective_int * 0.2 + effective_for * 0.15) / 200.0

	# Attack Power - use effective stats
	match attack_power_type:
		"strength":
			attack_power = effective_str * 2 + effective_dex * 0.5 + effective_vit * 0.5
		"dexterity":
			attack_power = effective_dex * 2 + effective_str * 0.5 + effective_agi * 0.5
		_:
			print("Invalid attack_power_type")

	# Spell Power - use effective stats
	match spell_power_type:
		"balanced":
			spell_power = (effective_int * 1.5 + effective_fai * 1.5 + effective_arc * 1.5) / 2
		"intelligence":
			spell_power = effective_int * 2 + effective_fai + effective_arc
		"arcane":
			spell_power = effective_arc * 2 + effective_int + effective_fai
		_:
			print("Invalid spell_power_type")
	
func equip_item(item: Equipment) -> Equipment:
	if not item.can_equip(self):
		print("Cannot equip %s - class restriction" % item.name)
		return null
	
	var old_item = equipment[item.slot]
	
	# CRITICAL FIX: Store the inventory key BEFORE any operations
	var item_inventory_key = item.inventory_key if item.inventory_key != "" else item.id
	
	print("Equipping %s to slot %s (key: %s)" % [item.name, item.slot, item_inventory_key])
	
	# If slot has an item, unequip it first
	if old_item:
		print("Slot %s already occupied by %s, unequipping first" % [item.slot, old_item.name])
		unequip_item(item.slot)
	
	# Now equip the new item
	equipment[item.slot] = item
	item.apply_effects(self)
	
	if item.has_method("apply_stat_modifiers"):
		item.apply_stat_modifiers(self)
	
	# Remove from inventory using the stored key
	var removed = inventory.remove_item(item_inventory_key, 1)
	if not removed:
		print("ERROR: Failed to remove item from inventory with key: %s" % item_inventory_key)
	else:
		print("Successfully removed item from inventory")
	
	calculate_secondary_attributes()
	return old_item
		
func unequip_item(slot: String) -> Equipment:
	var item = equipment[slot]
	if item:
		item.remove_effects(self)
		
		# Remove stat modifiers from the new rarity system
		if item.has_method("remove_stat_modifiers"):
			item.remove_stat_modifiers(self)
		
		equipment[slot] = null
		inventory.add_item(item, 1)
		calculate_secondary_attributes()
	return item

func get_attack_power() -> int:
	var base_power = attack_power
	if equipment["main_hand"]:
		base_power += equipment["main_hand"].damage
		# Add bonus damage from legendary items - use property check
		if "bonus_damage" in equipment["main_hand"]:
			base_power += equipment["main_hand"].bonus_damage
	return int(base_power)

func get_defense() -> int:
	var total_defense = defense
	for slot in equipment:
		if equipment[slot] and equipment[slot].armor_value:
			total_defense += equipment[slot].armor_value
	return total_defense

# Modified attack function with momentum damage bonus
func attack(target: CharacterData) -> String:
	if not target or not is_instance_valid(target):
		push_error("Attack failed: Invalid target")
		return "%s's attack failed - no valid target!" % name
	
	if not ("dodge" in target) or not ("toughness" in target):
		push_error("Attack failed: Target missing required properties")
		return "%s's attack failed - target not properly initialized!" % name
	
	if typeof(target.dodge) != TYPE_FLOAT and typeof(target.dodge) != TYPE_INT:
		push_error("Attack failed: Target dodge is not a valid number")
		return "%s's attack failed - target stats invalid!" % name
	
	# Apply momentum bonus to damage
	var momentum_multiplier = MomentumSystem.get_damage_multiplier()
	
	var base_damage = get_attack_power() * 0.5 * momentum_multiplier
	var resistance = target.get_defense()
	var accuracy_check = randf() < accuracy
	var dodge_check = randf() < target.dodge
	var crit_check = randf() < critical_hit_rate
	
	if not accuracy_check:
		return "%s's attack missed!" % name
	
	if dodge_check:
		return "%s dodged the attack!" % target.name
	
	var damage = max(1, base_damage - resistance)
	
	if crit_check:
		damage *= 1.5 + randf() * 0.5
		print("Critical hit!")
	
	damage = round(damage)
	target.take_damage(damage)
	
	# Status effect application
	var status_msg = ""
	if equipment["main_hand"] and equipment["main_hand"] is Equipment:
		var weapon = equipment["main_hand"]
		if "status_effect_type" in weapon and "status_effect_chance" in weapon:
			if weapon.status_effect_type != Skill.StatusEffect.NONE:
				if weapon.has_method("try_apply_status_effect"):
					if weapon.try_apply_status_effect(target):
						status_msg = " and applied %s" % Skill.StatusEffect.keys()[weapon.status_effect_type]
	
	# Restore resources
	var mp_restore = int(max_mp * 0.025)
	var sp_restore = int(max_sp * 0.025)
	restore_mp(mp_restore)
	restore_sp(sp_restore)
	
	var result = "%s attacks %s for %d damage" % [name, target.name, damage]
	
	# Show momentum bonus in combat log
	if momentum_multiplier > 1.0:
		var bonus_pct = int((momentum_multiplier - 1.0) * 100)
		result += " (+%d%% momentum)" % bonus_pct
	
	result += " and restores %d MP, %d SP%s" % [mp_restore, sp_restore, status_msg]
	
	if crit_check:
		result = "Critical hit! " + result
	
	return result

func take_damage(amount: float):
	if is_defending:
		amount = amount * 0.5  # Reduce damage by 50% when defending
	current_hp -= int(amount)
	current_hp = max(0, current_hp)  # Ensure HP doesn't go below 0
	
func heal(amount: int):
	current_hp += amount
	current_hp = min(current_hp, max_hp)  # Ensure HP doesn't exceed max_hp
	print("%s healed for %d HP. Current HP: %d/%d" % [name, amount, current_hp, max_hp])  # Debug print

func use_mp(amount: int) -> bool:
	if current_mp >= amount:
		current_mp -= amount
		return true
	return false

func restore_mp(amount: int):
	current_mp += amount
	current_mp = min(current_mp, max_mp)  # Ensure MP doesn't exceed max_mp

func use_sp(amount: int) -> bool:
	if current_sp >= amount:
		current_sp -= amount
		return true
	return false

func restore_sp(amount: int):
	current_sp += amount
	current_sp = min(current_sp, max_sp)  # Ensure SP doesn't exceed max_sp

func is_alive() -> bool:
	return current_hp > 0

func get_status_effects_string() -> String:
	var effects = []
	
	for effect in status_effects:
		effects.append("%s (%d)" % [Skill.StatusEffect.keys()[effect], status_effects[effect]])
	
	for attribute in buffs:
		effects.append("Buff %s (%d)" % [Skill.AttributeTarget.keys()[attribute], buffs[attribute].duration])
	
	for attribute in debuffs:
		effects.append("Debuff %s (%d)" % [Skill.AttributeTarget.keys()[attribute], debuffs[attribute].duration])
	
	if effects.is_empty():
		return "Normal"
	
	return ", ".join(effects)

# Also update the reset_for_new_battle function:
func reset_for_new_battle():
	current_hp = max_hp
	current_mp = max_mp
	current_sp = max_sp  # ADD THIS LINE
	status_effects.clear()
	skill_cooldowns.clear()
	is_stunned = false
	is_defending = false
	buffs.clear()
	debuffs.clear()

# Update the reset_for_new_game function:
func reset_for_new_game():
	calculate_secondary_attributes()
	current_hp = max_hp
	current_mp = max_mp
	current_sp = max_sp  # ADD THIS LINE
	
	inventory.clear()
	currency.copper = 0
	
	for slot in equipment:
		equipment[slot] = null
	
	level = 1

func get_attribute_with_effects(attribute: Skill.AttributeTarget) -> int:
	var attribute_name = Skill.AttributeTarget.keys()[attribute].to_lower()
	# Use 'in' operator for Resources instead of has()
	if not (attribute_name in self):
		push_error("Character missing attribute: %s" % attribute_name)
		return 0
	
	var base_value = get(attribute_name)
	var buff_value = buffs.get(attribute, {"value": 0})["value"]
	var debuff_value = debuffs.get(attribute, {"value": 0})["value"]
	return base_value + buff_value - debuff_value

# Update apply_buff to ensure it recalculates stats:
func apply_buff(attribute: Skill.AttributeTarget, value: int, duration: int):
	if attribute not in buffs:
		buffs[attribute] = {"value": value, "duration": duration}
	else:
		# If a buff for this attribute already exists, take the stronger one
		if value > buffs[attribute].value:
			buffs[attribute] = {"value": value, "duration": duration}
		elif value == buffs[attribute].value:
			buffs[attribute].duration = max(buffs[attribute].duration, duration)
	print("%s received a buff to %s of +%d for %d turns" % [name, Skill.AttributeTarget.keys()[attribute], value, duration])
	calculate_secondary_attributes()  # Recalculate with new buff

# Update apply_debuff to ensure it recalculates stats:
func apply_debuff(attribute: Skill.AttributeTarget, value: int, duration: int):
	if attribute not in debuffs:
		debuffs[attribute] = {"value": value, "duration": duration}
	else:
		# If a debuff for this attribute already exists, take the stronger one
		if value > debuffs[attribute].value:
			debuffs[attribute] = {"value": value, "duration": duration}
		elif value == debuffs[attribute].value:
			debuffs[attribute].duration = max(debuffs[attribute].duration, duration)
	print("%s received a debuff to %s of -%d for %d turns" % [name, Skill.AttributeTarget.keys()[attribute], value, duration])
	calculate_secondary_attributes()  # Recalculate with new debuff

# Update update_buffs_and_debuffs:
func update_buffs_and_debuffs():
	var stats_changed = false
	
	for attribute in buffs.keys():
		buffs[attribute].duration -= 1
		if buffs[attribute].duration <= 0:
			print("%s's buff to %s has expired" % [name, Skill.AttributeTarget.keys()[attribute]])
			buffs.erase(attribute)
			stats_changed = true
	
	for attribute in debuffs.keys():
		debuffs[attribute].duration -= 1
		if debuffs[attribute].duration <= 0:
			print("%s's debuff to %s has expired" % [name, Skill.AttributeTarget.keys()[attribute]])
			debuffs.erase(attribute)
			stats_changed = true
	
	# Recalculate stats if any buffs/debuffs expired
	if stats_changed:
		calculate_secondary_attributes()

# Cooldown Management Functions
func use_skill_cooldown(skill_name: String, cooldown_turns: int):
	"""Sets a skill on cooldown after use"""
	if cooldown_turns > 0:
		skill_cooldowns[skill_name] = cooldown_turns
		print("%s's %s is on cooldown for %d turns" % [name, skill_name, cooldown_turns])

func is_skill_ready(skill_name: String) -> bool:
	"""Check if a skill is off cooldown and ready to use"""
	return not skill_cooldowns.has(skill_name) or skill_cooldowns[skill_name] <= 0

func get_skill_cooldown(skill_name: String) -> int:
	"""Get remaining cooldown turns for a skill"""
	return skill_cooldowns.get(skill_name, 0)

func reduce_cooldowns():
	"""Reduce all skill cooldowns by 1 turn - called at start of this character's turn"""
	var skills_ready: Array = []
	for skill_name in skill_cooldowns.keys():
		skill_cooldowns[skill_name] -= 1
		if skill_cooldowns[skill_name] <= 0:
			skills_ready.append(skill_name)
			skill_cooldowns.erase(skill_name)
	
	if skills_ready.size() > 0:
		print("%s: Skills ready: %s" % [name, ", ".join(skills_ready)])

func get_attribute_with_buffs_and_debuffs(attribute: Skill.AttributeTarget) -> int:
	var attribute_name = Skill.AttributeTarget.keys()[attribute].to_lower()
	# Use 'in' operator for Resources instead of has()
	if not (attribute_name in self):
		push_error("Character missing attribute: %s" % attribute_name)
		return 0
	
	var base_value = get(attribute_name)
	var buff_value = buffs.get(attribute, {"value": 0})["value"]
	var debuff_value = debuffs.get(attribute, {"value": 0})["value"]
	var final_value = base_value + buff_value - debuff_value
	
	# Debug output
	if buff_value != 0 or debuff_value != 0:
		print("%s %s: base=%d, buff=+%d, debuff=-%d, final=%d" % [
			name, 
			Skill.AttributeTarget.keys()[attribute], 
			base_value, 
			buff_value, 
			debuff_value, 
			final_value
		])
	
	return final_value
	
func defend() -> String:
	is_defending = true
	return "%s takes a defensive stance" % name

func reset_defense():
	is_defending = false

# In CharacterData.gd, update the gain_xp function:
func gain_xp(amount: int):
	previous_level = level
	xp += amount
	print("XP gained. Current XP: ", xp, " Level: ", level)
	check_level_up()

# In the check_level_up function:
func check_level_up():
	var xp_required = LevelSystem.calculate_xp_for_level(level)
	print("XP required for next level: ", xp_required)
	while xp >= xp_required:
		level_up()
		xp -= xp_required
		xp_required = LevelSystem.calculate_xp_for_level(level)
		print("Leveled up! New level: ", level, " Remaining XP: ", xp)

func level_up() -> void:
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

func distribute_enemy_points() -> void:
	for _i in range(3):
		var random_attr = randi() % 10
		match random_attr:
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
	if attribute_points > 0:
		match attribute:
			"vitality": vitality += 1
			"strength": strength += 1
			"dexterity": dexterity += 1
			"intelligence": intelligence += 1
			"faith": faith += 1
			"mind": mind += 1
			"endurance": endurance += 1
			"arcane": arcane += 1
			"agility": agility += 1
			"fortitude": fortitude += 1
			_: return false
		attribute_points -= 1
		calculate_secondary_attributes()
		return true
	return false

# Applies or refreshes a status effect (keeps enum-based keys as before)
func apply_status_effect(effect: Skill.StatusEffect, duration: int) -> String:
	var effect_name = Skill.StatusEffect.keys()[effect]
	# Try to fetch data from the autoload; if not present, we'll still set the effect and use fallback logic
	var data = {}
	if Engine.has_singleton("StatusEffects"):
		data = StatusEffects.get_effect_data(effect_name)
	
	if effect not in status_effects:
		status_effects[effect] = duration
		# Apply stat modifiers (apply = true)
		apply_status_effect_modifiers(effect, true)
		if data and data.has("message"):
			return "%s for %d turns" % [effect_name, duration]  # The battle log will show more detailed messages per tick
		return "%s is now affected by %s for %d turns" % [name, effect_name, duration]
	else:
		status_effects[effect] = max(status_effects[effect], duration)
		return "%s's %s effect refreshed for %d turns" % [name, effect_name, duration]


# Removes a status effect and reverses its modifiers
func remove_status_effect(effect: Skill.StatusEffect) -> String:
	if effect in status_effects:
		# Reverse stat modifiers (apply = false)
		apply_status_effect_modifiers(effect, false)
		status_effects.erase(effect)
		return "%s is no longer affected by %s\n" % [name, Skill.StatusEffect.keys()[effect]]
	return ""


# Handles the per-turn behavior (damage, stun, messages) for a single effect.
# Uses StatusEffects autoload data when available; otherwise falls back to the old hardcoded behavior
func apply_status_effect_damage(effect: Skill.StatusEffect) -> String:
	var message = ""
	var effect_name = Skill.StatusEffect.keys()[effect]
	var data = {}
	if Engine.has_singleton("StatusEffects"):
		data = StatusEffects.get_effect_data(effect_name)

	# If we have data from JSON, use it
	if typeof(data) == TYPE_DICTIONARY and not data.is_empty():
		# damage_type: "hp_percent", "flat", or "none"
		if data.has("damage_type"):
			var dtype = data.damage_type
			if dtype == "hp_percent" and data.has("damage_value"):
				var dmg = int(max_hp * float(data.damage_value))
				take_damage(dmg)
				message += "%s took %d %s damage\n" % [name, dmg, effect_name.to_lower()]
			elif dtype == "flat" and data.has("damage_value"):
				var dmg2 = int(data.damage_value)
				take_damage(dmg2)
				message += "%s took %d %s damage\n" % [name, dmg2, effect_name.to_lower()]
			# else no damage

		# stun chance
		if data.has("stun_chance"):
			var sc = float(data.stun_chance)
			if randf() < sc:
				is_stunned = true
				message += "%s is stunned for this turn!\n" % name

		# message template fallback
		if data.has("message"):
			# If message contains {damage} it won't be replaced here â€“ we already appended a plain message above.
			# Keep the JSON message as supplemental if needed.
			# message += data.message.format({"name": name, "damage": dmg}) + "\n"
			pass

		return message

	# Fallback to original hardcoded behavior if no JSON data present
	match effect:
		Skill.StatusEffect.POISON:
			var damage = max_hp / 10
			take_damage(damage)
			message = "%s took %d poison damage\n" % [name, damage]
		Skill.StatusEffect.BURN:
			var damage = max_hp / 20
			take_damage(damage)
			message = "%s took %d burn damage\n" % [name, damage]
		Skill.StatusEffect.SHOCK:
			var damage = max_hp / 15
			take_damage(damage)
			message = "%s took %d shock damage\n" % [name, damage]
			if randf() < 0.2:
				is_stunned = true
				message += "%s is stunned for this turn!\n" % name
		Skill.StatusEffect.FREEZE:
			message = "%s is frozen, reducing their defense\n" % name
	return message


# Apply or remove stat modifiers for an effect.
# New signature: apply_status_effect_modifiers(effect, apply: bool)
# If autoload JSON contains stat_modifiers uses them; otherwise uses original BURN/FREEZE logic as fallback.
func apply_status_effect_modifiers(effect: Skill.StatusEffect, apply: bool = true) -> void:
	var effect_name = Skill.StatusEffect.keys()[effect]
	var data = {}
	if Engine.has_singleton("StatusEffects"):
		data = StatusEffects.get_effect_data(effect_name)

	if typeof(data) == TYPE_DICTIONARY and not data.is_empty() and data.has("stat_modifiers"):
		for stat_name in data.stat_modifiers.keys():
			var value = int(data.stat_modifiers[stat_name])
			# convert stat_name (string like "strength") to AttributeTarget enum if possible
			var attr_enum_val = null
			if Skill.AttributeTarget.has(stat_name.to_upper()):
				attr_enum_val = Skill.AttributeTarget[stat_name.to_upper()]
				modify_attribute(attr_enum_val, value, apply, status_effects.get(effect, 1))
			else:
				# If JSON uses plain attribute names that don't match, attempt sensible fallbacks (ignore if not found)
				# No-op
				pass
		return

	# Fallback to previous hard-coded behavior (only for the effects we had)
	match effect:
		Skill.StatusEffect.BURN:
			# apply -2 to strength while burning
			modify_attribute(Skill.AttributeTarget.STRENGTH, -2, apply, status_effects.get(effect, 1))
		Skill.StatusEffect.FREEZE:
			modify_attribute(Skill.AttributeTarget.VITALITY, -2, apply, status_effects.get(effect, 1))
			modify_attribute(Skill.AttributeTarget.AGILITY, -2, apply, status_effects.get(effect, 1))
			modify_attribute(Skill.AttributeTarget.ARCANE, -2, apply, status_effects.get(effect, 1))

# Modified modify_attribute to accept an explicit duration when applying, and to properly remove on unapply.
# attribute: Skill.AttributeTarget (enum), value: int, apply: bool, duration: int
func modify_attribute(attribute: Skill.AttributeTarget, value: int, apply: bool, duration: int = 1) -> void:
	if apply:
		# store as a debuff entry (keeps your original debuffs dict shape)
		debuffs[attribute] = {"value": value, "duration": duration}
	else:
		# remove the debuff (or buff) for this attribute
		if attribute in debuffs:
			debuffs.erase(attribute)


# Update all status effects each turn (keeps original outer logic but uses new apply_status_effect_damage/remove_status_effect)
func update_status_effects() -> String:
	var message = ""
	var effects_to_remove: Array = []

	for effect in status_effects.keys():
		# decrement duration first: original code decremented then checked >0 to apply damage; preserve same rhythm
		status_effects[effect] -= 1
		if status_effects[effect] <= 0:
			effects_to_remove.append(effect)
		else:
			message += apply_status_effect_damage(effect)

	for effect in effects_to_remove:
		message += remove_status_effect(effect)

	update_buffs_and_debuffs()

	return message

func update_max_floor_cleared(floor: int):
	"""Update the maximum floor cleared if the new floor is higher"""
	if floor > max_floor_cleared:
		max_floor_cleared = floor
		print("New max floor cleared: %d" % max_floor_cleared)
