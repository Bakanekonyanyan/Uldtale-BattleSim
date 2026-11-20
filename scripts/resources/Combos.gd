# res://scripts/resources/Combos.gd
# Set-up / payoff combos (the simple combo system). Data: data/combos.json.
#
#   set-up   a status on the target (Freeze, Bleed, Poison...)
#   payoff   a hit whose element, physical damage type, ability type or skill
#            name matches the combo
#   result   the hit deals x multiplier; the set-up status is consumed
#
# Only the best combo applies per hit. Heroes and enemies use the same combos
# (players = enemies). Callers: Skill.deal_damage / apply_debuff / drain and
# CombatEngine's basic attack; EnemyAI and the battle UI use preview().
class_name Combos
extends RefCounted

static func cfg() -> Dictionary:
	var d = DataRegistry.get_data("combos")
	return d if d is Dictionary and d.has("combos") else {"combos": {}}

static func all() -> Dictionary:
	return cfg().get("combos", {})

## Describe a hit for matching: {"elements": [names], "damage_type": int, "physical": bool, "skill": name}
static func hit_from_skill(user: CharacterData, skill: Skill) -> Dictionary:
	var names: Array = []
	for e in skill.elements:
		var n = Skill.ElementType.keys()[e]
		if n != "NONE" and n != "PHYSICAL":
			names.append(n)
	var physical = skill.ability_type == Skill.AbilityType.PHYSICAL
	return {"elements": names, "physical": physical, "skill": skill.name, "user": user,
		"damage_type": DamageTypes.attack_type(user, skill.damage_type) if physical else -1}

static func hit_from_attack(attacker: CharacterData) -> Dictionary:
	return {"elements": [], "physical": true, "skill": "", "user": attacker, "damage_type": DamageTypes.attack_type(attacker)}

static func _matches(payoff: Dictionary, hit: Dictionary) -> bool:
	for e in payoff.get("elements", []):
		if e in hit.elements:
			return true
	if hit.damage_type >= 0:
		var dt_name = DamageTypes.Type.keys()[hit.damage_type]
		if dt_name in payoff.get("damage_types", []):
			return true
	for a in payoff.get("ability_types", []):
		if (a == "PHYSICAL" and hit.physical) or (a == "MAGICAL" and not hit.physical):
			return true
	return hit.skill != "" and hit.skill in payoff.get("skills", [])

## The best combo this hit triggers on `target`, or {} if none.
## Returned dict: {"id", "name", "multiplier", "setup" (StatusEffect), "consume"}
static func find(target: CharacterData, hit: Dictionary) -> Dictionary:
	if target == null or target.status_manager == null:
		return {}
	var best := {}
	for id in all():
		var c: Dictionary = all()[id]
		var setup_name = String(c.get("setup", ""))
		if not Skill.StatusEffect.has(setup_name):
			continue
		var setup = Skill.StatusEffect[setup_name]
		if not target.status_manager.has_effect(setup):
			continue
		if not _matches(c.get("payoff", {}), hit):
			continue
		var mult = float(c.get("multiplier", 1.0))
		var user = hit.get("user")
		if user and user.talents:
			mult += user.talents.combo_bonus(id)        # talent combo mastery
		if best.is_empty() or mult > best.multiplier:
			best = {"id": id, "name": String(c.get("name", id)), "multiplier": mult, "setup": setup,
				"consume": bool(c.get("consume", true))}
	return best

## Call after the payoff hit landed: removes the set-up status if the combo consumes it.
## Combos triggered since BattleRules.before_action ([{target, combo}]).
static var recent: Array = []

static func consume(target: CharacterData, combo: Dictionary) -> void:
	if combo.is_empty():
		return
	recent.append({"target": target, "combo": combo})
	if not combo.consume or target.status_manager == null:
		return
	target.status_manager.remove_effect(combo.setup)

## Combat-log line for a triggered combo.
static func log_line(target: CharacterData, combo: Dictionary) -> String:
	return "[color=#e5c34a]COMBO - %s on %s (x%.2f)[/color]" % [combo.name, target.name, combo.multiplier]

## Which combo `skill` would trigger on `target` right now ({} = none). For AI and UI.
static func preview(user: CharacterData, skill: Skill, target: CharacterData) -> Dictionary:
	if skill.type not in [Skill.SkillType.DAMAGE, Skill.SkillType.DRAIN, Skill.SkillType.DEBUFF]:
		return {}
	return find(target, hit_from_skill(user, skill))
