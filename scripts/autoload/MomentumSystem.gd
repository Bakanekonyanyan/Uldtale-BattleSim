# scripts/autoload/MomentumSystem.gd
# FIXED: Preserve loot during reset, clear after bonus calculation

extends Node

signal momentum_changed(new_level: int)
signal momentum_bonus_applied(character: CharacterData)

var current_momentum: int = 0
const MAX_MOMENTUM: int = 10

# Momentum damage bonus: 5% per level
const DAMAGE_BONUS_PER_LEVEL: float = 0.05

# Track accumulated loot during momentum run
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
	"""Reset momentum but PRESERVE accumulated loot for bonus calculation"""
	if current_momentum > 0:
		print("Momentum reset from %d (loot preserved: %d currency, %d equipment)" % [
			current_momentum,
			momentum_loot_accumulated.currency,
			momentum_loot_accumulated.equipment_instances.size()
		])
		current_momentum = 0
		
		#  CRITICAL: DON'T clear accumulated loot here
		# It will be cleared after get_momentum_bonus_rewards() is called
		
		emit_signal("momentum_changed", current_momentum)

func clear_accumulated_loot() -> void:
	"""Clear accumulated loot after bonus rewards have been generated"""
	print("MomentumSystem: Clearing accumulated loot (%d currency, %d equipment)" % [
		momentum_loot_accumulated.currency,
		momentum_loot_accumulated.equipment_instances.size()
	])
	
	momentum_loot_accumulated = {
		"currency": 0,
		"equipment_instances": [],
		"consumables": {},
		"materials": {}
	}

func get_momentum() -> int:
	return current_momentum

func has_momentum_bonus() -> bool:
	return current_momentum >= 3

func get_reward_multiplier() -> float:
	"""Only apply if momentum >= 3"""
	if current_momentum >= 3:
		return 1.0 + ((current_momentum - 2) * 0.25)
	return 1.0

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

func accumulate_loot(rewards: Dictionary) -> void:
	"""Track loot generated during momentum run"""
	if current_momentum < 1:
		return  # Not in momentum run
	
	# Track currency
	if rewards.has("currency"):
		momentum_loot_accumulated.currency += rewards["currency"]
	
	# Track equipment instances
	if rewards.has("equipment_instances"):
		for equip in rewards["equipment_instances"]:
			if equip is Equipment:
				momentum_loot_accumulated.equipment_instances.append(equip)
	
	# Track consumables
	for item_id in rewards:
		if item_id in ["currency", "xp", "equipment_instances"]:
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

func get_momentum_bonus_rewards(current_floor: int) -> Dictionary:
	"""Generate bonus rewards from accumulated loot"""
	if current_momentum < 3 and momentum_loot_accumulated.currency == 0:
		print("MomentumSystem: No accumulated loot or momentum too low")
		return {}
	
	print("=== CALCULATING MOMENTUM BONUS REWARDS ===")
	print("Accumulated Currency: %d" % momentum_loot_accumulated.currency)
	print("Accumulated Equipment: %d pieces" % momentum_loot_accumulated.equipment_instances.size())
	
	var bonus_rewards = {
		"currency": int(momentum_loot_accumulated.currency * 0.4),  # 40% of accumulated
		"equipment_instances": []
	}
	
	# Process equipment
	var total_equipment = momentum_loot_accumulated.equipment_instances.size()
	if total_equipment > 0:
		# Sort by rarity (best to worst)
		var sorted_equipment = momentum_loot_accumulated.equipment_instances.duplicate()
		sorted_equipment.sort_custom(func(a, b): return _get_rarity_tier(a.rarity) > _get_rarity_tier(b.rarity))
		
		# Keep half, reroll the other half with improved stats
		var keep_count = max(1, int(total_equipment * 0.5))
		var reroll_count = total_equipment - keep_count
		
		print("Keeping %d best pieces, rerolling %d pieces" % [keep_count, reroll_count])
		
		# Keep best items
		for i in range(keep_count):
			bonus_rewards.equipment_instances.append(sorted_equipment[i])
			print("  Kept: %s (ilvl %d, %s)" % [
				sorted_equipment[i].display_name,
				sorted_equipment[i].item_level,
				sorted_equipment[i].rarity
			])
		
		# Reroll remaining items with improved rarity and ilvl
		# Use momentum from accumulated loot (stored before reset)
		var momentum_for_reroll = max(3, int(momentum_loot_accumulated.currency / 100))  # Estimate from currency
		for i in range(reroll_count):
			var original = sorted_equipment[keep_count + i]
			var improved = _reroll_equipment_improved(original, current_floor, momentum_for_reroll)
			bonus_rewards.equipment_instances.append(improved)
			print("  Rerolled: %s -> %s (ilvl %d->%d, %s->%s)" % [
				original.display_name,
				improved.display_name,
				original.item_level,
				improved.item_level,
				original.rarity,
				improved.rarity
			])
	
	print("Bonus rewards: %d currency, %d equipment" % [
		bonus_rewards.currency,
		bonus_rewards.equipment_instances.size()
	])
	print("=== END MOMENTUM BONUS ===")
	
	return bonus_rewards

func _reroll_equipment_improved(original_equipment: Equipment, current_floor: int, momentum_level: int) -> Equipment:
	"""Reroll equipment with improved ilvl and rarity"""
	var item_id = original_equipment.id
	
	# Boost ilvl by momentum level
	var boosted_floor = current_floor + momentum_level
	
	# Create new instance with boosted floor
	var new_equipment = ItemManager.create_equipment_for_floor(item_id, boosted_floor)
	
	if new_equipment:
		# Force upgrade rarity by 1-2 tiers based on momentum
		var rarity_boost = 1 if momentum_level < 6 else 2
		new_equipment.rarity = _upgrade_rarity(new_equipment.rarity, rarity_boost)
		
		# Recalculate stats with new rarity
		if new_equipment.has_method("_apply_rarity_bonuses"):
			new_equipment._apply_rarity_bonuses()
		
		print("    Reroll details: Floor %d -> %d, Rarity boost: +%d" % [
			current_floor,
			boosted_floor,
			rarity_boost
		])
		
		return new_equipment
	
	# Fallback: return original if reroll fails
	return original_equipment

func _upgrade_rarity(current_rarity: String, tiers: int) -> String:
	"""Upgrade rarity by specified number of tiers"""
	var rarities = ["common", "uncommon", "magic", "rare", "epic", "legendary"]
	var current_index = rarities.find(current_rarity)
	
	if current_index == -1:
		return current_rarity
	
	var new_index = min(current_index + tiers, rarities.size() - 1)
	return rarities[new_index]

func _get_rarity_tier(rarity: String) -> int:
	"""Get numeric tier for rarity comparison"""
	match rarity:
		"legendary": return 5
		"epic": return 4
		"rare": return 3
		"magic": return 2
		"uncommon": return 1
		_: return 0

func get_momentum_status() -> String:
	"""Get formatted momentum status string"""
	if current_momentum == 0:
		return "No Momentum"
	
	var damage_bonus = int(get_damage_multiplier() * 100 - 100)
	var status = "Momentum x%d (+%d%% damage)" % [current_momentum, damage_bonus]
	
	if has_momentum_bonus():
		var reward_bonus = int((get_reward_multiplier() - 1.0) * 100)
		status += " [+%d%% drop rates]" % reward_bonus
	
	return status

func should_show_bonus_notification() -> bool:
	"""Check if we should show the momentum=3 bonus notification"""
	return current_momentum == 3
