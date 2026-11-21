# res://scenes/battle/core/ReflectionInfo.gd
# Predicts how much damage a defender's reflection effects will bounce back.
#
# Reflection is APPLIED in exactly one place: CharacterData.take_damage(), and
# only when an attacker is passed. This helper just mirrors that math so the
# combat log can describe it. Shared by CombatEngine (basic attacks) and Skill.

class_name ReflectionInfo
extends RefCounted

static func predict(attacker: CharacterData, defender: CharacterData, damage: float) -> Dictionary:
	var info = {
		"reflected": false,
		"amount": 0,
		"percent": 0.0,
		"target_name": ""
	}

	if not attacker or attacker == defender or not defender.status_manager:
		return info

	var reflection = defender.status_manager.get_total_reflection()
	if reflection <= 0.0:
		return info

	# Must match CharacterData.take_damage(): defending halves damage first
	var incoming = damage * (0.5 if defender.is_defending else 1.0)
	var reflected = int(incoming * reflection)

	if reflected > 0:
		info.reflected = true
		info.amount = reflected
		info.percent = reflection * 100.0
		info.target_name = attacker.name

	return info
