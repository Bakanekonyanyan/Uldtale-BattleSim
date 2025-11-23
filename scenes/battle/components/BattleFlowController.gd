# res://scenes/battle/components/BattleFlowController.gd
# Manages battle end conditions, death handling, victory/defeat
# Separates flow control from action execution

class_name BattleFlowController
extends RefCounted

var combat_engine: CombatEngine
var visual_manager: BattleVisualManager
var ui_controller: BattleUIController
var turn_handler: TurnHandler
var context: BattleContext
var parent_node: Node  # For adding dialogs

signal battle_ended(player_won: bool, xp_gained: int)

func initialize(p_combat: CombatEngine, p_visual: BattleVisualManager, p_ui: BattleUIController, p_turn: TurnHandler, p_context: BattleContext, p_parent: Node):
	combat_engine = p_combat
	visual_manager = p_visual
	ui_controller = p_ui
	turn_handler = p_turn
	context = p_context
	parent_node = p_parent

func handle_death(character: CharacterData) -> void:
	var death_msg = "%s has been defeated!" % character.name
	ui_controller.add_combat_log(death_msg, "red")
	
	if visual_manager:
		visual_manager.play_death_animation(character)
		visual_manager.shake_on_death()
	
	turn_handler.remove_character(character)
	
	await _get_tree_timer(1.5)

func handle_deaths(dead_characters: Array[CharacterData]) -> bool:
	for dead in dead_characters:
		combat_engine.check_death_after_action(dead)
		
		if visual_manager:
			visual_manager.play_death_animation(dead)
			visual_manager.shake_on_death()
		
		if dead == context.player:
			print("BattleFlowController: Player died")
		else:
			print("BattleFlowController: %s died" % dead.name)
	
	return await check_battle_end()

func check_battle_end() -> bool:
	if not context.is_battle_ended():
		return false
	
	if context.did_player_win():
		await _handle_victory()
	else:
		await _handle_defeat()
	
	return true

# === VICTORY/DEFEAT ===

func _handle_victory() -> void:
	print("BattleFlowController: Player victory!")
	ui_controller.disable_actions()
	
	if context.is_pvp_mode:
		# Would handle PvP victory
		return
	
	var total_xp = _calculate_xp_reward()
	
	await _get_tree_timer(1.0)
	await _show_battle_complete_dialog(total_xp)

func _handle_defeat() -> void:
	print("BattleFlowController: Player defeated!")
	ui_controller.disable_actions()
	
	if context.is_pvp_mode:
		# Would handle PvP defeat
		return
	
	await _get_tree_timer(1.0)
	emit_signal("battle_ended", false, 0)

func _calculate_xp_reward() -> int:
	var total_xp = 0
	for enemy in context.enemies:
		total_xp += enemy.level * 50 * context.current_floor
	return total_xp

func _show_battle_complete_dialog(xp_gained: int) -> void:
	var dialog_scene = load("res://scenes/BattleCompleteDialog.tscn")
	if not dialog_scene:
		emit_signal("battle_ended", true, xp_gained)
		return
	
	ui_controller._force_ui_invisible()
	
	var dialog = dialog_scene.instantiate()
	parent_node.add_child(dialog)
	
	dialog.show_dialog(context.player, xp_gained)
	
	dialog.press_on_selected.connect(func(): _on_press_on(xp_gained))
	dialog.take_breather_selected.connect(func(): _on_take_breather(xp_gained))

func _on_press_on(xp_gained: int) -> void:
	print("BattleFlowController: Press on selected")
	MomentumSystem.gain_momentum()
	
	var level_before = context.player.level
	context.player.gain_xp(xp_gained)
	
	if context.player.level > level_before:
		await _show_level_up_overlay()
	
	SaveManager.save_game(context.player)
	emit_signal("battle_ended", true, -1)

func _on_take_breather(xp_gained: int) -> void:
	var momentum_before = MomentumSystem.get_momentum()
	var had_bonus = momentum_before >= 3
	
	MomentumSystem.reset_momentum()
	
	if had_bonus:
		context.player.set_meta("taking_breather_with_bonus", true)
		context.player.set_meta("momentum_level_at_breather", momentum_before)
		context.player.status_effects.clear()
	
	emit_signal("battle_ended", true, xp_gained)

func _show_level_up_overlay() -> void:
	var level_up_scene = load("res://scenes/LevelUpScene.tscn").instantiate()
	parent_node.add_child(level_up_scene)
	level_up_scene.setup(context.player)
	await level_up_scene.level_up_complete
	level_up_scene.queue_free()

func _get_tree_timer(seconds: float):
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(seconds).timeout
