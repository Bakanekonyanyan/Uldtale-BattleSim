# res://scenes/battle/flow/TurnStartProcessor.gd
# Everything that happens at the START of a combatant's turn, before they act:
#
#   1. Their Defend stance from last turn wears off
#   2. Armor proficiency ticks
#   3. Status effects tick (poison, regen, cooldowns, buff durations...)
#   4. If that killed them -> DIED
#   5. If they are stunned -> STUNNED (turn is lost)
#   6. Otherwise          -> CAN_ACT
#
# Returns a Result value so the orchestrator's turn loop can branch on it.

class_name TurnStartProcessor
extends RefCounted

enum Result { CAN_ACT, STUNNED, DIED }

var combat_engine: CombatEngine
var visual_manager: BattleVisualManager
var ui_controller: BattleUIController
var context: BattleContext
var network_sync: BattleNetworkSync  # PvP only, may be null

func initialize(p_combat: CombatEngine, p_visual: BattleVisualManager, p_ui: BattleUIController, p_context: BattleContext, p_network: BattleNetworkSync = null) -> void:
	combat_engine = p_combat
	visual_manager = p_visual
	ui_controller = p_ui
	context = p_context
	network_sync = p_network

func run(character: CharacterData) -> Result:
	ui_controller.update_all_character_info()
	ui_controller.update_turn_display("%s's turn" % character.name)

	# Defend lasts until the defender's next turn. (It was never reset before,
	# so a single Defend halved all incoming damage for the rest of the battle.)
	character.reset_defense()

	_track_armor_proficiency(character)

	if _should_process_status_locally(character):
		await _process_status_effects(character)

	if not combat_engine.is_alive(character):
		return Result.DIED

	if character.is_stunned:
		ui_controller.add_combat_log("%s is stunned and loses their turn!" % character.name, "purple")
		character.is_stunned = false
		await _wait(1.0)
		return Result.STUNNED

	return Result.CAN_ACT

# === STATUS EFFECTS ===

func _process_status_effects(character: CharacterData) -> void:
	var status_result = combat_engine.process_status_effects(character)
	if not status_result:
		return

	if context.is_pvp_mode and network_sync:
		network_sync.send_status_damage(character, status_result)

	if status_result.message != "":
		ui_controller.add_combat_log(status_result.message, "purple")

	ui_controller.update_all_character_info()

	if status_result.healing > 0:
		ui_controller.add_combat_log("%s healed for %d HP" % [character.name, status_result.healing], "green")

	if status_result.damage > 0:
		ui_controller.add_combat_log("%s took %d damage from status effects" % [character.name, status_result.damage], "red")
		if visual_manager:
			if character == context.player:
				visual_manager.shake_and_flash_screen(0.1)
			else:
				visual_manager.shake_on_hit(status_result.damage, false)
				visual_manager.flash_sprite_hit(character, false)

	# Only pause when something visibly happened
	if status_result.message != "" or status_result.damage > 0 or status_result.healing > 0:
		await _wait(1.0)

func _should_process_status_locally(character: CharacterData) -> bool:
	# In PvP each client ticks only its OWN character and syncs the result;
	# the opponent's ticks arrive over the network.
	if context.is_pvp_mode and network_sync and network_sync.my_character:
		return character == network_sync.my_character
	return true

# === PROFICIENCY ===

func _track_armor_proficiency(character: CharacterData) -> void:
	if not character.proficiency_manager:
		return

	for slot in ["head", "chest", "hands", "legs", "feet"]:
		var armor = character.equipment.get(slot)
		if armor and armor is Equipment and armor.type in ["cloth", "leather", "mail", "plate"]:
			var prof_msg = character.proficiency_manager.use_armor(armor.type)
			if prof_msg != "":
				ui_controller.add_combat_log(prof_msg, "cyan")

func _wait(seconds: float) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(seconds).timeout
