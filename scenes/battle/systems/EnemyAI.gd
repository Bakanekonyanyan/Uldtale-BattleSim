# res://scenes/battle/systems/EnemyAI.gd
# Enemy decision-making logic
# Extracted from Battle.gd for better testing and tuning

class_name EnemyAI
extends RefCounted

var enemy: CharacterData
var player: CharacterData
var current_floor: int = 1

func initialize(p_enemy: CharacterData, p_player: CharacterData, floor: int):
	enemy = p_enemy
	player = p_player
	current_floor = floor
	print("EnemyAI: Initialized for %s on floor %d" % [enemy.name, floor])

func decide_action() -> BattleAction:
	"""Main decision-making entry point"""
	var enemy_hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
	var player_hp_percent = float(player.current_hp) / float(player.max_hp)
	var momentum_level = MomentumSystem.get_momentum()
	
	# Item usage check (increases with floor and momentum)
	var item_chance = 0.1 + (current_floor * 0.02) + (momentum_level * 0.05)
	if randf() < item_chance:
		var item_action = _try_use_item()
		if item_action:
			return item_action
	
	# Low HP - defensive or heal
	if enemy_hp_percent < 0.3:
		var defensive_action = _decide_defensive_action()
		if defensive_action:
			return defensive_action
	
	# Try to use skill (80% chance)
	if randf() < 0.8:
		var skill_action = _try_use_skill()
		if skill_action:
			return skill_action
	
		
	# Default to attack
	return BattleAction.attack(enemy, player)

# === ITEM USAGE ===

func _try_use_item() -> BattleAction:
	"""Try to use a combat item"""
	if enemy.inventory.items.is_empty():
		return null
	
	var usable_items = _get_usable_items()
	if usable_items.is_empty():
		return null
	
	# Pick random usable item
	var item = usable_items[randi() % usable_items.size()]
	var targets = _get_item_targets(item)
	
	print("EnemyAI: Using item %s" % item.name)
	return BattleAction.item(enemy, item, targets)

func _get_usable_items() -> Array:
	"""Get items enemy can use in combat"""
	var usable = []
	for item_id in enemy.inventory.items:
		var item = enemy.inventory.items[item_id].item
		if item and item.item_type == Item.ItemType.CONSUMABLE and item.combat_usable:
			usable.append(item)
	return usable

func _get_item_targets(item: Item) -> Array:
	"""Get correct targets for an item"""
	match item.consumable_type:
		Item.ConsumableType.DAMAGE, Item.ConsumableType.DEBUFF:
			return [player]
		_:
			return [enemy]

# === SKILL USAGE ===

func _try_use_skill() -> BattleAction:
	"""Try to use a skill"""
	var available_skills = _get_available_skills()
	
	if available_skills.is_empty():
		return null
	
	# Pick random available skill
	var skill = available_skills[randi() % available_skills.size()]
	var targets = _get_skill_targets(skill)
	
	print("EnemyAI: Using skill %s" % skill.name)
	return BattleAction.skill(enemy, skill, targets)

func _get_available_skills() -> Array[Skill]:
	"""Get skills enemy can currently use"""
	var available: Array[Skill] = []
	
	for skill_name in enemy.skills:
		var skill = SkillManager.get_skill(skill_name)
		if not skill:
			continue
		
		# Check cooldown
		if enemy.get_skill_cooldown(skill_name) > 0:
			continue
		
		# Check resources
		var has_resources = false
		if skill.ability_type == Skill.AbilityType.PHYSICAL:
			has_resources = enemy.current_sp >= skill.sp_cost
		else:
			has_resources = enemy.current_mp >= skill.mp_cost
		
		if has_resources:
			available.append(skill)
		
	return available

func _get_skill_targets(skill: Skill) -> Array:
	"""Get correct targets for a skill"""
	match skill.target:
		Skill.TargetType.SELF, Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES:
			return [enemy]
		Skill.TargetType.ENEMY, Skill.TargetType.ALL_ENEMIES:
			return [player]
	return []

# === DEFENSIVE ACTIONS ===

func _decide_defensive_action() -> BattleAction:
	"""Decide what to do when low on HP"""
	# If already defending and enemy is also low health or low mp/sp try to use skill else attack
	if enemy.is_defending:
		if player.current_hp < enemy.current_hp:
			for skill_name in enemy.skills:
				var skill = SkillManager.get_skill(skill_name)
				if not skill or enemy.get_skill_cooldown(skill_name) > 0:
					continue
		
				if skill.type == Skill.SkillType.DAMAGE:
					var has_resources = enemy.current_mp >= skill.mp_cost if skill.ability_type != Skill.AbilityType.PHYSICAL else enemy.current_sp >= skill.sp_cost
					if has_resources:
						print("EnemyAI: Using damage skill %s" % skill.name)
						return BattleAction.skill(enemy, skill, [enemy])
		elif player.current_mp < enemy.current_mp:
			for skill_name in enemy.skills:
				var skill = SkillManager.get_skill(skill_name)
				if not skill or enemy.get_skill_cooldown(skill_name) > 0:
					continue
		
				if skill.type == Skill.SkillType.DAMAGE:
					var has_resources = enemy.current_mp >= skill.mp_cost if skill.ability_type != Skill.AbilityType.PHYSICAL else enemy.current_sp >= skill.sp_cost
					if has_resources:
						print("EnemyAI: Using damage skill %s" % skill.name)
						return BattleAction.skill(enemy, skill, [enemy])
		elif player.current_sp < enemy.current_sp:
			for skill_name in enemy.skills:
				var skill = SkillManager.get_skill(skill_name)
				if not skill or enemy.get_skill_cooldown(skill_name) > 0:
					continue
		
				if skill.type == Skill.SkillType.DAMAGE:
					var has_resources = enemy.current_mp >= skill.mp_cost if skill.ability_type != Skill.AbilityType.PHYSICAL else enemy.current_sp >= skill.sp_cost
					if has_resources:
						print("EnemyAI: Using damage skill %s" % skill.name)
						return BattleAction.skill(enemy, skill, [enemy])
		else:
			return BattleAction.attack(enemy, player)
	# Try to heal
	for skill_name in enemy.skills:
		var skill = SkillManager.get_skill(skill_name)
		if not skill or enemy.get_skill_cooldown(skill_name) > 0:
			continue
		
		if skill.type == Skill.SkillType.HEAL:
			var has_resources = enemy.current_mp >= skill.mp_cost if skill.ability_type != Skill.AbilityType.PHYSICAL else enemy.current_sp >= skill.sp_cost
			if has_resources:
				print("EnemyAI: Using heal skill %s" % skill.name)
				return BattleAction.skill(enemy, skill, [enemy])
	# No heal available, defend
	print("EnemyAI: Defending")
	return BattleAction.defend(enemy)
