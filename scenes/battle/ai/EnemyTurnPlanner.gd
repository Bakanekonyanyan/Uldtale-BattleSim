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

	print("EnemyTurnPlanner: %d AI controllers ready" % _brains.size())

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

	# Offensive actions with no target fall back to the hero the AI chose
	if action.type in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL] and action.targets.is_empty():
		if not (action.skill_data and action.skill_data.target == Skill.TargetType.ALL_ALLIES):
			action.primary_target = ai.target if ai.target else context.player

	return action
