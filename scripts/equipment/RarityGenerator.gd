# RarityGenerator.gd
# Handles all rarity-related logic
# Responsibility: Rarity rolls, stat modifier generation, status effects

class_name RarityGenerator
extends RefCounted

const RARITY_CHANCES = {
	"common": 0.50,
	"uncommon": 0.75,
	"magic": 0.87,
	"rare": 0.94,
	"epic": 0.98,
	"legendary": 1.00
}

const RARITY_ILVL_BONUS = {
	"common": 0,
	"uncommon": 1,
	"magic": 2,
	"rare": 3,
	"epic": 5,
	"legendary": 8
}

const RARITY_COLORS = {
	"common": "white",
	"uncommon": "blue",
	"magic": "yellow",
	"rare": "yellow",
	"epic": "purple",
	"legendary": "orange"
}

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

# === RARITY ROLLING ===

func roll_rarity() -> String:
	"""Roll random rarity tier"""
	var roll = randf()
	
	if roll < 0.50: return "common"
	elif roll < 0.75: return "uncommon"
	elif roll < 0.87: return "magic"
	elif roll < 0.94: return "rare"
	elif roll < 0.98: return "epic"
	else: return "legendary"

func get_ilvl_bonus(rarity: String) -> int:
	"""Get item level bonus for rarity"""
	return RARITY_ILVL_BONUS.get(rarity, 0)

func get_color(rarity: String) -> String:
	"""Get display color for rarity"""
	return RARITY_COLORS.get(rarity, "white")

# === MODIFIER GENERATION ===

func generate_modifiers(rarity: String, ilvl: int) -> Dictionary:
	"""Generate all modifiers for a rarity tier"""
	var result = {
		"stat_modifiers": {},
		"status_effect": Skill.StatusEffect.NONE,
		"status_chance": 0.0,
		"bonus_damage": 0
	}
	
	match rarity:
		"common":
			pass  # No modifiers
		"uncommon":
			result.stat_modifiers = _roll_stat_modifiers(1, ilvl, false)
		"magic":
			result.stat_modifiers = _roll_stat_modifiers(2, ilvl, false)
		"rare":
			if randf() < 0.3:
				result.stat_modifiers = _roll_stat_modifiers(2, ilvl, false)
				result.status_effect = _roll_status_effect()
				result.status_chance = _calculate_status_chance(rarity, ilvl)
			else:
				result.stat_modifiers = _roll_stat_modifiers(3, ilvl, false)
		"epic":
			result.stat_modifiers = _roll_stat_modifiers(3, ilvl, true)
			result.status_effect = _roll_status_effect()
			result.status_chance = _calculate_status_chance(rarity, ilvl)
		"legendary":
			result.stat_modifiers = _roll_stat_modifiers(3, ilvl, true)
			result.status_effect = _roll_status_effect()
			result.status_chance = _calculate_status_chance(rarity, ilvl)
			result.bonus_damage = int((5 + ilvl * 0.5) * (1 + randf() * 0.5))
	
	return result

# === STAT MODIFIERS ===

func _roll_stat_modifiers(count: int, ilvl: int, unique: bool) -> Dictionary:
	"""Roll random stat modifiers scaled by ilvl"""
	var modifiers = {}
	var available = PRIMARY_STATS.duplicate()
	
	var min_val = max(1, int(1 + ilvl * 0.15))
	var max_val = max(3, int(3 + ilvl * 0.25))
	
	for i in range(count):
		if available.is_empty():
			break
		
		var stat_idx = randi() % available.size()
		var stat = available[stat_idx]
		var value = randi_range(min_val, max_val)
		
		if unique:
			available.remove_at(stat_idx)
		
		if modifiers.has(stat):
			modifiers[stat] += value
		else:
			modifiers[stat] = value
	
	return modifiers

# === STATUS EFFECTS ===

func _roll_status_effect() -> Skill.StatusEffect:
	"""Roll random status effect"""
	var effects = [
		Skill.StatusEffect.BURN,
		Skill.StatusEffect.FREEZE,
		Skill.StatusEffect.POISON,
		Skill.StatusEffect.SHOCK
	]
	return effects[randi() % effects.size()]

func _calculate_status_chance(rarity: String, ilvl: int) -> float:
	"""Calculate status proc chance based on rarity and ilvl"""
	var base = 0.10 + (ilvl * 0.005)
	
	match rarity:
		"rare":
			return min(0.40, base + randf_range(0.05, 0.15))
		"epic":
			return min(0.50, base + randf_range(0.10, 0.25))
		"legendary":
			return min(0.60, base + randf_range(0.20, 0.35))
	
	return 0.0
