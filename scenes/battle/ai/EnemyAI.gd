# res://scenes/battle/ai/EnemyAI.gd
# Decision-making for a regular enemy: given the current state, pick a BattleAction.
# Priority: desperation -> items -> defensive -> buffs/debuffs -> damage skills -> attack.
# Owned by EnemyTurnPlanner (one instance per enemy).

class_name EnemyAI
extends RefCounted

var enemy: CharacterData
## The hero this enemy is acting against THIS decision (re-chosen every turn)
var target: CharacterData
## Where the living heroes come from: a Callable returning an Array, or a fixed
## Array / single CharacterData. Lets the AI work unchanged with a 1-3 hero party.
var _heroes_source: Variant
var current_floor: int = 1

# AI personality traits (can be randomized per enemy)
var aggression: float = 0.5  # 0.0 = defensive, 1.0 = aggressive
var intelligence: float = 0.5  # 0.0 = random, 1.0 = optimal
var desperation_threshold: float = 0.25  # HP% when desperation kicks in
## Archetype AI role tuning (EnemyArchetypes.role): skill_chance, consider_buffs,
## debuff_chance, combo_bias, defend_below, heal_ally_below
var role: Dictionary = EnemyArchetypes.DEFAULT_ROLE.duplicate()
## Living allies (this enemy's side): Callable returning an Array, or null
var _allies_source: Variant = null

func initialize(p_enemy: CharacterData, p_heroes: Variant, floor: int):
	enemy = p_enemy
	_heroes_source = p_heroes
	current_floor = floor
	
	# Randomize personality traits for variety
	aggression = randf_range(0.3, 0.8)
	intelligence = randf_range(0.4, 0.9)
	desperation_threshold = randf_range(0.2, 0.35)
	role = EnemyArchetypes.role(String(enemy.get_meta("ai_role", "")))
	
	print("EnemyAI: Initialized for %s (Aggression: %.2f, Intelligence: %.2f)" % [
		enemy.name, aggression, intelligence
	])
	
## Entry point: pick which hero to act against, then decide what to do.
func decide_action() -> BattleAction:
	target = choose_target()
	if target == null:
		return null
	return _decide()

func set_allies_source(source: Variant) -> void:
	_allies_source = source

func get_living_allies() -> Array:
	var allies: Array = []
	if _allies_source is Callable:
		allies = _allies_source.call()
	elif _allies_source is Array:
		allies = _allies_source
	if allies.is_empty():
		allies = [enemy]
	return allies.filter(func(a): return a != null and a.is_alive())

func get_living_heroes() -> Array:
	var heroes: Array = []
	if _heroes_source is Callable:
		heroes = _heroes_source.call()
	elif _heroes_source is Array:
		heroes = _heroes_source
	elif _heroes_source is CharacterData:
		heroes = [_heroes_source]
	return heroes.filter(func(h): return h != null and h.is_alive())

## Smarter enemies focus the most wounded hero; the rest pick at random.
func choose_target() -> CharacterData:
	var heroes = get_living_heroes()
	if heroes.is_empty():
		return null
	if heroes.size() == 1:
		return heroes[0]
	if RandomManager.randf() < intelligence:
		heroes.sort_custom(func(a, b): return float(a.current_hp) / a.max_hp < float(b.current_hp) / b.max_hp)
		return heroes[0]
	return heroes[RandomManager.randi() % heroes.size()]

## Decision logic against `target` (BossAI overrides this).
func _decide() -> BattleAction:
	"""Priority system"""
	var enemy_hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
	var target_hp_percent = float(target.current_hp) / float(target.max_hp)
	var momentum_level = MomentumSystem.get_momentum()
	
	# === DESPERATION MODE (Low HP - Last Stand) ===
	if enemy_hp_percent < desperation_threshold:
		var desperate_action = _decide_desperate_action()
		if desperate_action:
			return desperate_action
	
	# === SUPPORT: healers mend a wounded ally first ===
	if float(role.heal_ally_below) > 0.0:
		var support_action = _try_heal_ally()
		if support_action:
			return support_action
	
	# === COMBO OPPORTUNITY (target has a set-up status we can pay off) ===
	# Smarter enemies spot it more often (players = enemies: same combos as heroes).
	if RandomManager.randf() < 0.3 + intelligence * 0.6 + float(role.combo_bias):
		var combo_action = _try_combo()
		if combo_action:
			return combo_action
	
	# === ITEM USAGE (Proactive) ===
	var item_chance = 0.1 + (current_floor * 0.02) + (momentum_level * 0.05)
	if RandomManager.randf() < item_chance:
		var item_action = _try_use_item_smart()
		if item_action:
			return item_action
	
	# === LOW HP - DEFENSIVE/HEAL (Not desperate yet) ===
	if enemy_hp_percent < 0.5 and enemy_hp_percent >= desperation_threshold:
		var defensive_action = _decide_defensive_action()
		if defensive_action:
			return defensive_action
	
	# === BUFF/DEBUFF PRIORITY (If unbuffed/target unbuffed) ===
	if RandomManager.randf() < float(role.consider_buffs):
		var buff_action = _try_buff_or_debuff()
		if buff_action:
			return buff_action
	
	# === OFFENSIVE SKILLS (Primary damage dealer) ===
	if RandomManager.randf() < float(role.skill_chance):
		var skill_action = _try_use_damage_skill()
		if skill_action:
			return skill_action
	
	# === FALLBACK: Basic Attack ===
	return BattleAction.attack(enemy, target)

# =============================================
# DESPERATION MODE (Low HP - All-or-Nothing)
# =============================================

func _decide_desperate_action() -> BattleAction:
	"""When enemy is very low HP, go all-out or setup for final strike"""
	print("EnemyAI: DESPERATION MODE activated!")
	
	# Check target resources to assess threat
	var player_mp_percent = float(target.current_mp) / float(target.max_mp) if target.max_mp > 0 else 0.0
	var player_sp_percent = float(target.current_sp) / float(target.max_sp) if target.max_sp > 0 else 0.0
	
	# If target is low on resources, go for the kill
	if player_mp_percent < 0.3 and player_sp_percent < 0.3:
		print("EnemyAI: Player low on resources - FULL AGGRO!")
		# Must be affordable - an unaffordable skill fails and wastes the turn
		var best_damage_skill = _find_strongest_available_skill()
		if best_damage_skill:
			return BattleAction.skill(enemy, best_damage_skill, [target])
		return BattleAction.attack(enemy, target)
	
	# If target has resources, try to survive ONE more turn
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
		return BattleAction.skill(enemy, strongest_skill, [target])
	
	return BattleAction.attack(enemy, target)

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
	
	# Damage/debuff items (if target not debuffed)
	if not target.buff_manager.has_debuffs():
		var damage_item = _find_damage_item()
		if damage_item:
			print("EnemyAI: Using damage/debuff item")
			return BattleAction.item(enemy, damage_item, [target])
	
	return null

# =============================================
# BUFF/DEBUFF PRIORITY
# =============================================

func _try_buff_or_debuff() -> BattleAction:
	"""Apply buffs/debuffs strategically"""
	
	# Prioritize debuffing target if they're strong
	if not target.buff_manager.has_debuffs() and RandomManager.randf() < float(role.debuff_chance):
		var debuff_skill = _find_debuff_skill()
		if debuff_skill and _can_afford_skill(debuff_skill):
			print("EnemyAI: Applying debuff to player")
			return BattleAction.skill(enemy, debuff_skill, [target])
	
	#  FIX: Buff allies based on skill target type
	if not enemy.buff_manager.has_buffs():
		var buff_skill = _find_buff_skill()
		if buff_skill and _can_afford_skill(buff_skill):
			#  Check if skill targets ALL_ALLIES
			if buff_skill.target == Skill.TargetType.ALL_ALLIES:
				print("EnemyAI: Buffing all allies with %s" % buff_skill.name)
				# Pass empty array - CombatEngine will resolve via get_allies_for_character()
				return BattleAction.skill(enemy, buff_skill, [])
			else:
				print("EnemyAI: Buffing self with %s" % buff_skill.name)
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
		if target.current_hp < enemy.current_hp * 1.5:
			var damage_skill = _try_use_damage_skill()
			if damage_skill:
				return damage_skill
		return BattleAction.attack(enemy, target)
	
	# Try to heal
	var heal_skill = _find_healing_skill()
	if heal_skill and _can_afford_skill(heal_skill) and enemy_hp_percent < 0.6:
		print("EnemyAI: Using heal skill (HP: %.0f%%)" % (enemy_hp_percent * 100))
		return BattleAction.skill(enemy, heal_skill, [enemy])
	
	# Defend only if very low and no healing available
	if enemy_hp_percent < float(role.defend_below):
		print("EnemyAI: Defending (HP: %.0f%%)" % (enemy_hp_percent * 100))
		return BattleAction.defend(enemy)
	
	return null

# =============================================
# SUPPORT (healer role)
# =============================================

## Heal the most wounded ally under heal_ally_below, if a heal is ready.
func _try_heal_ally() -> BattleAction:
	var allies = get_living_allies()
	allies.sort_custom(func(a, b): return float(a.current_hp) / a.max_hp < float(b.current_hp) / b.max_hp)
	var hurt: CharacterData = allies[0] if not allies.is_empty() else null
	if hurt == null or float(hurt.current_hp) / hurt.max_hp >= float(role.heal_ally_below):
		return null
	var heal_skill = _find_healing_skill()
	if heal_skill == null or not _can_afford_skill(heal_skill):
		return null
	match heal_skill.target:
		Skill.TargetType.ALL_ALLIES:
			return BattleAction.skill(enemy, heal_skill, [])
		Skill.TargetType.SELF:
			return BattleAction.skill(enemy, heal_skill, [enemy]) if hurt == enemy else null
		_:
			print("EnemyAI: Healing %s with %s" % [hurt.name, heal_skill.name])
			return BattleAction.skill(enemy, heal_skill, [hurt])

# =============================================
# OFFENSIVE SKILLS
# =============================================

func _try_use_damage_skill() -> BattleAction:
	"""Try to use best available damage skill"""
	var available_skills = _get_damage_skills()
	
	if available_skills.is_empty():
		return null
	
	# Sort by power (descending), counting a combo's bonus against the target
	available_skills.sort_custom(func(a, b): return _effective_power(a) > _effective_power(b))
	
	# Pick best affordable skill
	for skill in available_skills:
		if _can_afford_skill(skill):
			print("EnemyAI: Using damage skill: %s" % skill.name)
			return BattleAction.skill(enemy, skill, [target])
	
	return null

## Use a skill (or a basic attack) that triggers a combo on the target, if any.
func _try_combo() -> BattleAction:
	var best: Skill = null
	var best_mult := 1.0
	for skill_name in enemy.skills:
		var skill = enemy.get_skill_instance(skill_name)
		if not skill or enemy.get_skill_cooldown(skill_name) > 0 or not _can_afford_skill(skill):
			continue
		if skill.type == Skill.SkillType.DRAIN and skill.drain_source != Skill.DrainTarget.HP:
			continue
		var combo = Combos.preview(enemy, skill, target)
		if not combo.is_empty() and combo.multiplier > best_mult:
			best = skill
			best_mult = combo.multiplier
	if best:
		print("EnemyAI: Combo with %s" % best.name)
		return BattleAction.skill(enemy, best, [target])   # same as other damage skills; the engine expands AoE
	if not Combos.find(target, Combos.hit_from_attack(enemy)).is_empty():
		return BattleAction.attack(enemy, target)
	return null

func _effective_power(skill: Skill) -> float:
	var combo = Combos.preview(enemy, skill, target)
	return skill.power * (combo.multiplier if not combo.is_empty() else 1.0)

# =============================================
# HELPER FUNCTIONS
# =============================================

func _can_afford_skill(skill: Skill) -> bool:
	"""Check if enemy can afford to use this skill"""
	return skill.can_afford(enemy)

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
		var skill = enemy.get_skill_instance(skill_name)  # enemy's own (leveled) copy, not the global template
		if not skill or enemy.get_skill_cooldown(skill_name) > 0:
			continue
		
		if skill.type == Skill.SkillType.DAMAGE:
			result.append(skill)
	
	return result

func _find_healing_skill() -> Skill:
	"""Find healing skill"""
	for skill_name in enemy.skills:
		var skill = enemy.get_skill_instance(skill_name)  # enemy's own (leveled) copy, not the global template
		if not skill or enemy.get_skill_cooldown(skill_name) > 0:
			continue
		
		if skill.type == Skill.SkillType.HEAL:
			return skill
	
	return null

func _find_buff_skill() -> Skill:
	"""Find buff skill"""
	for skill_name in enemy.skills:
		var skill = enemy.get_skill_instance(skill_name)  # enemy's own (leveled) copy, not the global template
		if not skill or enemy.get_skill_cooldown(skill_name) > 0:
			continue
		
		if skill.type == Skill.SkillType.BUFF:
			return skill
	
	return null

func _find_debuff_skill() -> Skill:
	"""Find debuff skill"""
	for skill_name in enemy.skills:
		var skill = enemy.get_skill_instance(skill_name)  # enemy's own (leveled) copy, not the global template
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
			return [target]
		_:
			return [enemy]
