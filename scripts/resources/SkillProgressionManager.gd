# SkillProgressionManager.gd
# Handles skill leveling, cooldowns, and progression
# Extracts ~120 lines from CharacterData

class_name SkillProgressionManager
extends RefCounted

## Weak back-reference: the character owns this manager, so a strong
## reference here would be a cycle and neither would ever be freed.
var _character_ref: WeakRef
var character: CharacterData:
	get: return _character_ref.get_ref() if _character_ref else null
	set(value): _character_ref = weakref(value) if value else null
var skill_levels: Dictionary = {}  # skill_name -> {level: int, uses: int}
var skill_instances: Dictionary = {}  # skill_name -> Skill instance
var skill_cooldowns: Dictionary = {}  # skill_name -> turns_remaining

func _init(owner_character: CharacterData):
	character = owner_character

# === SKILL MANAGEMENT ===

func add_skills(skill_names: Array):
	"""Initialize skills for character"""
	for skill_name in skill_names:
		if not skill_levels.has(skill_name):
			skill_levels[skill_name] = {"level": 1, "uses": 0}
		
		# Create instance
		var skill_data = SkillManager.get_skill(skill_name)
		if skill_data:
			var instance = skill_data.duplicate()
			instance.level = skill_levels[skill_name]["level"]
			instance.uses = skill_levels[skill_name]["uses"]
			_set_mods(instance)
			instance.calculate_level_bonuses()
			skill_instances[skill_name] = instance

## Talent upgrades for a skill (power/cooldown/costs/duration), applied on top of
## its level bonuses every time those are recalculated.
func _set_mods(instance: Skill) -> void:
	instance.talent_mods = character.talents.skill_mods(instance.name) if character and character.talents else {}
	instance.mutation = character.talents.mutation(instance.name) if character and character.talents else {}
	instance.apply_mutation(SkillManager.get_skill(instance.name))

func refresh_talent_mods() -> void:
	for skill_name in skill_instances:
		var inst: Skill = skill_instances[skill_name]
		_set_mods(inst)
		inst.calculate_level_bonuses()

func remove_skill(skill_name: String) -> void:
	skill_levels.erase(skill_name)
	skill_instances.erase(skill_name)
	skill_cooldowns.erase(skill_name)

func get_skill_instance(skill_name: String) -> Skill:
	"""Get the skill instance"""
	if skill_instances.has(skill_name):
		return skill_instances[skill_name]
	
	# Create if missing
	var skill_data = SkillManager.get_skill(skill_name)
	if skill_data:
		var instance = skill_data.duplicate()
		_set_mods(instance)
		if skill_levels.has(skill_name):
			instance.level = skill_levels[skill_name]["level"]
			instance.uses = skill_levels[skill_name]["uses"]
		instance.calculate_level_bonuses()
		skill_instances[skill_name] = instance
		return instance
	
	return null

# === SKILL USAGE ===

func use_skill(skill_name: String) -> String:
	"""Track skill usage and check for level-up"""
	if not skill_levels.has(skill_name):
		skill_levels[skill_name] = {"level": 1, "uses": 0}
	
	skill_levels[skill_name]["uses"] += 1
	
	# Update instance
	var instance = get_skill_instance(skill_name)
	# casting through a focus (tome, talisman...) trains it
	var art_msg := ""
	if instance and instance.ability_type == Skill.AbilityType.MAGICAL and character and character.proficiency_manager:
		var off = character.equipment.get("off_hand")
		if off is Equipment and WeaponArts.family_of(String(off.key)) == "focus":
			art_msg = character.proficiency_manager.use_weapon(String(off.key))
	if instance:
		instance.uses = skill_levels[skill_name]["uses"]
		var level_up_msg = instance.on_skill_used()
		if level_up_msg != "":
			skill_levels[skill_name]["level"] = instance.level
			return level_up_msg + (("\n" + art_msg) if art_msg != "" else "")
	
	return art_msg

# === COOLDOWN MANAGEMENT ===

func set_cooldown(skill_name: String, turns: int):
	"""Set a skill on cooldown"""
	if turns > 0:
		skill_cooldowns[skill_name] = turns
		Log.debug("skill_progression", "%s's %s on cooldown: %d turns" % [character.name, skill_name, turns])

func is_skill_ready(skill_name: String) -> bool:
	"""Check if skill is off cooldown"""
	return not skill_cooldowns.has(skill_name) or skill_cooldowns[skill_name] <= 0

func get_cooldown(skill_name: String) -> int:
	"""Get remaining cooldown"""
	return skill_cooldowns.get(skill_name, 0)

func reduce_cooldowns():
	"""Tick cooldowns at start of turn"""
	var ready_skills = []
	
	for skill_name in skill_cooldowns.keys():
		skill_cooldowns[skill_name] -= 1
		if skill_cooldowns[skill_name] <= 0:
			ready_skills.append(skill_name)
			skill_cooldowns.erase(skill_name)
	
	if not ready_skills.is_empty():
		Log.debug("skill_progression", "%s: Skills ready: %s" % [character.name, ", ".join(ready_skills)])

func clear_cooldowns():
	"""Remove all cooldowns"""
	skill_cooldowns.clear()

# === QUERY ===

func get_skill_level(skill_name: String) -> int:
	"""Get skill level"""
	return skill_levels.get(skill_name, {"level": 1})["level"]

func get_skill_uses(skill_name: String) -> int:
	"""Get skill use count"""
	return skill_levels.get(skill_name, {"uses": 0})["uses"]

func get_all_skills() -> Array:
	"""Get list of all skill names"""
	return skill_levels.keys()

func has_skill(skill_name: String) -> bool:
	return skill_levels.has(skill_name)

# === SAVE/LOAD ===

func get_save_data() -> Dictionary:
	"""Export skill data for saving"""
	return {
		"skill_levels": skill_levels.duplicate(),
		"skill_cooldowns": skill_cooldowns.duplicate()
	}

func load_save_data(data: Dictionary):
	"""Import skill data from save"""
	if data.has("skill_levels"):
		skill_levels = data["skill_levels"]
	
	if data.has("skill_cooldowns"):
		skill_cooldowns = data["skill_cooldowns"]
	
	# Rebuild instances
	for skill_name in skill_levels.keys():
		var skill_data = SkillManager.get_skill(skill_name)
		if skill_data:
			var instance = skill_data.duplicate()
			instance.level = skill_levels[skill_name]["level"]
			instance.uses = skill_levels[skill_name]["uses"]
			_set_mods(instance)
			instance.calculate_level_bonuses()
			skill_instances[skill_name] = instance
