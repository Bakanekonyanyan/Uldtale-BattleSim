# CombatEngine.gd - COMPLETE MULTI-ENEMY SUPPORT
#  VERIFIED: Handles both single enemy and multi-enemy battles
#  ENHANCED: Added utility methods for multi-enemy management

class_name CombatEngine
extends RefCounted

var player: CharacterData
var enemy: CharacterData  # Legacy: first enemy in list
var enemies: Array[CharacterData] = []

func initialize(p_player: CharacterData, single_enemy: CharacterData):
	"""Legacy single-enemy initialization"""
	player = p_player
	enemy = single_enemy
	enemies = [single_enemy]
	print("CombatEngine: Initialized (legacy) - Player: %s vs Enemy: %s" % [player.name, single_enemy.name])

func initialize_multi(p_player: CharacterData, p_enemies: Array[CharacterData]):
	"""Multi-enemy initialization"""
	player = p_player
	enemies = p_enemies
	enemy = enemies[0] if not enemies.is_empty() else null  # Set first as legacy reference
	print("CombatEngine: Initialized - Player: %s vs %d enemies" % [player.name, enemies.size()])

func execute_action(action: BattleAction) -> ActionResult:
	"""Main entry point for all combat actions"""
	if not action.is_valid():
		return ActionResult.failure_msg("Invalid action")
	
	print("CombatEngine: Executing %s" % action.get_description())
	
	var confusion_result = _check_confusion_before_action(action)
	if confusion_result:
		return confusion_result
	
	match action.type:
		BattleAction.ActionType.ATTACK:
			return _execute_attack(action)
		BattleAction.ActionType.DEFEND:
			return _execute_defend(action)
		BattleAction.ActionType.SKILL:
			return _execute_skill(action)
		BattleAction.ActionType.ITEM:
			return _execute_item(action)
		BattleAction.ActionType.VIEW_EQUIPMENT:
			return ActionResult.success_msg("Viewing equipment")
	
	return ActionResult.failure_msg("Unknown action type")

func _check_confusion_before_action(action: BattleAction) -> ActionResult:
	var actor = action.actor
	
	if action.type != BattleAction.ActionType.ATTACK and action.type != BattleAction.ActionType.DEFEND:
		return null
	
	if not actor.status_manager:
		return null
	
	var confusion_check = actor.status_manager.check_confusion_self_harm()
	
	if confusion_check.success:
		var result = ActionResult.new()
		result.success = true
		result.damage = confusion_check.damage
		result.message = confusion_check.message
		return result
	
	return null

# === ATTACK ===

func _execute_attack(action: BattleAction) -> ActionResult:
	var attacker = action.actor
	var target = action.target
	
	if not is_alive(target):
		return ActionResult.failure_msg("%s is already defeated" % target.name)
	
	var prof_level_up_msg = ""
	if attacker.equipment.has("main_hand") and attacker.equipment["main_hand"]:
		var weapon = attacker.equipment["main_hand"]
		
		if weapon is Equipment and attacker.proficiency_manager:
			if weapon.key == "" or weapon.key == null:
				weapon.key = EquipmentKeyHelper.get_equipment_key(weapon)
			
			if weapon.key != "" and weapon.key != null:
				prof_level_up_msg = attacker.proficiency_manager.use_weapon(weapon.key)
	
	var momentum_mult = MomentumSystem.get_damage_multiplier()
	var base_damage = attacker.get_attack_power() * 0.5 * momentum_mult
	var resistance = target.get_defense()
	
	if RandomManager.randf() >= attacker.accuracy:
		return ActionResult.missed_attack(attacker, target)
	
	if RandomManager.randf() < target.dodge:
		return ActionResult.dodged_attack(attacker, target)
	
	var is_crit = RandomManager.randf() < attacker.critical_hit_rate
	
	# NEW: Percentage-based damage reduction formula
	# Formula: damage = base_damage * (100 / (100 + resistance * 0.5))
	# Examples:
	#   0 def   = 100% damage
	#   50 def  = 80% damage  (100/(100+25))
	#   100 def = 66% damage  (100/(100+50))
	#   200 def = 50% damage  (100/(100+100))
	var damage_multiplier = 100.0 / (100.0 + (resistance * 0.5))
	var damage = base_damage * damage_multiplier
	
	# Ensure minimum damage (1% of base, min 1)
	var min_damage = max(1, base_damage * 0.01)
	damage = max(min_damage, damage)
	
	if is_crit:
		damage *= 1.5 + RandomManager.randf() * 0.5
	
	damage = round(damage)
	
	print("[COMBAT] Attack: base=%.1f, def=%d, mult=%.2f%%, final=%d" % [
		base_damage, resistance, damage_multiplier * 100, damage
	])
	
	# Track reflection BEFORE applying damage
	var reflection_info = _track_reflection_damage(attacker, target, damage)
	
	target.take_damage(damage, attacker)
	
	var status_msg = ""
	if attacker.equipment["main_hand"] and attacker.equipment["main_hand"] is Equipment:
		var weapon = attacker.equipment["main_hand"]
		if "status_effect_type" in weapon and "status_effect_chance" in weapon:
			if weapon.status_effect_type != Skill.StatusEffect.NONE:
				if weapon.has_method("try_apply_status_effect"):
					if weapon.try_apply_status_effect(target):
						status_msg = " and applied %s" % Skill.StatusEffect.keys()[weapon.status_effect_type]
	
	var mp_restore = int(attacker.max_mp * 0.08)
	var sp_restore = int(attacker.max_sp * 0.08)
	attacker.restore_mp(mp_restore)
	attacker.restore_sp(sp_restore)
	
	var result = ActionResult.attack_result(attacker, target, int(damage), is_crit)
	result.message += " and restores %d MP, %d SP%s" % [mp_restore, sp_restore, status_msg]
	
	# Add reflection info to result
	if reflection_info.reflected:
		result.message += "\n[color=cyan]%s's barrier reflects %d damage (%.0f%%) back to %s![/color]" % [
			target.name,
			reflection_info.amount,
			reflection_info.percent,
			reflection_info.target_name
		]
	
	if prof_level_up_msg != "":
		result.level_up_message = prof_level_up_msg
	
	return result

# === DEFEND ===

func _execute_defend(action: BattleAction) -> ActionResult:
	var defender = action.actor
	
	if not is_alive(defender):
		return ActionResult.failure_msg("%s cannot defend while defeated" % defender.name)
	
	defender.defend()
	return ActionResult.defend_result(defender)

# === SKILL ===

func _execute_skill(action: BattleAction) -> ActionResult:
	var caster = action.actor
	var skill = action.skill_data
	var targets = action.targets
	
	if not is_alive(caster):
		return ActionResult.failure_msg("%s cannot cast while defeated" % caster.name)
	
	var cost_type = "MP" if skill.ability_type != Skill.AbilityType.PHYSICAL else "SP"
	var cost = skill.mp_cost if cost_type == "MP" else skill.sp_cost
	var current = caster.current_mp if cost_type == "MP" else caster.current_sp
	
	if current < cost:
		return ActionResult.failure_msg("Not enough %s" % cost_type)
	
	if cost_type == "MP":
		caster.current_mp -= cost
	else:
		caster.current_sp -= cost
	
	#  CRITICAL FIX: Resolve empty targets for ALL_ALLIES skills
	if targets.is_empty() and skill.target == Skill.TargetType.ALL_ALLIES:
		targets = get_allies_for_character(caster)
		print("[COMBAT ENGINE] Resolved ALL_ALLIES targets: %d allies for %s" % [targets.size(), caster.name])
	
	# Execute skill and get result
	var skill_result = skill.use(caster, targets)
	var level_up_msg = caster.use_skill(skill.name)
	caster.use_skill_cooldown(skill.name, skill.cooldown)
	
	# Create ActionResult with direct values
	var result = ActionResult.new()
	result.success = true
	result.message = skill_result.message
	result.level_up_message = level_up_msg
	result.sp_cost = skill.sp_cost
	result.mp_cost = skill.mp_cost
	
	result.damage = skill_result.get("damage", 0)
	result.healing = skill_result.get("healing", 0)
	result.mp_gain = skill_result.get("mp_restored", 0)
	result.sp_gain = skill_result.get("sp_restored", 0)
	
	# Extract status effects from skill data
	if not skill.status_effects.is_empty():
		for effect_enum in skill.status_effects:
			if effect_enum != Skill.StatusEffect.NONE:
				result.status_effects.append({
					"name": Skill.StatusEffect.keys()[effect_enum],
					"duration": skill.duration
				})
	
	# Extract buffs/debuffs from skill data
	if not skill.attribute_targets.is_empty():
		for attr_enum in skill.attribute_targets:
			if attr_enum != Skill.AttributeTarget.NONE:
				var effect_data = {
					"stat": Skill.AttributeTarget.keys()[attr_enum],
					"amount": skill.power,
					"duration": skill.duration
				}
				
				if skill.type == Skill.SkillType.BUFF:
					result.buffs.append(effect_data)
				elif skill.type == Skill.SkillType.DEBUFF:
					effect_data["is_debuff"] = true
					result.debuffs.append(effect_data)
	
	print("[COMBAT ENGINE] Skill result - damage=%d, healing=%d, mp=%d, sp=%d" % [
		result.damage, result.healing, result.mp_gain, result.sp_gain
	])
	
	return result

# === ITEM ===

func _execute_item(action: BattleAction) -> ActionResult:
	""" CRITICAL FIX: Track HP changes BEFORE and AFTER item use"""
	var user = action.actor
	var item = action.item_data
	var targets = action.targets
	
	if not is_alive(user):
		return ActionResult.failure_msg("%s cannot use items while defeated" % user.name)
	
	print("[ITEM] %s using %s on %d target(s)" % [user.name, item.display_name, targets.size()])
	
	# Track ALL targets' HP BEFORE item use
	var targets_before = {}
	for t in targets:
		targets_before[t.get_instance_id()] = {
			"hp": t.current_hp,
			"mp": t.current_mp,
			"sp": t.current_sp,
			"name": t.name
		}
		print("[ITEM] Target %s BEFORE: HP=%d/%d" % [t.name, t.current_hp, t.max_hp])
	
	# Execute item (this modifies HP directly)
	var item_msg = item.use(user, targets)
	print("[ITEM] Item message: %s" % item_msg)
	
	# Calculate ACTUAL changes by comparing before/after
	var total_damage = 0
	var total_healing = 0
	var total_mp_restore = 0
	var total_sp_restore = 0
	
	for t in targets:
		var before = targets_before[t.get_instance_id()]
		var hp_change = t.current_hp - before.hp
		var mp_change = t.current_mp - before.mp
		var sp_change = t.current_sp - before.sp
		
		print("[ITEM] Target %s AFTER: HP=%d/%d (change: %+d)" % [
			t.name, t.current_hp, t.max_hp, hp_change
		])
		
		if hp_change < 0:
			total_damage += abs(hp_change)
			print("[ITEM]  %s took %d damage" % [t.name, abs(hp_change)])
		elif hp_change > 0:
			total_healing += hp_change
			print("[ITEM]  %s healed %d HP" % [t.name, hp_change])
		
		if mp_change > 0:
			total_mp_restore += mp_change
		if sp_change > 0:
			total_sp_restore += sp_change
	
	var item_id = item.id
	
	# For Equipment (unique items with inventory_key)
	if item is Equipment and item.inventory_key != "":
		item_id = item.inventory_key
	
	if user.inventory.items.has(item_id):
		user.inventory.remove_item(item_id, 1)
		print("[ITEM] Removed 1x %s from %s's inventory" % [item.display_name, user.name])
	else:
		print("[ITEM] WARNING: Item '%s' not found in %s's inventory!" % [item_id, user.name])
	
	# Create result with ACTUAL measured values
	var result = ActionResult.item_result(user, item, targets, item_msg)
	
	# Override parsed values with actual measured values
	result.damage = total_damage
	result.healing = total_healing
	result.mp_gain = total_mp_restore
	result.sp_gain = total_sp_restore
	
	print("[ITEM RESULT] Final - damage=%d, healing=%d, mp=%d, sp=%d" % [
		result.damage, result.healing, result.mp_gain, result.sp_gain
	])
	
	return result

# === STATUS EFFECTS ===

func process_status_effects(character: CharacterData) -> ActionResult:
	"""CRITICAL FIX: Accurately track HP/MP/SP changes from status effects"""
	
	# ADD THIS CHECK AT THE VERY START
	if not is_alive(character):
		print("[STATUS] Skipping status effects for %s (already dead)" % character.name)
		return ActionResult.success_msg("")
	
	print("[STATUS] Processing effects for %s (HP: %d/%d, Status: %s)" % [
		character.name, 
		character.current_hp, 
		character.max_hp,
		character.status_manager.get_effects_string() if character.status_manager else "None"
	])
	
	# Reduce cooldowns first
	character.reduce_cooldowns()
	
	# Capture state BEFORE processing
	var hp_before = character.current_hp
	var mp_before = character.current_mp
	var sp_before = character.current_sp
	
	print("[STATUS] BEFORE - HP: %d, MP: %d, SP: %d" % [hp_before, mp_before, sp_before])
	
	# Call update_status_effects ONCE
	var message = character.update_status_effects()
	
	# Capture state AFTER processing
	var hp_after = character.current_hp
	var mp_after = character.current_mp
	var sp_after = character.current_sp
	
	print("[STATUS] AFTER - HP: %d, MP: %d, SP: %d" % [hp_after, mp_after, sp_after])
	
	# Calculate changes
	var hp_change = hp_after - hp_before
	var mp_change = mp_after - mp_before
	var sp_change = sp_after - sp_before
	
	var damage = 0
	var healing = 0
	
	if hp_change < 0:
		damage = abs(hp_change)
		print("[STATUS]  %s took %d damage from status effects" % [character.name, damage])
	elif hp_change > 0:
		healing = hp_change
		print("[STATUS]  %s healed %d HP from status effects (REGENERATION)" % [character.name, healing])
	
	print("[COMBAT ENGINE] Status effects - HP: %d -> %d (dmg: %d, heal: %d)" % [
		hp_before, hp_after, damage, healing
	])
	
	return ActionResult.status_effect_result(character, damage, healing, message)

# === BATTLE STATE ===

func is_alive(character: CharacterData) -> bool:
	""" Check if character is alive"""
	return character and character.current_hp > 0

func check_battle_end() -> String:
	var any_enemy_alive = false
	for e in enemies:
		if is_alive(e):
			any_enemy_alive = true
			break
	
	var player_alive = is_alive(player)
	
	# ✅ CRITICAL: Player death takes priority over victory
	# This handles simultaneous death (reflection, etc.)
	if not player_alive:
		return "defeat"
	
	# Only return victory if player is alive AND enemies are dead
	if not any_enemy_alive:
		return "victory"
	
	return "ongoing"

func get_living_enemies() -> Array[CharacterData]:
	""" NEW: Get all living enemies"""
	var living: Array[CharacterData] = []
	for e in enemies:
		if is_alive(e):
			living.append(e)
	return living

func get_enemy_count() -> int:
	""" NEW: Get total enemy count"""
	return enemies.size()

func get_living_enemy_count() -> int:
	""" NEW: Get count of living enemies"""
	return get_living_enemies().size()

func get_allies_for_character(character: CharacterData) -> Array[CharacterData]:
	"""Get all living allies for a character (including self)"""
	var allies: Array[CharacterData] = []
	
	if character == player:
		# Player only has self as ally (single character for now)
		# FUTURE: When party system added, return all living party members here
		allies.append(player)
	else:
		# Enemy: all living enemies are allies to each other
		for e in enemies:
			if is_alive(e):
				allies.append(e)
	
	print("[ALLIES] Found %d allies for %s" % [allies.size(), character.name])
	return allies

func get_skill_targets(skill: Skill, caster: CharacterData, opponent: CharacterData) -> Array[CharacterData]:
	""" Get appropriate targets for skill (supports multi-enemy + ALL_ALLIES)"""
	var result: Array[CharacterData] = []
	
	match skill.target:
		Skill.TargetType.SELF:
			result.append(caster)
		Skill.TargetType.ALLY:
			result.append(caster)
		Skill.TargetType.ALL_ALLIES:
			#  FIX: Resolve all allies for caster (enemies buff each other)
			result = get_allies_for_character(caster)
			print("[SKILL TARGETS] ALL_ALLIES for %s: %d targets" % [caster.name, result.size()])
		Skill.TargetType.ENEMY:
			if opponent:
				result.append(opponent)
		Skill.TargetType.ALL_ENEMIES:
			# Return all living enemies for AOE skills
			result = get_living_enemies()
			print("[SKILL TARGETS] ALL_ENEMIES: %d targets" % result.size())
	
	return result

# === REFLECTION TRACKING ===

func _track_reflection_damage(attacker: CharacterData, defender: CharacterData, damage: float) -> Dictionary:
	"""
	Track reflection damage and return info for logging
	Returns: {reflected: bool, amount: int, percent: float, target_name: String}
	"""
	var result = {
		"reflected": false,
		"amount": 0,
		"percent": 0.0,
		"target_name": ""
	}
	
	if not defender.status_manager:
		return result
	
	var reflection = defender.status_manager.get_total_reflection()
	
	if reflection > 0.0:
		var reflected_damage = int(damage * reflection)
		
		if reflected_damage > 0:
			result.reflected = true
			result.amount = reflected_damage
			result.percent = reflection * 100
			result.target_name = attacker.name
			
			# Apply reflected damage (pass null to prevent reflection chain)
			attacker.take_damage(reflected_damage, null)
	
	return result

# === DEATH CHECKING ===

func check_death_after_action(character: CharacterData) -> bool:
	""" Check if character died and clamp HP to 0. Returns true if dead."""
	if character.current_hp <= 0:
		# Only log if HP wasn't already 0 (prevents duplicate death messages)
		if character.current_hp < 0:
			character.current_hp = 0
			print("[DEATH CHECK] %s has died (HP clamped to 0)" % character.name)
		# Else: Already at 0, don't log again
		return true
	return false


func check_all_deaths() -> Array[CharacterData]:
	""" NEW: Check all combatants for death, return list of dead characters"""
	var dead: Array[CharacterData] = []
	
	# Check player
	if check_death_after_action(player):
		dead.append(player)
	
	# Check all enemies
	for e in enemies:
		if check_death_after_action(e):
			dead.append(e)
	
	return dead

# Add to CombatEngine.gd

func validate_turn_order(character: CharacterData) -> bool:
	"""
	Validate if character can take turn (alive check)
	Call this BEFORE executing any action
	"""
	if not is_alive(character):
		print("[TURN VALIDATION] %s is dead, skipping turn" % character.name)
		return false
	return true

func get_next_living_enemy() -> CharacterData:
	"""
	Get next living enemy for turn order
	Returns null if all dead
	"""
	for e in enemies:
		if is_alive(e):
			return e
	return null

func rebuild_enemy_turn_queue() -> Array[CharacterData]:
	"""
	Rebuild turn queue with only living enemies
	Call this after status effects kill an enemy
	"""
	var living: Array[CharacterData] = []
	for e in enemies:
		if is_alive(e):
			living.append(e)
	print("[TURN QUEUE] Rebuilt: %d living enemies" % living.size())
	return living
