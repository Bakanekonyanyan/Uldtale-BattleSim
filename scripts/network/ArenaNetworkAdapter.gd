extends Node
class_name ArenaNetworkAdapter

signal action_received(action: Dictionary)
signal match_started(seed: int)

var is_host := false

func start_as_host():
	is_host = true
	var seed = RandomManager.new_game_seed()
	emit_signal("match_started", seed)

func start_as_client(seed: int):
	is_host = false
	RandomManager.seed = seed
	emit_signal("match_started", seed)

func send_action(action: Dictionary):
	# Placeholder for ENet / multiplayer integration
	emit_signal("action_received", action)

func on_network_packet(packet: Dictionary):
	emit_signal("action_received", packet)
