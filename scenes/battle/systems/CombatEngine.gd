# res://scenes/battle/systems/CombatEngine.gd
# Pure combat logic - no UI, no scene management
# Replaces the old CombatManager with cleaner separation

class_name CombatEngine
extends RefCounted

var player: CharacterData
var enemy: CharacterData

func initialize(p_player: CharacterData, p_enemy: CharacterData):
	player = p_player
	enemy = p_enemy
	print("CombatEngine: Initialized - Player: %s vs Enemy: %s" % [player.name, enemy.name])

func execute_action(action: BattleAction) -> ActionResult:
	"""Main entry point for all combat actions"""
	if not action.is_valid():
		return ActionResult.failure_msg("Invalid action")
	
	print("CombatEngine: Executing %s" % action.get_description())
	
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
			return ActionResult.success_msg("Viewing equipment") # Handled by UI
	
	return ActionResult.failure_msg("Unknown action type")

# === ATTACK ===

func _execute_attack(action: BattleAction) -> ActionResult:
	var attacker = action.actor
	var target = action.target
	
	if not is_alive(target):
		return ActionResult.failure_msg("%s is already defeated" % target.name)
	
	# === WEAPON PROFICIENCY TRACKING ===
	var prof_level_up_msg = ""
	if attacker.equipment.has("main_hand") and attacker.equipment["main_hand"]:
		var weapon = attacker.equipment["main_hand"]
		
		if weapon is Equipment and attacker.proficiency_manager:
			# Ensure weapon has a valid key
			if weapon.key == "" or weapon.key == null:
				print("[COMBAT] Weapon '%s' missing key, attempting to get from helper..." % weapon.name)
				weapon.key = EquipmentKeyHelper.get_equipment_key(weapon)
				print("[COMBAT] Helper returned key: '%s'" % weapon.key)
			
			# Track proficiency if we have a valid key
			if weapon.key != "" and weapon.key != null:
				print("[COMBAT] Tracking proficiency for weapon: %s" % weapon.key)
				prof_level_up_msg = attacker.proficiency_manager.use_weapon(weapon.key)
				
				# DEBUG: Always show current proficiency progress
				var uses = attacker.proficiency_manager.get_weapon_proficiency_uses(weapon.key)
				var level = attacker.proficiency_manager.get_weapon_proficiency_level(weapon.key)
				var next_threshold = attacker.proficiency_manager.get_uses_for_next_level(level)
				print("[PROFICIENCY] %s: %d/%d uses (Level %d)" % [weapon.key, uses, next_threshold, level])
				
				if prof_level_up_msg != "":
					print("[PROFICIENCY LEVEL UP!] %s" % prof_level_up_msg)
			else:
				print("[COMBAT ERROR] Could not determine weapon key for '%s'" % weapon.name)
		else:
			if not (weapon is Equipment):
				print("[COMBAT ERROR] main_hand weapon is not Equipment type")
			if not attacker.proficiency_manager:
				print("[COMBAT ERROR] Attacker has no proficiency_manager")
	
	# === MOMENTUM & DAMAGE CALCULATION ===
	var momentum_mult = MomentumSystem.get_damage_multiplier()
	var base_damage = attacker.get_attack_power() * 0.5 * momentum_mult
	var resistance = target.get_defense()
	
	# Accuracy check
	if RandomManager.randf() >= attacker.accuracy:
		return ActionResult.missed_attack(attacker, target)
	
	# Dodge check
	if RandomManager.randf() < target.dodge:
		return ActionResult.dodged_attack(attacker, target)
	
	# Calculate damage
	var is_crit = RandomManager.randf() < attacker.critical_hit_rate
	var damage = max(1, base_damage - resistance)
	
	if is_crit:
		damage *= 1.5 + RandomManager.randf() * 0.5
	
	damage = round(damage)
	
	# Apply damage (pass attacker for reflection mechanics)
	target.take_damage(damage, attacker)
	
	# === STATUS EFFECT FROM WEAPON ===
	var status_msg = ""
	if attacker.equipment["main_hand"] and attacker.equipment["main_hand"] is Equipment:
		var weapon = attacker.equipment["main_hand"]
		if "status_effect_type" in weapon and "status_effect_chance" in weapon:
			if weapon.status_effect_type != Skill.StatusEffect.NONE:
				if weapon.has_method("try_apply_status_effect"):
					if weapon.try_apply_status_effect(target):
						status_msg = " and applied %s" % Skill.StatusEffect.keys()[weapon.status_effect_type]
	
	# === RESOURCE REGENERATION ===
	var mp_restore = int(attacker.max_mp * 0.08)
	var sp_restore = int(attacker.max_sp * 0.08)
	attacker.restore_mp(mp_restore)
	attacker.restore_sp(sp_restore)
	
	# === BUILD RESULT ===
	var result = ActionResult.attack_result(attacker, target, int(damage), is_crit)
	result.message += " and restores %d MP, %d SP%s" % [mp_restore, sp_restore, status_msg]
	
	# Add proficiency level-up message to result if it occurred
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
	
	# Check resource costs
	var cost_type = "MP" if skill.ability_type != Skill.AbilityType.PHYSICAL else "SP"
	var cost = skill.mp_cost if cost_type == "MP" else skill.sp_cost
	var current = caster.current_mp if cost_type == "MP" else caster.current_sp
	
	if current < cost:
		return ActionResult.failure_msg("Not enough %s" % cost_type)
	
	# Deduct cost
	if cost_type == "MP":
		caster.current_mp -= cost
	else:
		caster.current_sp -= cost
	
	# Execute skill
	var skill_msg = skill.use(caster, targets)
	
	# Track skill usage for leveling
	var level_up_msg = caster.use_skill(skill.name)
	
	# Set cooldown
	caster.use_skill_cooldown(skill.name, skill.cooldown)
	
	var result = ActionResult.skill_result(caster, skill, targets, skill_msg)
	result.level_up_message = level_up_msg
	
	return result

# === ITEM ===

func _execute_item(action: BattleAction) -> ActionResult:
	var user = action.actor
	var item = action.item_data
	var targets = action.targets
	
	if not is_alive(user):
		return ActionResult.failure_msg("%s cannot use items while defeated" % user.name)
	
	# Use item
	var item_msg = item.use(user, targets)
	
	# Remove from inventory (if player)
	if user.is_player:
		var item_id = item.id
		if user.inventory.items.has(item_id):
			user.inventory.remove_item(item_id, 1)
			print("CombatEngine: Removed 1x %s from inventory" % item.name)
	
	return ActionResult.item_result(user, item, targets, item_msg)

# === STATUS EFFECTS ===

func process_status_effects(character: CharacterData) -> String:
	"""Process status effects at start of turn"""
	character.reduce_cooldowns()
	return character.update_status_effects()

# === BATTLE STATE ===

func is_alive(character: CharacterData) -> bool:
	return character and character.current_hp > 0

func check_battle_end() -> String:
	"""Returns 'victory', 'defeat', or 'ongoing'"""
	if not is_alive(enemy):
		return "victory"
	if not is_alive(player):
		return "defeat"
	return "ongoing"

func get_skill_targets(skill: Skill, caster: CharacterData, opponent: CharacterData) -> Array[CharacterData]:
	"""Get correct targets for a skill"""
	var result: Array[CharacterData] = []
	
	match skill.target:
		Skill.TargetType.SELF, Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES:
			result.append(caster)
		Skill.TargetType.ENEMY, Skill.TargetType.ALL_ENEMIES:
			result.append(opponent)
	
	return result
