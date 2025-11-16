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
const MAX_CLIENTS := 1  # 1v1 only

var peer: ENetMultiplayerPeer
var is_host := false
var players := {}  # peer_id -> player_info
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
	
	# Host is player 1 - initialize as NOT ready
	players[local_player_id] = {
		"character": CharacterManager.get_current_character(),
		"ready": false
	}
	
	print("[ARENA NET] Server created on port %d (ID: %d)" % [port, local_player_id])
	print("[ARENA NET] Host must call set_ready() when ready")
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
		# Generate match seed for deterministic gameplay
		match_seed = RandomManager.new_game_seed()
		
		# Request client's character data
		rpc_id(id, "_receive_match_setup", match_seed)

func _on_peer_disconnected(id: int):
	print("[ARENA NET] Peer disconnected: %d" % id)
	
	if players.has(id):
		players.erase(id)
		emit_signal("player_disconnected", id)
	
	# End match if opponent leaves
	if not is_host:
		disconnect_from_match()

func _on_connected_to_server():
	print("[ARENA NET] Connected to server successfully")
	local_player_id = multiplayer.get_unique_id()
	
	# Register ourselves locally first
	var character = CharacterManager.get_current_character()
	players[local_player_id] = {
		"character": character,
		"ready": false
	}
	print("[ARENA NET] Registered self (ID: %d) locally" % local_player_id)
	
	# Send our character to host
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
	
	# Deserialize character
	var character = _deserialize_character(character_data)
	
	players[peer_id] = {
		"character": character,
		"ready": false
	}
	
	print("[ARENA NET] Players dict now has %d players: %s" % [players.size(), players.keys()])
	
	emit_signal("player_connected", peer_id, players[peer_id])
	
	# If we're the host and client just registered, send our character back
	if is_host and peer_id != local_player_id:
		print("[ARENA NET] Sending host character to client %d" % peer_id)
		var host_character = players[local_player_id].character
		rpc_id(peer_id, "_receive_host_character", local_player_id, _serialize_character(host_character))
	
	# If we have 2 players, can start match
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
	
	# Register host (peer 1) in our local players dict
	# We'll receive their full character data via _sync_opponent_character
	print("[ARENA NET] Waiting for host character data...")
	
	# Send our character to host
	var character = CharacterManager.get_current_character()
	rpc_id(1, "_register_player", local_player_id, _serialize_character(character))

@rpc("any_peer", "call_local", "reliable")
func _player_ready(peer_id: int):
	print("[ARENA NET] Player %d ready signal received" % peer_id)
	
	if players.has(peer_id):
		players[peer_id].ready = true
		print("[ARENA NET] Player %d is now ready" % peer_id)
	else:
		print("[ARENA NET] WARNING: Player %d not found in players dict!" % peer_id)
	
	# Debug: Show all player ready states
	for pid in players:
		print("[ARENA NET] Player %d ready: %s" % [pid, players[pid].ready])
	
	# Check if both players ready
	if _all_players_ready():
		print("[ARENA NET] All players ready, starting match...")
		_start_match()
	else:
		print("[ARENA NET] Waiting for more players... (%d/%d ready)" % [_count_ready_players(), players.size()])

@rpc("any_peer", "call_local", "reliable")
func _start_match_signal(is_host_flag: bool):
	print("[ARENA NET] Match starting! (is_host: %s)" % is_host_flag)
	emit_signal("match_started", is_host_flag)

@rpc("any_peer", "unreliable")
func _send_action(action_data: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	print("[ARENA NET] Action received from %d: %s" % [sender_id, action_data])
	emit_signal("action_received", sender_id, action_data)

@rpc("any_peer", "call_local", "reliable")
func _end_match(winner_id: int):
	print("[ARENA NET] Match ended, winner: %d" % winner_id)
	emit_signal("match_ended", winner_id)

# === PUBLIC API ===

func set_ready():
	"""Call this when player is ready to start"""
	if multiplayer.multiplayer_peer:
		rpc("_player_ready", local_player_id)

func send_action(action: Dictionary):
	"""Send combat action to opponent"""
	if multiplayer.multiplayer_peer:
		rpc("_send_action", action)

func end_match(winner_id: int):
	"""Call this to end the match"""
	if multiplayer.multiplayer_peer:
		rpc("_end_match", winner_id)

func get_opponent_id() -> int:
	"""Get the opponent's peer ID"""
	for peer_id in players:
		if peer_id != local_player_id:
			return peer_id
	return -1

func get_opponent_character() -> CharacterData:
	"""Get opponent's character"""
	var opponent_id = get_opponent_id()
	if opponent_id != -1 and players.has(opponent_id):
		return players[opponent_id].character
	return null

# === HELPERS ===

func _all_players_ready() -> bool:
	if players.size() < 2:
		print("[ARENA NET] Not enough players: %d/2" % players.size())
		return false
	
	for pid in players:
		if not players[pid].ready:
			print("[ARENA NET] Player %d not ready yet" % pid)
			return false
	
	print("[ARENA NET] All %d players are ready!" % players.size())
	return true

func _count_ready_players() -> int:
	var count = 0
	for player_info in players.values():
		if player_info.ready:
			count += 1
	return count

func _start_match():
	"""Called when both players are ready"""
	print("[ARENA NET] Starting match with seed %d" % match_seed)
	RandomManager.seed = match_seed
	rpc("_start_match_signal", is_host)

# === CHARACTER SERIALIZATION ===

func _serialize_character(character: CharacterData) -> Dictionary:
	"""Convert CharacterData to network-safe Dictionary"""
	
	# Serialize skills - handle both Skill objects and strings
	var serialized_skills = []
	for skill in character.skills:
		if skill == null:
			continue  # Skip null skills
		elif skill is String:
			serialized_skills.append(skill)
		elif skill is Skill:
			serialized_skills.append(skill.name)
		else:
			print("[ARENA NET] Warning: Unknown skill type: %s" % typeof(skill))
	
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
		
		# Skills (array of skill names)
		"skills": serialized_skills,
		
		# Equipment (simplified)
		"equipment": _serialize_equipment(character.equipment)
	}

func _serialize_equipment(equipment: Dictionary) -> Dictionary:
	"""Serialize equipment dictionary"""
	var result = {}
	
	for slot in equipment:
		var item = equipment[slot]
		
		if item == null:
			continue
		
		# Handle Equipment objects
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
				"item_level": item.item_level
			}
		# Handle pre-serialized data
		elif item is Dictionary:
			result[slot] = item
		else:
			print("[ARENA NET] Warning: Unknown equipment type in slot %s: %s" % [slot, typeof(item)])
	
	return result

func _deserialize_character(data: Dictionary) -> CharacterData:
	"""Reconstruct CharacterData from Dictionary"""
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
	
	# Skills - filter out empty/null strings
	if data.has("skills"):
		var valid_skills = []
		for skill_name in data.skills:
			if skill_name != null and skill_name != "":
				valid_skills.append(skill_name)
		
		if not valid_skills.is_empty():
			character.skill_manager.add_skills(valid_skills)
	
	# Recalculate derived stats
	character.calculate_secondary_attributes()
	
	return character
