# res://scenes/battle/BattleOrchestrator.gd
extends Node

signal battle_completed(player_won: bool, xp_gained: int)

# Battle systems
var combat_engine: CombatEngine
var turn_controller: TurnController
var enemy_ai: EnemyAI
var ui_controller: BattleUIController

# Battle context
var player: CharacterData
var enemy: CharacterData
var is_boss_battle: bool = false
var current_wave: int
var current_floor: int
var dungeon_description: String

# ✅ FIX: Track both item and main action
var item_action_used: bool = false
var main_action_taken: bool = false

func _ready():
	ui_controller = get_node_or_null("BattleUIController")
	if not ui_controller:
		push_error("BattleOrchestrator: BattleUIController not found!")
		return
	
	print("BattleOrchestrator: Ready")

func start_battle():
	if not _validate_setup():
		return
	
	print("BattleOrchestrator: Starting battle - %s vs %s" % [player.name, enemy.name])
	
	# Initialize systems
	combat_engine = CombatEngine.new()
	combat_engine.initialize(player, enemy)
	
	turn_controller = TurnController.new()
	add_child(turn_controller)
	turn_controller.initialize(player, enemy)
	
	# ✅ NEW: Use BossAI for boss battles, regular AI for normal enemies
	if is_boss_battle:
		enemy_ai = BossAI.new()
		print("BattleOrchestrator: Using BOSS AI")
	else:
		enemy_ai = EnemyAI.new()
		print("BattleOrchestrator: Using regular AI")
	
	enemy_ai.initialize(enemy, player, current_floor)
	
	turn_controller.turn_started.connect(_on_turn_started)
	turn_controller.turn_ended.connect(_on_turn_ended)
	turn_controller.turn_skipped.connect(_on_turn_skipped)
	
	if ui_controller:
		ui_controller.initialize(player, enemy)
		ui_controller.action_selected.connect(_on_action_selected)
		
		ui_controller.update_character_info(player, enemy)
		ui_controller.update_xp_display()
		ui_controller.update_debug_display()
		ui_controller.update_dungeon_info(current_wave, current_floor, dungeon_description)
		
		print("BattleOrchestrator: UI initialized and updated")
	else:
		push_error("BattleOrchestrator: ui_controller is null!")
		return
	
	_initialize_resources()
	
	await _wait_for_ui_ready()
	
	ui_controller.setup_player_actions(false, false)
	ui_controller.disable_actions()
	
	turn_controller.start_first_turn()

func _wait_for_ui_ready():
	await get_tree().process_frame
	await get_tree().process_frame
	
	if ui_controller:
		ui_controller.update_character_info(player, enemy)
		ui_controller.update_turn_display("Battle starting...")
	
	print("BattleOrchestrator: UI ready, starting combat")

func _validate_setup() -> bool:
	if not player or not enemy:
		push_error("BattleOrchestrator: Missing player or enemy")
		return false
	
	if not ui_controller:
		push_error("BattleOrchestrator: Missing UI controller")
		return false
	
	return true

func _initialize_resources():
	if player.current_sp == 0:
		player.current_sp = player.max_sp
	if enemy.current_sp == 0:
		enemy.current_sp = enemy.max_sp

# === TURN FLOW ===

func _on_turn_started(character: CharacterData, is_player: bool):
	print("BattleOrchestrator: Turn started - %s" % character.name)
	
	if ui_controller:
		ui_controller.update_character_info(player, enemy)
		ui_controller.update_turn_display("%s's turn" % character.name)
	
	# ✅ FIX: Reset BOTH action flags at turn start
	if is_player:
		item_action_used = false
		main_action_taken = false
		print("BattleOrchestrator: Reset action flags for player turn")
	
	var status_message = combat_engine.process_status_effects(character)
	if status_message:
		ui_controller.add_combat_log(status_message, "purple")
		ui_controller.update_character_info(player, enemy)
		await get_tree().create_timer(1.0).timeout
	
	if not combat_engine.is_alive(character):
		_handle_death(character)
		return
	
	if character.is_stunned:
		var stun_msg = "%s is stunned and loses their turn!" % character.name
		turn_controller.skip_turn(character, "stunned")
		ui_controller.add_combat_log(stun_msg, "purple")
		character.is_stunned = false
		await get_tree().create_timer(1.0).timeout
		return
	
	turn_controller.advance_phase()
	
	if is_player:
		_setup_player_turn()
	else:
		_execute_enemy_turn()

func _on_turn_ended(character: CharacterData):
	print("BattleOrchestrator: Turn ended - %s" % character.name)
	ui_controller.disable_actions()

func _on_turn_skipped(character: CharacterData, reason: String):
	print("BattleOrchestrator: Turn skipped - %s (%s)" % [character.name, reason])

# === PLAYER TURN ===

func _setup_player_turn():
	print("BattleOrchestrator: Player's turn")
	
	# ✅ FIX: Pass both flags to UI
	ui_controller.setup_player_actions(item_action_used, main_action_taken)
	ui_controller.unlock_ui()
	ui_controller.enable_actions()

func _on_action_selected(action: BattleAction):
	print("BattleOrchestrator: Action selected - %s" % action.get_description())
	
	# ✅ FIX: Handle item as bonus action
	if action.type == BattleAction.ActionType.ITEM:
		if item_action_used:
			ui_controller.add_combat_log("You've already used an item this turn!", "red")
			ui_controller.unlock_ui()
			ui_controller.enable_actions()
			return
		_execute_item_action(action)
		return
	
	# ✅ FIX: All other actions are "main actions"
	if main_action_taken:
		ui_controller.add_combat_log("You've already taken your main action!", "red")
		ui_controller.unlock_ui()
		ui_controller.enable_actions()
		return
	
	# Execute main action (ends turn)
	_execute_action(action, true)

func _execute_item_action(action: BattleAction):
	print("BattleOrchestrator: Executing item as bonus action")
	
	var result = combat_engine.execute_action(action)
	ui_controller.display_result(result)
	
	await get_tree().create_timer(0.5).timeout
	
	# ✅ FIX: Mark item used but NOT main action
	item_action_used = true
	print("BattleOrchestrator: Item used - player can still take main action")
	
	if _check_battle_end():
		return
	
	# ✅ FIX: Refresh UI with both flags
	ui_controller.setup_player_actions(item_action_used, main_action_taken)
	ui_controller.unlock_ui()
	ui_controller.enable_actions()

# === ENEMY TURN ===

func _execute_enemy_turn():
	print("BattleOrchestrator: Enemy's turn")
	
	ui_controller.add_combat_log("Enemy's turn", "red")
	ui_controller.update_turn_display("Enemy is acting...")
	
	await get_tree().create_timer(1.0).timeout
	
	if not combat_engine.is_alive(enemy):
		_check_battle_end()
		return
	
	var action = enemy_ai.decide_action()
	_execute_action(action, false)

# === ACTION EXECUTION ===

func _execute_action(action: BattleAction, is_player: bool):
	print("BattleOrchestrator: Executing action - %s" % action.get_description())
	
	var result = combat_engine.execute_action(action)
	
	ui_controller.display_result(result)
	
	if result.has_level_up():
		ui_controller.add_combat_log(result.level_up_message, "cyan")
	
	# ✅ FIX: Mark main action taken if player
	if is_player:
		main_action_taken = true
		print("BattleOrchestrator: Main action taken - turn ending")
	
	await get_tree().create_timer(1.5).timeout
	
	if _check_battle_end():
		return
	
	turn_controller.end_current_turn()

# === BATTLE END ===

func _handle_death(character: CharacterData):
	var death_msg = "%s has been defeated!" % character.name
	ui_controller.add_combat_log(death_msg, "red")
	await get_tree().create_timer(1.5).timeout
	_check_battle_end()

func _check_battle_end() -> bool:
	var outcome = combat_engine.check_battle_end()
	
	if outcome == "victory":
		_handle_victory()
		return true
	elif outcome == "defeat":
		_handle_defeat()
		return true
	
	return false

func _handle_victory():
	print("BattleOrchestrator: Player victory!")
	ui_controller.disable_actions()
	
	var xp = enemy.level * 50 * current_floor
	await get_tree().create_timer(1.0).timeout
	
	_show_battle_complete_dialog(xp)

func _handle_defeat():
	print("BattleOrchestrator: Player defeated!")
	ui_controller.disable_actions()
	await get_tree().create_timer(1.0).timeout
	emit_signal("battle_completed", false, 0)

func _show_battle_complete_dialog(xp_gained: int):
	var dialog_scene = load("res://scenes/BattleCompleteDialog.tscn")
	if not dialog_scene:
		emit_signal("battle_completed", true, xp_gained)
		return
	
	var dialog = dialog_scene.instantiate()
	add_child(dialog)
	
	dialog.show_dialog(player, xp_gained)
	
	dialog.press_on_selected.connect(func(): _on_press_on_selected(xp_gained))
	dialog.take_breather_selected.connect(func(): _on_take_breather_selected(xp_gained))

func _on_press_on_selected(xp_gained: int):
	print("BattleOrchestrator: Press on selected")
	MomentumSystem.gain_momentum()
	
	var level_before = player.level
	player.gain_xp(xp_gained)
	
	if player.level > level_before:
		await _show_level_up_overlay()
	
	SaveManager.save_game(player)
	emit_signal("battle_completed", true, -1)

func _on_take_breather_selected(xp_gained: int):
	print("BattleOrchestrator: Take breather selected")
	MomentumSystem.reset_momentum()
	emit_signal("battle_completed", true, xp_gained)

func _show_level_up_overlay():
	var level_up_scene = load("res://scenes/LevelUpScene.tscn").instantiate()
	add_child(level_up_scene)
	level_up_scene.setup(player)
	await level_up_scene.level_up_complete
	level_up_scene.queue_free()

# === SETUP (called from Battle.tscn) ===

func set_player(character: CharacterData):
	player = character

func set_enemy(new_enemy: CharacterData):
	enemy = new_enemy
	enemy.calculate_secondary_attributes()
	if enemy.current_sp == 0:
		enemy.current_sp = enemy.max_sp

func set_dungeon_info(wave: int, floor: int, description: String):
	current_wave = wave
	current_floor = floor
	dungeon_description = description
	
	call_deferred("_deferred_start_battle")

func _deferred_start_battle():
	await get_tree().process_frame
	await get_tree().process_frame
	start_battle()
