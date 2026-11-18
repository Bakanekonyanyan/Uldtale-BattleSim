# scripts/autoload/MomentumSystem.gd
# FIXED: Preserve loot during reset, clear after bonus calculation

extends Node

signal momentum_changed(new_level: int)
signal momentum_bonus_applied(character: CharacterData)

var current_momentum: int = 0
const MAX_MOMENTUM: int = 10

# Momentum damage bonus: 5% per level
const DAMAGE_BONUS_PER_LEVEL: float = 0.05

# --- Reward bonus ---
# Each Press On adds momentum. Taking a Breather pays out this wave's rewards
# plus everything banked during the streak, boosted by the momentum reached:
# +10% per level, capped at +50% (momentum 5).
const REWARD_BONUS_PER_LEVEL: float = 0.10
const MAX_REWARD_BONUS: float = 0.50

# Rewards banked by Press-On waves, paid out at the next Breather (lost on death).
var momentum_loot_accumulated: Dictionary = {"currency": 0, "equipment_instances": [], "items": {}}

static func _empty_bank() -> Dictionary:
	return {"currency": 0, "equipment_instances": [], "items": {}}

func get_damage_multiplier() -> float:
	return 1.0 + (current_momentum * DAMAGE_BONUS_PER_LEVEL)

func gain_momentum() -> void:
	if current_momentum < MAX_MOMENTUM:
		current_momentum += 1
		emit_signal("momentum_changed", current_momentum)
		print("Momentum increased to: ", current_momentum)

func reset_momentum() -> void:
	"""Momentum back to 0. Banked rewards are NOT touched here - they are paid
	out by RewardsManager on a Breather, or discarded by clear_accumulated_loot()."""
	if current_momentum > 0:
		print("Momentum reset from %d" % current_momentum)
		current_momentum = 0
		emit_signal("momentum_changed", current_momentum)

func clear_accumulated_loot() -> void:
	"""Discard banked rewards (death, or a new expedition)."""
	momentum_loot_accumulated = _empty_bank()

## Bank one Press-On wave's rewards ({"currency", "equipment_instances", item_id: qty}).
func bank_rewards(rewards: Dictionary) -> void:
	momentum_loot_accumulated.currency += int(rewards.get("currency", 0))
	for equip in rewards.get("equipment_instances", []):
		momentum_loot_accumulated.equipment_instances.append(equip)
	for key in rewards:
		if key in ["currency", "xp", "equipment_instances"]:
			continue
		momentum_loot_accumulated.items[key] = momentum_loot_accumulated.items.get(key, 0) + int(rewards[key])

## Hand over everything banked (same shape as a rewards dict) and empty the bank.
func take_banked_rewards() -> Dictionary:
	var bank = momentum_loot_accumulated
	clear_accumulated_loot()
	var out = {"currency": bank.currency, "equipment_instances": bank.equipment_instances}
	out.merge(bank.items)
	return out

## Reward bonus for a momentum level (defaults to the current one): 0.0 .. 0.5
func get_reward_bonus(level: int = -1) -> float:
	if level < 0:
		level = current_momentum
	return min(MAX_REWARD_BONUS, level * REWARD_BONUS_PER_LEVEL)

func get_momentum() -> int:
	return current_momentum

func has_momentum_bonus() -> bool:
	return current_momentum > 0

func apply_momentum_effects(character: CharacterData) -> void:
	"""Press on keeps cooldowns, partial heal on breather"""
	if current_momentum == 0:
		# Breather - partial restore, clear effects, keep cooldowns
		var heal_percent = 0.5  # 50% restore
		character.current_hp = int(character.max_hp * heal_percent)
		character.current_mp = int(character.max_mp * heal_percent)
		character.current_sp = int(character.max_sp * heal_percent)
		
		# Clear status effects
		if character.status_manager:
			character.status_manager.clear_all_effects()
		
		character.is_stunned = false
		character.is_defending = false
		
		print("Breather: Restored 50%% HP/MP/SP, cleared status effects, kept cooldowns")
	# else: press on - keep everything as-is (including cooldowns)
	
	emit_signal("momentum_bonus_applied", character)

func get_momentum_status() -> String:
	"""Get formatted momentum status string"""
	if current_momentum == 0:
		return "No Momentum"
	var damage_bonus = int(round((get_damage_multiplier() - 1.0) * 100))
	var reward_bonus = int(round(get_reward_bonus() * 100))
	var status = "Momentum x%d (+%d%% damage, +%d%% rewards on Breather" % [current_momentum, damage_bonus, reward_bonus]
	status += ", MAX)" if get_reward_bonus() >= MAX_REWARD_BONUS else ")"
	return status

func should_show_bonus_notification() -> bool:
	"""True on the Press On that first reaches the reward bonus cap"""
	return get_reward_bonus() >= MAX_REWARD_BONUS and get_reward_bonus(current_momentum - 1) < MAX_REWARD_BONUS
