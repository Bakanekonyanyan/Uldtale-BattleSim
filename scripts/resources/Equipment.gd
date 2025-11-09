# Equipment.gd
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
var inventory_key: String = ""  # Stores the unique inventory key for this instance

# New rarity system properties
var stat_modifiers: Dictionary = {}  # Dictionary of AttributeTarget -> value
var status_effect_chance: float = 0.0  # Chance to apply status effect (0.0 to 1.0)
var status_effect_type: Skill.StatusEffect = Skill.StatusEffect.NONE
var bonus_damage: int = 0  # Flat damage bonus for legendary items
var item_prefix: String = ""  # "Burning", "Frozen", etc.
var item_suffix: String = ""  # "of the Flame", "of Solara", etc.
var flavor_text: String = ""  # Lore text based on pantheon

var rarities: Dictionary = {}

# Stat-based prefixes for the highest stat modifier
const STAT_PREFIXES = {
	Skill.AttributeTarget.VITALITY: ["Stalwart", "Enduring", "Resilient"],
	Skill.AttributeTarget.STRENGTH: ["Crushing", "Mighty", "Titanic"],
	Skill.AttributeTarget.DEXTERITY: ["Swift", "Precise", "Nimble"],
	Skill.AttributeTarget.INTELLIGENCE: ["Brilliant", "Cunning", "Sage's"],
	Skill.AttributeTarget.FAITH: ["Devout", "Hallowed", "Divine"],
	Skill.AttributeTarget.MIND: ["Focused", "Contemplative", "Mindful"],
	Skill.AttributeTarget.ENDURANCE: ["Tireless", "Steadfast", "Unyielding"],
	Skill.AttributeTarget.ARCANE: ["Mystical", "Arcane", "Eldritch"],
	Skill.AttributeTarget.AGILITY: ["Graceful", "Flowing", "Lithe"],
	Skill.AttributeTarget.FORTITUDE: ["Ironclad", "Fortified", "Unbreakable"]
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
	# Load rarities FIRST before anything else
	load_rarities()
	
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
	
	# Set the proper item_type based on whether it's a weapon or armor
	if type == "weapon":
		item_type = Item.ItemType.WEAPON
	elif type == "armor":
		item_type = Item.ItemType.ARMOR
	else:
		item_type = Item.ItemType.WEAPON
	
	# Check if rarity is already set in the data (for loading saves)
	# Use 'in' operator for dictionary checks instead of has()
	if "rarity" in data and data["rarity"] != "":
		rarity = data["rarity"]
		rarity_applied = data.get("rarity_applied", false)
		
		# Load saved modifiers if they exist (NEW SYSTEM)
		if "stat_modifiers" in data:
			# New system - has stat_modifiers
			stat_modifiers = data.get("stat_modifiers", {})
			status_effect_chance = data.get("status_effect_chance", 0.0)
			status_effect_type = data.get("status_effect_type", Skill.StatusEffect.NONE)
			bonus_damage = data.get("bonus_damage", 0)
			item_prefix = data.get("item_prefix", "")
			item_suffix = data.get("item_suffix", "")
			flavor_text = data.get("flavor_text", "")
			print("Equipment loaded with NEW rarity system: %s (%s)" % [name, rarity])
		else:
			# Old system - just had rarity multiplier applied
			# Leave item as-is, don't generate new modifiers
			print("Equipment loaded with OLD rarity system: %s (%s) - keeping as-is" % [name, rarity])
	else:
		# Only assign and apply rarity for NEW items
		assign_random_rarity()
		apply_rarity_modifiers()
		generate_procedural_name()
		print("New equipment created: %s with rarity %s (damage: %d, armor: %d)" % [name, rarity, damage, armor_value])

func assign_random_rarity():
	var rarity_roll = randf()
	if rarity_roll < 0.50:  # 50% common
		rarity = "common"
	elif rarity_roll < 0.75:  # 25% uncommon
		rarity = "uncommon"
	elif rarity_roll < 0.87:  # 12% magic
		rarity = "magic"
	elif rarity_roll < 0.94:  # 7% rare
		rarity = "rare"
	elif rarity_roll < 0.98:  # 4% epic
		rarity = "epic"
	else:  # 2% legendary
		rarity = "legendary"
	print("Assigned rarity: %s (roll: %.3f)" % [rarity, rarity_roll])

func apply_rarity_modifiers():
	"""Apply the new rarity system with stat modifiers and status effects"""
	if rarities.is_empty():
		print("ERROR: Rarities not loaded!")
		return
	
	if not rarity in rarities:
		print("ERROR: Invalid rarity: %s" % rarity)
		return
		
	var multiplier = rarities[rarity]["multiplier"]
	
	# Apply base multiplier to damage/armor
	if damage > 0:
		damage = int(damage * multiplier)
	if armor_value > 0:
		armor_value = int(armor_value * multiplier)
	value = int(value * multiplier)
	
	# Apply rarity-specific modifiers
	match rarity:
		"common":
			# No additional modifiers
			pass
		
		"uncommon":
			# 1 random stat modifier (+1 to +3)
			add_random_stat_modifier(1, 1, 3)
		
		"magic":
			# 2 random stat modifiers (+1 to +4)
			add_random_stat_modifier(2, 1, 4)
		
		"rare":
			# 3 random stat modifiers (+2 to +5) OR 2 mods + status effect
			if randf() < 0.3:  # 30% chance for status effect
				add_random_stat_modifier(2, 2, 5)
				add_status_effect()
			else:
				add_random_stat_modifier(3, 2, 5)
		
		"epic":
			# 3 unique stat modifiers (+3 to +6) + status effect
			add_random_stat_modifier(3, 3, 6, true)  # true = ensure unique
			add_status_effect()
		
		"legendary":
			# 3 unique stat modifiers (+4 to +7) + status effect + bonus damage
			add_random_stat_modifier(3, 4, 7, true)
			add_status_effect()
			bonus_damage = randi_range(5, 15)
			print("Legendary bonus damage: +%d" % bonus_damage)
	
	rarity_applied = true

func add_random_stat_modifier(count: int, min_value: int, max_value: int, unique: bool = false):
	"""Add random stat modifiers to the item"""
	var available_stats = PRIMARY_STATS.duplicate()
	
	for i in range(count):
		if available_stats.is_empty():
			break
		
		var stat: Skill.AttributeTarget
		if unique:
			# Pick a unique stat
			stat = available_stats[randi() % available_stats.size()]
			available_stats.erase(stat)
		else:
			# Can pick the same stat multiple times
			stat = PRIMARY_STATS[randi() % PRIMARY_STATS.size()]
		
		var modifier_value = randi_range(min_value, max_value)
		
		# If stat already has a modifier, add to it instead of replacing
		if stat_modifiers.has(stat):
			stat_modifiers[stat] += modifier_value
		else:
			stat_modifiers[stat] = modifier_value
		
		print("Added stat modifier: %s +%d" % [Skill.AttributeTarget.keys()[stat], modifier_value])

func add_status_effect():
	"""Add a random status effect with a chance to proc"""
	var status_effects = [
		Skill.StatusEffect.BURN,
		Skill.StatusEffect.FREEZE,
		Skill.StatusEffect.POISON,
		Skill.StatusEffect.SHOCK
	]
	
	status_effect_type = status_effects[randi() % status_effects.size()]
	
	# Chance varies by rarity
	match rarity:
		"rare":
			status_effect_chance = randf_range(0.10, 0.20)  # 10-20%
		"epic":
			status_effect_chance = randf_range(0.15, 0.30)  # 15-30%
		"legendary":
			status_effect_chance = randf_range(0.25, 0.40)  # 25-40%
	
	print("Added status effect: %s (%.1f%% chance)" % [Skill.StatusEffect.keys()[status_effect_type], status_effect_chance * 100])

func generate_procedural_name():
	"""Generate a procedurally named item based on its properties"""
	if rarity == "common":
		# Common items keep their base name
		return
	
	# Select pantheon based on status effect or random
	var pantheon_key = ""
	if status_effect_type != Skill.StatusEffect.NONE and STATUS_PANTHEON_MAP.has(status_effect_type):
		pantheon_key = STATUS_PANTHEON_MAP[status_effect_type]
	else:
		# Pick random pantheon
		var pantheon_keys = PANTHEON_NAMES.keys()
		pantheon_key = pantheon_keys[randi() % pantheon_keys.size()]
	
	var pantheon_data = PANTHEON_NAMES[pantheon_key]
	
	# Generate prefix based on highest stat modifier OR pantheon
	if not stat_modifiers.is_empty():
		# Find the stat with the highest modifier
		var highest_stat = null
		var highest_value = 0
		for stat in stat_modifiers:
			if stat_modifiers[stat] > highest_value:
				highest_value = stat_modifiers[stat]
				highest_stat = stat
		
		# Use stat-based prefix for the primary modifier
		if highest_stat != null and STAT_PREFIXES.has(highest_stat):
			var stat_prefix_options = STAT_PREFIXES[highest_stat]
			item_prefix = stat_prefix_options[randi() % stat_prefix_options.size()]
			print("Using stat-based prefix for %s: %s" % [Skill.AttributeTarget.keys()[highest_stat], item_prefix])
	
	# If no stat prefix was set, use pantheon adjective (70% chance)
	if item_prefix == "" and randf() < 0.7:
		item_prefix = pantheon_data["adjectives"][randi() % pantheon_data["adjectives"].size()]
	
	# Generate suffix (of + verb/noun) - 60% chance
	if randf() < 0.6:
		item_suffix = "of " + pantheon_data["verbs"][randi() % pantheon_data["verbs"].size()]
	
	# Build full name
	var new_name = ""
	if item_prefix != "":
		new_name = item_prefix + " " + name
	else:
		new_name = name
	
	if item_suffix != "":
		new_name = new_name + " " + item_suffix
	
	name = new_name
	
	# Generate flavor text
	flavor_text = "Blessed by %s, the god of %s. %s" % [
		pantheon_key,
		pantheon_data["domain"],
		"This %s radiates otherworldly power." % type if rarity in ["epic", "legendary"] else "A fine %s touched by divine essence." % type
	]
	
	print("Generated name: %s" % name)
	print("Flavor text: %s" % flavor_text)

func get_full_description() -> String:
	"""Get the full description including all modifiers"""
	var desc = description + "\n"
	
	if flavor_text != "":
		desc += "\n[i]" + flavor_text + "[/i]\n"
	
	if rarities.has(rarity):
		desc += "\n[color=%s]%s[/color]\n" % [rarities[rarity]["color"], rarity.capitalize()]
	
	if damage > 0:
		desc += "Damage: %d\n" % damage
	if armor_value > 0:
		desc += "Armor: %d\n" % armor_value
	if bonus_damage > 0:
		desc += "[color=orange]Bonus Damage: +%d[/color]\n" % bonus_damage
	
	if not stat_modifiers.is_empty():
		desc += "\n[color=green]Stat Modifiers:[/color]\n"
		for stat in stat_modifiers:
			desc += "  +%d %s\n" % [stat_modifiers[stat], Skill.AttributeTarget.keys()[stat].capitalize()]
	
	if status_effect_type != Skill.StatusEffect.NONE:
		desc += "\n[color=purple]%.1f%% chance to inflict %s[/color]\n" % [
			status_effect_chance * 100,
			Skill.StatusEffect.keys()[status_effect_type]
		]
	
	return desc

func apply_stat_modifiers(character: CharacterData):
	"""Apply stat modifiers to a character when equipped"""
	if not character or not is_instance_valid(character):
		push_error("Cannot apply stat modifiers: invalid character")
		return
	
	for stat in stat_modifiers:
		var stat_name = Skill.AttributeTarget.keys()[stat].to_lower()
		# Use 'in' operator for Resources instead of has()
		if stat_name in character:
			var current_value = character.get(stat_name)
			character.set(stat_name, current_value + stat_modifiers[stat])
			print("Applied +%d to %s" % [stat_modifiers[stat], stat_name])
		else:
			push_warning("Character missing stat: %s" % stat_name)

func remove_stat_modifiers(character: CharacterData):
	"""Remove stat modifiers from a character when unequipped"""
	if not character or not is_instance_valid(character):
		push_error("Cannot remove stat modifiers: invalid character")
		return
	
	for stat in stat_modifiers:
		var stat_name = Skill.AttributeTarget.keys()[stat].to_lower()
		# Use 'in' operator for Resources instead of has()
		if stat_name in character:
			var current_value = character.get(stat_name)
			character.set(stat_name, current_value - stat_modifiers[stat])
			print("Removed +%d from %s" % [stat_modifiers[stat], stat_name])
		else:
			push_warning("Character missing stat: %s" % stat_name)

func try_apply_status_effect(target: CharacterData) -> bool:
	"""Try to apply status effect on hit. Returns true if applied."""
	if not target or not is_instance_valid(target):
		push_error("Cannot apply status effect: invalid target")
		return false
	
	if status_effect_type != Skill.StatusEffect.NONE and randf() < status_effect_chance:
		target.apply_status_effect(status_effect_type, 3)  # 3 turn duration
		print("%s triggered %s on %s!" % [name, Skill.StatusEffect.keys()[status_effect_type], target.name])
		return true
	return false

func get_rarity_color() -> String:
	if rarities.is_empty():
		load_rarities()
	
	if rarities.has(rarity):
		return rarities[rarity]["color"]
	
	print("WARNING: Rarity '%s' not found in rarities dictionary" % rarity)
	return "white"  # Default fallback color
	
func load_rarities():
	if not FileAccess.file_exists("res://data/rarities.json"):
		print("ERROR: rarities.json not found!")
		# Create default rarities as fallback
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
		print("Loaded rarities: %s" % rarities.keys())
	else:
		print("ERROR: Could not open rarities.json")
		# Create default rarities as fallback
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
		# Use 'in' operator for Resources instead of has()
		if effect in character:
			character[effect] += effects[effect]
			
func remove_effects(character: CharacterData):
	for effect in effects:
		# Use 'in' operator for Resources instead of has()
		if effect in character:
			character[effect] -= effects[effect]

func get_save_data() -> Dictionary:
	"""Get data for saving, including new rarity properties"""
	return {
		"id": id,
		"name": name,  # Include the full name with prefix/suffix
		"rarity": rarity,
		"rarity_applied": rarity_applied,
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
