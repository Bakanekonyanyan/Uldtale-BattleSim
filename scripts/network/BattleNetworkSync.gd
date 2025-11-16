# res://scripts/network/BattleNetworkSync.gd
# Wraps BattleOrchestrator to add network synchronization for PvP
class_name BattleNetworkSync
extends RefCounted

signal sync_ready()

var orchestrator  # BattleOrchestrator (untyped to avoid circular dependency)
var network: ArenaNetworkManager
var is_pvp_mode := false
var is_my_turn := false
var waiting_for_opponent := false

func initialize(orch, is_pvp: bool = false):
	"""Initialize network sync wrapper"""
	orchestrator = orch
	is_pvp_mode = is_pvp
	
	if not is_pvp_mode:
		print("[BATTLE SYNC] Running in PvE mode, no network sync")
		return
	
	# Get network manager
	if not orch.has_node("/root/ArenaNetworkManager"):
		push_error("[BATTLE SYNC] ArenaNetworkManager not found!")
		return
	
	network = orch.get_node("/root/ArenaNetworkManager")
	
	# Connect network signals
	network.action_received.connect(_on_network_action_received)
	network.match_ended.connect(_on_match_ended)
	
	print("[BATTLE SYNC] Initialized in PvP mode")

# === TURN MANAGEMENT ===

func on_turn_started(character: CharacterData, is_player: bool):
	"""Called when a turn starts - determine if it's our turn"""
	if not is_pvp_mode:
		return
	
	# In PvP, check if it's actually the local player's character
	var local_player = CharacterManager.get_current_character()
	is_my_turn = (character == local_player)
	
	print("[BATTLE SYNC] Turn started - %s (my turn: %s)" % [character.name, is_my_turn])
	
	if not is_my_turn:
		waiting_for_opponent = true
		orchestrator.ui_controller.update_turn_display("Opponent's Turn - Waiting...")
		orchestrator.ui_controller.disable_actions()

func on_action_selected(action: BattleAction):
	"""Called when local player selects an action"""
	if not is_pvp_mode or not is_my_turn:
		return
	
	print("[BATTLE SYNC] Local action selected: %s" % action.get_description())
	
	# Send to opponent
	var action_data = _serialize_action(action)
	network.send_action(action_data)

func _on_network_action_received(peer_id: int, action_data: Dictionary):
	"""Received opponent's action from network"""
	if not waiting_for_opponent:
		print("[BATTLE SYNC] Ignoring action - not waiting")
		return
	
	waiting_for_opponent = false
	
	print("[BATTLE SYNC] Received opponent action: %s" % action_data)
	
	# Deserialize action
	var action = _deserialize_action(action_data)
	
	if not action:
		push_error("[BATTLE SYNC] Failed to deserialize action!")
		return
	
	# Execute via orchestrator's combat engine
	var result = orchestrator.combat_engine.execute_action(action)
	orchestrator.ui_controller.display_result(result)
	
	# Check battle end
	await orchestrator.get_tree().create_timer(1.5).timeout
	
	if orchestrator._check_battle_end():
		return
	
	# End turn
	orchestrator.turn_controller.end_current_turn()

# === BATTLE END ===

func on_battle_end(player_won: bool):
	"""Called when battle ends locally"""
	if not is_pvp_mode:
		return
	
	var winner_id = network.local_player_id if player_won else network.get_opponent_id()
	network.end_match(winner_id)

func _on_match_ended(winner_id: int):
	"""Called when opponent ends match"""
	var i_won = (winner_id == network.local_player_id)
	print("[BATTLE SYNC] Match ended via network, winner: %d (me: %s)" % [winner_id, i_won])

# === SERIALIZATION ===

func _serialize_action(action: BattleAction) -> Dictionary:
	"""Convert BattleAction to network dict"""
	var data = {
		"type": action.type,
		"timestamp": Time.get_ticks_msec()
	}
	
	match action.type:
		BattleAction.ActionType.ATTACK:
			pass  # No extra data
		
		BattleAction.ActionType.DEFEND:
			pass  # No extra data
		
		BattleAction.ActionType.SKILL:
			data["skill_name"] = action.skill_data.name
		
		BattleAction.ActionType.ITEM:
			data["item_id"] = action.item_data.id
	
	return data

func _deserialize_action(data: Dictionary) -> BattleAction:
	"""Convert network dict to BattleAction"""
	# Get opponent character
	var opponent_id = network.get_opponent_id()
	var opponent = network.players[opponent_id].character if network.players.has(opponent_id) else null
	
	if not opponent:
		push_error("[BATTLE SYNC] No opponent character found!")
		return null
	
	var local_player = CharacterManager.get_current_character()
	
	# Opponent is the actor, local player is the target
	var actor = opponent
	var target = local_player
	
	match int(data.type):
		BattleAction.ActionType.ATTACK:
			return BattleAction.attack(actor, target)
		
		BattleAction.ActionType.DEFEND:
			return BattleAction.defend(actor)
		
		BattleAction.ActionType.SKILL:
			var skill = actor.get_skill_instance(data.skill_name)
			if not skill:
				push_error("[BATTLE SYNC] Skill not found: %s" % data.skill_name)
				return null
			return BattleAction.skill(actor, skill, target)
		
		BattleAction.ActionType.ITEM:
			var item = ItemManager.get_item(data.item_id)
			if not item:
				push_error("[BATTLE SYNC] Item not found: %s" % data.item_id)
				return null
			
			# Determine targets based on item type
			var targets = []
			match item.consumable_type:
				Item.ConsumableType.DAMAGE, Item.ConsumableType.DEBUFF:
					targets = [target]  # Attack local player
				_:
					targets = [actor]  # Heal/buff opponent
			
			return BattleAction.item(actor, item, targets)
	
	return null
