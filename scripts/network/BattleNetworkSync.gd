# res://scripts/network/BattleNetworkSync.gd
# Fixed version - uses peer_id mapping to correctly identify local vs remote characters
class_name BattleNetworkSync
extends RefCounted

signal sync_ready()

var orchestrator
var network: ArenaNetworkManager
var is_pvp_mode := false
var is_my_turn := false
var waiting_for_opponent := false
var awaiting_turn_sync: bool = false

# ✅ CRITICAL: Track last timestamp PER action type to prevent duplicates
var last_status_damage_timestamp: int = 0
var last_item_timestamp: int = 0
var last_action_timestamp: int = 0
var last_turn_end_timestamp: int = 0  # ✅ NEW: Prevent ending turn twice

# ✅ NEW: Store which character belongs to which peer
var local_player_id: int = 0
var opponent_player_id: int = 0
var my_character: CharacterData = null
var opponent_character: CharacterData = null

func initialize(orch, is_pvp: bool = false):
	"""Initialize network sync wrapper"""
	orchestrator = orch
	is_pvp_mode = is_pvp
	
	if not is_pvp_mode:
		print("[BATTLE SYNC] Running in PvE mode, no network sync")
		return
	
	if not orch.has_node("/root/ArenaNetworkManager"):
		push_error("[BATTLE SYNC] ArenaNetworkManager not found!")
		return
	
	network = orch.get_node("/root/ArenaNetworkManager")
	
	# ✅ CRITICAL FIX: Determine character ownership
	local_player_id = network.local_player_id
	opponent_player_id = network.get_opponent_id()
	
	# Map characters based on who initialized the battle
	# The player who called setup_pvp_battle owns orchestrator.player
	my_character = orchestrator.player
	opponent_character = orchestrator.enemy
	
	print("[BATTLE SYNC] Character mapping:")
	print("  - My peer ID: %d, My character: %s (instance: %s)" % [
		local_player_id, my_character.name, my_character.get_instance_id()
	])
	print("  - Opponent peer ID: %d, Opponent character: %s (instance: %s)" % [
		opponent_player_id, opponent_character.name, opponent_character.get_instance_id()
	])
	
	# Connect network signals (disconnect first to prevent duplicates)
	if network.action_received.is_connected(_on_network_action_received):
		network.action_received.disconnect(_on_network_action_received)
	network.action_received.connect(_on_network_action_received)
	
	if network.match_ended.is_connected(_on_match_ended):
		network.match_ended.disconnect(_on_match_ended)
	network.match_ended.connect(_on_match_ended)
	
	print("[BATTLE SYNC] Initialized in PvP mode")

# === TURN MANAGEMENT ===

func on_turn_started(character: CharacterData, is_player: bool):
	"""Called when a turn starts locally"""
	# Determine if it's my turn based on character instance
	is_my_turn = (character.get_instance_id() == my_character.get_instance_id())
	
	print("[BATTLE SYNC] Turn started - %s (instance: %s, my turn: %s)" % [
		character.name, character.get_instance_id(), is_my_turn
	])
	
	if not is_my_turn:
		waiting_for_opponent = true
		print("[BATTLE SYNC] Now waiting for opponent action")
	else:
		waiting_for_opponent = false

func _on_network_action_received(peer_id: int, action_data: Dictionary):
	"""Received opponent's action from network"""
	var action_type = int(action_data.get("type", -1))
	var is_item = (action_type == BattleAction.ActionType.ITEM)
	var is_status_damage = (action_type == -2)
	var timestamp = action_data.get("timestamp", 0)
	
	# ✅ CRITICAL: Per-type duplicate detection
	if timestamp > 0:
		if is_status_damage and timestamp == last_status_damage_timestamp:
			print("[BATTLE SYNC] DUPLICATE status damage - Ignoring (timestamp: %d)" % timestamp)
			return
		elif is_item and timestamp == last_item_timestamp:
			print("[BATTLE SYNC] DUPLICATE item - Ignoring (timestamp: %d)" % timestamp)
			return
		elif not is_item and not is_status_damage and timestamp == last_action_timestamp:
			print("[BATTLE SYNC] DUPLICATE action - Ignoring (timestamp: %d)" % timestamp)
			return
		
		# Mark as processed
		if is_status_damage:
			last_status_damage_timestamp = timestamp
		elif is_item:
			last_item_timestamp = timestamp
		else:
			last_action_timestamp = timestamp
	
	# ✅ Status damage handling
	if is_status_damage:
		print("[BATTLE SYNC] Received status damage sync from peer %d (timestamp: %d)" % [peer_id, timestamp])
		_apply_status_damage(action_data)
		return
	
	if not is_item and not waiting_for_opponent:
		print("[BATTLE SYNC] Ignoring non-item action - not waiting")
		return
	
	if not is_item:
		waiting_for_opponent = false
	
	print("[BATTLE SYNC] Received opponent action: type=%d, is_item=%s, from peer=%d, timestamp=%d" % [
		action_type, is_item, peer_id, timestamp
	])
	
	_apply_opponent_action_result(action_data)

func _apply_status_damage(data: Dictionary):
	"""Apply status effect damage received from opponent"""
	var target_is_opponent = data.get("target_is_opponent", false)
	var target = my_character if target_is_opponent else opponent_character
	
	var damage = data.get("damage", 0)
	var healing = data.get("healing", 0)
	var message = data.get("message", "")
	
	print("[BATTLE SYNC] Applying status damage to %s: dmg=%d, heal=%d" % [
		target.name, damage, healing
	])
	
	# Apply damage
	if damage > 0:
		var old_hp = target.current_hp
		target.current_hp = max(0, target.current_hp - damage)
		print("[BATTLE SYNC] Status damage: %s HP %d -> %d" % [
			target.name, old_hp, target.current_hp
		])
	
	# Apply healing
	if healing > 0:
		var old_hp = target.current_hp
		target.current_hp = min(target.max_hp, target.current_hp + healing)
		print("[BATTLE SYNC] Status healing: %s HP %d -> %d" % [
			target.name, old_hp, target.current_hp
		])
	
	# Display message
	if message != "":
		var log_color = "purple"
		orchestrator.ui_controller.add_combat_log(message, log_color)
	
	# Update UI
	orchestrator.ui_controller.update_character_info(orchestrator.player, orchestrator.enemy)

func _apply_opponent_action_result(data: Dictionary):
	"""Apply the result of opponent's action"""
	var action_type = int(data.get("type", -1))
	var is_item = (action_type == BattleAction.ActionType.ITEM)
	
	# ✅ CRITICAL FIX: Use stored character references instead of orchestrator's
	# This ensures we always modify the correct character
	var actor = opponent_character  # Opponent always performs the action
	var target_is_opponent = data.get("target_is_opponent", false)
	
	# Target determination:
	# If opponent says "target_is_opponent=true", they're targeting THEIR opponent (which is ME)
	# If opponent says "target_is_opponent=false", they're targeting themselves
	var target = my_character if target_is_opponent else opponent_character
	
	print("[BATTLE SYNC] Applying action:")
	print("  - Actor: %s (instance: %s)" % [actor.name, actor.get_instance_id()])
	print("  - Target: %s (instance: %s)" % [target.name, target.get_instance_id()])
	print("  - target_is_opponent: %s" % target_is_opponent)
	
	print("[BATTLE SYNC] Before - My HP: %d/%d, Opponent HP: %d/%d" % [
		my_character.current_hp, my_character.max_hp,
		opponent_character.current_hp, opponent_character.max_hp
	])
	
	# Extract data
	var damage = data.get("damage", 0)
	var sp_cost = data.get("sp_cost", 0)
	var mp_cost = data.get("mp_cost", 0)
	var healing = data.get("healing", 0)
	var sp_gain = data.get("sp_gain", 0)
	var mp_gain = data.get("mp_gain", 0)
	var message = data.get("message", "")
	var status_effects = data.get("status_effects", [])
	var status_effects_removed = data.get("status_effects_removed", [])  # ✅ NEW
	var buffs_debuffs = data.get("buffs_debuffs", [])
	
	# Apply costs to actor
	if sp_cost > 0:
		actor.current_sp = max(0, actor.current_sp - sp_cost)
		print("[BATTLE SYNC] Applied SP cost: %d to %s (now: %d/%d)" % [
			sp_cost, actor.name, actor.current_sp, actor.max_sp
		])
	
	if mp_cost > 0:
		actor.current_mp = max(0, actor.current_mp - mp_cost)
		print("[BATTLE SYNC] Applied MP cost: %d to %s (now: %d/%d)" % [
			mp_cost, actor.name, actor.current_mp, actor.max_mp
		])
	
	# Apply resource gains to actor
	if sp_gain > 0:
		actor.current_sp = min(actor.max_sp, actor.current_sp + sp_gain)
		print("[BATTLE SYNC] Applied SP gain: %d to %s (now: %d/%d)" % [
			sp_gain, actor.name, actor.current_sp, actor.max_sp
		])
	
	if mp_gain > 0:
		actor.current_mp = min(actor.max_mp, actor.current_mp + mp_gain)
		print("[BATTLE SYNC] Applied MP gain: %d to %s (now: %d/%d)" % [
			mp_gain, actor.name, actor.current_mp, actor.max_mp
		])
	
	# Apply damage to target
	if damage > 0:
		var old_hp = target.current_hp
		target.current_hp = max(0, target.current_hp - damage)
		print("[BATTLE SYNC] Applied %d damage to %s: %d -> %d (max: %d)" % [
			damage, target.name, old_hp, target.current_hp, target.max_hp
		])
	
	# Apply healing
	if healing > 0:
		var is_drain = data.get("is_drain", false)
		
		if is_drain:
			# Drain: healing goes to actor
			var old_hp = actor.current_hp
			actor.current_hp = min(actor.max_hp, actor.current_hp + healing)
			print("[BATTLE SYNC] Applied %d healing to %s (drain): %d -> %d" % [
				healing, actor.name, old_hp, actor.current_hp
			])
		else:
			# Normal: healing goes to target
			var old_hp = target.current_hp
			target.current_hp = min(target.max_hp, target.current_hp + healing)
			print("[BATTLE SYNC] Applied %d healing to %s: %d -> %d" % [
				healing, target.name, old_hp, target.current_hp
			])
	
	# Apply status effects to target
	if not status_effects.is_empty() and target.status_manager:
		for status_data in status_effects:
			var status_name = status_data.get("name", "")
			var duration = status_data.get("duration", 3)
			
			if status_name != "" and Skill.StatusEffect.has(status_name):
				var status_enum = Skill.StatusEffect[status_name]
				target.status_manager.apply_effect(status_enum, duration)
				print("[BATTLE SYNC] Applied %s to %s for %d turns" % [
					status_name, target.name, duration
				])
	
	# ✅ NEW: Remove status effects from target (cure items)
	if not status_effects_removed.is_empty() and target.status_manager:
		print("[BATTLE SYNC] Processing %d status effect removals on %s" % [
			status_effects_removed.size(), target.name
		])
		for removal_data in status_effects_removed:
			var status_name = removal_data.get("name", "")
			print("[BATTLE SYNC] Attempting to remove: %s" % status_name)
			
			if status_name == "ALL":
				# Cure all effects (holy water)
				target.status_manager.clear_all_effects()
				print("[BATTLE SYNC] Removed ALL status effects from %s" % target.name)
			elif status_name != "" and Skill.StatusEffect.has(status_name):
				# Cure specific effect
				var status_enum = Skill.StatusEffect[status_name]
				print("[BATTLE SYNC] Checking if %s has %s..." % [target.name, status_name])
				if target.status_manager.active_effects.has(status_enum):
					var removal_msg = target.status_manager.remove_effect(status_enum)
					print("[BATTLE SYNC] Removed %s from %s: %s" % [status_name, target.name, removal_msg])
				else:
					print("[BATTLE SYNC] WARNING: %s does NOT have %s active!" % [target.name, status_name])
	
	# Apply buffs/debuffs to target
	if not buffs_debuffs.is_empty() and target.buff_manager:
		for buff in buffs_debuffs:
			var stat_name = buff.get("stat", "")
			var amount = buff.get("amount", 0)
			var duration = buff.get("duration", 4)
			var is_debuff = buff.get("is_debuff", false)
			
			if stat_name != "" and amount != 0 and Skill.AttributeTarget.has(stat_name):
				var attr = Skill.AttributeTarget[stat_name]
				if is_debuff:
					target.buff_manager.apply_debuff(attr, abs(amount), duration)
					print("[BATTLE SYNC] Applied DEBUFF to %s: %s -%d for %d turns" % [
						target.name, stat_name, abs(amount), duration
					])
				else:
					target.buff_manager.apply_buff(attr, amount, duration)
					print("[BATTLE SYNC] Applied BUFF to %s: %s +%d for %d turns" % [
						target.name, stat_name, amount, duration
					])
	
	# Display combat log
	if message != "":
		var log_color = "red" if target == my_character else "cyan"
		orchestrator.ui_controller.add_combat_log(message, log_color)
		print("[BATTLE SYNC] Combat log: %s (color: %s)" % [message, log_color])
	
	print("[BATTLE SYNC] After - My HP: %d/%d, Opponent HP: %d/%d" % [
		my_character.current_hp, my_character.max_hp,
		opponent_character.current_hp, opponent_character.max_hp
	])
	
	# Force UI update - use orchestrator's player/enemy for UI display
	orchestrator.ui_controller.update_character_info(orchestrator.player, orchestrator.enemy)
	
	# Wait before continuing
	await orchestrator.get_tree().create_timer(0.5 if is_item else 1.5).timeout
	
	# Check if battle ended
	var battle_result = orchestrator.combat_engine.check_battle_end()
	if battle_result != "ongoing":
		return
	
	# Only end turn for main actions, not items
	if not is_item:
		# ✅ CRITICAL: Prevent ending turn twice for same action
		var timestamp = data.get("timestamp", 0)
		if timestamp > 0 and timestamp == last_turn_end_timestamp:
			print("[BATTLE SYNC] Turn already ended for timestamp %d - skipping" % timestamp)
			return
		last_turn_end_timestamp = timestamp
		
		print("[BATTLE SYNC] Opponent main action complete - ending their turn")
		orchestrator.turn_controller.end_current_turn()
	else:
		print("[BATTLE SYNC] Opponent item complete - NO turn change")

# === BATTLE END ===

func _on_match_ended(winner_id: int):
	"""Called when opponent ends match via network signal"""
	var i_won = (winner_id == local_player_id)
	print("[BATTLE SYNC] Match ended via network signal, winner: %d (me: %s)" % [winner_id, i_won])
	await _show_battle_end_dialog(i_won)

func _cleanup_battle():
	"""Clean up network resources"""
	print("[BATTLE SYNC] Cleaning up battle")
	
	if network:
		if network.action_received.is_connected(_on_network_action_received):
			network.action_received.disconnect(_on_network_action_received)
		if network.match_ended.is_connected(_on_match_ended):
			network.match_ended.disconnect(_on_match_ended)
		
		if network.peer:
			network.peer.close()
		network = null

func send_status_damage(character: CharacterData, status_result: ActionResult):
	"""Send status effect damage to opponent at turn start"""
	if not is_pvp_mode or not network:
		return
	
	# Determine if the character taking damage is the opponent
	var target_is_opponent = (character.get_instance_id() == opponent_character.get_instance_id())
	
	var status_data = {
		"type": -2,  # Special type for status damage sync
		"timestamp": Time.get_ticks_msec(),
		"damage": status_result.damage,
		"healing": status_result.healing,
		"message": status_result.message,
		"target_is_opponent": target_is_opponent
	}
	
	print("[BATTLE SYNC] Sending status damage: dmg=%d, heal=%d to %s (target_is_opp=%s)" % [
		status_data["damage"], status_data["healing"], character.name, target_is_opponent
	])
	network.send_action(status_data)

func on_battle_end(player_won: bool):
	"""Called when battle ends - notify opponent and show dialog"""
	print("[BATTLE SYNC] Battle ended - Player won: ", player_won)
	
	var winner_id = local_player_id if player_won else opponent_player_id
	
	network.send_battle_end(winner_id)
	print("[BATTLE SYNC] Sent battle end notification to opponent")
	
	await _show_battle_end_dialog(player_won)

func _show_battle_end_dialog(i_won: bool):
	"""Show victory/defeat dialog"""
	await orchestrator.get_tree().create_timer(1.0).timeout
	
	var dialog = AcceptDialog.new()
	if i_won:
		dialog.dialog_text = "Victory!\n\nYou defeated your opponent in the arena!"
		dialog.title = "Victory!"
	else:
		dialog.dialog_text = "Defeat!\n\nYou were defeated in the arena."
		dialog.title = "Defeat"
	
	dialog.ok_button_text = "Return to Town"
	orchestrator.add_child(dialog)
	dialog.popup_centered()
	
	await dialog.confirmed
	dialog.queue_free()
	
	print("[BATTLE SYNC] Saving and returning to town...")
	SaveManager.save_game(orchestrator.player)
	_cleanup_battle()
	SceneManager.change_to_town(orchestrator.player)

func on_action_selected(action: BattleAction, result):
	"""Called when local player performs an action - send RESULT to opponent"""
	print("[BATTLE SYNC] Local action completed: %s" % action.get_description())
	
	var serialized = _serialize_action_result(action, result)
	network.send_action(serialized)
	
	print("[BATTLE SYNC] Action result sent to opponent: dmg=%d, heal=%d" % [
		serialized.get("damage", 0),
		serialized.get("healing", 0)
	])

# === ACTION RESULT SERIALIZATION ===

func _serialize_action_result(action: BattleAction, result) -> Dictionary:
	"""Convert action + result to network data"""
	var data = {
		"type": action.type,
		"timestamp": Time.get_ticks_msec(),
		"damage": 0,
		"healing": 0,
		"sp_cost": 0,
		"mp_cost": 0,
		"sp_gain": 0,
		"mp_gain": 0,
		"message": "",
		"target_is_opponent": false,
		"is_drain": false,
		"status_effects": [],
		"status_effects_removed": [],  # ✅ NEW: Track removed effects
		"buffs_debuffs": []
	}
	
	# ✅ CRITICAL FIX: Determine target based on character instance IDs
	if action.targets and not action.targets.is_empty():
		var target = action.targets[0]
		
		# Compare instance IDs to determine which character was targeted
		var target_instance = target.get_instance_id()
		var my_instance = my_character.get_instance_id()
		var opponent_instance = opponent_character.get_instance_id()
		
		# If I targeted my opponent, then target_is_opponent = true
		# If I targeted myself, then target_is_opponent = false
		data["target_is_opponent"] = (target_instance == opponent_instance)
		
		print("[BATTLE SYNC] Serializing:")
		print("  - My character: %s (instance: %s)" % [my_character.name, my_instance])
		print("  - Opponent: %s (instance: %s)" % [opponent_character.name, opponent_instance])
		print("  - Target: %s (instance: %s)" % [target.name, target_instance])
		print("  - target_is_opponent: %s" % data["target_is_opponent"])
	
	# Extract result data
	if result:
		if "damage" in result:
			data["damage"] = result.damage
		
		if "healing" in result:
			data["healing"] = result.healing
		
		if "sp_cost" in result:
			data["sp_cost"] = result.sp_cost
		
		if "mp_cost" in result:
			data["mp_cost"] = result.mp_cost
		
		if "sp_gain" in result:
			data["sp_gain"] = result.sp_gain
		
		if "mp_gain" in result:
			data["mp_gain"] = result.mp_gain
		
		if result.has_method("get_description"):
			data["message"] = result.get_description()
		elif "message" in result:
			data["message"] = result.message
		
		# Check for drain skills
		if action.type == BattleAction.ActionType.SKILL and action.skill_data:
			if action.skill_data.type == Skill.SkillType.DRAIN:
				data["is_drain"] = true
		
		# Extract status effects
		if "status_effects" in result and result.status_effects is Array:
			for effect in result.status_effects:
				data["status_effects"].append({
					"name": effect.get("name", ""),
					"duration": effect.get("duration", 3)
				})
		
		# ✅ NEW: Extract status effect removals (cure items)
		if "status_effects_removed" in result and result.status_effects_removed is Array:
			print("[BATTLE SYNC] Extracting %d status effect removals" % result.status_effects_removed.size())
			for effect in result.status_effects_removed:
				data["status_effects_removed"].append({
					"name": effect.get("name", "")
				})
				print("[BATTLE SYNC] Added removal: %s" % effect.get("name", ""))
		
		# Extract buffs/debuffs
		if "buffs" in result and result.buffs is Array:
			for buff in result.buffs:
				data["buffs_debuffs"].append({
					"stat": buff.get("stat", ""),
					"amount": buff.get("amount", 0),
					"duration": buff.get("duration", 4),
					"is_debuff": false
				})
		
		if "debuffs" in result and result.debuffs is Array:
			for debuff in result.debuffs:
				data["buffs_debuffs"].append({
					"stat": debuff.get("stat", ""),
					"amount": debuff.get("amount", 0),
					"duration": debuff.get("duration", 4),
					"is_debuff": true
				})
	
	# Add type-specific data
	match action.type:
		BattleAction.ActionType.SKILL:
			data["skill_name"] = action.skill_data.name if action.skill_data else ""
		BattleAction.ActionType.ITEM:
			data["item_id"] = action.item_data.id if action.item_data else ""
	
	print("[BATTLE SYNC] Serialized: dmg=%d, heal=%d, sp=%d, mp=%d, target_is_opp=%s, status_removed=%d" % [
		data["damage"], data["healing"], data["sp_cost"], data["mp_cost"], data["target_is_opponent"],
		data["status_effects_removed"].size()
	])
	
	return data
