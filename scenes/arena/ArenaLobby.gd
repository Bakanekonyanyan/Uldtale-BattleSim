# res://scenes/arena/ArenaLobby.gd
extends Control

# Main menu buttons
@onready var host_button = $UI/MenuContainer/HostButton
@onready var join_button = $UI/MenuContainer/JoinButton
@onready var back_button = $UI/MenuContainer/BackButton

# Host panel
@onready var host_panel = $UI/HostPanel
@onready var port_input = $UI/HostPanel/PortInput
@onready var start_host_button = $UI/HostPanel/StartHostButton
@onready var cancel_host_button = $UI/HostPanel/CancelButton
@onready var host_status_label = $UI/HostPanel/StatusLabel

# Join panel
@onready var join_panel = $UI/JoinPanel
@onready var address_input = $UI/JoinPanel/AddressInput
@onready var join_port_input = $UI/JoinPanel/PortInput
@onready var connect_button = $UI/JoinPanel/ConnectButton
@onready var cancel_join_button = $UI/JoinPanel/CancelButton
@onready var join_status_label = $UI/JoinPanel/StatusLabel

# Waiting panel
@onready var waiting_panel = $UI/WaitingPanel
@onready var waiting_label = $UI/WaitingPanel/WaitingLabel
@onready var ready_button = $UI/WaitingPanel/ReadyButton
@onready var cancel_waiting_button = $UI/WaitingPanel/CancelButton

var network: ArenaNetworkManager
var match_started := false  # ✅ NEW: Prevent duplicate match starts

func _ready():
	print("[ARENA LOBBY] Initializing...")
	
	# Get or create network manager
	if not has_node("/root/ArenaNetworkManager"):
		network = ArenaNetworkManager.new()
		network.name = "ArenaNetworkManager"
		get_tree().root.add_child(network)
		print("[ARENA LOBBY] Created new ArenaNetworkManager")
	else:
		network = get_node("/root/ArenaNetworkManager")
		print("[ARENA LOBBY] Using existing ArenaNetworkManager")
	
	# Connect network signals
	network.connection_success.connect(_on_connection_success)
	network.connection_failed.connect(_on_connection_failed)
	network.player_connected.connect(_on_player_connected)
	network.player_disconnected.connect(_on_player_disconnected)
	network.match_started.connect(_on_match_started)
	
	# Connect button signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	start_host_button.pressed.connect(_on_start_host_pressed)
	cancel_host_button.pressed.connect(_show_main_menu)
	
	connect_button.pressed.connect(_on_connect_pressed)
	cancel_join_button.pressed.connect(_show_main_menu)
	
	ready_button.pressed.connect(_on_ready_pressed)
	cancel_waiting_button.pressed.connect(_on_cancel_waiting_pressed)
	
	# Show main menu
	_show_main_menu()
	
	# Set default values
	port_input.text = str(ArenaNetworkManager.DEFAULT_PORT)
	join_port_input.text = str(ArenaNetworkManager.DEFAULT_PORT)
	address_input.text = "127.0.0.1"
	
	print("[ARENA LOBBY] Ready!")

# === UI STATE MANAGEMENT ===

func _show_main_menu():
	host_panel.hide()
	join_panel.hide()
	waiting_panel.hide()
	host_button.show()
	join_button.show()
	back_button.show()

func _show_host_panel():
	host_button.hide()
	join_button.hide()
	back_button.hide()
	host_panel.show()
	host_status_label.text = ""

func _show_join_panel():
	host_button.hide()
	join_button.hide()
	back_button.hide()
	join_panel.show()
	join_status_label.text = ""

func _show_waiting_panel(is_host: bool):
	host_panel.hide()
	join_panel.hide()
	waiting_panel.show()
	
	if is_host:
		waiting_label.text = "Hosting on port %s...\nWaiting for opponent..." % port_input.text
	else:
		waiting_label.text = "Connected to %s:%s\nWaiting for host..." % [
			address_input.text, join_port_input.text
		]
	
	ready_button.disabled = false
	ready_button.text = "Ready"

# === BUTTON CALLBACKS ===

func _on_host_pressed():
	print("[ARENA LOBBY] Host button pressed")
	_show_host_panel()

func _on_join_pressed():
	print("[ARENA LOBBY] Join button pressed")
	_show_join_panel()

func _on_back_pressed():
	print("[ARENA LOBBY] Back button pressed")
	var current_character = CharacterManager.get_current_character()
	SceneManager.change_to_town(current_character)

func _on_start_host_pressed():
	var port = int(port_input.text)
	
	if port < 1024 or port > 65535:
		host_status_label.text = "Invalid port (use 1024-65535)"
		return
	
	print("[ARENA LOBBY] Starting server on port %d..." % port)
	host_status_label.text = "Starting server..."
	
	var success = network.create_server(port)
	
	if success:
		print("[ARENA LOBBY] Server started successfully")
		_show_waiting_panel(true)
	else:
		print("[ARENA LOBBY] Failed to start server")
		host_status_label.text = "Failed to create server!"

func _on_connect_pressed():
	var address = address_input.text.strip_edges()
	var port = int(join_port_input.text)
	
	if address.is_empty():
		join_status_label.text = "Enter an IP address"
		return
	
	if port < 1024 or port > 65535:
		join_status_label.text = "Invalid port (use 1024-65535)"
		return
	
	print("[ARENA LOBBY] Connecting to %s:%d..." % [address, port])
	join_status_label.text = "Connecting..."
	
	var success = network.join_server(address, port)
	
	if not success:
		print("[ARENA LOBBY] Failed to initiate connection")
		join_status_label.text = "Failed to connect!"

func _on_ready_pressed():
	print("[ARENA LOBBY] Player pressed Ready")
	ready_button.disabled = true
	ready_button.text = "Waiting for opponent..."
	network.set_ready()

func _on_cancel_waiting_pressed():
	print("[ARENA LOBBY] Cancelling match")
	network.disconnect_from_match()
	_show_main_menu()

# === NETWORK CALLBACKS ===

func _on_connection_success():
	print("[ARENA LOBBY] Connection successful")
	_show_waiting_panel(false)

func _on_connection_failed():
	print("[ARENA LOBBY] Connection failed")
	join_status_label.text = "Connection failed!"
	await get_tree().create_timer(2.0).timeout
	_show_join_panel()

func _on_player_connected(peer_id: int, player_info: Dictionary):
	print("[ARENA LOBBY] Player connected: %d" % peer_id)
	waiting_label.text = "Opponent found!\nPress Ready when you're prepared."

func _on_player_disconnected(peer_id: int):
	print("[ARENA LOBBY] Player disconnected: %d" % peer_id)
	
	var dialog = AcceptDialog.new()
	dialog.dialog_text = "Opponent disconnected!"
	dialog.ok_button_text = "OK"
	add_child(dialog)
	dialog.popup_centered()
	
	await dialog.confirmed
	dialog.queue_free()
	
	network.disconnect_from_match()
	_show_main_menu()

func _on_match_started(is_host: bool):
	# ✅ CRITICAL FIX: Prevent duplicate match starts
	if match_started:
		print("[ARENA LOBBY] ❌ Match already started - ignoring duplicate signal")
		return
	match_started = true
	
	print("[ARENA LOBBY] Match starting! (is_host: %s)" % is_host)
	
	# Get opponent character
	var opponent = network.get_opponent_character()
	
	if not opponent:
		push_error("[ARENA LOBBY] ERROR: No opponent character found!")
		match_started = false  # Reset flag on error
		return
	
	print("[ARENA LOBBY] Opponent character loaded: %s (Level %d)" % [opponent.name, opponent.level])
	
	# Load Battle.tscn
	var battle_scene = load("res://scenes/battle/Battle.tscn")
	if not battle_scene:
		push_error("[ARENA LOBBY] Battle.tscn not found!")
		match_started = false  # Reset flag on error
		return
	
	var battle = battle_scene.instantiate()
	
	# ✅ FIX: The root node "Battle" IS the BattleOrchestrator
	# The .tscn file shows: [node name="Battle" type="Node2D" script="BattleOrchestrator.gd"]
	# So 'battle' already IS the orchestrator
	var orchestrator = battle  # Don't use get_node()!
	
	if not orchestrator:
		push_error("[ARENA LOBBY] Failed to get BattleOrchestrator!")
		battle.queue_free()
		match_started = false  # Reset flag on error
		return
	
	# Verify it's the right type
	if not orchestrator.has_method("setup_pvp_battle"):
		push_error("[ARENA LOBBY] BattleOrchestrator doesn't have setup_pvp_battle method!")
		push_error("  Node type: %s" % orchestrator.get_class())
		push_error("  Script: %s" % orchestrator.get_script())
		battle.queue_free()
		match_started = false  # Reset flag on error
		return
	
	print("[ARENA LOBBY] BattleOrchestrator found, setting up PvP battle...")
	
	# Setup PvP battle
	var local_player = CharacterManager.get_current_character()
	if not local_player:
		push_error("[ARENA LOBBY] No local player character!")
		battle.queue_free()
		match_started = false  # Reset flag on error
		return
	
	print("[ARENA LOBBY] Local player: %s (Level %d)" % [local_player.name, local_player.level])
	
	# Call setup
	orchestrator.setup_pvp_battle(local_player, opponent)
	
	print("[ARENA LOBBY] PvP battle configured, transitioning to battle scene...")
	
	# Change to battle scene
	get_tree().root.add_child(battle)
	queue_free()
	
	print("[ARENA LOBBY] Battle scene transition complete!")
