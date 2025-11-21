# Equipment.gd - REFACTORED
# Responsibility: Core equipment data and basic operations
# Delegates: Rarity → RarityGenerator, Naming → EquipmentNamer, Scaling → EquipmentScaler

extends Item
class_name Equipment

# === CORE PROPERTIES ===
var key: String = ""  # Unique identifier for proficiency tracking (e.g., "short_sword", "buckler")
var damage: int = 0
var armor_value: int = 0
var attribute_target: Variant
var attribute_increase: Variant
var type: String
var slot: String
var class_restriction: Array
var effects: Dictionary
var inventory_key: String = ""

# === RARITY SYSTEM ===
var rarity: String = "common"
var rarity_applied: bool = false
var stat_modifiers: Dictionary = {}
var status_effect_chance: float = 0.0
var status_effect_type: Skill.StatusEffect = Skill.StatusEffect.NONE
var bonus_damage: int = 0

# === NAMING ===
var item_prefix: String = ""
var item_suffix: String = ""
var flavor_text: String = ""

# === SCALING ===
var item_level: int = 1
var base_item_level: int = 1

# === MANAGERS (delegate complex operations) ===
var rarity_generator: RarityGenerator
var equipment_namer: EquipmentNamer
var equipment_scaler: EquipmentScaler


func _init(data: Dictionary):
	# Initialize managers
	rarity_generator = RarityGenerator.new()
	equipment_namer = EquipmentNamer.new()
	equipment_scaler = EquipmentScaler.new()
	
	# Set base properties
	_load_base_data(data)
	
	# Determine generation path
	if _is_saved_equipment(data):
		_load_from_save(data)
	elif _is_already_generated(data):
		_load_generated(data)
	else:
		_generate_new(data)

# === INITIALIZATION PATHS ===

func _is_saved_equipment(data: Dictionary) -> bool:
	"""Check if this is loaded from save file"""
	return data.has("stat_modifiers") and not data["stat_modifiers"].is_empty()

func _is_already_generated(data: Dictionary) -> bool:
	"""Check if this was already generated"""
	return data.get("rarity_applied", false) == true

func _load_generated(data: Dictionary):
	"""Load already-generated equipment"""
	print("Equipment: Already generated - %s" % display_name)
	rarity = data.get("rarity", "common")
	rarity_applied = true
	damage = data.get("damage", damage)
	armor_value = data.get("armor_value", armor_value)
	
	if "stat_modifiers" in data:
		_load_from_save(data)

func generate_for_floor(floor: int, min_rarity_tier: int = 0):
	"""Generate equipment for specific floor - delegates to managers"""
	base_item_level = floor
	
	# 1. Assign rarity (with optional minimum)
	rarity = rarity_generator.roll_rarity(min_rarity_tier)
	
	# 2. Calculate item level with rarity bonus
	item_level = equipment_scaler.calculate_item_level(floor, rarity)
	
	# 3. Apply rarity modifiers (scaled by ilvl)
	var mods = rarity_generator.generate_modifiers(rarity, item_level)
	stat_modifiers = mods.stat_modifiers
	status_effect_type = mods.status_effect
	status_effect_chance = mods.status_chance
	bonus_damage = mods.bonus_damage
	
	# 4. Scale base stats
	damage = equipment_scaler.scale_damage(damage, item_level, rarity)
	armor_value = equipment_scaler.scale_armor(armor_value, item_level, rarity)
	value = equipment_scaler.scale_value(value, item_level, rarity)
	
	# 5. Generate name
	var naming_data = {
		"base_name": display_name,
		"rarity": rarity,
		"stat_modifiers": stat_modifiers,
		"status_effect": status_effect_type,
		"type": type
	}
	var names = equipment_namer.generate_name(naming_data)
	display_name = names.full_name
	flavor_text = names.flavor_text
	
	rarity_applied = true
	print("Equipment: Generated ilvl %d %s (%s)" % [item_level, display_name, rarity])

func _generate_new(data: Dictionary):
	"""Generate fresh equipment"""
	print("Equipment: Generating new - %s" % display_name)
	
	var floor = data.get("floor_number", item_level)
	var min_rarity = data.get("min_rarity_tier", 0)
	
	if floor > 1 or min_rarity > 0:
		generate_for_floor(floor, min_rarity)
	else:
		generate_for_floor(1, 0)

# === EQUIPMENT OPERATIONS ===

func can_equip(character: CharacterData) -> bool:
	if class_restriction.is_empty():
		return true
	return character.character_class in class_restriction

func apply_effects(character: CharacterData):
	"""Apply secondary attribute effects (dodge, critical_hit_rate, etc)"""
	if effects.is_empty():
		return
	
	print("[EQUIPMENT] Applying effects from %s:" % display_name)
	
	for property_name in effects:
		var effect_value = effects[property_name]
		
		# Check if character has this property
		if property_name in character:
			var old_value = character.get(property_name)
			character.set(property_name, old_value + effect_value)
			print("  - %s: %s -> %s (%+.3f)" % [
				property_name, 
				old_value, 
				character.get(property_name),
				effect_value
			])
		else:
			push_warning("Equipment effect '%s' not found on character" % property_name)

func remove_effects(character: CharacterData):
	"""Remove secondary attribute effects"""
	if effects.is_empty():
		return
	
	print("[EQUIPMENT] Removing effects from %s:" % display_name)
	
	for property_name in effects:
		var effect_value = effects[property_name]
		
		if property_name in character:
			var old_value = character.get(property_name)
			character.set(property_name, old_value - effect_value)
			print("  - %s: %s -> %s (%-.3f)" % [
				property_name,
				old_value,
				character.get(property_name),
				effect_value
			])

func apply_stat_modifiers(character: CharacterData):
	for stat in stat_modifiers:
		var stat_name = Skill.AttributeTarget.keys()[stat].to_lower()
		if stat_name in character:
			character.set(stat_name, character.get(stat_name) + stat_modifiers[stat])

func remove_stat_modifiers(character: CharacterData):
	for stat in stat_modifiers:
		var stat_name = Skill.AttributeTarget.keys()[stat].to_lower()
		if stat_name in character:
			character.set(stat_name, character.get(stat_name) - stat_modifiers[stat])

func try_apply_status_effect(target: CharacterData) -> bool:
	if status_effect_type != Skill.StatusEffect.NONE and RandomManager.randf() < status_effect_chance:
		target.apply_status_effect(status_effect_type, 3)
		return true
	return false

# === DISPLAY ===

func get_rarity_color() -> String:
	return rarity_generator.get_color(rarity)

func get_full_description() -> String:
	"""Generate rich description with all stats"""
	var desc = "[b]%s[/b]\n" % display_name
	
	# QOL: Show slot prominently
	desc += "[color=cyan][b]Slot: %s[/b][/color]\n" % _get_slot_display_name()
	
	desc += "[color=gray]Item Level: %d[/color]\n" % item_level
	desc += "[color=%s]%s[/color]\n" % [get_rarity_color(), rarity.capitalize()]
	desc += "\n%s\n" % description
	
	if damage > 0:
		desc += "\n[b]Damage:[/b] %d" % damage
		if bonus_damage > 0:
			desc += " [color=orange](+%d bonus)[/color]" % bonus_damage
		desc += "\n"
	
	if armor_value > 0:
		desc += "[b]Armor:[/b] %d\n" % armor_value
	
	# Show equipment type (weapon/armor type)
	if type:
		desc += "[color=gray]Type: %s[/color]\n" % type.capitalize()
	
	if not stat_modifiers.is_empty():
		desc += "\n[color=green][b]Attribute Bonuses:[/b][/color]\n"
		var sorted = []
		for stat in stat_modifiers:
			sorted.append({"stat": stat, "value": stat_modifiers[stat]})
		sorted.sort_custom(func(a, b): return a["value"] > b["value"])
		
		for mod in sorted:
			desc += "  [color=lime]+%d %s[/color]\n" % [
				mod["value"],
				Skill.AttributeTarget.keys()[mod["stat"]].capitalize()
			]
	
	if status_effect_type != Skill.StatusEffect.NONE:
		var effect_color = equipment_namer.get_status_color(status_effect_type)
		desc += "\n[color=%s][b]Special Effect:[/b][/color]\n" % effect_color
		desc += "  [color=%s]%.0f%% chance to inflict %s[/color]\n" % [
			effect_color,
			status_effect_chance * 100,
			Skill.StatusEffect.keys()[status_effect_type]
		]
	
	# Show class restrictions if any
	if not class_restriction.is_empty():
		desc += "\n[color=yellow]Class Restriction: %s[/color]\n" % ", ".join(class_restriction)
	
	if flavor_text:
		desc += "\n[i][color=gray]%s[/color][/i]\n" % flavor_text
	
	return desc

func _get_slot_display_name() -> String:
	"""Get user-friendly slot name"""
	match slot:
		"main_hand":
			return "Main Hand (Weapon)"
		"off_hand":
			return "Off Hand (Shield/Source)"
		"head":
			return "Head (Helmet)"
		"chest":
			return "Chest (Armor)"
		"hands":
			return "Hands (Gloves)"
		"legs":
			return "Legs (Greaves)"
		"feet":
			return "Feet (Boots)"
		_:
			return slot.capitalize()

# Add this to Equipment.gd _load_base_data() method

func _load_base_data(data: Dictionary):
	"""Load common base properties"""
	id = data.get("id", "")
	display_name = data.get("name", "")
	description = data.get("description", "")
	value = data.get("value", 0)
	damage = data.get("damage", 0)
	armor_value = data.get("armor_value", 0)
	attribute_target = data.get("attribute_target", "")
	attribute_increase = data.get("attribute_increase", 0)
	type = data.get("type", "")
	slot = data.get("slot", "")
	class_restriction = data.get("class_restriction", [])
	effects = data.get("effects", {})
	inventory_key = data.get("inventory_key", "")
	item_level = data.get("item_level", 1)
	base_item_level = data.get("base_item_level", 1)
	
	# === CRITICAL: Always set proficiency key ===
	# Priority: data["key"] > inventory_key > id (cleaned) > derived from name
	key = data.get("key", "")
	
	if key == "":
		# Try inventory_key
		if inventory_key != "" and inventory_key != null:
			key = inventory_key
		# Try id (strip prefixes)
		elif id != "" and id != null:
			key = id.replace("weapon_", "").replace("armor_", "").replace("shield_", "").replace("source_", "")
		else:
			# Last resort: derive from name
			var clean_name = display_name.to_lower().replace(" ", "_")
			# Remove common prefixes/suffixes
			clean_name = clean_name.replace("the_", "").replace("a_", "").replace("an_", "")
			key = clean_name
	
	print("Equipment: Set proficiency key '%s' for '%s' (id: %s, inv_key: %s)" % [key, display_name, id, inventory_key])
	
	item_type = Item.ItemType.WEAPON if type == "weapon" else Item.ItemType.ARMOR

# Also update _load_from_save to preserve the key
func _load_from_save(data: Dictionary):
	"""Restore from save data"""
	print("Equipment: Loading from save - %s (ilvl %d)" % [display_name, item_level])
	rarity = data.get("rarity", "common")
	rarity_applied = true
	damage = data.get("damage", damage)
	armor_value = data.get("armor_value", armor_value)
	
	# NEW: Restore the key
	if "key" in data and data["key"] != "":
		key = data["key"]
	
	# Restore modifiers (convert string keys to enum)
	if "stat_modifiers" in data:
		stat_modifiers = {}
		for stat_key in data["stat_modifiers"]:
			if typeof(stat_key) == TYPE_STRING and Skill.AttributeTarget.has(stat_key):
				stat_modifiers[Skill.AttributeTarget[stat_key]] = data["stat_modifiers"][stat_key]
			elif typeof(stat_key) == TYPE_INT:
				stat_modifiers[stat_key] = data["stat_modifiers"][stat_key]
	
	# Restore other properties
	status_effect_chance = data.get("status_effect_chance", 0.0)
	status_effect_type = data.get("status_effect_type", Skill.StatusEffect.NONE)
	bonus_damage = data.get("bonus_damage", 0)
	item_prefix = data.get("item_prefix", "")
	item_suffix = data.get("item_suffix", "")
	flavor_text = data.get("flavor_text", "")
	if "name" in data:
		display_name = data["name"]

# Update get_save_data to include key
func get_save_data() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"key": key,  # NEW: Save the proficiency key
		"rarity": rarity,
		"rarity_applied": rarity_applied,
		"item_level": item_level,
		"base_item_level": base_item_level,
		"damage": damage,
		"armor_value": armor_value,
		"stat_modifiers": stat_modifiers,
		"status_effect_chance": status_effect_chance,
		"status_effect_type": status_effect_type,
		"bonus_damage": bonus_damage,
		"item_prefix": item_prefix,
		"item_suffix": item_suffix,
		"flavor_text": flavor_text
	}

func get_effects_description() -> String:
	"""Get formatted description of equipment effects"""
	if effects.is_empty():
		return ""
	
	var desc = "\n[color=cyan][b]Effects:[/b][/color]\n"
	
	for property_name in effects:
		var value = effects[property_name]
		var display_name = _format_property_name(property_name)
		var color = "lime" if value > 0 else "red"
		var sign = "+" if value > 0 else ""
		
		# Format based on value size (percentages vs flat values)
		if abs(value) < 1.0:
			# Likely a percentage (0.05 = 5%)
			desc += "  [color=%s]%s%.1f%% %s[/color]\n" % [color, sign, value * 100, display_name]
		else:
			# Flat value
			desc += "  [color=%s]%s%.0f %s[/color]\n" % [color, sign, value, display_name]
	
	return desc

func _format_property_name(property_name: String) -> String:
	"""Convert property_name to human-readable format"""
	# Replace underscores with spaces and capitalize words
	return property_name.replace("_", " ").capitalize()
