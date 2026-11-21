# res://scripts/autoload/DataRegistry.gd
# The one place game data is read from disk. Every data/*.json file is parsed
# once, on first use, and shared:
#   DataRegistry.get_data("classes")          -> res://data/classes.json
#   DataRegistry.get_data("items/weapons")    -> res://data/items/weapons.json
# Treat what it returns as read-only (it is shared).
# reload() drops the cache (e.g. after editing data in the Content Manager);
# systems that read through get_data() each time pick the change up at once.
extends Node

signal reloaded(name: String)

var _cache: Dictionary = {}

func path_of(name: String) -> String:
	return "res://data/%s.json" % name

## Parsed contents of data/<name>.json ({} if missing or invalid).
func get_data(name: String) -> Variant:
	if not _cache.has(name):
		_cache[name] = _load(name)
	return _cache[name]

## A top-level section of a data file, e.g. section("skills", "skills").
func section(name: String, key: String) -> Dictionary:
	var d = get_data(name)
	return d.get(key, {}) if d is Dictionary else {}

func _load(name: String) -> Variant:
	var path = path_of(name)
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataRegistry: %s not found" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("DataRegistry: %s is not valid JSON" % path)
		return {}
	Log.debug("data", "loaded ", path)
	return parsed

## Forget one file (or everything) so the next get_data() reads it again.
func reload(name: String = "") -> void:
	if name == "":
		_cache.clear()
	else:
		_cache.erase(name)
	reloaded.emit(name)
