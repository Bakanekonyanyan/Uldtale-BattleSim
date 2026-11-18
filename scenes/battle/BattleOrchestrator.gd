# res://scenes/battle/BattleOrchestrator.gd
# Root script of Battle.tscn. Builds the battle components and runs the turn loop.
#
# The whole fight reads top-to-bottom in _run_battle_loop() / _run_turn():
#
#   loop until battle_over:
#       actor = turn_queue.current_actor()
#       TurnStartProcessor.run(actor)        -> CAN_ACT / STUNNED / DIED
#       player  -> wait for UI action  -> ActionExecutor.execute()
#       enemy   -> EnemyTurnPlanner     -> ActionExecutor.execute()
#       remote  -> wait for BattleNetworkSync (PvP)
#       BattleOutcomeHandler.handle_deaths() / check_battle_end()
#       turn_queue.advance()
#
# See scenes/battle/README.md for a map of every component.

extends Node

## Emitted for SceneManager. xp_gained == -1 means the player chose "Press On".
signal battle_completed(player_won: bool, xp_gained: int)

signal _player_turn_finished
signal _remote_turn_finished

# --- Scene nodes ---
var ui_controller: BattleUIController
var visual_manager: BattleVisualManager

# --- Components (created in start_battle) ---
var context: BattleContext
var combat_engine: CombatEngine
var turn_queue: TurnQueue
var turn_start: TurnStartProcessor
var action_executor: ActionExecutor
var enemy_planner: EnemyTurnPlanner
var outcome: BattleOutcomeHandler
var network_sync: BattleNetworkSync  # PvP only

# Player-input guards
var _awaiting_player_action: bool = false
var _action_in_progress: bool = false

# Read-only accessors used by BattleNetworkSync
var player: CharacterData:
	get: return context.player if context else null
var enemy: CharacterData:
	get: return context.enemies[0] if context and not context.enemies.is_empty() else null

func _ready():
	ui_controller = get_node_or_null("BattleUIController")
	visual_manager = get_node_or_null("BattleVisualManager")

	if not ui_controller:
		push_error("BattleOrchestrator: BattleUIController not found!")
		return
	if not visual_manager:
		push_error("BattleOrchestrator: BattleVisualManager not found!")
		return

	var camera = get_node_or_null("Camera2D")
	var player_container = visual_manager.get_node_or_null("PlayerSpriteContainer")
	var enemy_container = visual_manager.get_node_or_null("EnemySpriteContainer")
	if camera and player_container and enemy_container:
		visual_manager.initialize(camera, player_container, enemy_container)

	ui_controller.action_selected.connect(_on_player_action_selected)

# =============================================================
# PUBLIC SETUP API (called by SceneManager / ArenaLobby)
# =============================================================

func set_player(character: CharacterData) -> void:
	_ensure_context()
	context.player = character

func set_enemies(enemy_list: Array[CharacterData]) -> void:
	_ensure_context()
	context.enemies = enemy_list
	for e in context.enemies:
		e.calculate_secondary_attributes()

func set_enemy(new_enemy: CharacterData) -> void:
	set_enemies([new_enemy])

## Last setup call for PvE - starts the battle on the next frames.
func set_dungeon_info(boss_fight: bool, wave: int, floor_num: int, max_floor: int, description: String) -> void:
	_ensure_context()
	context.set_dungeon_info(boss_fight, wave, floor_num, max_floor, description)
	call_deferred("_deferred_start_battle")

func setup_pvp_battle(local_player: CharacterData, remote_opponent: CharacterData) -> void:
	_ensure_context()
	context.is_pvp_mode = true
	context.player = local_player
	context.enemies = [remote_opponent]

	local_player.reset_for_new_battle()
	remote_opponent.reset_for_new_battle()
	if not remote_opponent.elemental_resistances:
		remote_opponent.elemental_resistances = ElementalResistanceManager.new(remote_opponent)
	remote_opponent.calculate_secondary_attributes()

	context.set_dungeon_info(false, 1, 1, 1, "Arena PvP Battle")
	call_deferred("start_battle")

## Called by BattleNetworkSync when the opponent finished their main action.
func finish_remote_turn() -> void:
	_remote_turn_finished.emit()

## Called by BattleNetworkSync when the match was decided on the other client.
func end_battle_from_network() -> void:
	if context:
		context.battle_over = true
	_awaiting_player_action = false
	if ui_controller:
		ui_controller.disable_actions()
	_remote_turn_finished.emit()
	_player_turn_finished.emit()

func _ensure_context() -> void:
	if not context:
		context = BattleContext.new()

func _deferred_start_battle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	start_battle()

# =============================================================
# BATTLE START
# =============================================================

func start_battle() -> void:
	if not context or context.battle_started:
		return
	if not _validate_setup():
		return
	context.battle_started = true

	print("BattleOrchestrator: Starting battle - %s vs %d enemies%s" % [
		context.player.name, context.enemies.size(), " (PvP)" if context.is_pvp_mode else ""
	])

	_build_components()
	_initialize_resources()
	_initialize_ui()
	_initialize_visuals()

	await get_tree().process_frame
	await get_tree().process_frame

	ui_controller.update_all_character_info()
	ui_controller.update_turn_display("Battle starting...")
	ui_controller.add_combat_log("Initiative order: " + turn_queue.describe_order(), "cyan")
	ui_controller.setup_player_actions(false, false)
	ui_controller.disable_actions()

	_run_battle_loop()

func _validate_setup() -> bool:
	if not context.player:
		push_error("BattleOrchestrator: Missing player")
		return false
	if context.enemies.is_empty():
		push_error("BattleOrchestrator: No enemies")
		return false
	if not ui_controller:
		push_error("BattleOrchestrator: Missing UI")
		return false
	return true

func _build_components() -> void:
	combat_engine = CombatEngine.new()
	combat_engine.initialize_multi(context.player, context.enemies)

	turn_queue = TurnQueue.new()
	turn_queue.initialize(context.player, context.enemies)

	if context.is_pvp_mode:
		network_sync = BattleNetworkSync.new()
		network_sync.initialize(self, true)
	else:
		enemy_planner = EnemyTurnPlanner.new()
		enemy_planner.initialize(context)

	turn_start = TurnStartProcessor.new()
	turn_start.initialize(combat_engine, visual_manager, ui_controller, context, network_sync)

	action_executor = ActionExecutor.new()
	action_executor.initialize(combat_engine, visual_manager, ui_controller, context)

	outcome = BattleOutcomeHandler.new()
	outcome.initialize(combat_engine, visual_manager, ui_controller, turn_queue, context, self, network_sync)
	outcome.battle_ended.connect(func(won, xp): battle_completed.emit(won, xp))

func _initialize_resources() -> void:
	for c in [context.player] + context.enemies:
		if c.current_sp == 0:
			c.current_sp = c.max_sp

func _initialize_ui() -> void:
	ui_controller.initialize_multi(context.player, context.enemies)
	ui_controller.update_xp_display()
	ui_controller.update_debug_display()
	if context.is_pvp_mode:
		ui_controller.hide_dungeon_info()
	else:
		ui_controller.update_dungeon_info(context.current_wave, context.current_floor, context.dungeon_description)

func _initialize_visuals() -> void:
	if visual_manager:
		visual_manager.setup_player_sprite(context.player)
		visual_manager.setup_enemy_sprites(context.enemies)

# =============================================================
# TURN LOOP
# =============================================================

func _run_battle_loop() -> void:
	while not context.battle_over:
		var actor := turn_queue.current_actor()
		if actor == null:
			break

		await _run_turn(actor)

		if await outcome.check_battle_end():
			break
		turn_queue.advance()

	print("BattleOrchestrator: Battle loop finished")

func _run_turn(actor: CharacterData) -> void:
	var turn_no = turn_queue.begin_turn()
	var is_player_turn = turn_queue.is_player(actor)
	print("BattleOrchestrator: Turn %d - %s" % [turn_no, actor.name])

	if network_sync:
		network_sync.on_turn_started(actor, is_player_turn)

	var start_result: TurnStartProcessor.Result = await turn_start.run(actor)
	match start_result:
		TurnStartProcessor.Result.DIED:
			await outcome.handle_deaths([actor])
			return
		TurnStartProcessor.Result.STUNNED:
			return

	if context.battle_over:
		return

	if is_player_turn:
		await _run_player_turn()
	elif context.is_pvp_mode:
		await _run_remote_turn()
	else:
		await _run_enemy_turn(actor)

	ui_controller.disable_actions()

# --- Player ---

func _run_player_turn() -> void:
	context.reset_turn_state()
	_awaiting_player_action = true
	_present_player_actions()
	await _player_turn_finished
	_awaiting_player_action = false

func _present_player_actions() -> void:
	ui_controller.setup_player_actions(context.item_action_used, context.main_action_taken)
	ui_controller.unlock_ui()
	ui_controller.enable_actions()

func _on_player_action_selected(action: BattleAction) -> void:
	if not _awaiting_player_action or _action_in_progress or context.battle_over:
		return

	match action.type:
		BattleAction.ActionType.ITEM:
			await _handle_player_item(action)
		BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL, BattleAction.ActionType.DEFEND:
			await _handle_player_main_action(action)
		_:
			_present_player_actions()

## Items are a free action: they don't end the turn, but only one per turn.
func _handle_player_item(action: BattleAction) -> void:
	if context.item_action_used:
		ui_controller.add_combat_log("You've already used an item this turn!", "red")
		_present_player_actions()
		return

	_action_in_progress = true
	ui_controller.disable_actions()

	var result: ActionExecutor.Outcome = await action_executor.execute(action)
	context.item_action_used = true
	if network_sync:
		network_sync.on_action_selected(action, result.result)

	await outcome.handle_deaths(result.dead)
	_action_in_progress = false

	if context.is_battle_decided():
		_player_turn_finished.emit()  # loop runs the victory/defeat sequence
	else:
		_present_player_actions()

## Attack / Skill / Defend - ends the player's turn.
func _handle_player_main_action(action: BattleAction) -> void:
	if context.main_action_taken:
		ui_controller.add_combat_log("You've already taken your action!", "red")
		_present_player_actions()
		return

	if action.type != BattleAction.ActionType.DEFEND:
		var needs_target = not (action.skill_data and action.skill_data.target == Skill.TargetType.ALL_ALLIES)
		if needs_target and action.targets.is_empty():
			ui_controller.add_combat_log("Error: No target", "red")
			_present_player_actions()
			return
		if action.primary_target and not action.primary_target.is_alive():
			ui_controller.add_combat_log("Target already defeated!", "red")
			_present_player_actions()
			return

	_action_in_progress = true
	ui_controller.disable_actions()

	var result: ActionExecutor.Outcome = await action_executor.execute(action)
	context.main_action_taken = true
	if network_sync:
		network_sync.on_action_selected(action, result.result)

	await outcome.handle_deaths(result.dead)
	_action_in_progress = false
	_player_turn_finished.emit()

# --- Enemy (PvE) ---

func _run_enemy_turn(enemy_character: CharacterData) -> void:
	ui_controller.add_combat_log("%s's turn" % enemy_character.name, "red")
	ui_controller.update_turn_display("%s is acting..." % enemy_character.name)

	await get_tree().create_timer(1.0).timeout

	if not enemy_character.is_alive() or not context.player.is_alive():
		return

	var action = enemy_planner.plan_action(enemy_character)
	if not action:
		return

	var result: ActionExecutor.Outcome = await action_executor.execute(action, true)
	await outcome.handle_deaths(result.dead)

# --- Remote opponent (PvP) ---

func _run_remote_turn() -> void:
	ui_controller.add_combat_log("Opponent's turn", "red")
	ui_controller.update_turn_display("Waiting for opponent...")
	await _remote_turn_finished
