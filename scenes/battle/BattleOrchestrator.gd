# res://scenes/battle/BattleOrchestrator.gd
# REFACTORED: Thin coordinator using component-based architecture
# Delegates responsibilities to specialized handlers

extends Node

signal battle_completed(player_won: bool, xp_gained: int)

# Core systems (unchanged)
var combat_engine: CombatEngine
var turn_controller: TurnController
var enemy_ai_controllers: Array[EnemyAI] = []
var ui_controller: BattleUIController
var visual_manager: BattleVisualManager
var network_sync: BattleNetworkSync

# NEW: Component handlers
var context: BattleContext
var action_handler: ActionHandler
var turn_handler: TurnHandler
var flow_controller: BattleFlowController

func _ready():
	ui_controller = get_node_or_null("BattleUIController")
	if not ui_controller:
		push_error("BattleOrchestrator: BattleUIController not found!")
		return
	
	visual_manager = get_node_or_null("BattleVisualManager")
	if not visual_manager:
		push_error("BattleOrchestrator: BattleVisualManager not found!")
		return
	
	_initialize_visual_manager()
	
	print("BattleOrchestrator: Ready")

func _initialize_visual_manager():
	var camera = get_node_or_null("Camera2D")
	var player_container = visual_manager.get_node_or_null("PlayerSpriteContainer")
	var enemy_container = visual_manager.get_node_or_null("EnemySpriteContainer")
	
	if camera and player_container and enemy_container:
		visual_manager.initialize(camera, player_container, enemy_container)

# === BATTLE START ===

func start_battle():
	if context.battle_started:
		print("BattleOrchestrator: Battle already started")
		return
	context.battle_started = true
	
	if not _validate_setup():
		context.battle_started = false
		return
	
	print("BattleOrchestrator: Starting battle - %s vs %d enemies" % [
		context.player.name, context.enemies.size()
	])
	
	_initialize_systems()
	_connect_signals()
	_initialize_ui()
	_initialize_visuals()
	_initialize_resources()
	
	await _wait_for_ui_ready()
	
	ui_controller.setup_player_actions(false, false)
	ui_controller.disable_actions()
	
	print("BattleOrchestrator: Battle initialized")
	turn_controller.start_first_turn()

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

func _initialize_systems():
	# Core systems
	combat_engine = CombatEngine.new()
	combat_engine.initialize_multi(context.player, context.enemies)
	
	turn_controller = TurnController.new()
	add_child(turn_controller)
	turn_controller.initialize(context.player, context.enemies)
	
	if context.is_pvp_mode:
		turn_controller.set_pvp_mode(true)
	
	# Display initiative order
	var all_combatants = [context.player] + context.enemies
	all_combatants.sort_custom(func(a, b): return a.agility > b.agility)
	
	var init_msg = "Initiative order: "
	for i in range(all_combatants.size()):
		init_msg += "%s (AGI: %.1f)" % [all_combatants[i].name, all_combatants[i].agility]
		if i < all_combatants.size() - 1:
			init_msg += " → "
	
	ui_controller.add_combat_log(init_msg, "cyan")
	
	# Initialize AI for enemies
	if not context.is_pvp_mode:
		_initialize_enemy_ai()
	
	# NEW: Component handlers
	action_handler = ActionHandler.new()
	action_handler.initialize(combat_engine, visual_manager, ui_controller, context)
	
	turn_handler = TurnHandler.new()
	turn_handler.initialize(turn_controller, combat_engine, visual_manager, ui_controller, context)
	
	flow_controller = BattleFlowController.new()
	flow_controller.initialize(combat_engine, visual_manager, ui_controller, turn_handler, context, self)

func _connect_signals():
	turn_controller.turn_started.connect(_on_turn_started)
	turn_controller.turn_ended.connect(_on_turn_ended)
	turn_controller.turn_skipped.connect(_on_turn_skipped)
	
	ui_controller.action_selected.connect(_on_action_selected)
	
	# NEW: Handler signals
	turn_handler.turn_ready_for_action.connect(_on_turn_ready_for_action)
	turn_handler.turn_skipped_death.connect(_on_turn_skipped_death)
	turn_handler.turn_skipped_stun.connect(_on_turn_skipped_stun)
	
	action_handler.action_executed.connect(_on_action_executed)
	action_handler.deaths_occurred.connect(_on_deaths_occurred)
	
	flow_controller.battle_ended.connect(func(won, xp): emit_signal("battle_completed", won, xp))

func _initialize_ui():
	ui_controller.initialize_multi(context.player, context.enemies)
	ui_controller.update_all_character_info()
	ui_controller.update_xp_display()
	ui_controller.update_debug_display()
	
	if context.is_pvp_mode:
		ui_controller.hide_dungeon_info()
	else:
		ui_controller.update_dungeon_info(
			context.current_wave,
			context.current_floor,
			context.dungeon_description
		)

func _initialize_visuals():
	if visual_manager:
		visual_manager.setup_player_sprite(context.player)
		visual_manager.setup_enemy_sprites(context.enemies)

func _initialize_enemy_ai():
	enemy_ai_controllers.clear()
	
	for enemy in context.enemies:
		var ai: EnemyAI
		
		if context.is_boss_battle and "King" in enemy.character_class:
			ai = BossAI.new()
		else:
			ai = EnemyAI.new()
		
		ai.initialize(enemy, context.player, context.current_floor)
		enemy_ai_controllers.append(ai)
	
	print("BattleOrchestrator: Initialized %d AI controllers" % enemy_ai_controllers.size())

func _initialize_resources():
	if context.player.current_sp == 0:
		context.player.current_sp = context.player.max_sp
	
	for enemy in context.enemies:
		if enemy.current_sp == 0:
			enemy.current_sp = enemy.max_sp

func _wait_for_ui_ready():
	await get_tree().process_frame
	await get_tree().process_frame
	
	ui_controller.update_all_character_info()
	ui_controller.update_turn_display("Battle starting...")

# === TURN FLOW (Simplified) ===

func _on_turn_started(character: CharacterData, is_player_turn: bool):
	print("BattleOrchestrator: Turn started - %s" % character.name)
	
	if await flow_controller.check_battle_end():
		return
	
	# Delegate to turn handler
	await turn_handler.start_turn(character, is_player_turn)

func _on_turn_ready_for_action(character: CharacterData, is_player: bool):
	if is_player:
		_setup_player_turn()
	else:
		await _execute_enemy_turn(character)

func _on_turn_skipped_death(character: CharacterData):
	await flow_controller.handle_death(character)
	if await flow_controller.check_battle_end():
		return
	turn_handler.end_turn()

func _on_turn_skipped_stun(character: CharacterData):
	if await flow_controller.check_battle_end():
		return
	turn_handler.end_turn()

func _on_turn_ended(character: CharacterData):
	print("BattleOrchestrator: Turn ended - %s" % character.name)
	ui_controller.disable_actions()

func _on_turn_skipped(character: CharacterData, reason: String):
	print("BattleOrchestrator: Turn skipped - %s (%s)" % [character.name, reason])

# === PLAYER TURN ===

func _setup_player_turn():
	print("BattleOrchestrator: Player's turn")
	ui_controller.setup_player_actions(context.item_action_used, context.main_action_taken)
	ui_controller.unlock_ui()
	ui_controller.enable_actions()

func _on_action_selected(action: BattleAction):
	print("BattleOrchestrator: Action selected - %s" % action.get_description())
	
	# Item actions
	if action.type == BattleAction.ActionType.ITEM:
		if context.item_action_used:
			ui_controller.add_combat_log("You've already used an item!", "red")
			ui_controller.unlock_ui()
			ui_controller.enable_actions()
			return
		
		ui_controller.disable_actions()
		await action_handler.execute_item_action(action)
		
		if await flow_controller.check_battle_end():
			return
		
		ui_controller.setup_player_actions(context.item_action_used, context.main_action_taken)
		ui_controller.unlock_ui()
		ui_controller.enable_actions()
		return
	
	# Main actions
	if action.type in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL, BattleAction.ActionType.DEFEND]:
		if context.main_action_taken:
			ui_controller.add_combat_log("You've already taken your action!", "red")
			ui_controller.unlock_ui()
			ui_controller.enable_actions()
			return
		
		# Validate target
		if action.type in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL]:
			if not action.target and (not action.targets or action.targets.is_empty()):
				ui_controller.add_combat_log("Error: No target", "red")
				ui_controller.unlock_ui()
				ui_controller.enable_actions()
				return
			
			if action.target and not action.target.is_alive():
				ui_controller.add_combat_log("Target already defeated!", "red")
				ui_controller.unlock_ui()
				ui_controller.enable_actions()
				return
		
		ui_controller.disable_actions()
		await action_handler.execute_main_action(action, true)

func _on_action_executed(action: BattleAction, result: ActionResult):
	# Action handler already updated UI, just track state
	pass

func _on_deaths_occurred(dead_characters: Array[CharacterData]):
	if dead_characters.is_empty():
		# No deaths, just end turn
		turn_handler.end_turn()
		return
	
	# Handle deaths
	var battle_ended = await flow_controller.handle_deaths(dead_characters)
	if battle_ended:
		return
	turn_handler.end_turn()

# === ENEMY TURN ===

func _execute_enemy_turn(enemy_character: CharacterData):
	if not combat_engine.is_alive(enemy_character):
		print("BattleOrchestrator: %s is dead, skipping" % enemy_character.name)
		turn_handler.end_turn()
		return
	
	print("BattleOrchestrator: %s's turn" % enemy_character.name)
	
	if context.is_pvp_mode:
		ui_controller.add_combat_log("Opponent's turn", "red")
		ui_controller.update_turn_display("Waiting for opponent...")
		return
	
	ui_controller.add_combat_log("%s's turn" % enemy_character.name, "red")
	ui_controller.update_turn_display("%s is acting..." % enemy_character.name)
	
	await get_tree().create_timer(1.0).timeout
	
	if not combat_engine.is_alive(enemy_character):
		print("BattleOrchestrator: %s died during delay" % enemy_character.name)
		await flow_controller.check_battle_end()
		return
	
	var ai_controller = _get_ai_for_enemy(enemy_character)
	if not ai_controller:
		push_error("BattleOrchestrator: No AI for %s" % enemy_character.name)
		turn_handler.end_turn()
		return
	
	if not combat_engine.is_alive(context.player):
		print("BattleOrchestrator: Player dead, ending enemy turn")
		await flow_controller.check_battle_end()
		return
	
	var action = ai_controller.decide_action()
	
	if not action:
		push_error("BattleOrchestrator: AI returned null action")
		turn_handler.end_turn()
		return
	
	# Validate target
	if action.type in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL]:
		if not action.target and (not action.targets or action.targets.is_empty()):
			action.target = context.player
			action.targets.clear()
			action.targets.append(context.player)
		
		if action.target and not action.target.is_alive():
			print("BattleOrchestrator: Enemy target died, skipping")
			turn_handler.end_turn()
			return
	
	await action_handler.execute_main_action(action, false)

func _get_ai_for_enemy(enemy_character: CharacterData) -> EnemyAI:
	for i in range(context.enemies.size()):
		if context.enemies[i] == enemy_character and i < enemy_ai_controllers.size():
			return enemy_ai_controllers[i]
	return null

# === SETUP (public API) ===

func set_player(character: CharacterData):
	if not context:
		context = BattleContext.new()
	context.player = character

func set_enemies(enemy_list: Array[CharacterData]):
	if not context:
		context = BattleContext.new()
	context.enemies = enemy_list
	
	for enemy in context.enemies:
		enemy.calculate_secondary_attributes()
		if enemy.current_sp == 0:
			enemy.current_sp = enemy.max_sp

func set_enemy(new_enemy: CharacterData):
	set_enemies([new_enemy])

func set_dungeon_info(boss_fight: bool, wave: int, floor: int, _max_floor: int, description: String):
	if not context:
		context = BattleContext.new()
	
	context.set_dungeon_info(boss_fight, wave, floor, _max_floor, description)
	call_deferred("_deferred_start_battle")

func _deferred_start_battle():
	await get_tree().process_frame
	await get_tree().process_frame
	start_battle()

func setup_pvp_battle(local_player: CharacterData, remote_opponent: CharacterData):
	if not context:
		context = BattleContext.new()
	
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
