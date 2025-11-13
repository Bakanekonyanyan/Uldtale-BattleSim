# Equipment.gd - COMPLETE FIXED VERSION
extends Item
class_name Equipment

var damage: int = 0
var armor_value: int = 0
var attribute_target: Variant
var attribute_increase: Variant
var type: String
var slot: String
var class_restriction: Array
var effects: Dictionary
var rarity: String = "common"
var rarity_applied: bool = false
var inventory_key: String = ""

# New rarity system properties
var rarity_stat_modifiers: Dictionary = {}
var stat_modifiers: Dictionary = {}
var status_effect_chance: float = 0.0
var status_effect_type: Skill.StatusEffect = Skill.StatusEffect.NONE
var bonus_damage: int = 0
var item_prefix: String = ""
var item_suffix: String = ""
var flavor_text: String = ""

var rarities: Dictionary = {}
var item_level: int = 1  # ilvl
var base_item_level: int = 1  # Floor-based base

const RARITY_ILVL_BONUS = {
	"common": 0,
	"uncommon": 1,
	"magic": 2,
	"rare": 3,
	"epic": 5,
	"legendary": 8
}

# Stat-based prefixes for the highest stat modifier
const STAT_PREFIXES = {
	Skill.AttributeTarget.VITALITY: ["Stalwart", "Enduring", "Resilient", "Vigorous", "Hardy"],
	Skill.AttributeTarget.STRENGTH: ["Crushing", "Mighty", "Titanic", "Brutal", "Overwhelming"],
	Skill.AttributeTarget.DEXTERITY: ["Swift", "Precise", "Nimble", "Keen", "Masterful"],
	Skill.AttributeTarget.INTELLIGENCE: ["Brilliant", "Cunning", "Sage's", "Scholarly", "Enlightened"],
	Skill.AttributeTarget.FAITH: ["Devout", "Hallowed", "Divine", "Sacred", "Blessed"],
	Skill.AttributeTarget.MIND: ["Focused", "Contemplative", "Mindful", "Serene", "Transcendent"],
	Skill.AttributeTarget.ENDURANCE: ["Tireless", "Steadfast", "Unyielding", "Indomitable", "Relentless"],
	Skill.AttributeTarget.ARCANE: ["Mystical", "Arcane", "Eldritch", "Enigmatic", "Occult"],
	Skill.AttributeTarget.AGILITY: ["Graceful", "Flowing", "Lithe", "Acrobatic", "Dancer's"],
	Skill.AttributeTarget.FORTITUDE: ["Ironclad", "Fortified", "Unbreakable", "Adamant", "Impervious"]
}

# Secondary prefixes for additional stat modifiers
const SECONDARY_PREFIXES = {
	Skill.AttributeTarget.VITALITY: ["Life-Giving", "Vital", "Living"],
	Skill.AttributeTarget.STRENGTH: ["Powerful", "Strong", "Forceful"],
	Skill.AttributeTarget.DEXTERITY: ["Deft", "Skilled", "Artful"],
	Skill.AttributeTarget.INTELLIGENCE: ["Wise", "Astute", "Cerebral"],
	Skill.AttributeTarget.FAITH: ["Pious", "Righteous", "Holy"],
	Skill.AttributeTarget.MIND: ["Clear", "Sharp", "Insightful"],
	Skill.AttributeTarget.ENDURANCE: ["Lasting", "Persistent", "Enduring"],
	Skill.AttributeTarget.ARCANE: ["Magical", "Enchanted", "Bewitched"],
	Skill.AttributeTarget.AGILITY: ["Quick", "Fleet", "Rapid"],
	Skill.AttributeTarget.FORTITUDE: ["Sturdy", "Tough", "Solid"]
}

# Pantheon-based naming data
const PANTHEON_NAMES = {
	"Aetherion": {"domain": "Elements", "adjectives": ["Elemental", "Harmonic", "Balanced"], "verbs": ["Unity", "Balance", "Harmony"]},
	"Nimue": {"domain": "Water/Spirits", "adjectives": ["Flowing", "Spiritual", "Serene"], "verbs": ["the Weaver", "the Tide", "Spirits"]},
	"Elandria": {"domain": "Earth/Nature", "adjectives": ["Verdant", "Earthen", "Living"], "verbs": ["the Grove", "Nature", "Growth"]},
	"Fenrisulfr": {"domain": "Wilderness/Beasts", "adjectives": ["Feral", "Primal", "Savage"], "verbs": ["the Hunt", "the Wild", "Fury"]},
	"Solara": {"domain": "Light/Purity", "adjectives": ["Radiant", "Blessed", "Pure"], "verbs": ["the Dawn", "Purity", "Light"]},
	"Arathorn": {"domain": "War/Honor", "adjectives": ["Mighty", "Honorable", "Warrior's"], "verbs": ["War", "Honor", "Valor"]},
	"Hel": {"domain": "Death/Shadows", "adjectives": ["Shadow", "Deathly", "Grim"], "verbs": ["Death", "Shadows", "the Grave"]},
	"Tsukuyomi": {"domain": "Moon/Secrets", "adjectives": ["Veiled", "Moonlit", "Secret"], "verbs": ["the Moon", "Secrets", "Night"]}
}

# Status effects mapped to pantheon
const STATUS_PANTHEON_MAP = {
	Skill.StatusEffect.BURN: "Solara",
	Skill.StatusEffect.FREEZE: "Nimue",
	Skill.StatusEffect.POISON: "Elandria",
	Skill.StatusEffect.SHOCK: "Aetherion"
}

# Status effect descriptors
const STATUS_DESCRIPTORS = {
	Skill.StatusEffect.BURN: ["Burning", "Flaming", "Blazing", "Scorching", "Infernal"],
	Skill.StatusEffect.FREEZE: ["Frozen", "Icy", "Glacial", "Frigid", "Chilling"],
	Skill.StatusEffect.POISON: ["Venomous", "Toxic", "Poisoned", "Virulent", "Noxious"],
	Skill.StatusEffect.SHOCK: ["Shocking", "Crackling", "Lightning", "Thunderous", "Voltaic"]
}

# Primary stats for random modifiers
const PRIMARY_STATS = [
	Skill.AttributeTarget.VITALITY,
	Skill.AttributeTarget.STRENGTH,
	Skill.AttributeTarget.DEXTERITY,
	Skill.AttributeTarget.INTELLIGENCE,
	Skill.AttributeTarget.FAITH,
	Skill.AttributeTarget.MIND,
	Skill.AttributeTarget.ENDURANCE,
	Skill.AttributeTarget.ARCANE,
	Skill.AttributeTarget.AGILITY,
	Skill.AttributeTarget.FORTITUDE
]

func _init(data: Dictionary):
	load_rarities()
	
	# Set base properties
	id = data.get("id", "")
	name = data.get("name", "")
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
	
	if type == "weapon":
		item_type = Item.ItemType.WEAPON
	elif type == "armor":
		item_type = Item.ItemType.ARMOR
	else:
		item_type = Item.ItemType.WEAPON
	
	# CRITICAL: Check if this is SAVED equipment (has full modifier data)
	if "stat_modifiers" in data and not data["stat_modifiers"].is_empty():
		# LOADED FROM SAVE - Restore all properties
		print("Equipment: Loading from save - %s" % name)
		_load_from_save_data(data)
		return  # DONE - Don't generate anything
	
	# CRITICAL: Check if this is ALREADY GENERATED equipment (has rarity_applied)
	if "rarity_applied" in data and data["rarity_applied"] == true:
		# ALREADY GENERATED - Just restore properties
		print("Equipment: Already generated - %s (%s)" % [name, data.get("rarity", "common")])
		rarity = data.get("rarity", "common")
		rarity_applied = true
		damage = data.get("damage", damage)
		armor_value = data.get("armor_value", armor_value)
		
		# Restore OLD system converted data (if any)
		if "stat_modifiers" in data:
			_load_from_save_data(data)
		return  # DONE
		if "stat_modifiers" in data and not data["stat_modifiers"].is_empty():
			_load_from_save_data(data)
		return
	
	# NEW EQUIPMENT - Generate with floor context
		if "floor_number" in data:
			generate_for_floor(data["floor_number"])
		else:
		# Fallback for shop/default generation
			generate_for_floor(1)
	# NEW EQUIPMENT - Generate everything fresh
	print("Equipment: Generating new - %s" % name)
	assign_random_rarity()
	apply_rarity_modifiers()
	generate_procedural_name()
	print("Equipment: Generated %s with rarity %s" % [name, rarity])

func _load_from_save_data(data: Dictionary):
	"""Load all properties from saved/generated data"""
	rarity = data.get("rarity", "common")
	rarity_applied = data.get("rarity_applied", true)
	damage = data.get("damage", damage)
	armor_value = data.get("armor_value", armor_value)
	
	# Load stat modifiers (convert string keys to enum)
	if "stat_modifiers" in data:
		stat_modifiers = {}
		for key in data["stat_modifiers"].keys():
			if typeof(key) == TYPE_STRING:
				if Skill.AttributeTarget.has(key):
					var enum_val = Skill.AttributeTarget[key]
					stat_modifiers[enum_val] = data["stat_modifiers"][key]
			elif typeof(key) == TYPE_INT:
				stat_modifiers[key] = data["stat_modifiers"][key]
	
	# Load other properties
	status_effect_chance = data.get("status_effect_chance", 0.0)
	status_effect_type = data.get("status_effect_type", Skill.StatusEffect.NONE)
	bonus_damage = data.get("bonus_damage", 0)
	item_prefix = data.get("item_prefix", "")
	item_suffix = data.get("item_suffix", "")
	flavor_text = data.get("flavor_text", "")
	
	# Restore name if saved
	if "name" in data:
		name = data["name"]

func generate_for_floor(floor: int):
	"""Generate equipment scaled to a specific floor"""
	base_item_level = floor
	
	# Assign rarity first
	assign_random_rarity()
	
	# Calculate ilvl with rarity bonus and variance
	var rarity_bonus = RARITY_ILVL_BONUS.get(rarity, 0)
	var variance = randi_range(-2, 2)
	item_level = max(1, base_item_level + rarity_bonus + variance)
	
	# Apply rarity modifiers SCALED by ilvl
	apply_rarity_modifiers_with_ilvl()
	
	# Generate name
	generate_procedural_name()
	
	print("Equipment: Generated ilvl %d %s (floor %d + rarity %d + var %d)" % [
		item_level, name, floor, rarity_bonus, variance
	])

func assign_random_rarity():
	var rarity_roll = randf()
	if rarity_roll < 0.50:
		rarity = "common"
	elif rarity_roll < 0.75:
		rarity = "uncommon"
	elif rarity_roll < 0.87:
		rarity = "magic"
	elif rarity_roll < 0.94:
		rarity = "rare"
	elif rarity_roll < 0.98:
		rarity = "epic"
	else:
		rarity = "legendary"

func apply_rarity_modifiers():
	if rarities.is_empty():
		print("ERROR: Rarities not loaded!")
		return
	
	if not rarity in rarities:
		print("ERROR: Invalid rarity: %s" % rarity)
		return
		
	var multiplier = rarities[rarity]["multiplier"]
	
	if damage > 0:
		damage = int(damage * multiplier)
	if armor_value > 0:
		armor_value = int(armor_value * multiplier)
	value = int(value * multiplier)
	
	match rarity:
		"common":
			pass
		"uncommon":
			add_random_stat_modifier(1, 1, 3)
		"magic":
			add_random_stat_modifier(2, 1, 4)
		"rare":
			if randf() < 0.3:
				add_random_stat_modifier(2, 2, 5)
				add_status_effect()
			else:
				add_random_stat_modifier(3, 2, 5)
		"epic":
			add_random_stat_modifier(3, 3, 6, true)
			add_status_effect()
		"legendary":
			add_random_stat_modifier(3, 4, 7, true)
			add_status_effect()
			bonus_damage = randi_range(5, 15)
	
	rarity_applied = true

func add_random_stat_modifier(count: int, min_val: int, max_val: int, unique := false):
	var available_stats = PRIMARY_STATS.duplicate()
	
	for i in range(count):
		if available_stats.is_empty():
			break
			
		var stat_index = randi() % available_stats.size()
		var stat = available_stats[stat_index]
		var value = randi_range(min_val, max_val)

		if unique:
			available_stats.remove_at(stat_index)

		if stat_modifiers.has(stat):
			stat_modifiers[stat] += value
		else:
			stat_modifiers[stat] = value

		if not rarity_stat_modifiers.has(stat):
			rarity_stat_modifiers[stat] = 0
		rarity_stat_modifiers[stat] += value

func add_status_effect():
	var status_effects = [
		Skill.StatusEffect.BURN,
		Skill.StatusEffect.FREEZE,
		Skill.StatusEffect.POISON,
		Skill.StatusEffect.SHOCK
	]
	
	status_effect_type = status_effects[randi() % status_effects.size()]
	
	match rarity:
		"rare":
			status_effect_chance = randf_range(0.10, 0.20)
		"epic":
			status_effect_chance = randf_range(0.15, 0.30)
		"legendary":
			status_effect_chance = randf_range(0.25, 0.40)

func generate_procedural_name():
	if rarity == "common":
		return
	
	var base_name = name
	var prefixes = []
	var suffix = ""
	
	# Select pantheon based on status effect or random
	var pantheon_key = ""
	if status_effect_type != Skill.StatusEffect.NONE and STATUS_PANTHEON_MAP.has(status_effect_type):
		pantheon_key = STATUS_PANTHEON_MAP[status_effect_type]
	else:
		var pantheon_keys = PANTHEON_NAMES.keys()
		pantheon_key = pantheon_keys[randi() % pantheon_keys.size()]
	
	var pantheon_data = PANTHEON_NAMES[pantheon_key]
	
	# Sort stat modifiers by value
	var sorted_stats = []
	for stat in stat_modifiers:
		sorted_stats.append({"stat": stat, "value": stat_modifiers[stat]})
	sorted_stats.sort_custom(func(a, b): return a["value"] > b["value"])
	
	# Add status effect descriptor as first prefix
	if status_effect_type != Skill.StatusEffect.NONE and STATUS_DESCRIPTORS.has(status_effect_type):
		var descriptors = STATUS_DESCRIPTORS[status_effect_type]
		prefixes.append(descriptors[randi() % descriptors.size()])
	
	# Add primary stat prefix
	if sorted_stats.size() > 0:
		var primary_stat = sorted_stats[0]["stat"]
		if STAT_PREFIXES.has(primary_stat):
			var stat_prefix_options = STAT_PREFIXES[primary_stat]
			prefixes.append(stat_prefix_options[randi() % stat_prefix_options.size()])
	
	# For epic/legendary, add secondary stat prefix
	if rarity in ["epic", "legendary"] and sorted_stats.size() > 1:
		var secondary_stat = sorted_stats[1]["stat"]
		if SECONDARY_PREFIXES.has(secondary_stat):
			var secondary_options = SECONDARY_PREFIXES[secondary_stat]
			prefixes.append(secondary_options[randi() % secondary_options.size()])
	
	# Generate suffix
	if rarity in ["rare", "epic", "legendary"]:
		suffix = "of " + pantheon_data["verbs"][randi() % pantheon_data["verbs"].size()]
	
	# Build full name
	var new_name = " ".join(prefixes)
	if new_name != "":
		new_name = new_name + " " + base_name
	else:
		new_name = base_name
	
	if suffix != "":
		new_name = new_name + " " + suffix
	
	name = new_name
	
	# Generate flavor text
	flavor_text = "Blessed by %s, the god of %s." % [pantheon_key, pantheon_data["domain"]]
	if rarity in ["epic", "legendary"]:
		flavor_text += " This %s radiates otherworldly power." % type
	else:
		flavor_text += " A fine %s touched by divine essence." % type

func get_rarity_color() -> String:
	if rarities.is_empty():
		load_rarities()
	
	if rarities.has(rarity):
		return rarities[rarity]["color"]
	
	return "white"
	
func load_rarities():
	if not FileAccess.file_exists("res://data/rarities.json"):
		rarities = {
			"common": {"multiplier": 1, "color": "white"},
			"uncommon": {"multiplier": 2, "color": "blue"},
			"magic": {"multiplier": 2.5, "color": "yellow"},
			"rare": {"multiplier": 3, "color": "yellow"},
			"epic": {"multiplier": 4, "color": "purple"},
			"legendary": {"multiplier": 5, "color": "orange"}
		}
		return
	
	var file = FileAccess.open("res://data/rarities.json", FileAccess.READ)
	if file:
		rarities = JSON.parse_string(file.get_as_text())
		file.close()
	else:
		rarities = {
			"common": {"multiplier": 1, "color": "white"},
			"uncommon": {"multiplier": 2, "color": "blue"},
			"magic": {"multiplier": 2.5, "color": "yellow"},
			"rare": {"multiplier": 3, "color": "yellow"},
			"epic": {"multiplier": 4, "color": "purple"},
			"legendary": {"multiplier": 5, "color": "orange"}
		}

func is_equippable() -> bool:
	return true

func can_equip(character: CharacterData) -> bool:
	if class_restriction.is_empty():
		return true
	return character.character_class in class_restriction

func apply_effects(character: CharacterData):
	for effect in effects:
		if effect in character:
			character[effect] += effects[effect]
			
func remove_effects(character: CharacterData):
	for effect in effects:
		if effect in character:
			character[effect] -= effects[effect]

func apply_stat_modifiers(character: CharacterData):
	if not character or not is_instance_valid(character):
		push_error("Cannot apply stat modifiers: invalid character")
		return
	
	for stat in stat_modifiers:
		var stat_name = Skill.AttributeTarget.keys()[stat].to_lower()
		if stat_name in character:
			var current_value = character.get(stat_name)
			character.set(stat_name, current_value + stat_modifiers[stat])
		else:
			push_warning("Character missing stat: %s" % stat_name)

func remove_stat_modifiers(character: CharacterData):
	if not character or not is_instance_valid(character):
		push_error("Cannot remove stat modifiers: invalid character")
		return
	
	for stat in stat_modifiers:
		var stat_name = Skill.AttributeTarget.keys()[stat].to_lower()
		if stat_name in character:
			var current_value = character.get(stat_name)
			character.set(stat_name, current_value - stat_modifiers[stat])
		else:
			push_warning("Character missing stat: %s" % stat_name)

func try_apply_status_effect(target: CharacterData) -> bool:
	if not target or not is_instance_valid(target):
		push_error("Cannot apply status effect: invalid target")
		return false
	
	if status_effect_type != Skill.StatusEffect.NONE and randf() < status_effect_chance:
		target.apply_status_effect(status_effect_type, 3)
		return true
	return false

func get_full_description() -> String:
	var desc = "[b]%s[/b]\n" % name
	# NEW: Show item level
	desc += "[color=gray]Item Level: %d[/color]\n" % item_level
	
	# Rarity display
	if rarities.has(rarity):
		var rarity_data = rarities[rarity]
		desc += "[color=%s]%s[/color]\n" % [rarity_data["color"], rarity.capitalize()]
	
	desc += "\n%s\n" % description

	# Base stats
	if damage > 0:
		desc += "\n[b]Damage:[/b] %d" % damage
		if bonus_damage > 0:
			desc += " [color=orange](+%d bonus)[/color]" % bonus_damage
		desc += "\n"
	if armor_value > 0:
		desc += "[b]Armor:[/b] %d\n" % armor_value

	# Stat Modifiers
	if not stat_modifiers.is_empty():
		desc += "\n[color=green][b]Attribute Bonuses:[/b][/color]\n"
		
		var sorted_mods = []
		for stat in stat_modifiers:
			sorted_mods.append({"stat": stat, "value": stat_modifiers[stat]})
		sorted_mods.sort_custom(func(a, b): return a["value"] > b["value"])
		
		for mod in sorted_mods:
			var stat_name = Skill.AttributeTarget.keys()[mod["stat"]].capitalize()
			var value = mod["value"]
			desc += "  [color=lime]+%d %s[/color]\n" % [value, stat_name]

	# Status Effect
	if status_effect_type != Skill.StatusEffect.NONE:
		var effect_name = Skill.StatusEffect.keys()[status_effect_type]
		var effect_color = "purple"
		match status_effect_type:
			Skill.StatusEffect.BURN:
				effect_color = "orange"
			Skill.StatusEffect.FREEZE:
				effect_color = "cyan"
			Skill.StatusEffect.POISON:
				effect_color = "green"
			Skill.StatusEffect.SHOCK:
				effect_color = "yellow"
		
		desc += "\n[color=%s][b]Special Effect:[/b][/color]\n" % effect_color
		desc += "  [color=%s]%.0f%% chance to inflict %s[/color]\n" % [
			effect_color,
			status_effect_chance * 100,
			effect_name
		]

	# Flavor text
	if flavor_text != "":
		desc += "\n[i][color=gray]%s[/color][/i]\n" % flavor_text

	return desc

func get_save_data() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"rarity": rarity,
		"rarity_applied": rarity_applied,
		"item_level": item_level,  # NEW
		"base_item_level": base_item_level,  # NEW
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

func apply_rarity_modifiers_with_ilvl():
	"""Apply rarity modifiers scaled by item level"""
	if rarities.is_empty():
		print("ERROR: Rarities not loaded!")
		return
	
	if not rarity in rarities:
		print("ERROR: Invalid rarity: %s" % rarity)
		return
	
	var base_multiplier = rarities[rarity]["multiplier"]
	
	# NEW: Scale multiplier by ilvl
	# ilvl 1 = 1.0x, ilvl 10 = 1.5x, ilvl 25 = 2.5x, ilvl 50 = 4.5x
	var ilvl_multiplier = 1.0 + (item_level - 1) * 0.05
	var total_multiplier = base_multiplier * ilvl_multiplier
	
	# Apply to base stats
	if damage > 0:
		damage = int(damage * total_multiplier)
	if armor_value > 0:
		armor_value = int(armor_value * total_multiplier)
	value = int(value * total_multiplier)
	
	# Scale stat modifiers by ilvl
	match rarity:
		"common":
			pass  # No modifiers
		"uncommon":
			add_random_stat_modifier_scaled(1, item_level)
		"magic":
			add_random_stat_modifier_scaled(2, item_level)
		"rare":
			if randf() < 0.3:
				add_random_stat_modifier_scaled(2, item_level)
				add_status_effect_scaled()
			else:
				add_random_stat_modifier_scaled(3, item_level)
		"epic":
			add_random_stat_modifier_scaled(3, item_level)
			add_status_effect_scaled()
		"legendary":
			add_random_stat_modifier_scaled(3, item_level)
			add_status_effect_scaled()
			bonus_damage = int((5 + item_level * 0.5) * (1 + randf() * 0.5))
	
	rarity_applied = true

func add_random_stat_modifier_scaled(count: int, ilvl: int, unique := false):
	"""Add stat modifiers scaled by item level"""
	var available_stats = PRIMARY_STATS.duplicate()
	
	# Base values scale with ilvl
	var min_val = max(1, int(1 + ilvl * 0.15))
	var max_val = max(3, int(3 + ilvl * 0.25))
	
	for i in range(count):
		if available_stats.is_empty():
			break
		
		var stat_index = randi() % available_stats.size()
		var stat = available_stats[stat_index]
		var value = randi_range(min_val, max_val)
		
		if unique:
			available_stats.remove_at(stat_index)
		
		if stat_modifiers.has(stat):
			stat_modifiers[stat] += value
		else:
			stat_modifiers[stat] = value
		
		if not rarity_stat_modifiers.has(stat):
			rarity_stat_modifiers[stat] = 0
		rarity_stat_modifiers[stat] += value

func add_status_effect_scaled():
	"""Add status effect with chance scaled by ilvl"""
	var status_effects = [
		Skill.StatusEffect.BURN,
		Skill.StatusEffect.FREEZE,
		Skill.StatusEffect.POISON,
		Skill.StatusEffect.SHOCK
	]
	
	status_effect_type = status_effects[randi() % status_effects.size()]
	
	# Base chance increases with ilvl
	var base_chance = 0.10 + (item_level * 0.005)
	
	match rarity:
		"rare":
			status_effect_chance = min(0.40, base_chance + randf_range(0.05, 0.15))
		"epic":
			status_effect_chance = min(0.50, base_chance + randf_range(0.10, 0.25))
		"legendary":
			status_effect_chance = min(0.60, base_chance + randf_range(0.20, 0.35))
