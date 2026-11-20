# res://scenes/battle/ai/BossAI.gd
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

func initialize(p_enemy: CharacterData, p_heroes: Variant, floor: int):
	super.initialize(p_enemy, p_heroes, floor)
	
	# Bosses are more aggressive and intelligent
	_roll_personality("boss")
	
	# Set enrage timer based on floor
	max_enrage_turns = max(10, 20 - floor)
	
	Log.debug("ai", "BossAI: Initialized BOSS %s (Enrage in %d turns)" % [enemy.name, max_enrage_turns])

func _decide() -> BattleAction:
	"""Boss decision-making with phase mechanics (target already chosen)"""
	
	# Update phase
	_check_phase_transition()
	
	# Increment enrage timer
	enrage_timer += 1
	if enrage_timer >= max_enrage_turns and current_phase != BossPhase.ENRAGED:
		_trigger_enrage()
	
	var enemy_hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
	
	# === HP TRIGGERS: signature / ultimate (data/enemy_archetypes.json boss.phases) ===
	var trigger_action = _try_hp_trigger(enemy_hp_percent)
	if trigger_action:
		return trigger_action
	
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
	return super._decide()

# =============================================
# HP TRIGGERS (archetype bosses)
# =============================================

## Each entry of boss.phases fires once when HP drops below hp_below: the boss
## uses its signature or its talent ultimate. A trigger whose skill is on
## cooldown or unaffordable waits for a later turn.
var _fired_triggers: Dictionary = {}

func _try_hp_trigger(hp_percent: float) -> BattleAction:
	var phases: Array = EnemyArchetypes.boss_cfg().get("phases", [])
	for i in range(phases.size()):
		var ph: Dictionary = phases[i]
		if _fired_triggers.has(i) or hp_percent > float(ph.get("hp_below", 0.0)):
			continue
		var skill_name = String(enemy.get_meta("boss_" + String(ph.get("use", "")), ""))
		if skill_name == "" or not enemy.skills.has(skill_name):
			_fired_triggers[i] = true      # nothing to use: don't keep checking
			continue
		var skill = enemy.get_skill_instance(skill_name)
		if skill == null or enemy.get_skill_cooldown(skill_name) > 0 or not _can_afford_skill(skill):
			continue
		_fired_triggers[i] = true
		Log.debug("ai", "BossAI: HP trigger (%.0f%%) - %s!" % [hp_percent * 100, skill_name])
		# Telegraphed: spend this turn charging, unleash it next turn (a Break
		# in between cancels it). data/combat.json intents.boss_charge
		if bool(BattleRules.cfg().get("intents", {}).get("boss_charge", true)):
			return BattleAction.charge(enemy, skill_name)
		return BattleAction.skill(enemy, skill, _get_skill_targets_smart(skill))
	return null

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
	Log.debug("ai", "BossAI: PHASE TRANSITION - %s -> %s!" % [
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
			Log.debug("ai", "BossAI: Phase 2 - Boss grows stronger!")
		
		BossPhase.PHASE_3:
			# Clear debuffs, then strong buff. (clear_all() AFTER the buff used
			# to wipe the buff it had just applied.)
			enemy.buff_manager.clear_debuffs()
			_apply_phase_buff(1.5)
			Log.debug("ai", "BossAI: Phase 3 - Boss enters final form!")

func _trigger_enrage():
	"""Boss enrages after too many turns"""
	Log.debug("ai", "BossAI: BOSS ENRAGED - Time limit exceeded!")
	current_phase = BossPhase.ENRAGED
	
	# Clear all debuffs first, then the massive stat boost
	# (previously clear_all() ran after the boost and erased it)
	if enemy.buff_manager:
		enemy.buff_manager.clear_debuffs()
	_apply_phase_buff(2.0)
	
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
		Log.debug("ai", "BossAI: Using PHASE SPECIAL - %s!" % special_skill.name)
		
		var targets = _get_skill_targets_smart(special_skill)
		return BattleAction.skill(enemy, special_skill, targets)
	
	return null

func _get_phase_special_skill() -> Skill:
	"""Get the best special skill for current phase"""
	var available_skills = []
	
	for skill_name in enemy.skills:
		var skill = enemy.get_skill_instance(skill_name)
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
			return [target]
	return []

# =============================================
# BOSS OPENER
# =============================================

func _boss_opener() -> BattleAction:
	"""Boss uses special move on first turn"""
	Log.debug("ai", "BossAI: BOSS OPENER!")
	
	# Try to buff self first turn
	var buff_skill = _find_buff_skill()
	if buff_skill and _can_afford_skill(buff_skill):
		Log.debug("ai", "BossAI: Opening with self-buff")
		return BattleAction.skill(enemy, buff_skill, [enemy])
	
	# Or debuff target
	var debuff_skill = _find_debuff_skill()
	if debuff_skill and _can_afford_skill(debuff_skill):
		Log.debug("ai", "BossAI: Opening with target debuff")
		return BattleAction.skill(enemy, debuff_skill, [target])
	
	# Or strong attack
	var damage_skill = _find_best_damage_skill()
	if damage_skill and _can_afford_skill(damage_skill):
		Log.debug("ai", "BossAI: Opening with strong attack")
		return BattleAction.skill(enemy, damage_skill, [target])
	
	return null

# =============================================
# ENRAGED BEHAVIOR
# =============================================

func _enraged_behavior() -> BattleAction:
	"""Ultra-aggressive behavior when enraged"""
	Log.debug("ai", "BossAI: ENRAGED ACTION!")
	
	# 80% chance to use skill, 20% attack
	if RandomManager.randf() < 0.8:
		var best_skill = _find_strongest_available_skill()
		if best_skill:
			Log.debug("ai", "BossAI: Enraged skill - %s" % best_skill.name)
			return BattleAction.skill(enemy, best_skill, [target])
	
	Log.debug("ai", "BossAI: Enraged attack")
	return BattleAction.attack(enemy, target)

# =============================================
# BOSS-SPECIFIC DESPERATION
# =============================================

func _decide_desperate_action() -> BattleAction:
	"""Boss desperation is more dangerous"""
	Log.debug("ai", "BossAI: BOSS DESPERATION MODE!")
	
	# Bosses always go all-out when desperate
	var strongest = _find_strongest_available_skill()
	if strongest:
		Log.debug("ai", "BossAI: Final desperate skill - %s!" % strongest.name)
		return BattleAction.skill(enemy, strongest, [target])
	
	# No mercy - attack
	Log.debug("ai", "BossAI: Final desperate attack!")
	return BattleAction.attack(enemy, target)
