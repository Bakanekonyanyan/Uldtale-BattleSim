# EquipmentKeyHelper.gd - FIXED PATHS
# Helper utility for getting equipment keys for proficiency tracking

class_name EquipmentKeyHelper
extends RefCounted

# Cache for loaded JSON data to avoid repeated file reads
static var _weapons_cache: Dictionary = {}
static var _armors_cache: Dictionary = {}
static var _cache_loaded: bool = false

## Get the equipment key for proficiency tracking
static func get_equipment_key(equipment: Equipment) -> String:
	"""
	Get the unique key for an equipment piece for proficiency tracking.
	
	Priority:
	1. If equipment has 'key' property, use that
	2. If equipment has 'base_name', search by that
	3. Otherwise, search JSON files to find the key by name (with prefix/suffix stripping)
	"""
	
	if not equipment:
		return ""
	
	# Check if equipment stores its own key
	if equipment.get("key") != null and equipment.key != "":
		return equipment.key
	
	if equipment.get("equipment_key") != null and equipment.equipment_key != "":
		return equipment.equipment_key
	
	# Check if equipment has a base_name property (before prefixes/suffixes)
	if equipment.get("base_name") != null and equipment.base_name != "":
		return find_key_by_name(equipment.base_name, equipment.slot)
	
	# Fallback: Strip prefixes/suffixes and search by base name
	var base_name = strip_affixes(equipment.display_name)
	return find_key_by_name(base_name, equipment.slot)

## Strip common prefixes and suffixes from equipment names
static func strip_affixes(full_name: String) -> String:
	"""
	Remove common prefixes and suffixes from equipment names.
	Example: "Relentless Great Staff of Nature" -> "Great Staff"
	"""
	
	# Common prefixes to remove
	var prefixes = [
		"Mighty ", "Relentless ", "Swift ", "Deadly ", "Blessed ", "Cursed ",
		"Ancient ", "Legendary ", "Epic ", "Rare ", "Common ", "Masterwork ",
		"Crude ", "Fine ", "Superior ", "Exquisite ", "Flawless ",
		"Burning ", "Frozen ", "Shocking ", "Toxic ", "Holy ", "Dark ",
		"Radiant ", "Shadow ", "Ethereal ", "Arcane ", "Divine "
	]
	
	# Common suffixes to remove (with " of ")
	var suffix_patterns = [
		" of Power", " of Strength", " of Agility", " of Intelligence",
		" of Wisdom", " of Nature", " of the Bear", " of the Eagle",
		" of the Wolf", " of the Dragon", " of Fire", " of Ice",
		" of Lightning", " of Poison", " of Light", " of Darkness",
		" of the Gods", " of Legends", " of Eternity", " of the Ancients",
		" of Doom", " of Glory", " of Honor", " of Vengeance",
		" of Protection", " of Warding", " of Healing", " of Destruction"
	]
	
	var cleaned_name = full_name
	
	# Remove prefixes
	for prefix in prefixes:
		if cleaned_name.begins_with(prefix):
			cleaned_name = cleaned_name.substr(prefix.length())
			break  # Only remove one prefix
	
	# Remove suffixes
	for suffix in suffix_patterns:
		if cleaned_name.ends_with(suffix):
			cleaned_name = cleaned_name.substr(0, cleaned_name.length() - suffix.length())
			break  # Only remove one suffix
	
	return cleaned_name.strip_edges()

## Find equipment key by searching JSON files
static func find_key_by_name(equipment_name: String, slot_hint: String = "") -> String:
	"""
	Search weapons.json and armors.json to find the equipment key.
	"""
	
	# Load cache if not already loaded
	if not _cache_loaded:
		_load_caches()
	
	# Clean the name first (strip affixes)
	var clean_name = strip_affixes(equipment_name)
	
	print("EquipmentKeyHelper: Searching for '%s' (cleaned from '%s')" % [clean_name, equipment_name])
	
	# Search weapons first (main_hand and off_hand slots)
	if slot_hint in ["main_hand", "off_hand", ""]:
		var weapon_key = _search_weapons(clean_name)
		if weapon_key != "":
			print("EquipmentKeyHelper: Found weapon key '%s' for '%s'" % [weapon_key, equipment_name])
			return weapon_key
	
	# Search armors (head, chest, hands, legs, feet slots)
	if slot_hint in ["head", "chest", "hands", "legs", "feet", ""]:
		var armor_key = _search_armors(clean_name)
		if armor_key != "":
			print("EquipmentKeyHelper: Found armor key '%s' for '%s'" % [armor_key, equipment_name])
			return armor_key
	
	print("EquipmentKeyHelper: WARNING - Could not find key for equipment: '%s' (cleaned: '%s', slot: %s)" % [equipment_name, clean_name, slot_hint])
	return ""

## Search weapons.json for equipment key
static func _search_weapons(equipment_name: String) -> String:
	if _weapons_cache.is_empty():
		return ""
	
	# Search main_hand weapons
	if _weapons_cache.has("main_hand"):
		# One-handed weapons
		if _weapons_cache["main_hand"].has("one_handed"):
			for weapon_key in _weapons_cache["main_hand"]["one_handed"]:
				var weapon = _weapons_cache["main_hand"]["one_handed"][weapon_key]
				if weapon.get("name", "") == equipment_name:
					return weapon_key
		
		# Two-handed weapons
		if _weapons_cache["main_hand"].has("two_handed"):
			for weapon_key in _weapons_cache["main_hand"]["two_handed"]:
				var weapon = _weapons_cache["main_hand"]["two_handed"][weapon_key]
				if weapon.get("name", "") == equipment_name:
					return weapon_key
	
	# Search off_hand items
	if _weapons_cache.has("off_hand"):
		# Shields
		if _weapons_cache["off_hand"].has("shield"):
			for shield_key in _weapons_cache["off_hand"]["shield"]:
				var shield = _weapons_cache["off_hand"]["shield"][shield_key]
				if shield.get("name", "") == equipment_name:
					return shield_key
		
		# Sources (Tome, Talisman, Fetish, Relic)
		if _weapons_cache["off_hand"].has("source"):
			for source_key in _weapons_cache["off_hand"]["source"]:
				var source = _weapons_cache["off_hand"]["source"][source_key]
				if source.get("name", "") == equipment_name:
					return source_key
	
	return ""

## Search armors.json for equipment key
static func _search_armors(equipment_name: String) -> String:
	if _armors_cache.is_empty():
		return ""
	
	# Search all armor types and slots
	for armor_type in _armors_cache:  # cloth, leather, mail, plate
		for slot in _armors_cache[armor_type]:  # head, chest, hands, legs, feet
			for armor_key in _armors_cache[armor_type][slot]:
				var armor = _armors_cache[armor_type][slot][armor_key]
				if armor.get("name", "") == equipment_name:
					return armor_key
	
	return ""

## Load JSON data into cache
static func _load_caches():
	"""Load weapons.json and armors.json into memory cache"""
	# Try multiple possible paths
	var weapons_paths = [
		"res://data/items/weapons.json",
		"res://Data/items/weapons.json",
		"res://Data/weapons.json",
		"res://data/weapons.json"
	]
	
	var armors_paths = [
		"res://data/items/armors.json",
		"res://Data/items/armors.json",
		"res://Data/armors.json",
		"res://data/armors.json"
	]
	
	# Load weapons
	for path in weapons_paths:
		if FileAccess.file_exists(path):
			_weapons_cache = _load_json_file(path)
			if not _weapons_cache.is_empty():
				print("EquipmentKeyHelper: Loaded weapons from: ", path)
				break
	
	# Load armors
	for path in armors_paths:
		if FileAccess.file_exists(path):
			_armors_cache = _load_json_file(path)
			if not _armors_cache.is_empty():
				print("EquipmentKeyHelper: Loaded armors from: ", path)
				break
	
	_cache_loaded = true
	
	if _weapons_cache.is_empty():
		print("EquipmentKeyHelper: ERROR - Failed to load weapons.json from any path!")
	if _armors_cache.is_empty():
		print("EquipmentKeyHelper: ERROR - Failed to load armors.json from any path!")

## Load and parse a JSON file
static func _load_json_file(file_path: String) -> Dictionary:
	"""Load and parse a JSON file, return empty dict on error"""
	if not FileAccess.file_exists(file_path):
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("EquipmentKeyHelper: Could not open file: ", file_path)
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	
	if error != OK:
		print("EquipmentKeyHelper: Error parsing JSON file: ", file_path)
		print("EquipmentKeyHelper: Parse error: ", json.get_error_message())
		return {}
	
	return json.data

## Clear cache (useful if JSON files are updated at runtime)
static func clear_cache():
	"""Clear the cached JSON data"""
	_weapons_cache.clear()
	_armors_cache.clear()
	_cache_loaded = false
