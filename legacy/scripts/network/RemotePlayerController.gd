extends Node
class_name RemotePlayerController

@export var actor_id: String = ""
var pending_actions: Array = []

func _ready():
	if has_node("/root/ArenaNetworkAdapter"):
		var net = get_node("/root/ArenaNetworkAdapter")
		net.connect("action_received", Callable(self, "_on_action_received"))

func submit_action(ability_id: String, target_id: String):
	var action := {
		"actor_id": actor_id,
		"ability_id": ability_id,
		"target_id": target_id,
		"time": Time.get_ticks_msec()
	}
	get_node("/root/ArenaNetworkAdapter").send_action(action)

func _on_action_received(action: Dictionary):
	if action.get("actor_id", "") == actor_id:
		pending_actions.append(action)

func fetch_next_action() -> Dictionary:
	if pending_actions.is_empty():
		return {}
	return pending_actions.pop_front()
