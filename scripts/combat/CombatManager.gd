# res://scripts/combat/CombatManager.gd
class_name CombatManager
extends RefCounted

signal combat_action_completed(result: Dictionary)

func execute_attack(attacker: CharacterData, target: CharacterData) -> String:
	if not is_character_alive(attacker) or not is_character_alive(target):
		return ""
	return attacker.attack(target)

func execute_defend(character: CharacterData) -> String:
	if not is_character_alive(character):
		return ""
	return character.defend()

func execute_skill(caster: CharacterData, skill: Skill, targets: Array) -> Dictionary:
	if not is_character_alive(caster):
		return {"success": false, "message": ""}
	
	var cost_type = "MP" if skill.ability_type != Skill.AbilityType.PHYSICAL else "SP"
	var cost = skill.mp_cost if cost_type == "MP" else skill.sp_cost
	var current = caster.current_mp if cost_type == "MP" else caster.current_sp
	
	if current < cost:
		return {"success": false, "message": "Not enough %s" % cost_type}
	
	if cost_type == "MP":
		caster.current_mp -= cost
	else:
		caster.current_sp -= cost
	
	var result = skill.use(caster, targets)
	caster.use_skill_cooldown(skill.name, skill.cooldown)
	
	return {"success": true, "message": result}

func execute_item(user: CharacterData, item: Item, targets: Array) -> Dictionary:
	if not is_character_alive(user):
		return {"success": false, "message": ""}
	
	var result = item.use(user, targets)
	return {"success": true, "message": result}

func process_status_effects(character: CharacterData) -> String:
	character.reduce_cooldowns()
	return character.update_status_effects()

func is_character_alive(character: CharacterData) -> bool:
	return character != null and character.current_hp > 0

func check_battle_outcome(player: CharacterData, enemy: CharacterData) -> String:
	if not is_character_alive(enemy):
		return "victory"
	if not is_character_alive(player):
		return "defeat"
	return "ongoing"

func get_skill_targets(skill: Skill, caster: CharacterData, opponent: CharacterData) -> Array:
	match skill.target:
		Skill.TargetType.SELF, Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES:
			return [caster]
		Skill.TargetType.ENEMY, Skill.TargetType.ALL_ENEMIES:
			return [opponent]
	return []
