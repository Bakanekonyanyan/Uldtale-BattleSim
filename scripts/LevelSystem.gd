# res://scripts/LevelSystem.gd
extends Node

# More aggressive curve: exponential growth with compounding
func calculate_xp_for_level(level: int) -> int:
	if level <= 1:
		return 100
	
	# Base formula: 100 * (1.5 ^ (level - 1))
	# This creates a steeper curve:
	# Level 2: 100 XP
	# Level 3: 150 XP
	# Level 4: 225 XP
	# Level 5: 338 XP
	# Level 6: 506 XP
	# Level 10: 3844 XP
	# Level 20: 867,362 XP
	
	var base_xp = 100.0
	var exponent = 1.5
	var required_xp = base_xp * pow(exponent, level - 2) + 100.0
	
	return int(required_xp)
