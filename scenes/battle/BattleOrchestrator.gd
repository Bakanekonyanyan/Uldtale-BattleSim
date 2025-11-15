# res://scenes/battle/BattleOrchestrator.gd
# Main battle controller - coordinates all battle systems
# Replaces old Battle.gd with cleaner architecture

extends Node
#class_name BattleOrchestrator

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
var item_action_used: bool = false

func _ready():
	"""Get UI controller reference"""
	ui_controller = get_node_or_null("BattleUIController")
	if not ui_controller:
		push_error("BattleOrchestrator: BattleUIController not found!")
		return
	
	print("BattleOrchestrator: Ready")

func start_battle():
	"""Initialize and start the battle"""
	if not _validate_setup():
		return
	
	print("BattleOrchestrator: Starting battle - %s vs %s" % [player.name, enemy.name])
	
	# Initialize systems
	combat_engine = CombatEngine.new()
	combat_engine.initialize(player, enemy)
	
	turn_controller = TurnController.new()
	add_child(turn_controller)
	turn_controller.initialize(player, enemy)
	
	enemy_ai = EnemyAI.new()
	enemy_ai.initialize(enemy, player, current_floor)
	
	# Connect signals
	turn_controller.turn_started.connect(_on_turn_started)
	turn_controller.turn_ended.connect(_on_turn_ended)
	turn_controller.turn_skipped.connect(_on_turn_skipped)
	
	# ✅ Initialize UI and force immediate update
	if ui_controller:
		ui_controller.initialize(player, enemy)
		ui_controller.action_selected.connect(_on_action_selected)
		
		# ✅ CRITICAL: Force immediate character info update
		ui_controller.update_character_info(player, enemy)
		ui_controller.update_xp_display()
		ui_controller.update_debug_display()
		
		print("BattleOrchestrator: UI initialized with character data")
	else:
		push_error("BattleOrchestrator: ui_controller is null!")
		return
	
	# Initialize resources
	_initialize_resources()
	
	# ✅ Now safe to start turn sequence (scene is already deferred)
	turn_controller.start_first_turn()

func _validate_setup() -> bool:
	"""Ensure all required data is set"""
	if not player or not enemy:
		push_error("BattleOrchestrator: Missing player or enemy")
		return false
	
	if not ui_controller:
		push_error("BattleOrchestrator: Missing UI controller")
		return false
	
	return true

func _initialize_resources():
	"""Ensure characters have resources"""
	if player.current_sp == 0:
		player.current_sp = player.max_sp
	if enemy.current_sp == 0:
		enemy.current_sp = enemy.max_sp

# === TURN FLOW ===

func _on_turn_started(character: CharacterData, is_player: bool):
	"""Handle start of turn"""
	print("BattleOrchestrator: Turn started - %s" % character.name)
	
	# ✅ FIX: Update UI immediately for both player and enemy
	if ui_controller:
		ui_controller.update_character_info(player, enemy)
	
	# Reset item action for player
	if is_player:
		item_action_used = false
	
	# Process status effects
	var status_message = combat_engine.process_status_effects(character)
	if status_message:
		ui_controller.add_combat_log(status_message, "purple")
		# ✅ Update UI again after status effects
		ui_controller.update_character_info(player, enemy)
		await get_tree().create_timer(1.0).timeout
	
	# Check if character died from status
	if not combat_engine.is_alive(character):
		_handle_death(character)
		return
	
	# Check if stunned
	if character.is_stunned:
		var stun_msg = "%s is stunned and loses their turn!" % character.name
		turn_controller.skip_turn(character, "stunned")
		ui_controller.add_combat_log(stun_msg, "purple")
		character.is_stunned = false
		await get_tree().create_timer(1.0).timeout
		return
	
	# Advance to action phase
	turn_controller.advance_phase()
	
	# Setup for action
	if is_player:
		_setup_player_turn()
	else:
		_execute_enemy_turn()

func _on_turn_ended(character: CharacterData):
	"""Handle end of turn"""
	print("BattleOrchestrator: Turn ended - %s" % character.name)
	ui_controller.disable_actions()

func _on_turn_skipped(character: CharacterData, reason: String):
	"""Handle skipped turn"""
	print("BattleOrchestrator: Turn skipped - %s (%s)" % [character.name, reason])

# === PLAYER TURN ===

func _setup_player_turn():
	"""Setup player's turn"""
	print("BattleOrchestrator: Player's turn")
	
	# ✅ FIX: Unlock UI when player's turn starts
	ui_controller.unlock_ui()
	
	ui_controller.setup_player_actions(item_action_used)
	ui_controller.enable_actions()

func _on_action_selected(action: BattleAction):
	"""Handle player action selection"""
	print("BattleOrchestrator: Action selected - %s" % action.get_description())
	
	# ✅ UI already locked by button press in BattleUIController
	
	# Special handling for item actions (bonus action)
	if action.type == BattleAction.ActionType.ITEM:
		_execute_item_action(action)
		return
	
	# Regular actions end the turn
	_execute_action(action, true)

func _execute_item_action(action: BattleAction):
	"""Execute item as bonus action"""
	print("BattleOrchestrator: Executing item as bonus action")
	
	# ✅ UI already locked by button press
	
	var result = combat_engine.execute_action(action)
	ui_controller.display_result(result)
	
	# Brief pause for feedback
	await get_tree().create_timer(0.5).timeout
	
	# Mark item action used
	item_action_used = true
	print("BattleOrchestrator: Item action used - player can still take main action")
	
	# Check for battle end
	if _check_battle_end():
		return
	
	# Refresh actions to show item used
	ui_controller.setup_player_actions(item_action_used)
	
	# ✅ FIX: Unlock UI so player can take main action
	ui_controller.unlock_ui()
	ui_controller.enable_actions()

# === ENEMY TURN ===

func _execute_enemy_turn():
	"""Execute enemy's turn"""
	print("BattleOrchestrator: Enemy's turn")
	ui_controller.add_combat_log("Enemy's turn", "red")
	await get_tree().create_timer(1.0).timeout
	
	# Check if enemy is still alive
	if not combat_engine.is_alive(enemy):
		_check_battle_end()
		return
	
	# AI decides action
	var action = enemy_ai.decide_action()
	
	# Execute action
	_execute_action(action, false)

# === ACTION EXECUTION ===

func _execute_action(action: BattleAction, is_player: bool):
	"""Execute any action"""
	print("BattleOrchestrator: Executing action - %s" % action.get_description())
	
	# ✅ UI already locked if player action (by button press)
	
	var result = combat_engine.execute_action(action)
	
	# Display result
	ui_controller.display_result(result)
	
	# Show level-up message if any
	if result.has_level_up():
		ui_controller.add_combat_log(result.level_up_message, "cyan")
	
	# Wait for animation/display
	await get_tree().create_timer(1.5).timeout
	
	# Check for battle end
	if _check_battle_end():
		# ✅ Battle over - don't unlock
		return
	
	# End turn (next turn will unlock/enable)
	turn_controller.end_current_turn()

# === BATTLE END ===

func _handle_death(character: CharacterData):
	"""Handle character death"""
	var death_msg = "%s has been defeated!" % character.name
	ui_controller.add_combat_log(death_msg, "red")
	await get_tree().create_timer(1.5).timeout
	_check_battle_end()

func _check_battle_end() -> bool:
	"""Check if battle has ended"""
	var outcome = combat_engine.check_battle_end()
	
	if outcome == "victory":
		_handle_victory()
		return true
	elif outcome == "defeat":
		_handle_defeat()
		return true
	
	return false

func _handle_victory():
	"""Handle player victory"""
	print("BattleOrchestrator: Player victory!")
	ui_controller.disable_actions()
	
	var xp = enemy.level * 50 * current_floor
	await get_tree().create_timer(1.0).timeout
	
	# Show battle complete dialog
	_show_battle_complete_dialog(xp)

func _handle_defeat():
	"""Handle player defeat"""
	print("BattleOrchestrator: Player defeated!")
	ui_controller.disable_actions()
	await get_tree().create_timer(1.0).timeout
	emit_signal("battle_completed", false, 0)

func _show_battle_complete_dialog(xp_gained: int):
	"""Show momentum choice dialog"""
	var dialog_scene = load("res://scenes/BattleCompleteDialog.tscn")
	if not dialog_scene:
		emit_signal("battle_completed", true, xp_gained)
		return
	
	var dialog = dialog_scene.instantiate()
	add_child(dialog)
	
	dialog.show_dialog(player, xp_gained)
	
	# Connect with proper callable binding
	dialog.press_on_selected.connect(func(): _on_press_on_selected(xp_gained))
	dialog.take_breather_selected.connect(func(): _on_take_breather_selected(xp_gained))

func _on_press_on_selected(xp_gained: int):
	"""Player chose momentum"""
	print("BattleOrchestrator: Press on selected")
	MomentumSystem.gain_momentum()
	
	var level_before = player.level
	player.gain_xp(xp_gained)
	
	if player.level > level_before:
		await _show_level_up_overlay()
	
	SaveManager.save_game(player)
	emit_signal("battle_completed", true, -1)

func _on_take_breather_selected(xp_gained: int):
	"""Player chose rest"""
	print("BattleOrchestrator: Take breather selected")
	MomentumSystem.reset_momentum()
	emit_signal("battle_completed", true, xp_gained)

func _show_level_up_overlay():
	"""Show level-up UI"""
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
	
	if ui_controller:
		ui_controller.update_dungeon_info(wave, floor, description)
	
	# ✅ FIX: Don't call start_battle immediately - wait for scene to be fully ready
	# Use call_deferred to ensure UI is completely initialized
	call_deferred("_deferred_start_battle")

func _deferred_start_battle():
	"""Start battle after scene is fully ready"""
	# Wait one additional frame to ensure UI rendering is complete
	await get_tree().process_frame
	start_battle()
