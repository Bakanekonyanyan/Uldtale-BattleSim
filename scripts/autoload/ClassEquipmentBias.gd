# ClassEquipmentBias.gd - MODULAR VERSION (FIXED VARIABLE NAMES)
# Dynamically builds bias from class_restriction arrays in JSON
extends Node

const BIAS_WEIGHT = 0.65  # 65% chance for preferred equipment

# Cached data (built once at runtime from JSON)
var _class_weapon_cache = {}
var _class_armor_cache = {}
var _cache_built = false

func _ready():
	_build_class_caches()

func _build_class_caches():
	# Dynamically build class preferences from equipment JSON data
	if _cache_built:
		return
	
	print("[ClassEquipmentBias] Building dynamic class caches from equipment data...")
	
	# Get all equipment templates
	var all_weapons = ItemManager.weapons
	var all_armors = ItemManager.armors
	
	# Build weapon cache by scanning class_restriction arrays
	for weapon_id in all_weapons:
		var template = ItemManager.get_equipment_template(weapon_id)
		var restrictions = template.get("class_restriction", [])
		
		# If empty restrictions = all classes can use
		if restrictions.is_empty():
			_add_weapon_to_all_classes(weapon_id)
		else:
			for cls_name in restrictions:
				if not _class_weapon_cache.has(cls_name):
					_class_weapon_cache[cls_name] = {"main_hand": [], "off_hand": []}
				
				var slot = template.get("slot", "main_hand")
				if slot == "off_hand":
					_class_weapon_cache[cls_name]["off_hand"].append(weapon_id)
				else:
					_class_weapon_cache[cls_name]["main_hand"].append(weapon_id)
	
	# Build armor cache by scanning class_restriction arrays
	for armor_id in all_armors:
		var template = ItemManager.get_equipment_template(armor_id)
		var restrictions = template.get("class_restriction", [])
		var armor_type = template.get("type", "")
		
		# If empty restrictions = all classes can use
		if restrictions.is_empty():
			_add_armor_to_all_classes(armor_id, armor_type)
		else:
			for cls_name in restrictions:
				if not _class_armor_cache.has(cls_name):
					_class_armor_cache[cls_name] = {}
				
				if not _class_armor_cache[cls_name].has(armor_type):
					_class_armor_cache[cls_name][armor_type] = []
				
				_class_armor_cache[cls_name][armor_type].append(armor_id)
	
	_cache_built = true
	_print_cache_summary()

func _add_weapon_to_all_classes(weapon_id: String):
	# Add unrestricted weapon to all known classes
	var template = ItemManager.get_equipment_template(weapon_id)
	var slot = template.get("slot", "main_hand")
	
	for cls_name in _get_all_class_names():
		if not _class_weapon_cache.has(cls_name):
			_class_weapon_cache[cls_name] = {"main_hand": [], "off_hand": []}
		
		if slot == "off_hand":
			_class_weapon_cache[cls_name]["off_hand"].append(weapon_id)
		else:
			_class_weapon_cache[cls_name]["main_hand"].append(weapon_id)

func _add_armor_to_all_classes(armor_id: String, armor_type: String):
	# Add unrestricted armor to all known classes
	for cls_name in _get_all_class_names():
		if not _class_armor_cache.has(cls_name):
			_class_armor_cache[cls_name] = {}
		
		if not _class_armor_cache[cls_name].has(armor_type):
			_class_armor_cache[cls_name][armor_type] = []
		
		_class_armor_cache[cls_name][armor_type].append(armor_id)

func _get_all_class_names() -> Array:
	# Get all class names from classes.json
	var classes = []
	var file_path = "res://data/classes.json"
	
	if not FileAccess.file_exists(file_path):
		print("[ClassEquipmentBias] ERROR: classes.json not found!")
		return classes
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		print("[ClassEquipmentBias] ERROR: Failed to parse classes.json")
		return classes
	
	var data = json.data
	
	# Extract all class names from playable, non_playable, and boss sections
	for category in ["playable", "non_playable", "boss"]:
		if data.has(category):
			for cls_name in data[category]:
				classes.append(cls_name)
	
	return classes

func _print_cache_summary():
	# Debug output
	print("[ClassEquipmentBias] Cache built successfully!")
	print("  Classes with weapon data: %d" % _class_weapon_cache.size())
	print("  Classes with armor data: %d" % _class_armor_cache.size())
	
	# Sample output for first class
	if not _class_weapon_cache.is_empty():
		var sample_class = _class_weapon_cache.keys()[0]
		print("  Sample: %s can use %d main_hand, %d off_hand weapons" % [
			sample_class,
			_class_weapon_cache[sample_class]["main_hand"].size(),
			_class_weapon_cache[sample_class]["off_hand"].size()
		])

# === PUBLIC API ===

func get_biased_equipment_id(character_class: String, slot_category: String) -> String:
	# Get class-biased equipment ID
	# slot_category: "weapons", "main_hand", "off_hand", "armors"
	# Returns item_id or empty string
	if not _cache_built:
		_build_class_caches()
	
	if character_class == "" or not _has_class_data(character_class):
		return _get_random_equipment_id(slot_category)
	
	match slot_category:
		"weapons":
			return _roll_biased_weapon(character_class, "")
		"main_hand":
			return _roll_biased_weapon(character_class, "main_hand")
		"off_hand":
			return _roll_biased_weapon(character_class, "off_hand")
		"armors":
			return _roll_biased_armor(character_class)
	
	return ""

func _has_class_data(character_class: String) -> bool:
	# Check if we have cached data for this class
	return _class_weapon_cache.has(character_class) or _class_armor_cache.has(character_class)

func _roll_biased_weapon(character_class: String, slot_filter: String) -> String:
	# Roll weapon with bias toward class restrictions
	if not _class_weapon_cache.has(character_class):
		return _get_random_weapon_id(slot_filter)
	
	var class_weapons = _class_weapon_cache[character_class]
	var can_use = []
	
	# Collect weapons this class can use
	if slot_filter == "":
		can_use = class_weapons["main_hand"] + class_weapons["off_hand"]
	elif slot_filter == "main_hand":
		can_use = class_weapons["main_hand"]
	elif slot_filter == "off_hand":
		can_use = class_weapons["off_hand"]
	
	# Get weapons this class CANNOT use
	var cannot_use = _get_weapons_class_cannot_use(character_class, slot_filter)
	
	# Weighted roll
	if can_use.is_empty():
		if cannot_use.is_empty():
			return ""
		return cannot_use[RandomManager.randi() % cannot_use.size()]
	
	if cannot_use.is_empty():
		return can_use[RandomManager.randi() % can_use.size()]
	
	# 65% chance for preferred, 35% for other
	if RandomManager.randf() < BIAS_WEIGHT:
		return can_use[RandomManager.randi() % can_use.size()]
	else:
		return cannot_use[RandomManager.randi() % cannot_use.size()]

func _roll_biased_armor(character_class: String) -> String:
	# Roll armor with bias toward class restrictions
	if not _class_armor_cache.has(character_class):
		return _get_random_armor_id()
	
	var class_armors = _class_armor_cache[character_class]
	var can_use = []
	
	# Collect all armor IDs this class can use
	for armor_type in class_armors:
		can_use.append_array(class_armors[armor_type])
	
	# Get armors this class CANNOT use
	var cannot_use = _get_armors_class_cannot_use(character_class)
	
	# Weighted roll
	if can_use.is_empty():
		if cannot_use.is_empty():
			return ""
		return cannot_use[RandomManager.randi() % cannot_use.size()]
	
	if cannot_use.is_empty():
		return can_use[RandomManager.randi() % can_use.size()]
	
	# 65% chance for preferred, 35% for other
	if RandomManager.randf() < BIAS_WEIGHT:
		return can_use[RandomManager.randi() % can_use.size()]
	else:
		return cannot_use[RandomManager.randi() % cannot_use.size()]

func _get_weapons_class_cannot_use(character_class: String, slot_filter: String) -> Array:
	# Get weapon IDs NOT in class restrictions
	var cannot_use = []
	var can_use_set = {}
	
	if _class_weapon_cache.has(character_class):
		var class_weapons = _class_weapon_cache[character_class]
		if slot_filter == "":
			for weapon_id in class_weapons["main_hand"] + class_weapons["off_hand"]:
				can_use_set[weapon_id] = true
		elif slot_filter == "main_hand":
			for weapon_id in class_weapons["main_hand"]:
				can_use_set[weapon_id] = true
		elif slot_filter == "off_hand":
			for weapon_id in class_weapons["off_hand"]:
				can_use_set[weapon_id] = true
	
	# Find weapons NOT in can_use_set
	for weapon_id in ItemManager.weapons:
		if not can_use_set.has(weapon_id):
			var template = ItemManager.get_equipment_template(weapon_id)
			var slot = template.get("slot", "main_hand")
			
			# Apply slot filter
			if slot_filter == "" or slot == slot_filter:
				cannot_use.append(weapon_id)
	
	return cannot_use

func _get_armors_class_cannot_use(character_class: String) -> Array:
	# Get armor IDs NOT in class restrictions
	var cannot_use = []
	var can_use_set = {}
	
	if _class_armor_cache.has(character_class):
		var class_armors = _class_armor_cache[character_class]
		for armor_type in class_armors:
			for armor_id in class_armors[armor_type]:
				can_use_set[armor_id] = true
	
	# Find armors NOT in can_use_set
	for armor_id in ItemManager.armors:
		if not can_use_set.has(armor_id):
			cannot_use.append(armor_id)
	
	return cannot_use

func _get_random_equipment_id(slot_category: String) -> String:
	# Fallback for unknown classes
	match slot_category:
		"weapons":
			return _get_random_weapon_id("")
		"main_hand":
			return _get_random_weapon_id("main_hand")
		"off_hand":
			return _get_random_weapon_id("off_hand")
		"armors":
			return _get_random_armor_id()
	return ""

func _get_random_weapon_id(slot_filter: String) -> String:
	# Random weapon selection
	var all_weapons = ItemManager.weapons.keys()
	
	if slot_filter != "":
		var filtered = []
		for weapon_id in all_weapons:
			var template = ItemManager.get_equipment_template(weapon_id)
			if template.get("slot", "main_hand") == slot_filter:
				filtered.append(weapon_id)
		all_weapons = filtered
	
	if all_weapons.is_empty():
		return ""
	return all_weapons[RandomManager.randi() % all_weapons.size()]

func _get_random_armor_id() -> String:
	# Random armor selection
	var all_armors = ItemManager.armors.keys()
	if all_armors.is_empty():
		return ""
	return all_armors[RandomManager.randi() % all_armors.size()]
