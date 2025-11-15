# res://scenes/battle/systems/EnemyAI.gd
# Enhanced AI with smarter decision-making and desperation mechanics

class_name EnemyAI
extends RefCounted

var enemy: CharacterData
var player: CharacterData
var current_floor: int = 1

# AI personality traits (can be randomized per enemy)
var aggression: float = 0.5  # 0.0 = defensive, 1.0 = aggressive
var intelligence: float = 0.5  # 0.0 = random, 1.0 = optimal
var desperation_threshold: float = 0.25  # HP% when desperation kicks in

func initialize(p_enemy: CharacterData, p_player: CharacterData, floor: int):
	enemy = p_enemy
	player = p_player
	current_floor = floor
	
	# Randomize personality traits for variety
	aggression = randf_range(0.3, 0.8)
	intelligence = randf_range(0.4, 0.9)
	desperation_threshold = randf_range(0.2, 0.35)
	
	print("EnemyAI: Initialized for %s (Aggression: %.2f, Intelligence: %.2f)" % [
		enemy.name, aggression, intelligence
	])
	print(enemy.inventory.items)
	
func decide_action() -> BattleAction:
	"""Main decision-making entry point with priority system"""
	var enemy_hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
	var player_hp_percent = float(player.current_hp) / float(player.max_hp)
	var momentum_level = MomentumSystem.get_momentum()
	
	# === DESPERATION MODE (Low HP - Last Stand) ===
	if enemy_hp_percent < desperation_threshold:
		var desperate_action = _decide_desperate_action()
		if desperate_action:
			return desperate_action
	
	# === ITEM USAGE (Proactive) ===
	var item_chance = 0.1 + (current_floor * 0.02) + (momentum_level * 0.05)
	if randf() < item_chance:
		var item_action = _try_use_item_smart()
		if item_action:
			return item_action
	
	# === LOW HP - DEFENSIVE/HEAL (Not desperate yet) ===
	if enemy_hp_percent < 0.5 and enemy_hp_percent >= desperation_threshold:
		var defensive_action = _decide_defensive_action()
		if defensive_action:
			return defensive_action
	
	# === BUFF/DEBUFF PRIORITY (If unbuffed/player unbuffed) ===
	if randf() < 0.6:  # 60% chance to consider buffs
		var buff_action = _try_buff_or_debuff()
		if buff_action:
			return buff_action
	
	# === OFFENSIVE SKILLS (Primary damage dealer) ===
	if randf() < 0.75:
		var skill_action = _try_use_damage_skill()
		if skill_action:
			return skill_action
	
	# === FALLBACK: Basic Attack ===
	return BattleAction.attack(enemy, player)

# =============================================
# DESPERATION MODE (Low HP - All-or-Nothing)
# =============================================

func _decide_desperate_action() -> BattleAction:
	"""When enemy is very low HP, go all-out or setup for final strike"""
	print("EnemyAI: DESPERATION MODE activated!")
	
	# Check player resources to assess threat
	var player_mp_percent = float(player.current_mp) / float(player.max_mp) if player.max_mp > 0 else 0.0
	var player_sp_percent = float(player.current_sp) / float(player.max_sp) if player.max_sp > 0 else 0.0
	
	# If player is low on resources, go for the kill
	if player_mp_percent < 0.3 and player_sp_percent < 0.3:
		print("EnemyAI: Player low on resources - FULL AGGRO!")
		var best_damage_skill = _find_best_damage_skill()
		if best_damage_skill:
			return BattleAction.skill(enemy, best_damage_skill, [player])
		return BattleAction.attack(enemy, player)
	
	# If player has resources, try to survive ONE more turn
	# Use healing item if available
	var heal_item = _find_healing_item()
	if heal_item:
		print("EnemyAI: Desperate heal attempt!")
		return BattleAction.item(enemy, heal_item, [enemy])
	
	# Try to heal with skill
	var heal_skill = _find_healing_skill()
	if heal_skill and _can_afford_skill(heal_skill):
		print("EnemyAI: Desperate heal skill!")
		return BattleAction.skill(enemy, heal_skill, [enemy])
	
	# Last resort: ALL-OUT ATTACK
	print("EnemyAI: Final desperate attack!")
	var strongest_skill = _find_strongest_available_skill()
	if strongest_skill:
		return BattleAction.skill(enemy, strongest_skill, [player])
	
	return BattleAction.attack(enemy, player)

# =============================================
# SMART ITEM USAGE
# =============================================

func _try_use_item_smart() -> BattleAction:
	"""Intelligent item usage based on situation"""
	var enemy_hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
	var enemy_mp_percent = float(enemy.current_mp) / float(enemy.max_mp) if enemy.max_mp > 0 else 1.0
	var enemy_sp_percent = float(enemy.current_sp) / float(enemy.max_sp) if enemy.max_sp > 0 else 1.0
	
	# Healing items (only if actually hurt)
	if enemy_hp_percent < 0.7:
		var heal_item = _find_healing_item()
		if heal_item:
			print("EnemyAI: Using heal item (HP: %.0f%%)" % (enemy_hp_percent * 100))
			return BattleAction.item(enemy, heal_item, [enemy])
	
	# Resource restore items (only if low)
	if enemy_mp_percent < 0.3 or enemy_sp_percent < 0.3:
		var restore_item = _find_restore_item()
		if restore_item:
			print("EnemyAI: Using restore item")
			return BattleAction.item(enemy, restore_item, [enemy])
	
	# Buff items (if not already buffed)
	if not enemy.buff_manager.has_buffs():
		var buff_item = _find_buff_item()
		if buff_item:
			print("EnemyAI: Using buff item")
			return BattleAction.item(enemy, buff_item, [enemy])
	
	# Damage/debuff items (if player not debuffed)
	if not player.buff_manager.has_debuffs():
		var damage_item = _find_damage_item()
		if damage_item:
			print("EnemyAI: Using damage/debuff item")
			return BattleAction.item(enemy, damage_item, [player])
	
	return null

# =============================================
# BUFF/DEBUFF PRIORITY
# =============================================

func _try_buff_or_debuff() -> BattleAction:
	"""Apply buffs/debuffs strategically"""
	
	# Prioritize debuffing player if they're strong
	if not player.buff_manager.has_debuffs() and randf() < 0.6:
		var debuff_skill = _find_debuff_skill()
		if debuff_skill and _can_afford_skill(debuff_skill):
			print("EnemyAI: Applying debuff to player")
			return BattleAction.skill(enemy, debuff_skill, [player])
	
	# Buff self if not buffed
	if not enemy.buff_manager.has_buffs():
		var buff_skill = _find_buff_skill()
		if buff_skill and _can_afford_skill(buff_skill):
			print("EnemyAI: Buffing self")
			return BattleAction.skill(enemy, buff_skill, [enemy])
	
	return null

# =============================================
# DEFENSIVE ACTIONS (Not Desperate)
# =============================================

func _decide_defensive_action() -> BattleAction:
	"""Handle moderate HP situations"""
	var enemy_hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
	
	# Don't defend if already defending
	if enemy.is_defending:
		# Check if safe to go offensive
		if player.current_hp < enemy.current_hp * 1.5:
			var damage_skill = _try_use_damage_skill()
			if damage_skill:
				return damage_skill
		return BattleAction.attack(enemy, player)
	
	# Try to heal
	var heal_skill = _find_healing_skill()
	if heal_skill and _can_afford_skill(heal_skill) and enemy_hp_percent < 0.6:
		print("EnemyAI: Using heal skill (HP: %.0f%%)" % (enemy_hp_percent * 100))
		return BattleAction.skill(enemy, heal_skill, [enemy])
	
	# Defend only if very low and no healing available
	if enemy_hp_percent < 0.35:
		print("EnemyAI: Defending (HP: %.0f%%)" % (enemy_hp_percent * 100))
		return BattleAction.defend(enemy)
	
	return null

# =============================================
# OFFENSIVE SKILLS
# =============================================

func _try_use_damage_skill() -> BattleAction:
	"""Try to use best available damage skill"""
	var available_skills = _get_damage_skills()
	
	if available_skills.is_empty():
		return null
	
	# Sort by power (descending)
	available_skills.sort_custom(func(a, b): return a.power > b.power)
	
	# Pick best affordable skill
	for skill in available_skills:
		if _can_afford_skill(skill):
			print("EnemyAI: Using damage skill: %s" % skill.name)
			return BattleAction.skill(enemy, skill, [player])
	
	return null

# =============================================
# HELPER FUNCTIONS
# =============================================

func _can_afford_skill(skill: Skill) -> bool:
	"""Check if enemy can afford to use this skill"""
	if skill.ability_type == Skill.AbilityType.PHYSICAL:
		return enemy.current_sp >= skill.sp_cost
	else:
		return enemy.current_mp >= skill.mp_cost

func _find_best_damage_skill() -> Skill:
	"""Find highest damage skill regardless of cost"""
	var damage_skills = _get_damage_skills()
	if damage_skills.is_empty():
		return null
	
	damage_skills.sort_custom(func(a, b): return a.power > b.power)
	return damage_skills[0]

func _find_strongest_available_skill() -> Skill:
	"""Find strongest skill enemy can currently afford"""
	var available = _get_damage_skills()
	available = available.filter(func(s): return _can_afford_skill(s))
	
	if available.is_empty():
		return null
	
	available.sort_custom(func(a, b): return a.power > b.power)
	return available[0]

func _get_damage_skills() -> Array[Skill]:
	"""Get all damage-dealing skills"""
	var result: Array[Skill] = []
	
	for skill_name in enemy.skills:
		var skill = SkillManager.get_skill(skill_name)
		if not skill or enemy.get_skill_cooldown(skill_name) > 0:
			continue
		
		if skill.type == Skill.SkillType.DAMAGE:
			result.append(skill)
	
	return result

func _find_healing_skill() -> Skill:
	"""Find healing skill"""
	for skill_name in enemy.skills:
		var skill = SkillManager.get_skill(skill_name)
		if not skill or enemy.get_skill_cooldown(skill_name) > 0:
			continue
		
		if skill.type == Skill.SkillType.HEAL:
			return skill
	
	return null

func _find_buff_skill() -> Skill:
	"""Find buff skill"""
	for skill_name in enemy.skills:
		var skill = SkillManager.get_skill(skill_name)
		if not skill or enemy.get_skill_cooldown(skill_name) > 0:
			continue
		
		if skill.type == Skill.SkillType.BUFF:
			return skill
	
	return null

func _find_debuff_skill() -> Skill:
	"""Find debuff skill"""
	for skill_name in enemy.skills:
		var skill = SkillManager.get_skill(skill_name)
		if not skill or enemy.get_skill_cooldown(skill_name) > 0:
			continue
		
		if skill.type in [Skill.SkillType.DEBUFF, Skill.SkillType.INFLICT_STATUS]:
			return skill
	
	return null

# === ITEM FINDERS ===

func _find_healing_item() -> Item:
	"""Find healing item (checks quantity and inventory existence)"""
	# NEW: Check if inventory exists and has items
	if not enemy.inventory or enemy.inventory.items.is_empty():
		return null
	
	for item_id in enemy.inventory.items:
		var item_data = enemy.inventory.items[item_id]
		var item = item_data.item
		
		# Check if we actually have quantity
		if item and item.item_type == Item.ItemType.CONSUMABLE and item_data.quantity > 0:
			if item.consumable_type == Item.ConsumableType.HEAL:
				return item
	return null

func _find_restore_item() -> Item:
	"""Find MP/SP restore item"""
	# NEW: Check if inventory exists and has items
	if not enemy.inventory or enemy.inventory.items.is_empty():
		return null
	
	for item_id in enemy.inventory.items:
		var item_data = enemy.inventory.items[item_id]
		var item = item_data.item
		if item and item.item_type == Item.ItemType.CONSUMABLE and item_data.quantity > 0:
			if item.consumable_type == Item.ConsumableType.RESTORE:
				return item
	return null

func _find_buff_item() -> Item:
	"""Find buff item"""
	# NEW: Check if inventory exists and has items
	if not enemy.inventory or enemy.inventory.items.is_empty():
		return null
	
	for item_id in enemy.inventory.items:
		var item_data = enemy.inventory.items[item_id]
		var item = item_data.item
		if item and item.item_type == Item.ItemType.CONSUMABLE and item_data.quantity > 0:
			if item.consumable_type == Item.ConsumableType.BUFF:
				return item
	return null

func _find_damage_item() -> Item:
	"""Find damage/debuff item"""
	# NEW: Check if inventory exists and has items
	if not enemy.inventory or enemy.inventory.items.is_empty():
		return null
	
	for item_id in enemy.inventory.items:
		var item_data = enemy.inventory.items[item_id]
		var item = item_data.item
		if item and item.item_type == Item.ItemType.CONSUMABLE and item_data.quantity > 0:
			if item.consumable_type in [Item.ConsumableType.DAMAGE, Item.ConsumableType.DEBUFF]:
				return item
	return null

func _get_item_targets(item: Item) -> Array:
	"""Get correct targets for an item"""
	match item.consumable_type:
		Item.ConsumableType.DAMAGE, Item.ConsumableType.DEBUFF:
			return [player]
		_:
			return [enemy]
