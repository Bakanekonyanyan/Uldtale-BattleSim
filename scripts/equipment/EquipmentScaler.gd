# EquipmentScaler.gd
# Handles all scaling calculations
# Responsibility: ilvl calculation, stat scaling formulas

class_name EquipmentScaler
extends RefCounted

const RARITY_ILVL_BONUS = {
	"common": 0,
	"uncommon": 1,
	"magic": 2,
	"rare": 3,
	"epic": 5,
	"legendary": 8
}

const RARITY_MULTIPLIERS = {
	"common": 1.0,
	"uncommon": 2.0,
	"magic": 2.5,
	"rare": 3.0,
	"epic": 4.0,
	"legendary": 5.0
}

# === ITEM LEVEL ===

func calculate_item_level(floor: int, rarity: String) -> int:
	"""Calculate final ilvl from floor + rarity + variance"""
	var rarity_bonus = RARITY_ILVL_BONUS.get(rarity, 0)
	var variance = randi_range(-2, 2)
	return max(1, floor + rarity_bonus + variance)

# === STAT SCALING ===

func scale_damage(base_damage: int, ilvl: int, rarity: String) -> int:
	"""Scale weapon damage by ilvl and rarity"""
	if base_damage == 0:
		return 0
	
	var multiplier = _get_total_multiplier(ilvl, rarity)
	return int(base_damage * multiplier)

func scale_armor(base_armor: int, ilvl: int, rarity: String) -> int:
	"""Scale armor value by ilvl and rarity"""
	if base_armor == 0:
		return 0
	
	var multiplier = _get_total_multiplier(ilvl, rarity)
	return int(base_armor * multiplier)

func scale_value(base_value: int, ilvl: int, rarity: String) -> int:
	"""Scale item value by ilvl and rarity"""
	var multiplier = _get_total_multiplier(ilvl, rarity)
	return int(base_value * multiplier)

# === MULTIPLIER CALCULATION ===

func _get_total_multiplier(ilvl: int, rarity: String) -> float:
	"""Calculate combined ilvl + rarity multiplier"""
	var rarity_mult = RARITY_MULTIPLIERS.get(rarity, 1.0)
	var ilvl_mult = _get_ilvl_multiplier(ilvl)
	return rarity_mult * ilvl_mult

func _get_ilvl_multiplier(ilvl: int) -> float:
	"""
	Calculate ilvl scaling multiplier
	ilvl 1 = 1.0x
	ilvl 10 = 1.45x
	ilvl 25 = 2.2x
	ilvl 50 = 3.45x
	"""
	return 1.0 + (ilvl - 1) * 0.05

# === STAT MODIFIER SCALING ===

func get_scaled_stat_range(ilvl: int) -> Dictionary:
	"""Get min/max stat modifier values for ilvl"""
	var min_val = max(1, int(1 + ilvl * 0.15))
	var max_val = max(3, int(3 + ilvl * 0.25))
	return {"min": min_val, "max": max_val}

# === DISPLAY HELPERS ===

func get_scaling_info(ilvl: int, rarity: String) -> Dictionary:
	"""Get human-readable scaling info for tooltips"""
	var total_mult = _get_total_multiplier(ilvl, rarity)
	var ilvl_mult = _get_ilvl_multiplier(ilvl)
	var rarity_mult = RARITY_MULTIPLIERS.get(rarity, 1.0)
	
	return {
		"total_multiplier": total_mult,
		"ilvl_multiplier": ilvl_mult,
		"rarity_multiplier": rarity_mult,
		"ilvl_bonus_pct": int((ilvl_mult - 1.0) * 100),
		"rarity_bonus_pct": int((rarity_mult - 1.0) * 100),
		"total_bonus_pct": int((total_mult - 1.0) * 100)
	}
