# res://scenes/battle/ai/EnemyTurnPlanner.gd
# Owns one AI brain per enemy and turns "it's this enemy's turn" into a
# valid BattleAction. Bosses ("King" classes in boss fights) get BossAI.
#
# Only decides - ActionExecutor carries the action out.

class_name EnemyTurnPlanner
extends RefCounted

var _brains: Dictionary = {}  # CharacterData -> EnemyAI
var context: BattleContext

func initialize(p_context: BattleContext) -> void:
	context = p_context
	_brains.clear()

	for enemy in context.enemies:
		var ai: EnemyAI
		if context.is_boss_battle and "King" in enemy.character_class:
			ai = BossAI.new()
		else:
			ai = EnemyAI.new()
		# AI reads the current living heroes each turn (party-ready)
		ai.initialize(enemy, context.get_living_heroes, context.current_floor)
		ai.set_allies_source(context.get_living_enemies)   # healers mend the pack
		_brains[enemy] = ai

	Log.debug("ai", "EnemyTurnPlanner: %d AI controllers ready" % _brains.size())

## An enemy that joins mid-battle (encounters) gets its own brain.
func add_enemy(enemy: CharacterData) -> void:
	if _brains.has(enemy):
		return
	var ai := EnemyAI.new()
	ai.initialize(enemy, context.get_living_heroes, context.current_floor)
	ai.set_allies_source(context.get_living_enemies)
	_brains[enemy] = ai

# ------------------------------------------------------------------ intents
# Each enemy's next action is decided ahead of time and stored as meta
# "intent" so the UI (and the hero AI) can see it. At the enemy's turn
# take_intent() returns it - re-targeted or re-planned if it went stale.

func plan_intent(enemy: CharacterData) -> void:
	if enemy == null or not enemy.is_alive() or enemy.get_meta("broken", false) or context.get_living_heroes().is_empty():
		return
	var a: BattleAction = _charged_action(enemy) if enemy.has_meta("charging") else plan_action(enemy)
	if a:
		context.intents[enemy] = a

func plan_all_intents() -> void:
	for e in context.enemies:
		if e.is_alive() and not context.intents.has(e):
			plan_intent(e)

## The action for this enemy's turn.
func take_intent(enemy: CharacterData) -> BattleAction:
	var a = context.intents.get(enemy, null)
	context.intents.erase(enemy)
	if enemy.has_meta("charging"):
		var charged = _charged_action(enemy)
		enemy.remove_meta("charging")
		if charged:
			return charged
	if a is BattleAction and _refresh(a):
		return a
	return plan_action(enemy)

## Unleash a charged skill.
func _charged_action(enemy: CharacterData) -> BattleAction:
	var skill_name = String(enemy.get_meta("charging", ""))
	var s: Skill = enemy.get_skill_instance(skill_name) if skill_name != "" else null
	if s == null:
		return null
	enemy.set_meta("charged_strike", true)   # x charge_power_mult (BattleFormulas); cleared after the action
	var ai: EnemyAI = _brains.get(enemy)
	var tgt = ai.choose_target() if ai else null
	match s.target:
		Skill.TargetType.SELF, Skill.TargetType.ALLY:
			return BattleAction.skill(enemy, s, [enemy])
		Skill.TargetType.ALL_ALLIES:
			return BattleAction.skill(enemy, s, [])
	return BattleAction.skill(enemy, s, [tgt] if tgt else [])

## Keep a planned action usable: drop dead targets, re-target, check costs.
func _refresh(a: BattleAction) -> bool:
	if a.actor == null or not a.actor.is_alive():
		return false
	if a.type == BattleAction.ActionType.SKILL:
		if a.actor.get_skill_cooldown(a.skill_data.name) > 0 or not a.skill_data.can_afford(a.actor):
			return false
		if a.skill_data.target == Skill.TargetType.ALL_ALLIES:
			return true
	if a.type in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL]:
		var alive = a.targets.filter(func(t): return t != null and t.is_alive())
		if alive.is_empty():
			var ai: EnemyAI = _brains.get(a.actor)
			var t = ai.choose_target() if ai else null
			if t == null:
				return false
			alive = [t]
		a.targets.clear()
		for t in alive:
			a.targets.append(t)
	return true

## Returns the action this enemy will take, or null if it cannot act.
func plan_action(enemy: CharacterData) -> BattleAction:
	var ai: EnemyAI = _brains.get(enemy)
	if not ai:
		push_error("EnemyTurnPlanner: No AI for %s" % enemy.name)
		return null

	var action := ai.decide_action()
	if not action:
		push_error("EnemyTurnPlanner: AI for %s returned no action" % enemy.name)
		return null

	# Regular enemies sometimes wind up a heavy skill: a visible charge-up you
	# can Perfect Guard, Break or race (combat.json intents.regular_charge_*)
	var ic: Dictionary = BattleRules.cfg().get("intents", {})
	if action.type == BattleAction.ActionType.SKILL and action.skill_data and not enemy.has_meta("charging") \
			and action.skill_data.type in [Skill.SkillType.DAMAGE, Skill.SkillType.DRAIN] \
			and float(action.skill_data.power) >= float(ic.get("regular_charge_min_power", 30)) \
			and not enemy.character_class.begins_with("King") and not enemy.has_meta("boss_signature") \
			and RandomManager.randf() < float(ic.get("regular_charge_chance", 0.0)):
		return BattleAction.charge(enemy, action.skill_data.name)
	# Offensive actions with no target fall back to the hero the AI chose
	if action.type in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL] and action.targets.is_empty():
		if not (action.skill_data and action.skill_data.target == Skill.TargetType.ALL_ALLIES):
			action.primary_target = ai.target if ai.target else context.player

	return action
