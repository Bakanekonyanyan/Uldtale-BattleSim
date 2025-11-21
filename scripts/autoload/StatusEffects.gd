# res://scripts/autoload/StatusEffectData.gd
# This is the autoload registered as "StatusEffects" in Project Settings

extends Node

var effects: Dictionary = {}

func _ready():
	print("[StatusEffects] Autoload initializing...")
	_load_status_effects()

func _load_status_effects():
	var path = "res://data/status_effects.json"
	
	print("[StatusEffects] Looking for JSON at: %s" % path)
	
	if not FileAccess.file_exists(path):
		push_error("StatusEffects: JSON file not found at " + path)
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("StatusEffects: Could not open file at " + path)
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	print("[StatusEffects] JSON text length: %d" % json_text.length())
	
	var result = JSON.parse_string(json_text)
	if typeof(result) != TYPE_DICTIONARY:
		push_error("StatusEffects: Invalid JSON format in " + path)
		push_error("StatusEffects: JSON parse result type: %d" % typeof(result))
		return
	
	effects = result
	print(" StatusEffects: Loaded %d effects: %s" % [effects.size(), effects.keys()])
	
	# Debug: Verify REGENERATION loaded
	if effects.has("REGENERATION"):
		print(" REGENERATION data loaded: %s" % str(effects["REGENERATION"]))
	else:
		push_error("❌ REGENERATION not found in effects!")
	
	# Debug: Verify ENRAGED loaded
	if effects.has("ENRAGED"):
		print(" ENRAGED data loaded: %s" % str(effects["ENRAGED"]))
	else:
		push_error("❌ ENRAGED not found in effects!")
	
	# Debug: Verify REFLECT loaded
	if effects.has("REFLECT"):
		print(" REFLECT data loaded: %s" % str(effects["REFLECT"]))
	else:
		push_error("❌ REFLECT not found in effects!")

func get_effect_data(effect_name: String) -> Dictionary:
	"""Get status effect data by name"""
	if effects.has(effect_name):
		var data = effects[effect_name].duplicate(true)
		print("[StatusEffects] get_effect_data('%s') returning: %s" % [effect_name, str(data)])
		return data
	
	push_warning("StatusEffects: No data found for effect '%s'" % effect_name)
	push_warning("StatusEffects: Available effects: %s" % str(effects.keys()))
	return {}

func has_effect(effect_name: String) -> bool:
	"""Check if effect data exists"""
	return effects.has(effect_name)
