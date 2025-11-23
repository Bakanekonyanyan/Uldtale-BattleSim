# res://scripts/combat/CombatActions.gd
class_name CombatActions
extends RefCounted

static func execute_basic_attack(attacker: CharacterData, target: CharacterData) -> String:
	if not target or not is_instance_valid(target):
		return "%s's attack failed - no valid target!" % attacker.name
	
	var momentum_mult = MomentumSystem.get_damage_multiplier()
	var base_damage = attacker.get_attack_power() * 0.5 * momentum_mult
	var resistance = target.get_defense()
	
	# Combat rolls
	if RandomManager.randf() >= attacker.accuracy:
		return "%s's attack missed!" % attacker.name
	if RandomManager.randf() < target.dodge:
		return "%s dodged the attack!" % target.name
	
	var is_crit = RandomManager.randf() < attacker.critical_hit_rate
	var damage = max(1, base_damage - resistance)
	
	if is_crit:
		damage *= 1.5 + RandomManager.randf() * 0.5
	
	damage = round(damage)
	
	# Apply damage (pass attacker for reflection)
	apply_damage(target, damage, attacker)
	
	# Track weapon proficiency
	_track_weapon_proficiency(attacker)
	
	# Status effect from weapon
	var status_msg = _apply_weapon_status(attacker, target)
	
	# Resource regen
	var mp_restore = int(attacker.max_mp * 0.08)
	var sp_restore = int(attacker.max_sp * 0.08)
	attacker.restore_mp(mp_restore)
	attacker.restore_sp(sp_restore)
	
	# Build message
	var result = "%s attacks %s for %d damage" % [attacker.name, target.name, damage]
	
	if momentum_mult > 1.0:
		result += " (+%d%% momentum)" % int((momentum_mult - 1.0) * 100)
	
	result += " and restores %d MP, %d SP%s" % [mp_restore, sp_restore, status_msg]
	
	if is_crit:
		result = "Critical hit! " + result
	
	return result

static func apply_damage(target: CharacterData, amount: float, attacker: CharacterData = null):
	if target.current_hp <= 0:
		target.current_hp = 0
		print("[DAMAGE] %s already dead, ignoring damage" % target.name)
		return
	
	# Track armor proficiency
	_track_armor_proficiency(target)
	
	# Store attacker for reflection
	if attacker:
		target.last_attacker = attacker
	
	# Apply defense reduction
	if target.is_defending:
		amount *= 0.5
	
	# Reflection mechanic
	if target.last_attacker and target.last_attacker != target:
		var reflection = target.status_manager.get_total_reflection()
		if reflection > 0.0:
			var reflected = int(amount * reflection)
			if reflected > 0:
				print("%s reflected %d damage back to %s!" % [target.name, reflected, target.last_attacker.name])
				apply_damage(target.last_attacker, reflected, null)
	
	# Apply damage
	target.current_hp -= int(amount)
	target.current_hp = clamp(target.current_hp, 0, target.max_hp)
	
	print("[DAMAGE] %s took %d damage. HP: %d/%d" % [target.name, int(amount), target.current_hp, target.max_hp])

static func _track_weapon_proficiency(character: CharacterData):
	if not character.equipment["main_hand"] or not character.proficiency_manager:
		return
	
	var weapon = character.equipment["main_hand"]
	if not weapon is Equipment:
		return
	
	var weapon_key = EquipmentKeyHelper.get_equipment_key(weapon)
	if weapon_key != "":
		var msg = character.proficiency_manager.use_weapon(weapon_key)
		if msg != "":
			print("[PROFICIENCY] %s" % msg)

static func _track_armor_proficiency(character: CharacterData):
	if not character.proficiency_manager:
		return
	
	var armor_slots = ["head", "chest", "hands", "legs", "feet"]
	for slot in armor_slots:
		if character.equipment[slot] and character.equipment[slot] is Equipment:
			var armor = character.equipment[slot]
			if armor.type in ["cloth", "leather", "mail", "plate"]:
				var msg = character.proficiency_manager.use_armor(armor.type)
				if msg != "":
					print("[PROFICIENCY] %s" % msg)
					break

static func _apply_weapon_status(attacker: CharacterData, target: CharacterData) -> String:
	var status_msg = ""
	if attacker.equipment["main_hand"] and attacker.equipment["main_hand"] is Equipment:
		var weapon = attacker.equipment["main_hand"]
		if "status_effect_type" in weapon and "status_effect_chance" in weapon:
			if weapon.status_effect_type != Skill.StatusEffect.NONE:
				if weapon.has_method("try_apply_status_effect"):
					if weapon.try_apply_status_effect(target):
						status_msg = " and applied %s" % Skill.StatusEffect.keys()[weapon.status_effect_type]
	return status_msg
