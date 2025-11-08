class_name Skill
extends Resource

enum SkillType { DAMAGE, HEAL, BUFF, DEBUFF, RESTORE, INFLICT_STATUS }
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
enum StatusEffect { NONE, POISON, BURN, FREEZE, SHOCK }
enum AbilityType { PHYSICAL, MAGICAL }

@export var ability_type: AbilityType
@export var name: String
@export var description: String
@export var type: SkillType
@export var target: TargetType
@export var attribute_target: AttributeTarget
@export var status_effect: StatusEffect
@export var power: int
@export var duration: int  # For buffs, debuffs, and status effects
@export var mp_cost: int
@export var cooldown: int

static func create_from_dict(data: Dictionary) -> Skill:
	var skill = Skill.new()
	skill.name = data.name
	skill.description = data.description
	skill.ability_type = AbilityType[data.ability_type.to_upper()]
	skill.type = SkillType[data.type.to_upper()]
	skill.target = TargetType[data.target.to_upper()]
	skill.attribute_target = AttributeTarget[data.attribute_target.to_upper()]
	skill.status_effect = StatusEffect[data.status_effect.to_upper()]
	skill.power = data.power
	skill.duration = data.duration
	skill.mp_cost = data.mp_cost
	skill.cooldown = data.cooldown
	return skill

func use(user: CharacterData, targets: Array):
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

func deal_damage(user: CharacterData, targets: Array):
	var total_damage = 0
	for t in targets:
		var base_damage = power + (user.attack_power if ability_type == AbilityType.PHYSICAL else user.spell_power)
		var resistance = (t.toughness if ability_type == AbilityType.PHYSICAL else t.spell_ward)
		var accuracy_check = randf() < user.accuracy
		var dodge_check = randf() < t.dodge
		var crit_check = randf() < user.critical_hit_rate
		
		if not accuracy_check:
			return "%s's attack missed!" % user.name
		
		if dodge_check:
			return "%s dodged the attack!" % t.name
		
		var damage = max(1, base_damage - resistance)
		
		if crit_check:
			damage *= 1.5 + randf() * 0.5  # Random between 1.5x and 2x
			print("Critical hit!")
		
		t.take_damage(damage)
		total_damage += damage
		
		# Apply status effect if this skill has one
		if status_effect != StatusEffect.NONE:
			t.apply_status_effect(status_effect, duration)
	
		var result = "%s dealt %.1f damage to %d target(s)" % [name, total_damage, targets.size()]
		if crit_check:
			result = "Critical hit! " + result
		if status_effect != StatusEffect.NONE:
			result += " and applied %s status effect" % StatusEffect.keys()[status_effect]
		return result


func heal(user: CharacterData, targets: Array):
	var total_heal = 0
	for t in targets:
		var heal_amount = power + user.spell_power
		t.heal(heal_amount)
		total_heal += heal_amount
	return "%s healed %d HP to %d target(s)" % [name, total_heal, targets.size()]

func apply_buff(_user: CharacterData, targets: Array):
	for t in targets:
		t.apply_buff(attribute_target, power, duration)
	return "%s buffed %s of %d target(s) by %d for %d turns" % [name, AttributeTarget.keys()[attribute_target], targets.size(), power, duration]

func apply_debuff(_user: CharacterData, targets: Array):
	for t in targets:
		if status_effect != StatusEffect.NONE:
			t.apply_status_effect(status_effect, duration)
			return "%s inflicted %s on %d target(s) for %d turns" % [name, StatusEffect.keys()[status_effect], targets.size(), duration]
		else:
			t.apply_debuff(attribute_target, power, duration)
			return "%s debuffed %s of %d target(s) by %d for %d turns" % [name, AttributeTarget.keys()[attribute_target], targets.size(), power, duration]

func restore(user: CharacterData, targets: Array):
	var total_heal = 0
	for t in targets:
		var heal_amount = power + user.spell_power
		t.restore_mp(heal_amount)
		total_heal += heal_amount
	return "%s healed %d MP to %d target(s)" % [name, total_heal, targets.size()]

func inflict_status(_user: CharacterData, targets: Array):
	var affected_targets = 0
	for t in targets:
		if t.apply_status_effect(status_effect, duration):
			affected_targets += 1
	return "%s inflicted %s on %d target(s) for %d turns" % [name, StatusEffect.keys()[status_effect], affected_targets, duration]
