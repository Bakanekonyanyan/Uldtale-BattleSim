# res://scripts/autoload/Log.gd
# Leveled logging. Gameplay code calls Log.debug("battle", "...") instead of
# print(): it is silent unless enabled, so turns, status ticks and enemy
# creation don't flood stdout (a full balance sim used to write 1.3 GB).
#
# Enable from the command line (after --):
#   godot -- --log=debug            everything
#   godot -- --log=battle:debug     one category (repeat for more)
#   godot -- --log=info             info and up
# Warnings and errors always show (and go to the debugger as warnings/errors).
extends Node

enum Level { DEBUG, INFO, WARN, ERROR, OFF }

## Default level for categories without their own setting.
var level: Level = Level.WARN
## Per-category overrides, e.g. {"battle": Level.DEBUG}
var category_levels: Dictionary = {}

func _init() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if not String(a).begins_with("--log="):
			continue
		for part in String(a).trim_prefix("--log=").split(",", false):
			var kv = part.split(":", true, 1)
			if kv.size() == 2:
				category_levels[kv[0]] = _parse(kv[1])
			else:
				level = _parse(kv[0])

func _parse(s: String) -> Level:
	match s.to_lower():
		"debug": return Level.DEBUG
		"info": return Level.INFO
		"warn", "warning": return Level.WARN
		"error": return Level.ERROR
		"off", "none": return Level.OFF
	return Level.WARN

## True if `category` logs at `lvl`. Guard expensive messages with it:
##   if Log.enabled("ai"): Log.debug("ai", heavy_description())
func enabled(category: String, lvl: Level = Level.DEBUG) -> bool:
	return lvl >= category_levels.get(category, level)

func _join(a, b, c, d, e, f) -> String:
	var out = str(a)
	for x in [b, c, d, e, f]:
		if x != null:
			out += str(x)
	return out

func debug(category: String, a, b = null, c = null, d = null, e = null, f = null) -> void:
	if enabled(category, Level.DEBUG):
		print("[%s] %s" % [category, _join(a, b, c, d, e, f)])

func info(category: String, a, b = null, c = null, d = null, e = null, f = null) -> void:
	if enabled(category, Level.INFO):
		print("[%s] %s" % [category, _join(a, b, c, d, e, f)])

func warn(category: String, a, b = null, c = null, d = null, e = null, f = null) -> void:
	if enabled(category, Level.WARN):
		push_warning("[%s] %s" % [category, _join(a, b, c, d, e, f)])

func error(category: String, a, b = null, c = null, d = null, e = null, f = null) -> void:
	if enabled(category, Level.ERROR):
		push_error("[%s] %s" % [category, _join(a, b, c, d, e, f)])
