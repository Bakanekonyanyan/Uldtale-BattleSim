# res://scenes/battle/flow/BattleOutcomeHandler.gd
# Deaths and the end of the battle:
#
#   handle_deaths()    - log, animate and remove fallen combatants
#   check_battle_end() - if one side is wiped out, run victory/defeat ONCE
#
# Victory (PvE) shows the Press On / Take a Breather dialog, then emits
# `battle_ended`, which BattleOrchestrator re-emits as `battle_completed`
# for SceneManager. PvP results are handed to BattleNetworkSync.

class_name BattleOutcomeHandler
extends RefCounted

## xp_gained == -1 means "Press On" (SceneManager continues the dungeon run).
signal battle_ended(player_won: bool, xp_gained: int)

var combat_engine: CombatEngine
var visual_manager: BattleVisualManager
var ui_controller: BattleUIController
var turn_queue: TurnQueue
var context: BattleContext
var parent_node: Node  # where dialogs are added
var network_sync: BattleNetworkSync  # PvP only, may be null

func initialize(p_combat: CombatEngine, p_visual: BattleVisualManager, p_ui: BattleUIController, p_queue: TurnQueue, p_context: BattleContext, p_parent: Node, p_network: BattleNetworkSync = null) -> void:
	combat_engine = p_combat
	visual_manager = p_visual
	ui_controller = p_ui
	turn_queue = p_queue
	context = p_context
	parent_node = p_parent
	network_sync = p_network

# === DEATHS ===

func handle_deaths(dead_characters: Array[CharacterData]) -> void:
	if dead_characters.is_empty():
		return

	for dead in dead_characters:
		combat_engine.check_death_after_action(dead)  # clamps HP to 0
		if context.is_hero(dead):
			ui_controller.add_combat_log("%s is knocked out!" % dead.name, "orange")
			if not context.is_pvp_mode:
				PartyManager.on_hero_knocked_out(dead)
		else:
			ui_controller.add_combat_log("%s has been defeated!" % dead.name, "red")
		if visual_manager:
			visual_manager.play_death_animation(dead)
		turn_queue.remove(dead)
		# Tell town systems (Guild bounties, later quests). PvE only.
		if dead in context.enemies and not context.is_pvp_mode:
			GameEvents.enemy_killed.emit(dead, DungeonStateManager.current_location,
				context.current_floor, dead.character_class.begins_with("King"))

	if visual_manager:
		visual_manager.shake_on_death()

	ui_controller.update_all_character_info()
	await _wait(1.5)

# === BATTLE END ===

## Returns true if the battle is over (now or previously). Safe to call often.
func check_battle_end() -> bool:
	if context.battle_over:
		return true
	if not context.is_battle_decided():
		return false

	context.battle_over = true
	ui_controller.disable_actions()

	if context.did_player_win():
		await _handle_victory()
	else:
		await _handle_defeat()
	return true

func _handle_victory() -> void:
	Log.debug("battle", "BattleOutcomeHandler: Player victory!")

	if context.is_pvp_mode:
		if network_sync:
			network_sync.on_battle_end(true)
		return

	if parent_node.has_method("finish_encounter"):
		parent_node.finish_encounter(true)
	var total_xp = _calculate_xp_reward()
	# Knocked-out heroes get back up after a won fight (injured: PartyManager)
	for h in context.get_heroes():
		if not h.is_alive():
			h.current_hp = max(1, int(h.max_hp * 0.1))
			ui_controller.add_combat_log("%s gets back on their feet." % h.name, "orange")
	await _wait(1.0)
	if context.is_boss_battle and DungeonStateManager.dungeon_active:
		var offer = BoonPicker.offer()
		if not offer.is_empty():
			ui_controller.hide_battle_ui()
			var picker = BoonPicker.open(parent_node, offer)
			var boon_id = await picker.chosen
			ui_controller.add_combat_log("Boon gained: %s" % RunState.all_boons().get(boon_id, {}).get("name", boon_id), "lime")
	_show_battle_complete_dialog(total_xp)

func _handle_defeat() -> void:
	Log.debug("battle", "BattleOutcomeHandler: Player defeated!")

	if context.is_pvp_mode:
		if network_sync:
			network_sync.on_battle_end(false)
		return

	if parent_node.has_method("finish_encounter"):
		parent_node.finish_encounter(false)
	await _wait(1.0)
	battle_ended.emit(false, 0)

func _calculate_xp_reward() -> int:
	var total_xp = 0
	for enemy in context.enemies:
		total_xp += enemy.level * 50 * context.current_floor
	return total_xp

# === POST-BATTLE DIALOG (PvE) ===

func _show_battle_complete_dialog(xp_gained: int) -> void:
	var dialog_scene = load("res://scenes/BattleCompleteDialog.tscn")
	if not dialog_scene:
		battle_ended.emit(true, xp_gained)
		return

	ui_controller.hide_battle_ui()

	var dialog = dialog_scene.instantiate()
	parent_node.add_child(dialog)
	dialog.show_dialog(context.player, xp_gained, context.allies)
	dialog.press_on_selected.connect(func(): _on_press_on(xp_gained), CONNECT_ONE_SHOT)
	dialog.take_breather_selected.connect(func(): _on_take_breather(xp_gained), CONNECT_ONE_SHOT)

func _on_press_on(xp_gained: int) -> void:
	Log.debug("battle", "BattleOutcomeHandler: Press on selected")
	MomentumSystem.gain_momentum()

	var level_before = context.player.level
	context.player.gain_xp(xp_gained)
	if context.player.level > level_before:
		await _show_level_up_overlay()

	SaveManager.save_game(context.player)
	battle_ended.emit(true, -1)

func _on_take_breather(xp_gained: int) -> void:
	# Momentum is reset by SceneManager AFTER the Breather payout is calculated
	var momentum_before = MomentumSystem.get_momentum()

	if momentum_before >= 3:
		context.player.set_meta("taking_breather_with_bonus", true)
		context.player.set_meta("momentum_level_at_breather", momentum_before)
		# `player.status_effects` returns a COPY, so clearing it did nothing.
		if context.player.status_manager:
			context.player.status_manager.clear_all_effects()

	battle_ended.emit(true, xp_gained)

func _show_level_up_overlay() -> void:
	var level_up_scene = load("res://scenes/LevelUpScene.tscn").instantiate()
	parent_node.add_child(level_up_scene)
	level_up_scene.setup(context.player)
	await level_up_scene.level_up_complete
	level_up_scene.queue_free()

func _wait(seconds: float) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(seconds).timeout
