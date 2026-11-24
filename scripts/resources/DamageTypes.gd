# res://scripts/resources/DamageTypes.gd
# Physical damage types (Slash / Pierce / Blunt): what an attack deals and how
# much a defender takes from it. Tuning lives in data/damage_types.json.
#
#   attack type   skill's damage_type, else the main-hand weapon's, else unarmed
#                 (untyped by default, so fresh heroes with no weapon are neutral)
#   multiplier    1 + race affinity + armor affinity, clamped (default 0.5 .. 1.75)
#   armor         each equipped armor piece's type, averaged over the 5 armor slots
#
# Only physical hits use this (BattleFormulas.hit_damage). Magic uses elements.
# Heroes and enemies use the same tables.
class_name DamageTypes
extends RefCounted

enum Type { SLASH, PIERCE, BLUNT }
const FROM_WEAPON := -1          # skill/attack has no fixed type: use the weapon
const ARMOR_SLOTS := ["head", "chest", "hands", "legs", "feet"]

static func cfg() -> Dictionary:
	var d = DataRegistry.get_data("damage_types")
	return d if d is Dictionary and not d.is_empty() else {"weapons": {}, "armor": {}, "races": {}}

static func type_name(t: int) -> String:
	return Type.keys()[t].capitalize() if t >= 0 and t < Type.size() else "None"

static func parse(s: String) -> int:
	s = s.strip_edges().to_upper()
	return Type[s] if Type.has(s) else FROM_WEAPON

## The damage type of `attacker`'s physical hit (`override` from a skill, if any).
static func attack_type(attacker: CharacterData, override: int = FROM_WEAPON) -> int:
	if override >= 0:
		return override
	var weapon = attacker.equipment.get("main_hand") if attacker else null
	if weapon is Equipment:
		return weapon_type(weapon)
	# Unarmed: untyped unless the class fights bare-handed on purpose (Monk = Blunt)
	var by_class: Dictionary = cfg().get("unarmed_by_class", {})
	if attacker and by_class.has(attacker.character_class):
		return parse(String(by_class[attacker.character_class]))
	return parse(String(cfg().get("unarmed", "")))

static func weapon_type(weapon: Equipment) -> int:
	var t = parse(String(cfg().get("weapons", {}).get(weapon.key, "")))
	return t

## Race + armor affinity for one type: >0 weak (takes more), <0 resists.
static func affinity(target: CharacterData, t: int) -> float:
	var extra = float(target.get_meta("affinity_bonus", {}).get(Type.keys()[t], 0.0)) if target.has_meta("affinity_bonus") else 0.0
	return race_affinity(String(target.race), t) + armor_affinity(target, t) + extra

static func race_affinity(race: String, t: int) -> float:
	return float(cfg().get("races", {}).get(race, {}).get(Type.keys()[t], 0.0))

static func armor_affinity(target: CharacterData, t: int) -> float:
	var total := 0.0
	for slot in ARMOR_SLOTS:
		var piece = target.equipment.get(slot)
		if piece is Equipment:
			total += armor_piece_affinity(piece, t)
	return total / ARMOR_SLOTS.size()

static func armor_piece_affinity(piece: Equipment, t: int) -> float:
	return float(cfg().get("armor", {}).get(String(piece.type), {}).get(Type.keys()[t], 0.0))

## Damage multiplier `target` takes from a hit of type `t`.
static func multiplier(target: CharacterData, t: int) -> float:
	if t < 0:
		return 1.0
	return clamp(1.0 + affinity(target, t), float(cfg().get("min_multiplier", 0.5)), float(cfg().get("max_multiplier", 1.75)))

## Combat-log tag for a hit, e.g. " [color=...](Blunt - weak!)[/color]"; "" when neutral.
static func log_tag(mult: float, t: int) -> String:
	if mult >= 1.1:
		return " [color=#8fd46a](%s - weak spot!)[/color]" % type_name(t)
	if mult <= 0.9:
		return " [color=#a99f90](%s - resisted)[/color]" % type_name(t)
	return ""

## Short description of an affinity dict for UI: "weak to Blunt, resists Slash"
static func describe(affinities: Dictionary) -> String:
	var weak: PackedStringArray = []
	var resist: PackedStringArray = []
	for key in Type.keys():
		var v = float(affinities.get(key, 0.0))
		if v > 0.0:
			weak.append("%s +%d%%" % [key.capitalize(), int(round(v * 100))])
		elif v < 0.0:
			resist.append("%s %d%%" % [key.capitalize(), int(round(v * 100))])
	var parts: PackedStringArray = []
	if not weak.is_empty():
		parts.append("takes more from " + ", ".join(weak))
	if not resist.is_empty():
		parts.append("takes less from " + ", ".join(resist))
	return "; ".join(parts)
