# res://scripts/network/ArenaNetworkManager.gd
extends Node

signal connection_success()
signal connection_failed()
signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal match_started(is_host: bool)
signal match_ended(winner_id: int)
signal action_received(peer_id: int, action: Dictionary)

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 1

var peer: ENetMultiplayerPeer
var is_host := false
var players := {}
var local_player_id := 1
var match_seed := 0

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# === HOST ===

func create_server(port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	
	if error != OK:
		print("[ARENA NET] Failed to create server: ", error)
		return false
	
	multiplayer.multiplayer_peer = peer
	is_host = true
	local_player_id = multiplayer.get_unique_id()
	
	players[local_player_id] = {
		"character": CharacterManager.get_current_character(),
		"ready": false
	}
	
	print("[ARENA NET] Server created on port %d (ID: %d)" % [port, local_player_id])
	return true

# === CLIENT ===

func join_server(address: String, port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		print("[ARENA NET] Failed to connect to %s:%d - Error: %d" % [address, port, error])
		return false
	
	multiplayer.multiplayer_peer = peer
	is_host = false
	
	print("[ARENA NET] Connecting to %s:%d..." % [address, port])
	return true

# === DISCONNECT ===

func disconnect_from_match():
	if peer:
		peer.close()
		peer = null
	
	players.clear()
	is_host = false
	match_seed = 0
	multiplayer.multiplayer_peer = null
	print("[ARENA NET] Disconnected from match")

# === CALLBACKS ===

func _on_peer_connected(id: int):
	print("[ARENA NET] Peer connected: %d" % id)
	
	if is_host:
		match_seed = RandomManager.new_game_seed()
		rpc_id(id, "_receive_match_setup", match_seed)

func _on_peer_disconnected(id: int):
	print("[ARENA NET] Peer disconnected: %d" % id)
	
	if players.has(id):
		players.erase(id)
		emit_signal("player_disconnected", id)
	
	if not is_host:
		disconnect_from_match()

func _on_connected_to_server():
	print("[ARENA NET] Connected to server successfully")
	local_player_id = multiplayer.get_unique_id()
	
	var character = CharacterManager.get_current_character()
	players[local_player_id] = {
		"character": character,
		"ready": false
	}
	print("[ARENA NET] Registered self (ID: %d) locally" % local_player_id)
	
	rpc_id(1, "_register_player", local_player_id, _serialize_character(character))
	emit_signal("connection_success")

func _on_connection_failed():
	print("[ARENA NET] Connection failed")
	emit_signal("connection_failed")
	disconnect_from_match()

func _on_server_disconnected():
	print("[ARENA NET] Server disconnected")
	disconnect_from_match()

# === RPC FUNCTIONS ===

@rpc("any_peer", "reliable")
func _register_player(peer_id: int, character_data: Dictionary):
	print("[ARENA NET] Player registered: %d" % peer_id)
	
	var character = _deserialize_character(character_data)
	
	players[peer_id] = {
		"character": character,
		"ready": false
	}
	
	print("[ARENA NET] Players dict now has %d players: %s" % [players.size(), players.keys()])
	emit_signal("player_connected", peer_id, players[peer_id])
	
	if is_host and peer_id != local_player_id:
		print("[ARENA NET] Sending host character to client %d" % peer_id)
		var host_character = players[local_player_id].character
		rpc_id(peer_id, "_receive_host_character", local_player_id, _serialize_character(host_character))
	
	if players.size() == 2:
		print("[ARENA NET] Both players connected, ready to start")

@rpc("authority", "reliable")
func _receive_host_character(host_id: int, character_data: Dictionary):
	print("[ARENA NET] Received host character (ID: %d)" % host_id)
	
	var character = _deserialize_character(character_data)
	
	players[host_id] = {
		"character": character,
		"ready": false
	}
	
	print("[ARENA NET] Players dict now has %d players: %s" % [players.size(), players.keys()])
	emit_signal("player_connected", host_id, players[host_id])

@rpc("authority", "reliable")
func _receive_match_setup(seed: int):
	print("[ARENA NET] Received match setup with seed: %d" % seed)
	match_seed = seed
	RandomManager.seed = seed
	
	var character = CharacterManager.get_current_character()
	rpc_id(1, "_register_player", local_player_id, _serialize_character(character))

@rpc("any_peer", "call_local", "reliable")
func _player_ready(peer_id: int):
	print("[ARENA NET] Player %d ready signal received" % peer_id)
	
	if players.has(peer_id):
		players[peer_id].ready = true
		print("[ARENA NET] Player %d is now ready" % peer_id)
	
	if _all_players_ready():
		print("[ARENA NET] All players ready, starting match...")
		_start_match()

@rpc("any_peer", "call_local", "reliable")
func _start_match_signal(is_host_flag: bool):
	print("[ARENA NET] Match starting! (is_host: %s)" % is_host_flag)
	emit_signal("match_started", is_host_flag)

# ✅ CRITICAL FIX: Changed to reliable to prevent duplicate/lost actions
@rpc("any_peer", "call_remote", "reliable")
func _send_action(action_data: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	print("[ARENA NET] Action received from %d (timestamp: %d)" % [sender_id, action_data.get("timestamp", 0)])
	emit_signal("action_received", sender_id, action_data)

@rpc("any_peer", "call_local", "reliable")
func _end_match(winner_id: int):
	print("[ARENA NET] Match ended, winner: %d" % winner_id)
	emit_signal("match_ended", winner_id)

# === PUBLIC API ===

func set_ready():
	if multiplayer.multiplayer_peer:
		rpc("_player_ready", local_player_id)

func send_action(action: Dictionary):
	"""Send combat action to opponent"""
	if multiplayer.multiplayer_peer:
		print("[ARENA NET] Sending action to opponent (timestamp: %d)" % action.get("timestamp", 0))
		rpc("_send_action", action)

func send_battle_end(winner_id: int):
	"""Send battle end notification to opponent"""
	if multiplayer.multiplayer_peer:
		print("[ARENA NET] Sending battle end, winner: %d" % winner_id)
		rpc("_end_match", winner_id)

func end_match(winner_id: int):
	if multiplayer.multiplayer_peer:
		rpc("_end_match", winner_id)

func get_opponent_id() -> int:
	for peer_id in players:
		if peer_id != local_player_id:
			return peer_id
	return -1

func get_opponent_character() -> CharacterData:
	var opponent_id = get_opponent_id()
	if opponent_id != -1 and players.has(opponent_id):
		return players[opponent_id].character
	return null

# === HELPERS ===

func _all_players_ready() -> bool:
	if players.size() < 2:
		return false
	
	for pid in players:
		if not players[pid].ready:
			return false
	
	return true

func _start_match():
	print("[ARENA NET] Starting match with seed %d" % match_seed)
	RandomManager.seed = match_seed
	rpc("_start_match_signal", is_host)

# === CHARACTER SERIALIZATION ===

func _serialize_character(character: CharacterData) -> Dictionary:
	"""Convert CharacterData to network-safe Dictionary"""
	
	var serialized_skills = []
	for skill in character.skills:
		if skill == null:
			continue
		elif skill is String:
			serialized_skills.append(skill)
		elif skill is Skill:
			serialized_skills.append(skill.name)
	
	return {
		"name": character.name,
		"level": character.level,
		"race": character.race,
		"character_class": character.character_class,
		
		# Primary attributes
		"vitality": character.vitality,
		"strength": character.strength,
		"dexterity": character.dexterity,
		"intelligence": character.intelligence,
		"faith": character.faith,
		"mind": character.mind,
		"endurance": character.endurance,
		"arcane": character.arcane,
		"agility": character.agility,
		"fortitude": character.fortitude,
		
		# Secondary attributes
		"max_hp": character.max_hp,
		"max_mp": character.max_mp,
		"max_sp": character.max_sp,
		
		# Skills
		"skills": serialized_skills,
		
		# ✅ FIXED: Complete equipment serialization
		"equipment": _serialize_equipment(character.equipment)
	}

func _serialize_equipment(equipment: Dictionary) -> Dictionary:
	"""✅ FIXED: Complete equipment serialization including stat modifiers"""
	var result = {}
	
	for slot in equipment:
		var item = equipment[slot]
		
		if item == null:
			continue
		
		if item is Equipment:
			result[slot] = {
				"id": item.id,
				"key": item.key,
				"name": item.name,
				"type": item.type,
				"slot": item.slot,
				"damage": item.damage,
				"armor_value": item.armor_value,
				"rarity": item.rarity,
				"item_level": item.item_level,
				
				# ✅ NEW: Serialize stat modifiers
				"stat_modifiers": item.stat_modifiers,
				"status_effect_type": item.status_effect_type,
				"status_effect_chance": item.status_effect_chance,
				"bonus_damage": item.bonus_damage,
				
				# ✅ NEW: Serialize naming
				"item_prefix": item.item_prefix,
				"item_suffix": item.item_suffix,
				"flavor_text": item.flavor_text,
				
				# ✅ NEW: Mark as already generated
				"rarity_applied": item.rarity_applied,
				"base_item_level": item.base_item_level
			}
		elif item is Dictionary:
			result[slot] = item
	
	return result

func _deserialize_character(data: Dictionary) -> CharacterData:
	"""✅ FIXED: Reconstruct CharacterData with equipment"""
	var character = CharacterData.new()
	
	character.name = data.name
	character.level = data.level
	character.race = data.race
	character.character_class = data.character_class
	
	# Primary attributes
	character.vitality = data.vitality
	character.strength = data.strength
	character.dexterity = data.dexterity
	character.intelligence = data.intelligence
	character.faith = data.faith
	character.mind = data.mind
	character.endurance = data.endurance
	character.arcane = data.arcane
	character.agility = data.agility
	character.fortitude = data.fortitude
	
	# Secondary attributes
	character.max_hp = data.max_hp
	character.max_mp = data.max_mp
	character.max_sp = data.max_sp
	character.current_hp = character.max_hp
	character.current_mp = character.max_mp
	character.current_sp = character.max_sp
	
	# Initialize managers
	character.status_manager = StatusEffectManager.new(character)
	character.buff_manager = BuffDebuffManager.new(character)
	character.skill_manager = SkillProgressionManager.new(character)
	character.proficiency_manager = ProficiencyManager.new(character)
	character.elemental_resistances = ElementalResistanceManager.new(character)
	
	# Skills
	if data.has("skills"):
		var valid_skills = []
		for skill_name in data.skills:
			if skill_name != null and skill_name != "":
				valid_skills.append(skill_name)
		
		if not valid_skills.is_empty():
			character.skill_manager.add_skills(valid_skills)
	
	# ✅ CRITICAL FIX: Deserialize equipment
	if data.has("equipment"):
		_deserialize_equipment(character, data.equipment)
	
	# Recalculate with equipment bonuses
	character.calculate_secondary_attributes()
	
	print("[ARENA NET] Deserialized character: %s (Level %d)" % [character.name, character.level])
	print("  - HP: %d/%d" % [character.current_hp, character.max_hp])
	print("  - Equipment slots: %s" % [character.equipment.keys()])
	
	return character

func _deserialize_equipment(character: CharacterData, equipment_data: Dictionary):
	"""✅ NEW: Deserialize equipment and apply to character"""
	
	for slot in equipment_data:
		var item_data = equipment_data[slot]
		
		if item_data is Dictionary and not item_data.is_empty():
			# Reconstruct Equipment object
			var equipment = Equipment.new(item_data)
			
			# Apply to character WITHOUT triggering inventory removal
			character.equipment[slot] = equipment
			equipment.apply_effects(character)
			
			if equipment.has_method("apply_stat_modifiers"):
				equipment.apply_stat_modifiers(character)
			
			print("[ARENA NET] Deserialized %s: %s (dmg=%d, armor=%d, mods=%d)" % [
				slot, equipment.name, equipment.damage, equipment.armor_value, 
				equipment.stat_modifiers.size()
			])
