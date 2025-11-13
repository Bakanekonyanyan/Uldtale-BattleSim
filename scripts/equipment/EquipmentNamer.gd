# EquipmentNamer.gd
# Generates procedural names and flavor text
# Responsibility: Build names from stat mods, status effects, and pantheon

class_name EquipmentNamer
extends RefCounted

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

const STATUS_DESCRIPTORS = {
	Skill.StatusEffect.BURN: ["Burning", "Flaming", "Blazing", "Scorching", "Infernal"],
	Skill.StatusEffect.FREEZE: ["Frozen", "Icy", "Glacial", "Frigid", "Chilling"],
	Skill.StatusEffect.POISON: ["Venomous", "Toxic", "Poisoned", "Virulent", "Noxious"],
	Skill.StatusEffect.SHOCK: ["Shocking", "Crackling", "Lightning", "Thunderous", "Voltaic"]
}

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

const STATUS_PANTHEON_MAP = {
	Skill.StatusEffect.BURN: "Solara",
	Skill.StatusEffect.FREEZE: "Nimue",
	Skill.StatusEffect.POISON: "Elandria",
	Skill.StatusEffect.SHOCK: "Aetherion"
}

# === NAME GENERATION ===

func generate_name(data: Dictionary) -> Dictionary:
	"""Generate full name and flavor text"""
	var base_name = data.base_name
	var rarity = data.rarity
	var stat_mods = data.stat_modifiers
	var status = data.status_effect
	var type = data.type
	
	if rarity == "common":
		return {"full_name": base_name, "flavor_text": ""}
	
	# Choose pantheon
	var pantheon = _choose_pantheon(status)
	var pantheon_data = PANTHEON_NAMES[pantheon]
	
	# Build prefixes
	var prefixes = []
	
	# Status prefix
	if status != Skill.StatusEffect.NONE and STATUS_DESCRIPTORS.has(status):
		var descriptors = STATUS_DESCRIPTORS[status]
		prefixes.append(descriptors[randi() % descriptors.size()])
	
	# Primary stat prefix
	if not stat_mods.is_empty():
		var sorted = _sort_stats(stat_mods)
		var primary = sorted[0]["stat"]
		if STAT_PREFIXES.has(primary):
			var options = STAT_PREFIXES[primary]
			prefixes.append(options[randi() % options.size()])
	
	# Secondary stat prefix (epic/legendary only)
	if rarity in ["epic", "legendary"] and stat_mods.size() > 1:
		var sorted = _sort_stats(stat_mods)
		var secondary = sorted[1]["stat"]
		if SECONDARY_PREFIXES.has(secondary):
			var options = SECONDARY_PREFIXES[secondary]
			prefixes.append(options[randi() % options.size()])
	
	# Build suffix
	var suffix = ""
	if rarity in ["rare", "epic", "legendary"]:
		var verbs = pantheon_data["verbs"]
		suffix = "of " + verbs[randi() % verbs.size()]
	
	# Combine
	var full_name = " ".join(prefixes)
	if full_name:
		full_name += " " + base_name
	else:
		full_name = base_name
	
	if suffix:
		full_name += " " + suffix
	
	# Flavor text
	var flavor = "Blessed by %s, the god of %s." % [pantheon, pantheon_data["domain"]]
	if rarity in ["epic", "legendary"]:
		flavor += " This %s radiates otherworldly power." % type
	else:
		flavor += " A fine %s touched by divine essence." % type
	
	return {"full_name": full_name, "flavor_text": flavor}

# === HELPERS ===

func _choose_pantheon(status: Skill.StatusEffect) -> String:
	"""Choose pantheon based on status or random"""
	if status != Skill.StatusEffect.NONE and STATUS_PANTHEON_MAP.has(status):
		return STATUS_PANTHEON_MAP[status]
	
	var keys = PANTHEON_NAMES.keys()
	return keys[randi() % keys.size()]

func _sort_stats(stat_mods: Dictionary) -> Array:
	"""Sort stat modifiers by value"""
	var sorted = []
	for stat in stat_mods:
		sorted.append({"stat": stat, "value": stat_mods[stat]})
	sorted.sort_custom(func(a, b): return a["value"] > b["value"])
	return sorted

func get_status_color(status: Skill.StatusEffect) -> String:
	"""Get color for status effect display"""
	match status:
		Skill.StatusEffect.BURN:
			return "orange"
		Skill.StatusEffect.FREEZE:
			return "cyan"
		Skill.StatusEffect.POISON:
			return "green"
		Skill.StatusEffect.SHOCK:
			return "yellow"
		_:
			return "purple"
