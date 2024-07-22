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
var status_effects: Dictionary = {}  # Will store {StatusEffect: remaining_duration}
var is_defending: bool = false
var is_stunned: bool = false
var buffs: Dictionary = {}
var debuffs: Dictionary = {}
@export var inventory: Inventory
@export var currency: Currency

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

func _init(p_name: String = "", p_race: String = "", p_class: String = ""):
	name = p_name
	race = p_race
	character_class = p_class
	inventory = Inventory.new()
	currency = Currency.new()

# Add this method to the class
func add_skills(new_skills: Array):
	skills.clear()
	for skill in new_skills:
		if skill is String:
			skills.append(skill)
		else:
			print("Warning: Invalid skill type encountered: ", skill)

func remove_skill(skill_name: String):
	skills.erase(skill_name)

func calculate_secondary_attributes():
	max_hp = vitality * 10
	current_hp = max_hp
	max_mp = mind * 5
	current_mp = max_mp
	max_sp = endurance * 5
	current_sp = max_sp
	toughness = (vitality + strength) / 5.0
	
	dodge = 0.05 + (agility + dexterity) / (400.0)  # Base 5% dodge, max ~30% with very high agility and dexterity
	
	spell_ward = arcane + (mind / 2.0)
	
	accuracy = 0.7 + (mind + agility + fortitude) / (300.0)  # Base 70% accuracy, max ~90% with very high stats
	
	match attack_power_type:
		"strength":
			attack_power = (strength * 1.5) + (dexterity * 0.5) + (agility * 1.5)
		"dexterity":
			attack_power = (dexterity * 1.5) + (strength * 0.5) + (agility * 1.5)
		_:
			print("Invalid attack_power_type")
	
	match spell_power_type:
		"balanced":
			spell_power = (intelligence * 1.5) + (faith * 1.5) + (arcane * 1.5)
		"intelligence":
			spell_power = (intelligence * 2) + (faith * 1.5) + (arcane * 1.5)
		"arcane":
			spell_power = (intelligence * 2) + (faith * 1.5) + (arcane * 2)
		_:
			print("Invalid spell_power_type")
	
	critical_hit_rate = dexterity + (agility / 2.0)

func equip_item(item: Equipment) -> Equipment:
	if not item.can_equip(self):
		return null
	
	var old_item = equipment[item.slot]
	if old_item:
		unequip_item(item.slot)
	
	equipment[item.slot] = item
	item.apply_effects(self)
	inventory.remove_item(item.id, 1)
	calculate_secondary_attributes()
	return old_item

func unequip_item(slot: String) -> Equipment:
	var item = equipment[slot]
	if item:
		item.remove_effects(self)
		equipment[slot] = null
		inventory.add_item(item, 1)
		calculate_secondary_attributes()
	return item

func get_attack_power() -> int:
	var base_power = attack_power
	if equipment["main_hand"]:
		base_power += equipment["main_hand"].damage
	return int(base_power)

func get_defense() -> int:
	var total_defense = defense
	for slot in equipment:
		if equipment[slot] and equipment[slot].armor_value:
			total_defense += equipment[slot].armor_value
	return total_defense

func attack(target: CharacterData) -> String:
	var base_damage = get_attack_power() * 0.5
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
		damage *= 1.5 + randf() * 0.5  # Random between 1.5x and 2x
		print("Critical hit!")
	
	damage = round(damage)  # Round the damage to the nearest integer
	target.take_damage(damage)
	
	# Restore MP
	var mp_restore = int(max_mp * 0.025)  # Restore 2.5% of max MP
	restore_mp(mp_restore)
	
	var result = "%s attacks %s for %d damage and restores %d MP" % [name, target.name, damage, mp_restore]
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

func reset_for_new_game():
	# Reset HP, MP, etc. to initial values
	calculate_secondary_attributes()
	current_hp = max_hp
	current_mp = max_mp
	current_sp = max_sp
	
	# Clear inventory except for starting items
	inventory.clear()
	# Add starting items here if needed
	
	# Reset currency
	currency.copper = 0  # Or whatever starting amount you want
	
	# Clear equipment
	for slot in equipment:
		equipment[slot] = null
	
	# Reset any other properties that should be set to initial values for a new game
	level = 1
	# ... any other resets needed

func apply_status_effect(effect: Skill.StatusEffect, duration: int) -> String:
	if effect not in status_effects:
		status_effects[effect] = duration
		apply_status_effect_modifiers(effect)
		return "%s is now affected by %s for %d turns" % [name, Skill.StatusEffect.keys()[effect], duration]
	else:
		status_effects[effect] = max(status_effects[effect], duration)  # Refresh duration if already present
		return "%s's %s effect refreshed for %d turns" % [name, Skill.StatusEffect.keys()[effect], duration]

func remove_status_effect(effect: Skill.StatusEffect) -> String:
	if effect in status_effects:
		apply_status_effect_modifiers(effect)
		status_effects.erase(effect)
		return "%s is no longer affected by %s\n" % [name, Skill.StatusEffect.keys()[effect]]
	return ""

func apply_status_effect_damage(effect: Skill.StatusEffect) -> String:
	var message = ""
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
			# Freeze doesn't deal damage, but reduces defense
			message = "%s is frozen, reducing their defense\n" % name
	return message

func apply_status_effect_modifiers(effect: Skill.StatusEffect):
	match effect:
		Skill.StatusEffect.BURN:
			modify_attribute(Skill.AttributeTarget.STRENGTH, -2, effect in status_effects)
		Skill.StatusEffect.FREEZE:
			modify_attribute(Skill.AttributeTarget.VITALITY, -2, effect in status_effects)
			modify_attribute(Skill.AttributeTarget.AGILITY, -2, effect in status_effects)
			modify_attribute(Skill.AttributeTarget.ARCANE, -2, effect in status_effects)
			
func modify_attribute(attribute: Skill.AttributeTarget, value: int, apply: bool):
	var mod_value = value if apply else -value
	if apply:
		# Use a default duration if the status effect is not in the dictionary
		var duration = status_effects.get(attribute, 1)  # Default to 1 if not found
		debuffs[attribute] = {"value": mod_value, "duration": duration}
	else:
		debuffs.erase(attribute)

func get_attribute_with_effects(attribute: Skill.AttributeTarget) -> int:
	var base_value = get(Skill.AttributeTarget.keys()[attribute].to_lower())
	var buff_value = buffs.get(attribute, {"value": 0})["value"]
	var debuff_value = debuffs.get(attribute, {"value": 0})["value"]
	return base_value + buff_value - debuff_value

func apply_buff(attribute: Skill.AttributeTarget, value: int, duration: int):
	if attribute not in buffs:
		buffs[attribute] = {"value": value, "duration": duration}
	else:
		# If a buff for this attribute already exists, take the stronger one
		if value > buffs[attribute].value:
			buffs[attribute] = {"value": value, "duration": duration}
		elif value == buffs[attribute].value:
			# If the values are equal, take the longer duration
			buffs[attribute].duration = max(buffs[attribute].duration, duration)
	print("%s received a buff to %s of %d for %d turns" % [name, Skill.AttributeTarget.keys()[attribute], value, duration])

func apply_debuff(attribute: Skill.AttributeTarget, value: int, duration: int):
	if attribute not in debuffs:
		debuffs[attribute] = {"value": value, "duration": duration}
	else:
		# If a debuff for this attribute already exists, take the stronger one
		if value > debuffs[attribute].value:
			debuffs[attribute] = {"value": value, "duration": duration}
		elif value == debuffs[attribute].value:
			# If the values are equal, take the longer duration
			debuffs[attribute].duration = max(debuffs[attribute].duration, duration)
	print("%s received a debuff to %s of %d for %d turns" % [name, Skill.AttributeTarget.keys()[attribute], value, duration])

func update_buffs_and_debuffs():
	for attribute in buffs.keys():
		buffs[attribute].duration -= 1
		if buffs[attribute].duration <= 0:
			print("%s's buff to %s has expired" % [name, Skill.AttributeTarget.keys()[attribute]])
			buffs.erase(attribute)
	
	for attribute in debuffs.keys():
		debuffs[attribute].duration -= 1
		if debuffs[attribute].duration <= 0:
			print("%s's debuff to %s has expired" % [name, Skill.AttributeTarget.keys()[attribute]])
			debuffs.erase(attribute)

func get_attribute_with_buffs_and_debuffs(attribute: Skill.AttributeTarget) -> int:
	var base_value = get(Skill.AttributeTarget.keys()[attribute].to_lower())
	var buff_value = buffs.get(attribute, {"value": 0})["value"]
	var debuff_value = debuffs.get(attribute, {"value": 0})["value"]
	return base_value + buff_value - debuff_value

func update_status_effects() -> String:
	var message = ""
	var effects_to_remove = []
	
	for effect in status_effects.keys():
		status_effects[effect] -= 1
		if status_effects[effect] <= 0:
			effects_to_remove.append(effect)
		else:
			message += apply_status_effect_damage(effect)
	
	for effect in effects_to_remove:
		message += remove_status_effect(effect)
	
	update_buffs_and_debuffs()
	
	return message

func defend() -> String:
	is_defending = true
	return "%s takes a defensive stance" % name

func reset_defense():
	is_defending = false

func reset_for_new_battle():
	current_hp = max_hp
	current_mp = max_mp
	status_effects.clear()
	is_stunned = false
	is_defending = false
	buffs.clear()
	debuffs.clear()
