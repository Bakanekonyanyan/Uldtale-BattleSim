# res://scenes/battle/BattleOrchestrator.gd
# UPDATED: Integrated BattleVisualManager for sprites and effects

extends Node

signal battle_completed(player_won: bool, xp_gained: int)

var rand_manager = RandomManager 

# Battle systems
var combat_engine: CombatEngine
var turn_controller: TurnController
var enemy_ai_controllers: Array[EnemyAI] = []
var ui_controller: BattleUIController
var visual_manager: BattleVisualManager  # NEW
var network_sync: BattleNetworkSync
var is_pvp_mode := false
var battle_started := false

# Battle context
var player: CharacterData
var enemies: Array[CharacterData] = []
var is_boss_battle: bool = false
var current_wave: int
var current_floor: int
var max_floor: int
var dungeon_description: String
var item_action_used: bool = false
var main_action_taken: bool = false

func _ready():
	ui_controller = get_node_or_null("BattleUIController")
	if not ui_controller:
		push_error("BattleOrchestrator: BattleUIController not found!")
		return
	
	# NEW: Get visual manager reference
	visual_manager = get_node_or_null("BattleVisualManager")
	if not visual_manager:
		push_error("BattleOrchestrator: BattleVisualManager not found!")
		return
	
	# Initialize visual manager with camera and containers
	var camera = get_node_or_null("Camera2D")
	var player_container = visual_manager.get_node_or_null("PlayerSpriteContainer")
	var enemy_container = visual_manager.get_node_or_null("EnemySpriteContainer")
	
	if camera and player_container and enemy_container:
		visual_manager.initialize(camera, player_container, enemy_container)
	
	print("BattleOrchestrator: Ready")

func start_battle():
	if battle_started:
		print("BattleOrchestrator: Battle already started, ignoring duplicate call")
		return
	battle_started = true
	print("BattleOrchestrator: Battle start flag set - preventing duplicates")
	
	if not _validate_setup():
		battle_started = false
		return
	
	print("BattleOrchestrator: Starting battle - %s vs %d enemies (PvP: %s)" % [
		player.name, enemies.size(), is_pvp_mode
	])
	
	# Initialize systems
	combat_engine = CombatEngine.new()
	combat_engine.initialize_multi(player, enemies)
	
	turn_controller = TurnController.new()
	add_child(turn_controller)
	turn_controller.initialize(player, enemies)
	
	if is_pvp_mode:
		turn_controller.set_pvp_mode(true)
	
	# Calculate initiative display
	var all_combatants = [player] + enemies
	all_combatants.sort_custom(func(a, b): return a.agility > b.agility)
	
	var init_msg = "Initiative order: "
	for i in range(all_combatants.size()):
		init_msg += "%s (AGI: %.1f)" % [all_combatants[i].name, all_combatants[i].agility]
		if i < all_combatants.size() - 1:
			init_msg += " → "
	
	ui_controller.add_combat_log(init_msg, "cyan")
	
	# Initialize AI for each enemy (PvE only)
	if not is_pvp_mode:
		_initialize_enemy_ai()
	
	if is_pvp_mode:
		network_sync = BattleNetworkSync.new()
		network_sync.initialize(self, true)
		print("BattleOrchestrator: Network sync enabled")
	
	turn_controller.turn_started.connect(_on_turn_started)
	turn_controller.turn_ended.connect(_on_turn_ended)
	turn_controller.turn_skipped.connect(_on_turn_skipped)
	
	if ui_controller:
		ui_controller.initialize_multi(player, enemies)
		ui_controller.action_selected.connect(_on_action_selected)
		
		ui_controller.update_all_character_info()
		ui_controller.update_xp_display()
		ui_controller.update_debug_display()
		
		if is_pvp_mode:
			ui_controller.hide_dungeon_info()
		else:
			ui_controller.update_dungeon_info(current_wave, current_floor, dungeon_description)
		
		print("BattleOrchestrator: UI initialized and updated")
	else:
		push_error("BattleOrchestrator: ui_controller is null!")
		battle_started = false
		return
	
	# NEW: Setup visual sprites
	if visual_manager:
		visual_manager.setup_player_sprite(player)
		visual_manager.setup_enemy_sprites(enemies)
	
	_initialize_resources()
	await _wait_for_ui_ready()
	
	ui_controller.setup_player_actions(false, false)
	ui_controller.disable_actions()
	
	print("BattleOrchestrator: Battle successfully initialized")
	
	turn_controller.start_first_turn()

func _validate_setup() -> bool:
	if not player:
		push_error("BattleOrchestrator: Missing player")
		return false
	
	if enemies.is_empty():
		push_error("BattleOrchestrator: No enemies in battle")
		return false
	
	if not ui_controller:
		push_error("BattleOrchestrator: Missing UI controller")
		return false
	
	return true

func _initialize_enemy_ai():
	"""Create AI controller for each enemy"""
	enemy_ai_controllers.clear()
	
	for enemy in enemies:
		var ai: EnemyAI
		
		if is_boss_battle and "King" in enemy.character_class:
			ai = BossAI.new()
			print("BattleOrchestrator: Created BossAI for %s" % enemy.name)
		else:
			ai = EnemyAI.new()
			print("BattleOrchestrator: Created EnemyAI for %s" % enemy.name)
		
		ai.initialize(enemy, player, current_floor)
		enemy_ai_controllers.append(ai)
	
	print("BattleOrchestrator: Initialized %d AI controllers" % enemy_ai_controllers.size())

func _initialize_resources():
	if player.current_sp == 0:
		player.current_sp = player.max_sp
	
	for enemy in enemies:
		if enemy.current_sp == 0:
			enemy.current_sp = enemy.max_sp

func _wait_for_ui_ready():
	await get_tree().process_frame
	await get_tree().process_frame
	
	if ui_controller:
		ui_controller.update_all_character_info()
		ui_controller.update_turn_display("Battle starting...")
	
	print("BattleOrchestrator: UI ready, starting combat")

# === TURN FLOW ===

func _on_turn_started(character: CharacterData, is_player_turn: bool):
	print("BattleOrchestrator: Turn started - %s" % character.name)
	_check_battle_end()
	
	if ui_controller:
		ui_controller.update_all_character_info()
		ui_controller.update_turn_display("%s's turn" % character.name)
	
	if is_pvp_mode and network_sync:
		network_sync.on_turn_started(character, is_player_turn)
	
	if is_player_turn:
		item_action_used = false
		main_action_taken = false
		print("BattleOrchestrator: Reset action flags for player turn")
	
	# Armor proficiency tracking
	if character.proficiency_manager:
		var armor_slots = ["head", "chest", "hands", "legs", "feet"]
		for slot in armor_slots:
			if character.equipment[slot] and character.equipment[slot] is Equipment:
				var armor = character.equipment[slot]
				if armor.type in ["cloth", "leather", "mail", "plate"]:
					var prof_msg = character.proficiency_manager.use_armor(armor.type)
					if prof_msg != "":
						ui_controller.add_combat_log(prof_msg, "cyan")
						print("[PROFICIENCY LEVEL UP!] %s" % prof_msg)
	
	var should_process_status = true
	if is_pvp_mode and network_sync:
		should_process_status = (character.get_instance_id() == network_sync.my_character.get_instance_id())
	
	if should_process_status:
		var status_result = combat_engine.process_status_effects(character)
		
		if status_result and status_result.message != "":
			ui_controller.add_combat_log(status_result.message, "purple")
		
		if ui_controller:
			ui_controller.update_all_character_info()
			
			if status_result.healing > 0:
				ui_controller.add_combat_log(
					"%s healed for %d HP" % [character.name, status_result.healing], 
					"green"
				)
			if status_result.damage > 0:
				ui_controller.add_combat_log(
					"%s took %d damage from status effects" % [character.name, status_result.damage],
					"red"
				)
				
				# NEW: Visual feedback for status damage
				if visual_manager:
					# Check if player took status damage
					if character == player:
						visual_manager.shake_and_flash_screen(0.1)
					else:
						visual_manager.shake_on_hit(status_result.damage, false)
						visual_manager.flash_sprite_hit(character, false)
		
		if is_pvp_mode and network_sync:
			network_sync.send_status_damage(character, status_result)
		
		await get_tree().create_timer(1.0).timeout
	else:
		print("[BATTLE ORCH] Skipping local status processing - waiting for opponent's data")
	
	turn_controller._remove_dead_from_queue()
	
	if not combat_engine.is_alive(character):
		await _handle_death(character)
		
		if _check_battle_end():
			return
		turn_controller.end_current_turn()
		return
	
	if character.is_stunned:
		var stun_msg = "%s is stunned and loses their turn!" % character.name
		ui_controller.add_combat_log(stun_msg, "purple")
		character.is_stunned = false
		
		await get_tree().create_timer(1.0).timeout
		
		print("BattleOrchestrator: %s stunned - ending turn immediately" % character.name)
		
		if _check_battle_end():
			return
		
		turn_controller.end_current_turn()
		return
	
	turn_controller.advance_phase()
	
	if is_pvp_mode and network_sync and not network_sync.is_my_turn:
		return
	
	if is_player_turn:
		_setup_player_turn()
	else:
		_execute_enemy_turn(character)

func _on_turn_ended(character: CharacterData):
	print("BattleOrchestrator: Turn ended - %s" % character.name)
	ui_controller.disable_actions()

func _on_turn_skipped(character: CharacterData, reason: String):
	print("BattleOrchestrator: Turn skipped - %s (%s)" % [character.name, reason])

# === PLAYER TURN ===

func _setup_player_turn():
	print("BattleOrchestrator: Player's turn")
	ui_controller.setup_player_actions(item_action_used, main_action_taken)
	ui_controller.unlock_ui()
	ui_controller.enable_actions()

func _on_action_selected(action: BattleAction):
	print("BattleOrchestrator: Action selected - %s" % action.get_description())
	
	if action.type == BattleAction.ActionType.ITEM:
		if item_action_used:
			ui_controller.add_combat_log("You've already used an item this turn!", "red")
			ui_controller.unlock_ui()
			ui_controller.enable_actions()
			return
		_execute_item_action(action)
		return
	
	if action.type == BattleAction.ActionType.DEFEND:
		if main_action_taken:
			ui_controller.add_combat_log("You've already taken your action!", "red")
			ui_controller.unlock_ui()
			ui_controller.enable_actions()
			return
		
		ui_controller.disable_actions()
		_execute_action(action, true)
		return
	
	if action.type in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL]:
		if not action.target and (not action.targets or action.targets.is_empty()):
			push_error("BattleOrchestrator: Action missing target - this should not happen!")
			ui_controller.add_combat_log("Error: No target selected", "red")
			ui_controller.unlock_ui()
			ui_controller.enable_actions()
			return
		
		if action.target and not action.target.is_alive():
			ui_controller.add_combat_log("Target is already defeated!", "red")
			ui_controller.unlock_ui()
			ui_controller.enable_actions()
			return
	
	if main_action_taken:
		ui_controller.add_combat_log("You've already taken your action!", "red")
		ui_controller.unlock_ui()
		ui_controller.enable_actions()
		return
	
	ui_controller.disable_actions()
	_execute_action(action, true)

func _execute_action(action: BattleAction, is_player: bool):
	print("BattleOrchestrator: Executing MAIN action - %s" % action.get_description())
	
	if not is_player:
		var action_name = ""
		match action.type:
			BattleAction.ActionType.ATTACK:
				action_name = "Attack"
			BattleAction.ActionType.DEFEND:
				action_name = "Defend"
			BattleAction.ActionType.SKILL:
				action_name = action.skill_data.name
			BattleAction.ActionType.ITEM:
				action_name = action.item_data.display_name
		
		ui_controller.add_combat_log("[color=red]%s uses %s![/color]" % [action.actor.name, action_name], "white")
	
	# NEW: Play attack animation BEFORE damage
	if visual_manager and action.type in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL]:
		# Check if AOE skill/attack
		var is_aoe = action.targets.size() > 1
		var is_magic = false
		
		if action.type == BattleAction.ActionType.SKILL:
			is_magic = action.skill_data.ability_type != Skill.AbilityType.PHYSICAL
		
		if is_aoe:
			# AOE - play magic animation on all targets
			visual_manager.play_aoe_attack_animation(action.actor, action.targets, is_magic)
			await get_tree().create_timer(0.3).timeout
		elif action.target:
			# Single target
			visual_manager.play_attack_animation(action.actor, action.target, is_magic)
			await get_tree().create_timer(0.3).timeout
	
	var result = combat_engine.execute_action(action)
	
	if not result:
		push_error("[BATTLE ORCH] Combat engine returned null result!")
		return
	
	print("[BATTLE ORCH] Action result: damage=%d, healing=%d, sp=%d, mp=%d" % [
		result.damage if "damage" in result else 0,
		result.healing if "healing" in result else 0, 
		result.sp_cost if "sp_cost" in result else 0,
		result.mp_cost if "mp_cost" in result else 0
	])
	
	# NEW: Handle dodge animation
	if visual_manager and (result.was_dodged or result.was_missed):
		for target in action.targets:
			if target:
				visual_manager.play_dodge_animation(target)
	
	# NEW: Visual feedback for hits
	if visual_manager and result.damage > 0:
		# Check if player was hit (no sprite, use screen flash)
		var player_was_hit = false
		for target in action.targets:
			if target == player:
				player_was_hit = true
				break
		
		if player_was_hit:
			# Player hit - screen shake + white flash
			visual_manager.shake_and_flash_screen(0.15)
		else:
			# Enemy hit - normal shake
			visual_manager.shake_on_hit(result.damage, result.is_critical)
		
		# Flash sprites for enemies that were hit
		for target in action.targets:
			if target and combat_engine.is_alive(target) and target != player:
				visual_manager.flash_sprite_hit(target, result.is_critical)
	
	if is_pvp_mode and network_sync and is_player:
		print("[BATTLE ORCH] Sending action to network sync...")
		network_sync.on_action_selected(action, result)
		print("[BATTLE ORCH] Main action + result synced to network")
	
	ui_controller.display_result(result, action)
	
	if result.has_level_up():
		ui_controller.add_combat_log(result.level_up_message, "cyan")
	
	if is_player:
		main_action_taken = true
		print("BattleOrchestrator: Main action taken - turn ending")
	
	await get_tree().create_timer(1.5).timeout
	
	var dead_characters: Array[CharacterData] = []
	
	if action.target and not combat_engine.is_alive(action.target):
		dead_characters.append(action.target)
	
	for target in action.targets:
		if target and not combat_engine.is_alive(target) and target not in dead_characters:
			dead_characters.append(target)
	
	if not combat_engine.is_alive(action.actor) and action.actor not in dead_characters:
		dead_characters.append(action.actor)
	
	if not dead_characters.is_empty():
		for dead in dead_characters:
			combat_engine.check_death_after_action(dead)
			
			# NEW: Play death animation
			if visual_manager:
				visual_manager.play_death_animation(dead)
				visual_manager.shake_on_death()
			
			if dead == player:
				print("[BATTLE ORCH] Player died")
			else:
				print("[BATTLE ORCH] %s died" % dead.name)
		
		if _check_battle_end():
			return
	
	turn_controller.end_current_turn()

func _execute_item_action(action: BattleAction):
	print("BattleOrchestrator: Executing item as bonus action")
	
	# NEW: Play animation for damage items
	if visual_manager and action.item_data.consumable_type == Item.ConsumableType.DAMAGE:
		var is_aoe = action.targets.size() > 1
		
		if is_aoe:
			visual_manager.play_aoe_attack_animation(action.actor, action.targets, true)
		elif action.target:
			visual_manager.play_attack_animation(action.actor, action.target, true)
		
		await get_tree().create_timer(0.3).timeout
	
	var result = combat_engine.execute_action(action)
	
	if result:
		print("[BATTLE ORCH] Item result: damage=%d, healing=%d" % [
			result.damage if "damage" in result else 0,
			result.healing if "healing" in result else 0
		])
		
		# NEW: Visual feedback for item effects
		if visual_manager:
			# Check if player was hit by item
			var player_was_hit = false
			for target in action.targets:
				if target == player and result.damage > 0:
					player_was_hit = true
					break
			
			if player_was_hit:
				visual_manager.shake_and_flash_screen(0.15)
			elif result.damage > 0 or result.healing > 0:
				visual_manager.add_trauma(0.15)
			
			# Flash sprites for enemies hit by items
			if result.damage > 0:
				for target in action.targets:
					if target and target != player:
						visual_manager.flash_sprite_hit(target, false)
	
	ui_controller.display_result(result, action)
	
	if is_pvp_mode and network_sync:
		print("[BATTLE ORCH] Sending item action to network...")
		network_sync.on_action_selected(action, result)
		print("BattleOrchestrator: Item action + result synced to network")
	
	await get_tree().create_timer(0.5).timeout
	
	item_action_used = true
	print("BattleOrchestrator: Item used - player can still take main action")
	
	if _check_battle_end():
		return
	
	ui_controller.setup_player_actions(item_action_used, main_action_taken)
	ui_controller.unlock_ui()
	ui_controller.enable_actions()

# === ENEMY TURN ===

func _execute_enemy_turn(enemy_character: CharacterData):
	if not combat_engine.is_alive(enemy_character):
		print("BattleOrchestrator: %s is dead, skipping turn entirely" % enemy_character.name)
		turn_controller.end_current_turn()
		return
	
	print("BattleOrchestrator: %s's turn" % enemy_character.name)
	
	if is_pvp_mode:
		ui_controller.add_combat_log("Opponent's turn", "red")
		ui_controller.update_turn_display("Waiting for opponent...")
		return
	
	ui_controller.add_combat_log("%s's turn" % enemy_character.name, "red")
	ui_controller.update_turn_display("%s is acting..." % enemy_character.name)
	
	await get_tree().create_timer(1.0).timeout
	
	if not combat_engine.is_alive(enemy_character):
		print("BattleOrchestrator: %s died during delay, skipping turn" % enemy_character.name)
		_check_battle_end()
		return
	
	var ai_controller = _get_ai_for_enemy(enemy_character)
	if not ai_controller:
		push_error("BattleOrchestrator: No AI found for %s, skipping turn" % enemy_character.name)
		turn_controller.end_current_turn()
		return
	
	if not combat_engine.is_alive(player):
		print("BattleOrchestrator: Player is dead, ending enemy turn")
		_check_battle_end()
		return
	
	var action = ai_controller.decide_action()
	
	if not action:
		push_error("BattleOrchestrator: AI returned null action for %s" % enemy_character.name)
		turn_controller.end_current_turn()
		return
	
	if action.type in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL]:
		if action.type == BattleAction.ActionType.SKILL and action.skill_data:
			if action.skill_data.target == Skill.TargetType.ALL_ALLIES:
				print("BattleOrchestrator: ALL_ALLIES skill - targets will be resolved by CombatEngine")
				_execute_action(action, false)
				return
		
		if not action.target and (not action.targets or action.targets.is_empty()):
			push_warning("BattleOrchestrator: Action missing target, defaulting to player")
			action.target = player
			action.targets.clear()
			action.targets.append(player)
		
		if action.target and not action.target.is_alive():
			print("BattleOrchestrator: Enemy's target died, skipping action")
			turn_controller.end_current_turn()
			return
	
	_execute_action(action, false)

func _get_ai_for_enemy(enemy_character: CharacterData) -> EnemyAI:
	for i in range(enemies.size()):
		if enemies[i] == enemy_character and i < enemy_ai_controllers.size():
			return enemy_ai_controllers[i]
	
	push_error("BattleOrchestrator: Could not find AI for %s (index out of range or mismatch)" % enemy_character.name)
	return null

# === BATTLE END ===

func _handle_death(character: CharacterData):
	var death_msg = "%s has been defeated!" % character.name
	ui_controller.add_combat_log(death_msg, "red")
	
	# NEW: Play death animation
	if visual_manager:
		visual_manager.play_death_animation(character)
		visual_manager.shake_on_death()
	
	turn_controller.remove_combatant(character)
	
	await get_tree().create_timer(1.5).timeout
	_check_battle_end()

func _check_battle_end() -> bool:
	var living_enemies = _get_living_enemies()
	
	if living_enemies.is_empty():
		_handle_victory()
		return true
	elif not combat_engine.is_alive(player):
		_handle_defeat()
		return true
	
	return false

func _get_living_enemies() -> Array[CharacterData]:
	var living: Array[CharacterData] = []
	for e in enemies:
		if e.is_alive():
			living.append(e)
	return living

func _handle_victory():
	print("BattleOrchestrator: Player victory!")
	ui_controller.disable_actions()
	
	if is_pvp_mode and network_sync:
		network_sync.on_battle_end(true)
		return
	
	var total_xp = 0
	for enemy in enemies:
		total_xp += enemy.level * 50 * current_floor
	
	await get_tree().create_timer(1.0).timeout
	_show_battle_complete_dialog(total_xp)

func _handle_defeat():
	print("BattleOrchestrator: Player defeated!")
	ui_controller.disable_actions()
	
	if is_pvp_mode and network_sync:
		network_sync.on_battle_end(false)
		return
	
	await get_tree().create_timer(1.0).timeout
	emit_signal("battle_completed", false, 0)

func _show_battle_complete_dialog(xp_gained: int):
	var dialog_scene = load("res://scenes/BattleCompleteDialog.tscn")
	if not dialog_scene:
		emit_signal("battle_completed", true, xp_gained)
		return
	
	ui_controller._force_ui_invisible()

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
	var momentum_before_reset = MomentumSystem.get_momentum()
	var had_momentum_bonus = momentum_before_reset >= 3
	
	MomentumSystem.reset_momentum()
	
	if had_momentum_bonus:
		player.set_meta("taking_breather_with_bonus", true)
		player.set_meta("momentum_level_at_breather", momentum_before_reset)
		player.status_effects.clear()
	emit_signal("battle_completed", true, xp_gained)

func _show_level_up_overlay():
	var level_up_scene = load("res://scenes/LevelUpScene.tscn").instantiate()
	add_child(level_up_scene)
	level_up_scene.setup(player)
	await level_up_scene.level_up_complete
	level_up_scene.queue_free()

# === SETUP ===

func set_player(character: CharacterData):
	player = character

func set_enemies(enemy_list: Array[CharacterData]):
	enemies = enemy_list
	
	for enemy in enemies:
		enemy.calculate_secondary_attributes()
		if enemy.current_sp == 0:
			enemy.current_sp = enemy.max_sp
	
	print("BattleOrchestrator: Set %d enemies" % enemies.size())

func set_enemy(new_enemy: CharacterData):
	enemies = [new_enemy]
	set_enemies(enemies)

func set_dungeon_info(boss_fight: bool, wave: int, floor: int, _max_floor:int, description: String):
	is_boss_battle = boss_fight
	current_wave = wave
	current_floor = floor
	
	if description == null or description == "":
		dungeon_description = "Dungeon Floor %d" % floor
	elif typeof(description) == TYPE_STRING:
		dungeon_description = description
	else:
		dungeon_description = str(description)
		push_warning("BattleOrchestrator: Description was type %d, converted to String" % typeof(description))
		
	call_deferred("_deferred_start_battle")

func _deferred_start_battle():
	print("BattleOrchestrator: _deferred_start_battle called")
	print("  - Player: ", player.name if player else "NULL")
	print("  - Enemies: %d" % enemies.size())
	print("  - Floor: %d, Wave: %d" % [current_floor, current_wave])
	
	if not player:
		push_error("BattleOrchestrator: Cannot start battle - player is null!")
		return
	
	if enemies.is_empty():
		push_error("BattleOrchestrator: Cannot start battle - no enemies!")
		return
	
	if not ui_controller:
		push_error("BattleOrchestrator: Cannot start battle - ui_controller is null!")
		return
	
	var tree = get_tree()
	if not tree:
		push_error("BattleOrchestrator: Scene tree is null!")
		return
	
	print("BattleOrchestrator: Waiting for scene to stabilize...")
	
	var frames_waited = 0
	var max_frames = 30
	
	while frames_waited < max_frames:
		if not is_inside_tree():
			push_error("BattleOrchestrator: Node removed from tree while waiting!")
			return
		
		await tree.process_frame
		frames_waited += 1
		
		if ui_controller and ui_controller.is_inside_tree():
			print("BattleOrchestrator: Scene ready after %d frames" % frames_waited)
			break
	
	if frames_waited >= max_frames:
		push_error("BattleOrchestrator: Timeout waiting for scene!")
		return
	
	print("BattleOrchestrator: Starting battle now...")
	start_battle()

# === PVP ===

func setup_pvp_battle(local_player: CharacterData, remote_opponent: CharacterData):
	print("BattleOrchestrator: setup_pvp_battle called")
	
	is_pvp_mode = true
	player = local_player
	enemies = [remote_opponent]
	
	player.reset_for_new_battle()
	remote_opponent.reset_for_new_battle()
	
	if not remote_opponent.elemental_resistances:
		remote_opponent.elemental_resistances = ElementalResistanceManager.new(remote_opponent)
	
	remote_opponent.calculate_secondary_attributes()
	
	current_wave = 1
	current_floor = 1
	dungeon_description = "Arena PvP Battle"
	is_boss_battle = false
	
	print("BattleOrchestrator: PvP battle configured")
	
	call_deferred("start_battle")
