# ProficiencyManager.gd
# Handles weapon and armor proficiency progression
# Responsibility: Track usage, calculate bonuses, level-up checks

class_name ProficiencyManager
extends RefCounted

var character: CharacterData

# Proficiency data: type -> {level: int, uses: int}
var weapon_proficiencies: Dictionary = {}
var armor_proficiencies: Dictionary = {}

# Level thresholds (same as skill system for consistency)
const LEVEL_THRESHOLDS = [10, 50, 250, 1250, 3000]
const MAX_LEVEL = 6

# Bonus multipliers per level
const WEAPON_DAMAGE_BONUS = {
	1: 0.0,
	2: 0.05,   # +5% damage
	3: 0.10,   # +10% damage
	4: 0.15,   # +15% damage
	5: 0.20,   # +20% damage
	6: 0.30    # +30% damage
}

const ARMOR_EFFECTIVENESS_BONUS = {
	1: 0.0,
	2: 0.05,   # +5% armor value
	3: 0.10,   # +10% armor value
	4: 0.15,   # +15% armor value
	5: 0.20,   # +20% armor value
	6: 0.30    # +30% armor value
}

func _init(owner_character: CharacterData):
	character = owner_character

# === WEAPON PROFICIENCY ===

func use_weapon(weapon_type: String) -> String:
	"""Track weapon usage and check for level-up"""
	if not weapon_proficiencies.has(weapon_type):
		weapon_proficiencies[weapon_type] = {"level": 1, "uses": 0}
	
	weapon_proficiencies[weapon_type]["uses"] += 1
	
	var level_up_msg = _check_weapon_level_up(weapon_type)
	if level_up_msg != "":
		return level_up_msg
	
	return ""

func _check_weapon_level_up(weapon_type: String) -> String:
	"""Check if weapon proficiency should level up"""
	var prof = weapon_proficiencies[weapon_type]
	
	if prof["level"] >= MAX_LEVEL:
		return ""
	
	var threshold_index = prof["level"] - 1
	if prof["uses"] >= LEVEL_THRESHOLDS[threshold_index]:
		prof["level"] += 1
		return "%s proficiency increased to level %s!" % [
			weapon_type.capitalize(),
			_get_level_string(prof["level"])
		]
	
	return ""

func get_weapon_damage_multiplier(weapon_type: String) -> float:
	"""Get damage bonus multiplier for weapon type"""
	if not weapon_proficiencies.has(weapon_type):
		return 1.0
	
	var level = weapon_proficiencies[weapon_type]["level"]
	return 1.0 + WEAPON_DAMAGE_BONUS.get(level, 0.0)

func get_weapon_proficiency_level(weapon_type: String) -> int:
	"""Get current proficiency level for weapon type"""
	if not weapon_proficiencies.has(weapon_type):
		return 1
	return weapon_proficiencies[weapon_type]["level"]

func get_weapon_proficiency_uses(weapon_type: String) -> int:
	"""Get use count for weapon type"""
	if not weapon_proficiencies.has(weapon_type):
		return 0
	return weapon_proficiencies[weapon_type]["uses"]

# === ARMOR PROFICIENCY ===

func use_armor(armor_type: String) -> String:
	"""Track armor usage and check for level-up"""
	if not armor_proficiencies.has(armor_type):
		armor_proficiencies[armor_type] = {"level": 1, "uses": 0}
	
	armor_proficiencies[armor_type]["uses"] += 1
	
	var level_up_msg = _check_armor_level_up(armor_type)
	if level_up_msg != "":
		return level_up_msg
	
	return ""

func _check_armor_level_up(armor_type: String) -> String:
	"""Check if armor proficiency should level up"""
	var prof = armor_proficiencies[armor_type]
	
	if prof["level"] >= MAX_LEVEL:
		return ""
	
	var threshold_index = prof["level"] - 1
	if prof["uses"] >= LEVEL_THRESHOLDS[threshold_index]:
		prof["level"] += 1
		return "%s armor proficiency increased to level %s!" % [
			armor_type.capitalize(),
			_get_level_string(prof["level"])
		]
	
	return ""

func get_armor_effectiveness_multiplier(armor_type: String) -> float:
	"""Get armor effectiveness bonus multiplier for armor type"""
	if not armor_proficiencies.has(armor_type):
		return 1.0
	
	var level = armor_proficiencies[armor_type]["level"]
	return 1.0 + ARMOR_EFFECTIVENESS_BONUS.get(level, 0.0)

func get_armor_proficiency_level(armor_type: String) -> int:
	"""Get current proficiency level for armor type"""
	if not armor_proficiencies.has(armor_type):
		return 1
	return armor_proficiencies[armor_type]["level"]

func get_armor_proficiency_uses(armor_type: String) -> int:
	"""Get use count for armor type"""
	if not armor_proficiencies.has(armor_type):
		return 0
	return armor_proficiencies[armor_type]["uses"]

# === HELPERS ===

func _get_level_string(level: int) -> String:
	"""Get display string for level"""
	return "Max" if level >= MAX_LEVEL else str(level)

func get_uses_for_next_level(level: int) -> int:
	"""Get use count needed for next level"""
	if level >= MAX_LEVEL:
		return -1
	return LEVEL_THRESHOLDS[level - 1]

# === DISPLAY ===

func get_weapon_proficiency_string(weapon_type: String) -> String:
	"""Get formatted proficiency info for display"""
	if not weapon_proficiencies.has(weapon_type):
		return "%s: Level 1 (0 uses)" % weapon_type.capitalize()
	
	var prof = weapon_proficiencies[weapon_type]
	var level_str = _get_level_string(prof["level"])
	var bonus = int(WEAPON_DAMAGE_BONUS.get(prof["level"], 0.0) * 100)
	
	if prof["level"] >= MAX_LEVEL:
		return "%s: Level %s (+%d%% damage)" % [
			weapon_type.capitalize(), level_str, bonus
		]
	
	var next_threshold = LEVEL_THRESHOLDS[prof["level"] - 1]
	return "%s: Level %s (+%d%% damage) [%d/%d uses]" % [
		weapon_type.capitalize(), level_str, bonus, prof["uses"], next_threshold
	]

func get_armor_proficiency_string(armor_type: String) -> String:
	"""Get formatted proficiency info for display"""
	if not armor_proficiencies.has(armor_type):
		return "%s: Level 1 (0 uses)" % armor_type.capitalize()
	
	var prof = armor_proficiencies[armor_type]
	var level_str = _get_level_string(prof["level"])
	var bonus = int(ARMOR_EFFECTIVENESS_BONUS.get(prof["level"], 0.0) * 100)
	
	if prof["level"] >= MAX_LEVEL:
		return "%s: Level %s (+%d%% armor)" % [
			armor_type.capitalize(), level_str, bonus
		]
	
	var next_threshold = LEVEL_THRESHOLDS[prof["level"] - 1]
	return "%s: Level %s (+%d%% armor) [%d/%d uses]" % [
		armor_type.capitalize(), level_str, bonus, prof["uses"], next_threshold
	]

func get_all_weapon_proficiencies() -> Array:
	"""Get list of all weapon proficiencies for display"""
	var result = []
	for weapon_type in weapon_proficiencies:
		result.append(get_weapon_proficiency_string(weapon_type))
	return result

func get_all_armor_proficiencies() -> Array:
	"""Get list of all armor proficiencies for display"""
	var result = []
	for armor_type in armor_proficiencies:
		result.append(get_armor_proficiency_string(armor_type))
	return result

# === SAVE/LOAD ===

func get_save_data() -> Dictionary:
	"""Export proficiency data for saving"""
	return {
		"weapon_proficiencies": weapon_proficiencies.duplicate(),
		"armor_proficiencies": armor_proficiencies.duplicate()
	}

func load_save_data(data: Dictionary):
	"""Import proficiency data from save"""
	if data.has("weapon_proficiencies"):
		weapon_proficiencies = data["weapon_proficiencies"]
	
	if data.has("armor_proficiencies"):
		armor_proficiencies = data["armor_proficiencies"]
