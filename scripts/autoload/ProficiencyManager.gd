# ProficiencyManager.gd - UPDATED to track specific equipment types
# Handles weapon and armor proficiency progression for specific equipment

class_name ProficiencyManager
extends RefCounted

var character: CharacterData

# Proficiency data: specific_type -> {level: int, uses: int}
# e.g., "short_sword", "buckler", "tome", etc.
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

func use_weapon(weapon_key: String) -> String:
	"""Track weapon usage and check for level-up
	weapon_key should be the specific weapon type: 'short_sword', 'buckler', 'tome', etc."""
	if not weapon_proficiencies.has(weapon_key):
		weapon_proficiencies[weapon_key] = {"level": 1, "uses": 0}
	
	weapon_proficiencies[weapon_key]["uses"] += 1
	
	var level_up_msg = _check_weapon_level_up(weapon_key)
	if level_up_msg != "":
		return level_up_msg
	
	return ""

func _check_weapon_level_up(weapon_key: String) -> String:
	"""Check if weapon proficiency should level up"""
	var prof = weapon_proficiencies[weapon_key]
	
	if prof["level"] >= MAX_LEVEL:
		return ""
	
	var threshold_index = prof["level"] - 1
	if prof["uses"] >= LEVEL_THRESHOLDS[threshold_index]:
		prof["level"] += 1
		return "%s proficiency increased to level %s!" % [
			_format_weapon_name(weapon_key),
			_get_level_string(prof["level"])
		]
	
	return ""

func get_weapon_damage_multiplier(weapon_key: String) -> float:
	"""Get damage bonus multiplier for weapon type"""
	if not weapon_proficiencies.has(weapon_key):
		return 1.0
	
	var level = weapon_proficiencies[weapon_key]["level"]
	return 1.0 + WEAPON_DAMAGE_BONUS.get(level, 0.0)

func get_weapon_proficiency_level(weapon_key: String) -> int:
	"""Get current proficiency level for weapon type"""
	if not weapon_proficiencies.has(weapon_key):
		return 1
	return weapon_proficiencies[weapon_key]["level"]

func get_weapon_proficiency_uses(weapon_key: String) -> int:
	"""Get use count for weapon type"""
	if not weapon_proficiencies.has(weapon_key):
		return 0
	return weapon_proficiencies[weapon_key]["uses"]

# === ARMOR PROFICIENCY ===

func use_armor(armor_type: String) -> String:
	"""Track armor usage and check for level-up
	armor_type: 'cloth', 'leather', 'mail', 'plate'"""
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

func _format_weapon_name(weapon_key: String) -> String:
	"""Format weapon key for display"""
	# Convert snake_case to Title Case
	return weapon_key.replace("_", " ").capitalize()

# === DISPLAY ===

func get_weapon_proficiency_string(weapon_key: String) -> String:
	"""Get formatted proficiency info for display - ALWAYS shows level 1 if not tracked"""
	var uses = get_weapon_proficiency_uses(weapon_key)
	var level = get_weapon_proficiency_level(weapon_key)
	var level_str = _get_level_string(level)
	var bonus = int(WEAPON_DAMAGE_BONUS.get(level, 0.0) * 100)
	
	var display_name = _format_weapon_name(weapon_key)
	
	if level >= MAX_LEVEL:
		return "%s: Level %s (+%d%% damage)" % [
			display_name, level_str, bonus
		]
	
	var next_threshold = LEVEL_THRESHOLDS[level - 1]
	return "%s: Level %s (+%d%% damage) [%d/%d uses]" % [
		display_name, level_str, bonus, uses, next_threshold
	]

func get_armor_proficiency_string(armor_type: String) -> String:
	"""Get formatted proficiency info for display - ALWAYS shows level 1 if not tracked"""
	var uses = get_armor_proficiency_uses(armor_type)
	var level = get_armor_proficiency_level(armor_type)
	var level_str = _get_level_string(level)
	var bonus = int(ARMOR_EFFECTIVENESS_BONUS.get(level, 0.0) * 100)
	
	var display_name = armor_type.capitalize()
	
	if level >= MAX_LEVEL:
		return "%s: Level %s (+%d%% armor)" % [
			display_name, level_str, bonus
		]
	
	var next_threshold = LEVEL_THRESHOLDS[level - 1]
	return "%s: Level %s (+%d%% armor) [%d/%d uses]" % [
		display_name, level_str, bonus, uses, next_threshold
	]

func get_all_weapon_proficiencies() -> Array:
	"""Get list of all weapon proficiencies for display"""
	var result = []
	for weapon_key in weapon_proficiencies:
		result.append(get_weapon_proficiency_string(weapon_key))
	return result

func get_all_armor_proficiencies() -> Array:
	"""Get list of all armor proficiencies for display"""
	var result = []
	for armor_type in armor_proficiencies:
		result.append(get_armor_proficiency_string(armor_type))
	return result

# === CLASS-BASED EQUIPMENT AVAILABILITY ===

func get_available_weapon_types() -> Array:
	"""Get all weapon types this character can equip based on class"""
	var available = []
	var char_class = character.character_class
	
	# Load weapons data
	var weapons_data = _load_weapons_data()
	if not weapons_data:
		print("ProficiencyManager: Failed to load weapons data")
		return available
	
	# Check main_hand weapons
	if weapons_data.has("main_hand"):
		# One-handed weapons
		if weapons_data["main_hand"].has("one_handed"):
			for weapon_key in weapons_data["main_hand"]["one_handed"]:
				var weapon_data = weapons_data["main_hand"]["one_handed"][weapon_key]
				if typeof(weapon_data) != TYPE_DICTIONARY:
					print("ProficiencyManager: Invalid weapon data for %s" % weapon_key)
					continue
				if _can_equip_weapon(weapon_data, char_class):
					available.append(weapon_key)
		
		# Two-handed weapons
		if weapons_data["main_hand"].has("two_handed"):
			for weapon_key in weapons_data["main_hand"]["two_handed"]:
				var weapon_data = weapons_data["main_hand"]["two_handed"][weapon_key]
				if typeof(weapon_data) != TYPE_DICTIONARY:
					print("ProficiencyManager: Invalid weapon data for %s" % weapon_key)
					continue
				if _can_equip_weapon(weapon_data, char_class):
					available.append(weapon_key)
	
	# Check off_hand items
	if weapons_data.has("off_hand"):
		# Shields
		if weapons_data["off_hand"].has("shield"):
			for shield_key in weapons_data["off_hand"]["shield"]:
				var shield_data = weapons_data["off_hand"]["shield"][shield_key]
				if typeof(shield_data) != TYPE_DICTIONARY:
					print("ProficiencyManager: Invalid shield data for %s" % shield_key)
					continue
				if _can_equip_weapon(shield_data, char_class):
					available.append(shield_key)
		
		# Sources (Tome, Talisman, Fetish, Relic)
		if weapons_data["off_hand"].has("source"):
			for source_key in weapons_data["off_hand"]["source"]:
				var source_data = weapons_data["off_hand"]["source"][source_key]
				if typeof(source_data) != TYPE_DICTIONARY:
					print("ProficiencyManager: Invalid source data for %s" % source_key)
					continue
				if _can_equip_weapon(source_data, char_class):
					available.append(source_key)
	
	return available

func get_available_armor_types() -> Array:
	"""Get all armor types this character can equip based on class"""
	var available = []
	var char_class = character.character_class
	
	# Load armors data
	var armors_data = _load_armors_data()
	if not armors_data:
		return ["cloth", "leather", "mail", "plate"]  # Default to all
	
	# Check each armor type to see if class can equip it
	for armor_category in armors_data:  # cloth, leather, mail, plate
		for slot in armors_data[armor_category]:  # head, chest, hands, legs, feet
			var armor_pieces = armors_data[armor_category][slot]
			for armor_key in armor_pieces:
				var armor = armor_pieces[armor_key]
				# FIX: Pass the armor Dictionary, not the key
				if _can_equip_armor(armor, char_class):
					if armor_category not in available:
						available.append(armor_category)
					break
	
	# Fallback to all types if none found
	if available.is_empty():
		available = ["cloth", "leather", "mail", "plate"]
	
	return available

func _can_equip_weapon(weapon_data: Dictionary, char_class: String) -> bool:
	"""Check if character class can equip this weapon"""
	if not weapon_data.has("class_restriction"):
		return true
	
	var restrictions = weapon_data["class_restriction"]
	
	# Empty array means no restrictions (all classes can equip)
	if restrictions.is_empty():
		return true
	
	# Check if character's class is in the allowed list
	return char_class in restrictions

func _can_equip_armor(armor_data: Dictionary, char_class: String) -> bool:
	"""Check if character class can equip this armor"""
	if not armor_data.has("class_restriction"):
		return true
	
	var restrictions = armor_data["class_restriction"]
	
	# Empty array means no restrictions (all classes can equip)
	if restrictions.is_empty():
		return true
	
	# Check if character's class is in the allowed list
	return char_class in restrictions

func _load_weapons_data() -> Dictionary:
	"""Load weapons.json data"""
	var file_path = "res://data/items/weapons.json"
	if not FileAccess.file_exists(file_path):
		print("ProficiencyManager: weapons.json not found at: ", file_path)
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	
	if error != OK:
		print("ProficiencyManager: Error parsing weapons.json")
		return {}
	
	return json.data

func _load_armors_data() -> Dictionary:
	"""Load armors.json data"""
	var file_path = "res://data/items/armors.json"
	if not FileAccess.file_exists(file_path):
		print("ProficiencyManager: armors.json not found at: ", file_path)
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	
	if error != OK:
		print("ProficiencyManager: Error parsing armors.json")
		return {}
	
	return json.data

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
