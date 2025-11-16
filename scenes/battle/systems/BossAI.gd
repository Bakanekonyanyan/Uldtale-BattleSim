# res://scenes/battle/systems/BossAI.gd
# Boss AI with phase transitions, enrage mechanics, and special abilities

class_name BossAI
extends EnemyAI

# Boss-specific mechanics
enum BossPhase { PHASE_1, PHASE_2, PHASE_3, ENRAGED }

var current_phase: BossPhase = BossPhase.PHASE_1
var enrage_timer: int = 0
var max_enrage_turns: int = 15  # Boss enrages after 15 turns
var phase_skill_used: Dictionary = {}  # Track phase-specific abilities

# Phase transition thresholds
const PHASE_2_HP_THRESHOLD = 0.66
const PHASE_3_HP_THRESHOLD = 0.33

func initialize(p_enemy: CharacterData, p_player: CharacterData, floor: int):
	super.initialize(p_enemy, p_player, floor)
	
	# Bosses are more aggressive and intelligent
	aggression = randf_range(0.6, 0.9)
	intelligence = randf_range(0.7, 1.0)
	desperation_threshold = randf_range(0.15, 0.25)
	
	# Set enrage timer based on floor
	max_enrage_turns = max(10, 20 - floor)
	
	print("BossAI: Initialized BOSS %s (Enrage in %d turns)" % [enemy.name, max_enrage_turns])

func decide_action() -> BattleAction:
	"""Boss decision-making with phase mechanics"""
	
	# Update phase
	_check_phase_transition()
	
	# Increment enrage timer
	enrage_timer += 1
	if enrage_timer >= max_enrage_turns and current_phase != BossPhase.ENRAGED:
		_trigger_enrage()
	
	var enemy_hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
	
	# === PHASE-SPECIFIC ABILITIES (Priority) ===
	var phase_action = _try_phase_ability()
	if phase_action:
		return phase_action
	
	# === ENRAGED BEHAVIOR (Ultra Aggressive) ===
	if current_phase == BossPhase.ENRAGED:
		return _enraged_behavior()
	
	# === BOSS OPENER (First Turn Special) ===
	if enrage_timer == 1:
		var opener = _boss_opener()
		if opener:
			return opener
	
	# Otherwise use enhanced base AI
	return super.decide_action()

# =============================================
# PHASE MANAGEMENT
# =============================================

func _check_phase_transition():
	"""Check if boss should transition to new phase"""
	var hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
	var old_phase = current_phase
	
	if current_phase == BossPhase.ENRAGED:
		return  # Already enraged, no further transitions
	
	if hp_percent <= PHASE_3_HP_THRESHOLD and current_phase != BossPhase.PHASE_3:
		current_phase = BossPhase.PHASE_3
		_on_phase_transition(old_phase, current_phase)
	elif hp_percent <= PHASE_2_HP_THRESHOLD and current_phase == BossPhase.PHASE_1:
		current_phase = BossPhase.PHASE_2
		_on_phase_transition(old_phase, current_phase)

func _on_phase_transition(old_phase: BossPhase, new_phase: BossPhase):
	"""Handle phase transition effects"""
	print("BossAI: PHASE TRANSITION - %s -> %s!" % [
		BossPhase.keys()[old_phase],
		BossPhase.keys()[new_phase]
	])
	
	# Reset phase skill tracking
	phase_skill_used.clear()
	
	# Phase transition bonuses
	match new_phase:
		BossPhase.PHASE_2:
			# Moderate buff
			_apply_phase_buff(1.2)
			print("BossAI: Phase 2 - Boss grows stronger!")
		
		BossPhase.PHASE_3:
			# Strong buff + clear debuffs
			_apply_phase_buff(1.5)
			enemy.buff_manager.clear_all()
			print("BossAI: Phase 3 - Boss enters final form!")

func _trigger_enrage():
	"""Boss enrages after too many turns"""
	print("BossAI: BOSS ENRAGED - Time limit exceeded!")
	current_phase = BossPhase.ENRAGED
	
	# Massive stat boost
	_apply_phase_buff(2.0)
	
	# Clear all debuffs
	if enemy.buff_manager:
		enemy.buff_manager.clear_all()
	
	# Clear all status effects
	if enemy.status_manager:
		enemy.status_manager.clear_all_effects()

func _apply_phase_buff(multiplier: float):
	"""Apply temporary stat boost"""
	var duration = 999  # Effectively permanent
	
	# Buff primary combat stats
	enemy.apply_buff(Skill.AttributeTarget.STRENGTH, int(enemy.strength * (multiplier - 1.0)), duration)
	enemy.apply_buff(Skill.AttributeTarget.INTELLIGENCE, int(enemy.intelligence * (multiplier - 1.0)), duration)
	enemy.apply_buff(Skill.AttributeTarget.AGILITY, int(enemy.agility * (multiplier - 1.0)), duration)

# =============================================
# PHASE-SPECIFIC ABILITIES
# =============================================

func _try_phase_ability() -> BattleAction:
	"""Bosses have special abilities in each phase"""
	
	# Each phase gets ONE special ability use
	var phase_key = "phase_%d" % current_phase
	if phase_skill_used.get(phase_key, false):
		return null  # Already used this phase's special
	
	var special_skill = _get_phase_special_skill()
	if special_skill and _can_afford_skill(special_skill):
		phase_skill_used[phase_key] = true
		print("BossAI: Using PHASE SPECIAL - %s!" % special_skill.name)
		
		var targets = _get_skill_targets_smart(special_skill)
		return BattleAction.skill(enemy, special_skill, targets)
	
	return null

func _get_phase_special_skill() -> Skill:
	"""Get the best special skill for current phase"""
	var available_skills = []
	
	for skill_name in enemy.skills:
		var skill = SkillManager.get_skill(skill_name)
		if not skill or enemy.get_skill_cooldown(skill_name) > 0:
			continue
		
		# Phase 1: Debuffs
		if current_phase == BossPhase.PHASE_1:
			if skill.type in [Skill.SkillType.DEBUFF, Skill.SkillType.INFLICT_STATUS]:
				available_skills.append(skill)
		
		# Phase 2: High damage
		elif current_phase == BossPhase.PHASE_2:
			if skill.type == Skill.SkillType.DAMAGE and skill.power >= 40:
				available_skills.append(skill)
		
		# Phase 3: AOE or strongest
		elif current_phase == BossPhase.PHASE_3:
			if skill.power >= 50:
				available_skills.append(skill)
	
	if available_skills.is_empty():
		return null
	
	# Return highest power skill
	available_skills.sort_custom(func(a, b): return a.power > b.power)
	return available_skills[0]

func _get_skill_targets_smart(skill: Skill) -> Array:
	"""Get smart targets for skill"""
	match skill.target:
		Skill.TargetType.SELF, Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES:
			return [enemy]
		Skill.TargetType.ENEMY, Skill.TargetType.ALL_ENEMIES:
			return [player]
	return []

# =============================================
# BOSS OPENER
# =============================================

func _boss_opener() -> BattleAction:
	"""Boss uses special move on first turn"""
	print("BossAI: BOSS OPENER!")
	
	# Try to buff self first turn
	var buff_skill = _find_buff_skill()
	if buff_skill and _can_afford_skill(buff_skill):
		print("BossAI: Opening with self-buff")
		return BattleAction.skill(enemy, buff_skill, [enemy])
	
	# Or debuff player
	var debuff_skill = _find_debuff_skill()
	if debuff_skill and _can_afford_skill(debuff_skill):
		print("BossAI: Opening with player debuff")
		return BattleAction.skill(enemy, debuff_skill, [player])
	
	# Or strong attack
	var damage_skill = _find_best_damage_skill()
	if damage_skill and _can_afford_skill(damage_skill):
		print("BossAI: Opening with strong attack")
		return BattleAction.skill(enemy, damage_skill, [player])
	
	return null

# =============================================
# ENRAGED BEHAVIOR
# =============================================

func _enraged_behavior() -> BattleAction:
	"""Ultra-aggressive behavior when enraged"""
	print("BossAI: ENRAGED ACTION!")
	
	# 80% chance to use skill, 20% attack
	if RandomManager.randf() < 0.8:
		var best_skill = _find_strongest_available_skill()
		if best_skill:
			print("BossAI: Enraged skill - %s" % best_skill.name)
			return BattleAction.skill(enemy, best_skill, [player])
	
	print("BossAI: Enraged attack")
	return BattleAction.attack(enemy, player)

# =============================================
# BOSS-SPECIFIC DESPERATION
# =============================================

func _decide_desperate_action() -> BattleAction:
	"""Boss desperation is more dangerous"""
	print("BossAI: BOSS DESPERATION MODE!")
	
	# Bosses always go all-out when desperate
	var strongest = _find_strongest_available_skill()
	if strongest:
		print("BossAI: Final desperate skill - %s!" % strongest.name)
		return BattleAction.skill(enemy, strongest, [player])
	
	# No mercy - attack
	print("BossAI: Final desperate attack!")
	return BattleAction.attack(enemy, player)
