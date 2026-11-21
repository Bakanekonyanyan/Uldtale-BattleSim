# res://scripts/LevelSystem.gd
extends Node

## XP to go from `level` to level + 1 (data/progression.json xp):
## base + per_level x (L-1) + per_level_sq x (L-1)^2 - steady, never a wall.
func calculate_xp_for_level(level: int) -> int:
	var d = DataRegistry.get_data("progression")
	var c: Dictionary = d.get("xp", {}) if d is Dictionary else {}
	var l = max(0, level - 1)
	return int(float(c.get("base", 100)) + float(c.get("per_level", 40)) * l + float(c.get("per_level_sq", 30)) * l * l)
