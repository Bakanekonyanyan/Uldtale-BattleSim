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
@export var sp_cost: int  # Stamina cost for physical skills
@export var cooldown: int

# Skill level system
@export var level: int = 1  # Current skill level (1-5, then Max)
@export var uses: int = 0  # Number of times skill has been used
@export var base_power: int  # Base power for scaling
@export var base_mp_cost: int  # Base MP cost for scaling
@export var base_sp_cost: int  # Base SP cost for scaling
@export var base_cooldown: int  # Base cooldown for scaling
@export var base_duration: int  # Base duration for scaling

# Level thresholds for skill advancement
const LEVEL_THRESHOLDS = [5, 25, 125, 625, 1500]  # Uses needed for levels 2, 3, 4, 5, Max

static func create_from_dict(data: Dictionary) -> Skill:
	var skill = Skill.new()
	skill.name = data.name
	skill.description = data.description
	skill.ability_type = AbilityType[data.ability_type.to_upper()]
	skill.type = SkillType[data.type.to_upper()]
	skill.target = TargetType[data.target.to_upper()]
	skill.attribute_target = AttributeTarget[data.attribute_target.to_upper()]
	skill.status_effect = StatusEffect[data.status_effect.to_upper()]
	
	# Store base values for level scaling
	skill.base_power = data.power
	skill.base_mp_cost = data.get("mp_cost", 0)
	skill.base_sp_cost = data.get("sp_cost", 0)
	skill.base_cooldown = data.cooldown
	skill.base_duration = data.duration
	
	# Initialize at level 1
	skill.level = 1
	skill.uses = 0
	
	# Set initial values (same as base at level 1)
	skill.power = skill.base_power
	skill.mp_cost = skill.base_mp_cost
	skill.sp_cost = skill.base_sp_cost
	skill.cooldown = skill.base_cooldown
	skill.duration = skill.base_duration
	
	return skill

# Get the display level string
func get_level_string() -> String:
	if level >= 6:
		return "Max"
	else:
		return str(level)

# Get uses needed for next level
func get_uses_for_next_level() -> int:
	if level <= 5:
		return LEVEL_THRESHOLDS[level - 1]
	return -1  # Max level

# Check and apply level up
func check_level_up() -> bool:
	if level >= 6:  # Already at max
		return false
	
	var threshold_index = level - 1
	if uses >= LEVEL_THRESHOLDS[threshold_index]:
		level_up()
		return true
	return false

# Apply level up bonuses
func level_up():
	level += 1
	calculate_level_bonuses()
	
func calculate_level_bonuses():
	# Calculate scaling based on level
	# Level 1: 100%, Level 2: 110%, Level 3: 125%, Level 4: 145%, Level 5: 170%, Max: 200%
	var power_multipliers = [1.0, 1.1, 1.25, 1.45, 1.7, 2.0]
	var cost_multipliers = [1.0, 0.95, 0.9, 0.85, 0.75, 0.6]  # Costs decrease
	var cooldown_reductions = [0, 0, 1, 1, 2, 3]  # Cooldown reduction per level
	var duration_bonuses = [0, 1, 1, 2, 2, 3]  # Duration bonus per level
	
	var level_index = min(level - 1, 5)
	
	# Apply bonuses based on skill type
	if type in [SkillType.DAMAGE, SkillType.HEAL, SkillType.RESTORE]:
		power = int(base_power * power_multipliers[level_index])
	elif type in [SkillType.BUFF, SkillType.DEBUFF]:
		power = int(base_power * power_multipliers[level_index])
		duration = base_duration + duration_bonuses[level_index]
	elif type == SkillType.INFLICT_STATUS:
		duration = base_duration + duration_bonuses[level_index]
	
	# Reduce costs
	mp_cost = max(1, int(base_mp_cost * cost_multipliers[level_index]))
	sp_cost = max(1, int(base_sp_cost * cost_multipliers[level_index]))
	
	# Reduce cooldown
	cooldown = max(0, base_cooldown - cooldown_reductions[level_index])

# Track skill use and check for level up
func on_skill_used():
	uses += 1
	if check_level_up():
		return "Skill leveled up to " + get_level_string() + "!"
	return ""

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
