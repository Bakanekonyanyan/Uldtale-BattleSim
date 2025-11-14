# scripts/autoload/MomentumSystem.gd
extends Node

signal momentum_changed(new_level: int)
signal momentum_bonus_applied(character: CharacterData)

var current_momentum: int = 0
const MAX_MOMENTUM: int = 10

# Momentum damage bonus: 5% per level
const DAMAGE_BONUS_PER_LEVEL: float = 0.05

# QOL: Track accumulated loot during momentum run
var momentum_loot_accumulated: Dictionary = {
	"currency": 0,
	"equipment_instances": [],
	"consumables": {},
	"materials": {}
}

func get_damage_multiplier() -> float:
	return 1.0 + (current_momentum * DAMAGE_BONUS_PER_LEVEL)

func gain_momentum() -> void:
	if current_momentum < MAX_MOMENTUM:
		current_momentum += 1
		emit_signal("momentum_changed", current_momentum)
		print("Momentum increased to: ", current_momentum)

func reset_momentum() -> void:
	"""QOL: Fixed - clear accumulated loot on reset"""
	if current_momentum > 0:
		print("Momentum reset from: ", current_momentum)
		current_momentum = 0
		
		# Clear accumulated loot
		momentum_loot_accumulated = {
			"currency": 0,
			"equipment_instances": [],
			"consumables": {},
			"materials": {}
		}
		
		emit_signal("momentum_changed", current_momentum)

func get_momentum() -> int:
	return current_momentum

func has_momentum_bonus() -> bool:
	return current_momentum >= 3

func get_reward_multiplier() -> float:
	"""QOL: Only apply if momentum >= 3"""
	if current_momentum >= 3:
		return 1.0 + ((current_momentum - 2) * 0.25)
	return 1.0

func apply_momentum_effects(character: CharacterData) -> void:
	"""QOL: Fixed - press on keeps cooldowns, partial heal on breather"""
	if current_momentum == 0:
		# QOL: Breather - partial restore, clear effects, keep cooldowns
		var heal_percent = 0.5  # 50% restore
		character.current_hp = int(character.max_hp * heal_percent)
		character.current_mp = int(character.max_mp * heal_percent)
		character.current_sp = int(character.max_sp * heal_percent)
		
		# Clear status effects
		if character.status_manager:
			character.status_manager.clear_all_effects()
		
		# QOL: DON'T clear cooldowns - they persist
		# character.skill_manager.clear_cooldowns()  # REMOVED
		
		character.is_stunned = false
		character.is_defending = false
		
		print("Breather: Restored 50%% HP/MP/SP, cleared status effects, kept cooldowns")
	# else: press on - keep everything as-is (including cooldowns)
	
	emit_signal("momentum_bonus_applied", character)

# QOL: Track loot during momentum runs
func accumulate_loot(rewards: Dictionary) -> void:
	"""Track loot generated during momentum run"""
	if current_momentum < 1:
		return  # Not in momentum run
	
	# Track currency
	if rewards.has("currency"):
		momentum_loot_accumulated.currency += rewards["currency"]
	
	# Track equipment
	if rewards.has("equipment_instances"):
		momentum_loot_accumulated.equipment_instances.append_array(rewards["equipment_instances"])
	
	# Track consumables
	for item_id in rewards:
		if item_id in ["currency", "equipment_instances"]:
			continue
		
		var item = ItemManager.get_item(item_id)
		if item and item.item_type == Item.ItemType.CONSUMABLE:
			if not momentum_loot_accumulated.consumables.has(item_id):
				momentum_loot_accumulated.consumables[item_id] = 0
			momentum_loot_accumulated.consumables[item_id] += rewards[item_id]
		elif item and item.item_type == Item.ItemType.MATERIAL:
			if not momentum_loot_accumulated.materials.has(item_id):
				momentum_loot_accumulated.materials[item_id] = 0
			momentum_loot_accumulated.materials[item_id] += rewards[item_id]
	
	print("Momentum loot accumulated: %d currency, %d equipment, %d consumables" % [
		momentum_loot_accumulated.currency,
		momentum_loot_accumulated.equipment_instances.size(),
		momentum_loot_accumulated.consumables.size()
	])

func get_momentum_bonus_rewards() -> Dictionary:
	"""QOL: Generate bonus rewards from accumulated loot"""
	if current_momentum < 3:
		return {}
	
	print("Calculating momentum bonus rewards from accumulated loot...")
	
	var bonus_rewards = {
		"currency": int(momentum_loot_accumulated.currency * 0.4),  # 40% of accumulated
		"equipment_instances": []
	}
	
	# Reroll half of equipment with increased rarity
	var total_equipment = momentum_loot_accumulated.equipment_instances.size()
	var keep_count = max(1, int(total_equipment * 0.4))
	
	# Sort by rarity, keep best items
	var sorted_equipment = momentum_loot_accumulated.equipment_instances.duplicate()
	sorted_equipment.sort_custom(func(a, b): return _get_rarity_tier(a.rarity) > _get_rarity_tier(b.rarity))
	
	for i in range(min(keep_count, sorted_equipment.size())):
		bonus_rewards.equipment_instances.append(sorted_equipment[i])
	
	print("Momentum bonus: %d currency, %d equipment (from %d accumulated)" % [
		bonus_rewards.currency,
		bonus_rewards.equipment_instances.size(),
		total_equipment
	])
	
	return bonus_rewards

func _get_rarity_tier(rarity: String) -> int:
	match rarity:
		"legendary": return 5
		"epic": return 4
		"rare": return 3
		"magic": return 2
		"uncommon": return 1
		_: return 0

func get_momentum_status() -> String:
	if current_momentum == 0:
		return "No Momentum"
	
	var damage_bonus = int(get_damage_multiplier() * 100 - 100)
	var status = "Momentum x%d (+%d%% damage)" % [current_momentum, damage_bonus]
	
	if has_momentum_bonus():
		var reward_bonus = int((get_reward_multiplier() - 1.0) * 100)
		status += " [+%d%% drop rates]" % reward_bonus
	
	return status

func should_show_bonus_notification() -> bool:
	return current_momentum == 3
