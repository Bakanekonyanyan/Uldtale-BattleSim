# res://scenes/battle/components/TurnHandler.gd
# Manages turn flow, status effects, and turn-based state changes
# Wraps TurnController and adds orchestration logic

class_name TurnHandler
extends RefCounted

var turn_controller: TurnController
var combat_engine: CombatEngine
var visual_manager: BattleVisualManager
var ui_controller: BattleUIController
var context: BattleContext

signal turn_ready_for_action(character: CharacterData, is_player: bool)
signal turn_skipped_death(character: CharacterData)
signal turn_skipped_stun(character: CharacterData)

func initialize(p_turn_ctrl: TurnController, p_combat: CombatEngine, p_visual: BattleVisualManager, p_ui: BattleUIController, p_context: BattleContext):
	turn_controller = p_turn_ctrl
	combat_engine = p_combat
	visual_manager = p_visual
	ui_controller = p_ui
	context = p_context

func start_turn(character: CharacterData, is_player: bool) -> void:
	print("TurnHandler: Starting turn for %s" % character.name)
	
	ui_controller.update_all_character_info()
	ui_controller.update_turn_display("%s's turn" % character.name)
	
	if is_player:
		context.reset_turn_state()
	
	# Armor proficiency tracking
	_track_armor_proficiency(character)
	
	# Process status effects
	var should_process = _should_process_status_locally(character)
	if should_process:
		await _process_status_effects(character)
	
	# Remove dead from queue
	turn_controller._remove_dead_from_queue()
	
	# Check if character died from status
	if not combat_engine.is_alive(character):
		emit_signal("turn_skipped_death", character)
		return
	
	# Check stun
	if character.is_stunned:
		await _handle_stunned_turn(character)
		return
	
	# Advance to action phase
	turn_controller.advance_phase()
	
	emit_signal("turn_ready_for_action", character, is_player)

func end_turn():
	turn_controller.end_current_turn()

func remove_character(character: CharacterData):
	turn_controller.remove_combatant(character)

# === STATUS EFFECTS ===

func _process_status_effects(character: CharacterData) -> void:
	var status_result = combat_engine.process_status_effects(character)
	
	if status_result and status_result.message != "":
		ui_controller.add_combat_log(status_result.message, "purple")
	
	if not status_result:
		return
	
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
		
		# Visual feedback
		if visual_manager:
			if character == context.player:
				visual_manager.shake_and_flash_screen(0.1)
			else:
				visual_manager.shake_on_hit(status_result.damage, false)
				visual_manager.flash_sprite_hit(character, false)
	
	await _get_tree_timer(1.0)

func _handle_stunned_turn(character: CharacterData) -> void:
	var stun_msg = "%s is stunned and loses their turn!" % character.name
	ui_controller.add_combat_log(stun_msg, "purple")
	character.is_stunned = false
	
	await _get_tree_timer(1.0)
	
	emit_signal("turn_skipped_stun", character)

# === PROFICIENCY ===

func _track_armor_proficiency(character: CharacterData):
	if not character.proficiency_manager:
		return
	
	var armor_slots = ["head", "chest", "hands", "legs", "feet"]
	for slot in armor_slots:
		if character.equipment[slot] and character.equipment[slot] is Equipment:
			var armor = character.equipment[slot]
			if armor.type in ["cloth", "leather", "mail", "plate"]:
				var prof_msg = character.proficiency_manager.use_armor(armor.type)
				if prof_msg != "":
					ui_controller.add_combat_log(prof_msg, "cyan")

# === HELPERS ===

func _should_process_status_locally(character: CharacterData) -> bool:
	# For PvP, only process status for your character
	if context.is_pvp_mode:
		# Would need network sync reference here
		return true  # Simplified for refactor
	return true

func _get_tree_timer(seconds: float):
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(seconds).timeout
