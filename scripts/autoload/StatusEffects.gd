# res://scripts/autoload/StatusEffectData.gd
# This is the autoload registered as "StatusEffects" in Project Settings

extends Node

var effects: Dictionary = {}

func _ready():
	Log.debug("status", "[StatusEffects] Autoload initializing...")
	_load_status_effects()

func _load_status_effects():
	var path = DataRegistry.path_of("status_effects")
	var result = DataRegistry.get_data("status_effects")
	if typeof(result) != TYPE_DICTIONARY:
		push_error("StatusEffects: Invalid JSON format in " + path)
		push_error("StatusEffects: JSON parse result type: %d" % typeof(result))
		return
	
	effects = result
	Log.debug("status", " StatusEffects: Loaded %d effects: %s" % [effects.size(), effects.keys()])
	
	# Debug: Verify REGENERATION loaded
	if effects.has("REGENERATION"):
		Log.debug("status", " REGENERATION data loaded: %s" % str(effects["REGENERATION"]))
	else:
		push_error("❌ REGENERATION not found in effects!")
	
	# Debug: Verify ENRAGED loaded
	if effects.has("ENRAGED"):
		Log.debug("status", " ENRAGED data loaded: %s" % str(effects["ENRAGED"]))
	else:
		push_error("❌ ENRAGED not found in effects!")
	
	# Debug: Verify REFLECT loaded
	if effects.has("REFLECT"):
		Log.debug("status", " REFLECT data loaded: %s" % str(effects["REFLECT"]))
	else:
		push_error("❌ REFLECT not found in effects!")

func get_effect_data(effect_name: String) -> Dictionary:
	"""Get status effect data by name"""
	if effects.has(effect_name):
		var data = effects[effect_name].duplicate(true)
		Log.debug("status", "[StatusEffects] get_effect_data('%s') returning: %s" % [effect_name, str(data)])
		return data
	
	push_warning("StatusEffects: No data found for effect '%s'" % effect_name)
	push_warning("StatusEffects: Available effects: %s" % str(effects.keys()))
	return {}

func has_effect(effect_name: String) -> bool:
	"""Check if effect data exists"""
	return effects.has(effect_name)
