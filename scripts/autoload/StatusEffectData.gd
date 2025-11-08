extends Node
class_name StatusEffectData

var effects: Dictionary = {}

func _ready():
	var path = "res://data/status_effects.json"
	if not FileAccess.file_exists(path):
		push_error("StatusEffectData: JSON file not found at " + path)
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		if typeof(result) == TYPE_DICTIONARY:
			effects = result
			print("✅ Loaded status effects: ", effects.keys())
		else:
			push_error("StatusEffectData: Invalid JSON format in " + path)
