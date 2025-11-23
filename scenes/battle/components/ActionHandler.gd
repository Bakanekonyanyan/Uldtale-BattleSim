# res://scenes/battle/components/ActionHandler.gd
# Handles action execution with visual feedback coordination
# Separates action logic from orchestrator

class_name ActionHandler
extends RefCounted

var combat_engine: CombatEngine
var visual_manager: BattleVisualManager
var ui_controller: BattleUIController
var context: BattleContext

signal action_executed(action: BattleAction, result: ActionResult)
signal deaths_occurred(dead_characters: Array[CharacterData])

func initialize(p_combat: CombatEngine, p_visual: BattleVisualManager, p_ui: BattleUIController, p_context: BattleContext):
	combat_engine = p_combat
	visual_manager = p_visual
	ui_controller = p_ui
	context = p_context

func execute_main_action(action: BattleAction, is_player: bool) -> void:
	print("ActionHandler: Executing main action - %s" % action.get_description())
	
	if not is_player:
		var action_name = _get_action_name(action)
		ui_controller.add_combat_log("[color=red]%s uses %s![/color]" % [action.actor.name, action_name], "white")
	
	# Play attack animation BEFORE damage
	await _play_attack_animation(action)
	
	# Execute action through combat engine
	var result = combat_engine.execute_action(action)
	
	if not result:
		push_error("ActionHandler: Combat engine returned null result!")
		return
	
	# Visual feedback for results
	await _handle_visual_feedback(action, result)
	
	# Update UI
	ui_controller.display_result(result, action)
	
	if result.has_level_up():
		ui_controller.add_combat_log(result.level_up_message, "cyan")
	
	if is_player:
		context.main_action_taken = true
	
	emit_signal("action_executed", action, result)
	
	await _get_tree_timer(1.5)
	
	# Check for deaths (always emit, even if empty array)
	var dead = _collect_dead_characters(action)
	emit_signal("deaths_occurred", dead)

func execute_item_action(action: BattleAction) -> void:
	print("ActionHandler: Executing item action")
	
	await _play_item_animation(action)
	
	var result = combat_engine.execute_action(action)
	
	if result:
		await _handle_item_visual_feedback(action, result)
	
	ui_controller.display_result(result, action)
	
	await _get_tree_timer(0.5)
	
	context.item_action_used = true
	emit_signal("action_executed", action, result)

# === ANIMATION HELPERS ===

func _play_attack_animation(action: BattleAction) -> void:
	if not visual_manager or action.type not in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL]:
		return
	
	var is_aoe = action.targets.size() > 1
	var is_magic = false
	
	if action.type == BattleAction.ActionType.SKILL:
		is_magic = action.skill_data.ability_type != Skill.AbilityType.PHYSICAL
	
	if is_aoe:
		visual_manager.play_aoe_attack_animation(action.actor, action.targets, is_magic)
	elif action.target:
		visual_manager.play_attack_animation(action.actor, action.target, is_magic)
	
	await _get_tree_timer(0.3)

func _play_item_animation(action: BattleAction) -> void:
	if not visual_manager or action.item_data.consumable_type != Item.ConsumableType.DAMAGE:
		return
	
	var is_aoe = action.targets.size() > 1
	
	if is_aoe:
		visual_manager.play_aoe_attack_animation(action.actor, action.targets, true)
	elif action.target:
		visual_manager.play_attack_animation(action.actor, action.target, true)
	
	await _get_tree_timer(0.3)

# === VISUAL FEEDBACK ===

func _handle_visual_feedback(action: BattleAction, result: ActionResult) -> void:
	if not visual_manager:
		return
	
	# Dodge/miss animations
	if result.was_dodged or result.was_missed:
		for target in action.targets:
			if target:
				visual_manager.play_dodge_animation(target)
		return
	
	# Hit feedback
	if result.damage > 0:
		var player_was_hit = _player_in_targets(action.targets)
		
		if player_was_hit:
			visual_manager.shake_and_flash_screen(0.15)
		else:
			visual_manager.shake_on_hit(result.damage, result.is_critical)
		
		# Flash enemy sprites
		for target in action.targets:
			if target and target.is_alive() and target != context.player:
				visual_manager.flash_sprite_hit(target, result.is_critical)

func _handle_item_visual_feedback(action: BattleAction, result: ActionResult) -> void:
	if not visual_manager:
		return
	
	var player_was_hit = _player_in_targets(action.targets) and result.damage > 0
	
	if player_was_hit:
		visual_manager.shake_and_flash_screen(0.15)
	elif result.damage > 0 or result.healing > 0:
		visual_manager.add_trauma(0.15)
	
	if result.damage > 0:
		for target in action.targets:
			if target and target != context.player:
				visual_manager.flash_sprite_hit(target, false)

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
	return "Unknown"

func _player_in_targets(targets: Array[CharacterData]) -> bool:
	for target in targets:
		if target == context.player:
			return true
	return false

func _collect_dead_characters(action: BattleAction) -> Array[CharacterData]:
	var dead: Array[CharacterData] = []
	
	if action.target and not combat_engine.is_alive(action.target):
		dead.append(action.target)
	
	for target in action.targets:
		if target and not combat_engine.is_alive(target) and target not in dead:
			dead.append(target)
	
	if not combat_engine.is_alive(action.actor) and action.actor not in dead:
		dead.append(action.actor)
	
	return dead

func _get_tree_timer(seconds: float):
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(seconds).timeout
