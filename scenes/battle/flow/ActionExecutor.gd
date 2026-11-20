# res://scenes/battle/flow/ActionExecutor.gd
# Carries out ONE BattleAction end-to-end:
#
#   animation -> CombatEngine.execute_action() -> hit/dodge feedback -> combat log
#
# Returns an Outcome describing what happened and who died, so the caller
# (the orchestrator's turn loop) decides what to do next. It never ends turns
# or checks victory itself.

class_name ActionExecutor
extends RefCounted

## What execute() hands back to the turn loop.
class Outcome:
	var result: ActionResult
	var dead: Array[CharacterData] = []

	func succeeded() -> bool:
		return result != null and result.success

var combat_engine: CombatEngine
var visual_manager: BattleVisualManager
var ui_controller: BattleUIController
var context: BattleContext

func initialize(p_combat: CombatEngine, p_visual: BattleVisualManager, p_ui: BattleUIController, p_context: BattleContext) -> void:
	combat_engine = p_combat
	visual_manager = p_visual
	ui_controller = p_ui
	context = p_context

## Execute any action. `announce` logs "X uses Y!" first (used for enemy turns).
func execute(action: BattleAction, announce: bool = false) -> Outcome:
	var outcome = Outcome.new()
	Log.debug("battle", "ActionExecutor: %s" % action.get_description())

	if announce:
		ui_controller.add_combat_log("%s uses %s!" % [action.actor.name, _get_action_name(action)], "red")

	var is_item = action.type == BattleAction.ActionType.ITEM

	await _play_animation(action)

	var rules: BattleRules = context.rules
	var snap = rules.before_action(action) if rules else {}
	outcome.result = combat_engine.execute_action(action)
	if not outcome.result:
		push_error("ActionExecutor: CombatEngine returned null for %s" % action.get_description())
		outcome.result = ActionResult.failure_msg("Action failed")

	await _play_feedback(action, outcome.result)

	ui_controller.display_result(outcome.result, action)
	# Break, Link, turn order, elite affixes (BattleRules)
	if rules:
		for line in rules.after_action(action, snap):
			ui_controller.add_combat_log(line, "gold")
			if line.contains("BREAK") and visual_manager:
				visual_manager.shake_and_flash_screen(0.25)
		ui_controller.update_all_character_info()
	if outcome.result.has_level_up():
		ui_controller.add_combat_log(outcome.result.level_up_message, "cyan")

	await _wait(0.5 if is_item else 1.5)

	outcome.dead = _collect_dead(action)
	return outcome

# === ANIMATION ===

func _play_animation(action: BattleAction) -> void:
	if not visual_manager:
		return

	var is_magic := false
	match action.type:
		BattleAction.ActionType.ATTACK:
			is_magic = false
		BattleAction.ActionType.SKILL:
			is_magic = action.skill_data.ability_type != Skill.AbilityType.PHYSICAL
		BattleAction.ActionType.ITEM:
			if action.item_data.consumable_type != Item.ConsumableType.DAMAGE:
				return
			is_magic = true
		_:
			return

	if action.has_multiple_targets():
		visual_manager.play_aoe_attack_animation(action.actor, action.targets, is_magic)
	elif action.primary_target:
		visual_manager.play_attack_animation(action.actor, action.primary_target, is_magic)

	await _wait(0.3)

# === FEEDBACK (shake / flash / dodge) ===

func _play_feedback(action: BattleAction, result: ActionResult) -> void:
	if not visual_manager:
		return

	if result.was_dodged or result.was_missed:
		for target in action.targets:
			if target:
				visual_manager.play_dodge_animation(target)
		return

	if result.damage <= 0:
		if result.healing > 0:
			visual_manager.add_trauma(0.15)
		return

	# Confusion self-harm: the actor was hurt, not the targets
	var hurt: Array[CharacterData] = []
	if result.self_inflicted:
		hurt.append(action.actor)
	else:
		hurt.append_array(action.targets)

	if hurt.any(func(h): return context.is_hero(h)):
		visual_manager.shake_and_flash_screen(0.15)
	else:
		visual_manager.shake_on_hit(result.damage, result.is_critical)

	for c in hurt:
		if c and not context.is_hero(c) and c.is_alive():
			visual_manager.flash_sprite_hit(c, result.is_critical)

# === HELPERS ===

func _get_action_name(action: BattleAction) -> String:
	match action.type:
		BattleAction.ActionType.ATTACK:
			return "Attack"
		BattleAction.ActionType.DEFEND:
			return "Defend"
		BattleAction.ActionType.SKILL:
			return action.skill_data.name
		BattleAction.ActionType.ITEM:
			return action.item_data.display_name
		BattleAction.ActionType.CHARGE:
			return "a charge-up"
		BattleAction.ActionType.UNISON:
			return "Unison Strike"
	return "Unknown"

## Anyone touched by the action who is now dead (targets + the actor, who can
## die from reflection or confusion).
func _collect_dead(action: BattleAction) -> Array[CharacterData]:
	var dead: Array[CharacterData] = []
	for c in action.targets + [action.actor]:
		if c and not combat_engine.is_alive(c) and c not in dead:
			dead.append(c)
	return dead

func _wait(seconds: float) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(seconds).timeout
