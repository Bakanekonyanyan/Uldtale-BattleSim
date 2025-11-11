# MomentumSystem.gd
# Autoload: Add to project.godot as MomentumSystem
extends Node

signal momentum_changed(new_level: int)
signal momentum_bonus_applied(character: CharacterData)

var current_momentum: int = 0
const MAX_MOMENTUM: int = 10

# Momentum damage bonus: 5% per level
const DAMAGE_BONUS_PER_LEVEL: float = 0.05

# Get current damage multiplier
func get_damage_multiplier() -> float:
	return 1.0 + (current_momentum * DAMAGE_BONUS_PER_LEVEL)

# Gain momentum (skip rest, press on)
func gain_momentum() -> void:
	if current_momentum < MAX_MOMENTUM:
		current_momentum += 1
		emit_signal("momentum_changed", current_momentum)
		print("Momentum increased to: ", current_momentum)

# Reset momentum (player takes a breather)
func reset_momentum() -> void:
	if current_momentum > 0:
		print("Momentum reset from: ", current_momentum)
		current_momentum = 0
		emit_signal("momentum_changed", current_momentum)

# Get current momentum level
func get_momentum() -> int:
	return current_momentum

# Check if player has momentum bonuses active
func has_momentum_bonus() -> bool:
	return current_momentum >= 3

# Get reward bonus multiplier for momentum
func get_reward_multiplier() -> float:
	if current_momentum >= 3:
		return 1.0 + ((current_momentum - 2) * 0.25)
	return 1.0

# Apply momentum effects to character (called at wave start)
func apply_momentum_effects(character: CharacterData) -> void:
	if current_momentum == 0:
		# Full rest: restore everything
		character.current_hp = character.max_hp
		character.current_mp = character.max_mp
		character.current_sp = character.max_sp
		character.status_effects.clear()
		character.skill_cooldowns.clear()
		character.is_stunned = false
		character.is_defending = false
	# else: player keeps current state (no restoration)
	
	emit_signal("momentum_bonus_applied", character)

# Get momentum status string for UI
func get_momentum_status() -> String:
	if current_momentum == 0:
		return "No Momentum"
	
	var damage_bonus = int(get_damage_multiplier() * 100 - 100)
	var status = "Momentum x%d (+%d%% damage)" % [current_momentum, damage_bonus]
	
	if has_momentum_bonus():
		var reward_bonus = int((get_reward_multiplier() - 1.0) * 100)
		status += " [+%d%% drop rates]" % reward_bonus
	
	return status

# Should we show enhanced drops notification?
func should_show_bonus_notification() -> bool:
	return current_momentum == 3  # Show only when first reaching bonus threshold
