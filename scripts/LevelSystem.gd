# LevelSystem.gd
extends Node

const BASE_XP_REQUIRED = 100
const XP_INCREASE_PER_LEVEL = 50

func calculate_xp_for_level(level: int) -> int:
	return BASE_XP_REQUIRED + (level - 1) * XP_INCREASE_PER_LEVEL
