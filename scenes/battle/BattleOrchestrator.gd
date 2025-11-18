# res://scenes/battle/BattleOrchestrator.gd
extends Node

signal battle_completed(player_won: bool, xp_gained: int)

var rand_manager = RandomManager 

# Battle systems
var combat_engine: CombatEngine
var turn_controller: TurnController
var enemy_ai: EnemyAI
var ui_controller: BattleUIController
var network_sync: BattleNetworkSync
var is_pvp_mode := false
var battle_started := false

# Battle context
var player: CharacterData
var enemy: CharacterData
var is_boss_battle: bool = false
var current_wave: int
var current_floor: int
var max_floor: int
var dungeon_description: String
var item_action_used: bool = false
var main_action_taken: bool = false

# ✅ FIX: Track action flags per character
var player_item_used: bool = false
var player_main_action_taken: bool = false
var enemy_item_used: bool = false
var enemy_main_action_taken: bool = false

func _ready():
	ui_controller = get_node_or_null("BattleUIController")
	if not ui_controller:
		push_error("BattleOrchestrator: BattleUIController not found!")
		return
	
	print("BattleOrchestrator: Ready")

func start_battle():
	# ✅ CRITICAL FIX: Set flag IMMEDIATELY to prevent race condition
	if battle_started:
		print("BattleOrchestrator: Battle already started, ignoring duplicate call")
		return
	battle_started = true
	print("BattleOrchestrator: Battle start flag set - preventing duplicates")
	
	if not _validate_setup():
		battle_started = false  # Reset if validation fails
		return
	
	print("BattleOrchestrator: Starting battle - %s vs %s (PvP: %s)" % [
		player.name, enemy.name, is_pvp_mode
	])
	
	# Initialize systems
	combat_engine = CombatEngine.new()
	combat_engine.initialize(player, enemy)
	
	turn_controller = TurnController.new()
	add_child(turn_controller)
	turn_controller.initialize(player, enemy)
	
	if is_pvp_mode:
		turn_controller.set_pvp_mode(true)
	
	var player_agility = player.agility
	var enemy_agility = enemy.agility
	
	if player_agility > enemy_agility:
		ui_controller.add_combat_log("%s wins initiative! (Agility: %.1f vs %.1f)" % [player.name, player_agility, enemy_agility], "cyan")
		ui_controller.add_combat_log("%s goes first!" % player.name, "cyan")
	elif enemy_agility > player_agility:
		ui_controller.add_combat_log("%s wins initiative! (Agility: %.1f vs %.1f)" % [enemy.name, enemy_agility, player_agility], "red")
		ui_controller.add_combat_log("%s goes first!" % enemy.name, "red")
	else:
		ui_controller.add_combat_log("Initiative tied! (Agility: %.1f) - Random turn order" % player_agility, "yellow")
	
	# ✅ NEW: Initialize network sync if PvP
	if is_pvp_mode:
		network_sync = BattleNetworkSync.new()
		network_sync.initialize(self, true)
		print("BattleOrchestrator: Network sync enabled")
	
	# ✅ MODIFIED: Use regular AI only in PvE mode
	if not is_pvp_mode:
		if is_boss_battle:
			enemy_ai = BossAI.new()
			print("BattleOrchestrator: Using BOSS AI")
		else:
			enemy_ai = EnemyAI.new()
			print("BattleOrchestrator: Using regular AI")
		
		enemy_ai.initialize(enemy, player, current_floor)
	else:
		print("BattleOrchestrator: PvP mode - no AI")
	
	turn_controller.turn_started.connect(_on_turn_started)
	turn_controller.turn_ended.connect(_on_turn_ended)
	turn_controller.turn_skipped.connect(_on_turn_skipped)
	
	if ui_controller:
		ui_controller.initialize(player, enemy)
		ui_controller.action_selected.connect(_on_action_selected)
		
		ui_controller.update_character_info(player, enemy)
		ui_controller.update_xp_display()
		ui_controller.update_debug_display()
		
		if is_pvp_mode:
			ui_controller.hide_dungeon_info()
		else:
			ui_controller.update_dungeon_info(current_wave, current_floor, dungeon_description)
		
		print("BattleOrchestrator: UI initialized and updated")
	else:
		push_error("BattleOrchestrator: ui_controller is null!")
		battle_started = false  # Reset if UI init fails
		return
	
	_initialize_resources()
	await _wait_for_ui_ready()
	
	ui_controller.setup_player_actions(false, false)
	ui_controller.disable_actions()
	
	print("BattleOrchestrator: Battle successfully initialized")
	
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
	
	if is_pvp_mode and network_sync:
		network_sync.on_turn_started(character, is_player)
	
	if is_player:
		item_action_used = false
		main_action_taken = false
		print("BattleOrchestrator: Reset action flags for player turn")
	
	# === ARMOR PROFICIENCY TRACKING ===
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
	
	# ✅ CRITICAL FIX: In PvP, only process status effects for MY character
	# Opponent's status effects are handled by them and synced via network
	var should_process_status = true
	if is_pvp_mode and network_sync:
		# Only process if this is my character
		should_process_status = (character.get_instance_id() == network_sync.my_character.get_instance_id())
		print("[BATTLE ORCH] PvP status check: character=%s, my_char=%s, process=%s" % [
			character.get_instance_id(), network_sync.my_character.get_instance_id(), should_process_status
		])
	
	if should_process_status:
		var status_result = combat_engine.process_status_effects(character)
		if status_result and status_result.message != "":
			ui_controller.add_combat_log(status_result.message, "purple")
			ui_controller.update_character_info(player, enemy)
			
			# ✅ NEW: In PvP, send status damage to opponent
			if is_pvp_mode and network_sync:
				print("[BATTLE ORCH] Syncing status effect result to opponent")
				network_sync.send_status_damage(character, status_result)
			
			await get_tree().create_timer(1.0).timeout
	else:
		print("[BATTLE ORCH] Skipping local status processing - waiting for opponent's data")
	
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
	
	turn_controller.advance_phase()
	
	if is_pvp_mode and network_sync and not network_sync.is_my_turn:
		return
	
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
	ui_controller.setup_player_actions(item_action_used, main_action_taken)
	ui_controller.unlock_ui()
	ui_controller.enable_actions()

func _on_action_selected(action: BattleAction):
	print("BattleOrchestrator: Action selected - %s" % action.get_description())
	
	# ✅ CRITICAL: Handle item as bonus action - sync to network but don't end turn
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
		ui_controller.add_combat_log("You've already taken your action!", "red")
		ui_controller.unlock_ui()
		ui_controller.enable_actions()
		return
	
	ui_controller.disable_actions()
	_execute_action(action, true)

func _execute_action(action: BattleAction, is_player: bool):
	print("BattleOrchestrator: Executing MAIN action - %s" % action.get_description())
	
	# ✅ CRITICAL: Execute FIRST, then send result to network
	var result = combat_engine.execute_action(action)
	
	# ✅ CRITICAL FIX: Ensure result is valid before sending
	if not result:
		push_error("[BATTLE ORCH] Combat engine returned null result!")
		return
	
	# ✅ NEW: Debug log the result before sending
	print("[BATTLE ORCH] Action result: damage=%d, healing=%d, sp=%d, mp=%d" % [
		result.damage if "damage" in result else 0,
		result.healing if "healing" in result else 0, 
		result.sp_cost if "sp_cost" in result else 0,
		result.mp_cost if "mp_cost" in result else 0
	])
	
	# ✅ CRITICAL: Send action AND RESULT to network in PvP (AFTER execution)
	if is_pvp_mode and network_sync and is_player:
		print("[BATTLE ORCH] Sending action to network sync...")
		network_sync.on_action_selected(action, result)
		print("[BATTLE ORCH] Main action + result synced to network")
	
	# ✅ FIXED: Pass action to display_result so it has actor context
	ui_controller.display_result(result, action)
	
	if result.has_level_up():
		ui_controller.add_combat_log(result.level_up_message, "cyan")
	
	if is_player:
		main_action_taken = true
		print("BattleOrchestrator: Main action taken - turn ending")
	
	await get_tree().create_timer(1.5).timeout
	
	if _check_battle_end():
		return
	
	# End turn - this advances to next player
	turn_controller.end_current_turn()

func _execute_item_action(action: BattleAction):
	print("BattleOrchestrator: Executing item as bonus action")
	
	var result = combat_engine.execute_action(action)
	
	# ✅ NEW: Debug log the result
	if result:
		print("[BATTLE ORCH] Item result: damage=%d, healing=%d" % [
			result.damage if "damage" in result else 0,
			result.healing if "healing" in result else 0
		])
	
	# ✅ FIXED: Pass action to display_result so it has actor context
	ui_controller.display_result(result, action)
	
	# ✅ CRITICAL: Send item AND RESULT to network AFTER execution
	if is_pvp_mode and network_sync:
		print("[BATTLE ORCH] Sending item action to network...")
		network_sync.on_action_selected(action, result)
		print("BattleOrchestrator: Item action + result synced to network")
	
	await get_tree().create_timer(0.5).timeout
	
	# Mark item used but NOT main action
	item_action_used = true
	print("BattleOrchestrator: Item used - player can still take main action")
	
	if _check_battle_end():
		return
	
	# Refresh UI with both flags - turn continues
	ui_controller.setup_player_actions(item_action_used, main_action_taken)
	ui_controller.unlock_ui()
	ui_controller.enable_actions()

# === ENEMY TURN ===

func _execute_enemy_turn():
	print("BattleOrchestrator: Enemy's turn")
	
	# ✅ NEW: In PvP, opponent actions come via network
	if is_pvp_mode:
		ui_controller.add_combat_log("Opponent's turn", "red")
		ui_controller.update_turn_display("Waiting for opponent...")
		# Network sync will handle receiving the action
		return
	
	# PvE: Use AI
	ui_controller.add_combat_log("Enemy's turn", "red")
	ui_controller.update_turn_display("Enemy is acting...")
	
	await get_tree().create_timer(1.0).timeout
	
	if not combat_engine.is_alive(enemy):
		_check_battle_end()
		return
	
	var action = enemy_ai.decide_action()
	_execute_action(action, false)

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
	
	# ✅ FIX: In PvP, notify opponent first, then wait for sync
	if is_pvp_mode and network_sync:
		network_sync.on_battle_end(true)
		# Network sync will handle the rest (dialog, save, return to town)
		return
	
	# PvE: Normal flow with XP
	var xp = enemy.level * 50 * current_floor
	await get_tree().create_timer(1.0).timeout
	_show_battle_complete_dialog(xp)

func _handle_defeat():
	print("BattleOrchestrator: Player defeated!")
	ui_controller.disable_actions()
	
	# ✅ FIX: In PvP, notify opponent first, then wait for sync
	if is_pvp_mode and network_sync:
		network_sync.on_battle_end(false)
		# Network sync will handle the rest (dialog, save, return to town)
		return
	
	# PvE: Normal flow
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

func set_dungeon_info(boss_fight: bool, wave: int, floor: int, _max_floor:int, description: String):
	current_wave = wave
	current_floor = floor
	dungeon_description = description
	# CRITICAL FIX: Safely handle description parameter
	if description == null or description == "":
		dungeon_description = "Dungeon Floor %d" % floor
	elif typeof(description) == TYPE_STRING:
		dungeon_description = description
	else:
		# Convert whatever type it is to String
		dungeon_description = str(description)
		push_warning("BattleOrchestrator: Description was type %d, converted to String" % typeof(description))
		
	call_deferred("_deferred_start_battle")

func _deferred_start_battle():
	print("BattleOrchestrator: _deferred_start_battle called")
	print("  - Player: ", player.name if player else "NULL")
	print("  - Enemy: ", enemy.name if enemy else "NULL")
	print("  - Floor: %d, Wave: %d" % [current_floor, current_wave])
	
	# Validation
	if not player:
		push_error("BattleOrchestrator: Cannot start battle - player is null!")
		return
	
	if not enemy:
		push_error("BattleOrchestrator: Cannot start battle - enemy is null!")
		return
	
	if not ui_controller:
		push_error("BattleOrchestrator: Cannot start battle - ui_controller is null!")
		return
	
	# ✅ FIX: Check if tree is valid before awaiting
	var tree = get_tree()
	if not tree:
		push_error("BattleOrchestrator: Scene tree is null!")
		return
	
	print("BattleOrchestrator: Waiting for scene to stabilize...")
	
	# Wait with timeout protection
	var frames_waited = 0
	var max_frames = 30
	
	while frames_waited < max_frames:
		if not is_inside_tree():
			push_error("BattleOrchestrator: Node removed from tree while waiting!")
			return
		
		await tree.process_frame
		frames_waited += 1
		
		# Check if we're ready
		if ui_controller and ui_controller.is_inside_tree():
			print("BattleOrchestrator: Scene ready after %d frames" % frames_waited)
			break
	
	if frames_waited >= max_frames:
		push_error("BattleOrchestrator: Timeout waiting for scene!")
		return
	
	print("BattleOrchestrator: Starting battle now...")
	start_battle()

func debug_proficiency_status():
	"""Debug command to check proficiency status"""
	if not player or not player.proficiency_manager:
		print("[DEBUG] No player or proficiency manager!")
		return
	
	print("\n=== PLAYER PROFICIENCY DEBUG ===")
	
	# Check weapon
	if player.equipment["main_hand"]:
		var weapon = player.equipment["main_hand"]
		print("Main Hand: %s" % weapon.name)
		print("  Key: '%s'" % weapon.key)
		
		if weapon.key != "":
			var uses = player.proficiency_manager.get_weapon_proficiency_uses(weapon.key)
			var level = player.proficiency_manager.get_weapon_proficiency_level(weapon.key)
			var next = player.proficiency_manager.get_uses_for_next_level(level)
			print("  Proficiency: Level %d (%d/%d uses)" % [level, uses, next])
	
	# Check all tracked proficiencies
	print("\nAll Weapon Proficiencies:")
	var all_weapons = player.proficiency_manager.get_all_weapon_proficiencies()
	if all_weapons.is_empty():
		print("  (none)")
	else:
		for prof in all_weapons:
			print("  %s" % prof)
	
	print("\nAll Armor Proficiencies:")
	var all_armor = player.proficiency_manager.get_all_armor_proficiencies()
	if all_armor.is_empty():
		print("  (none)")
	else:
		for prof in all_armor:
			print("  %s" % prof)
	
	print("================================\n")

# === PVP SETUP FUNCTION ===

func setup_pvp_battle(local_player: CharacterData, remote_opponent: CharacterData):
	"""Setup battle in PvP mode"""
	print("BattleOrchestrator: setup_pvp_battle called")
	print("  - Local player: %s (Level %d, HP: %d/%d)" % [
		local_player.name, local_player.level, local_player.current_hp, local_player.max_hp
	])
	print("  - Remote opponent: %s (Level %d, HP: %d/%d)" % [
		remote_opponent.name, remote_opponent.level, remote_opponent.current_hp, remote_opponent.max_hp
	])
	
	is_pvp_mode = true
	player = local_player
	enemy = remote_opponent
	
	# Reset for battle
	player.reset_for_new_battle()
	enemy.reset_for_new_battle()
	
	if not enemy.elemental_resistances:
		enemy.elemental_resistances = ElementalResistanceManager.new(enemy)
	
	enemy.calculate_secondary_attributes()
	
	# Set dummy dungeon info
	current_wave = 1
	current_floor = 1
	dungeon_description = "Arena PvP Battle"
	is_boss_battle = false
	
	print("BattleOrchestrator: PvP battle configured")
	print("  - Player instance ID: %s" % player.get_instance_id())
	print("  - Enemy instance ID: %s" % enemy.get_instance_id())
	
	call_deferred("start_battle")

func debug_character_references():
	"""Debug to verify all character references point to same objects"""
	print("\n=== CHARACTER REFERENCE DEBUG ===")
	
	if not is_pvp_mode:
		print("Not in PvP mode")
		return
	
	var local_char = CharacterManager.get_current_character()
	var network_opponent_id = network_sync.network.get_opponent_id()
	var network_opponent = network_sync.network.players.get(network_opponent_id, {}).get("character", null)
	
	print("orchestrator.player: %s (%s)" % [player.name, player.get_instance_id()])
	print("orchestrator.enemy: %s (%s)" % [enemy.name, enemy.get_instance_id()])
	print("CharacterManager.current: %s (%s)" % [local_char.name, local_char.get_instance_id()])
	
	if network_opponent:
		print("Network opponent: %s (%s)" % [network_opponent.name, network_opponent.get_instance_id()])
	
	print("\nPlayer HP: %d/%d" % [player.current_hp, player.max_hp])
	print("Enemy HP: %d/%d" % [enemy.current_hp, enemy.max_hp])
	
	if player == local_char:
		print("✅ player == CharacterManager.current")
	else:
		print("❌ player != CharacterManager.current - THIS IS THE BUG!")
	
	if network_opponent and enemy.get_instance_id() == network_opponent.get_instance_id():
		print("✅ enemy == network opponent")
	else:
		print("❌ enemy != network opponent - THIS IS THE BUG!")
	
	print("=================================\n")

func debug_stat_comparison():
	"""Debug function to compare local vs opponent stats"""
	print("\n=== STAT COMPARISON DEBUG ===")
	
	print("\nLOCAL PLAYER (%s):" % player.name)
	print("  Base Stats:")
	print("    STR: %d, DEX: %d, INT: %d" % [player.strength, player.dexterity, player.intelligence])
	print("    VIT: %d, AGI: %d" % [player.vitality, player.agility])
	
	print("  Equipment:")
	for slot in player.equipment:
		var item = player.equipment[slot]
		if item:
			print("    [%s] %s (dmg=%d, armor=%d, mods=%d)" % [
				slot, item.name, item.damage, item.armor_value, item.stat_modifiers.size()
			])
			for stat in item.stat_modifiers:
				print("      +%d %s" % [item.stat_modifiers[stat], Skill.AttributeTarget.keys()[stat]])
	
	print("  Calculated:")
	print("    Attack Power: %d" % player.get_attack_power())
	print("    Defense: %d" % player.get_defense())
	print("    Max HP: %d" % player.max_hp)
	
	print("\nOPPONENT (%s):" % enemy.name)
	print("  Base Stats:")
	print("    STR: %d, DEX: %d, INT: %d" % [enemy.strength, enemy.dexterity, enemy.intelligence])
	print("    VIT: %d, AGI: %d" % [enemy.vitality, enemy.agility])
	
	print("  Equipment:")
	for slot in enemy.equipment:
		var item = enemy.equipment[slot]
		if item:
			print("    [%s] %s (dmg=%d, armor=%d, mods=%d)" % [
				slot, item.name, item.damage, item.armor_value, item.stat_modifiers.size()
			])
			for stat in item.stat_modifiers:
				print("      +%d %s" % [item.stat_modifiers[stat], Skill.AttributeTarget.keys()[stat]])
	
	print("  Calculated:")
	print("    Attack Power: %d" % enemy.get_attack_power())
	print("    Defense: %d" % enemy.get_defense())
	print("    Max HP: %d" % enemy.max_hp)
	
	print("=================================\n")
