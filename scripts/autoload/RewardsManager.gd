# RewardsManager.gd
# Autoload: Add to project.godot as RewardsManager
extends Node

signal rewards_calculated(rewards: Dictionary)

# Reward calculation based on battle outcome
func calculate_battle_rewards(battle_data: Dictionary) -> Dictionary:
	var current_wave = battle_data.get("current_wave", 1)
	var current_floor = battle_data.get("current_floor", 1)
	var is_boss = battle_data.get("is_boss_fight", false)
	var xp_gained = battle_data.get("xp_gained", 0)
	var enemy = battle_data.get("enemy")
	var momentum_level = battle_data.get("momentum_level", 0)
	
	var rewards = {
		"currency": (50 + (current_wave * 10)) * current_floor,
		"xp": xp_gained
	}
	
	# Momentum bonus: increased drop rates for momentum >= 3
	var momentum_bonus = 1.0
	if momentum_level >= 3:
		momentum_bonus = 1.0 + ((momentum_level - 2) * 0.25)  # +25% per level past 3
	
	var drop_chance_multiplier = (1 + (current_floor * 0.1)) * momentum_bonus
	
	# Equipment drops from enemy
	if enemy and enemy.has_meta("equipped_items"):
		var equipped_items = enemy.get_meta("equipped_items")
		for item in equipped_items:
			if item is Equipment:
				var drop_chance = get_equipment_drop_chance(item.rarity, is_boss, momentum_level)
				if randf() < drop_chance:
					var item_key = item.inventory_key if item.inventory_key != "" else item.id
					if not rewards.has(item_key):
						rewards[item_key] = 0
					rewards[item_key] += 1
	
	# Regular loot drops
	if is_boss:
		rewards["currency"] *= 2
		add_random_item_to_rewards(rewards, "consumable", 1.0 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "material", 1.0 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "weapon", 0.5 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "armor", 0.5 * drop_chance_multiplier)
	else:
		add_random_item_to_rewards(rewards, "consumable", 0.7 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "material", 0.3 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "equipment", 0.1 * drop_chance_multiplier)
	
	emit_signal("rewards_calculated", rewards)
	return rewards

func get_equipment_drop_chance(rarity: String, is_boss: bool, momentum_level: int) -> float:
	var base_chance = 0.0
	
	match rarity:
		"uncommon": base_chance = 0.50
		"magic": base_chance = 0.65
		"rare": base_chance = 0.75
		"epic": base_chance = 0.85
		"legendary": base_chance = 0.95
		_: return 0.0
	
	if is_boss:
		base_chance = min(1.0, base_chance + 0.15)
	
	# Momentum bonus for drops
	if momentum_level >= 3:
		base_chance = min(1.0, base_chance + ((momentum_level - 2) * 0.10))
	
	return base_chance

func add_random_item_to_rewards(rewards: Dictionary, item_type: String, chance: float):
	if randf() < chance:
		var item_id = ""
		match item_type:
			"consumable": item_id = ItemManager.get_random_consumable()
			"material": item_id = ItemManager.get_random_material()
			"weapon": item_id = ItemManager.get_random_weapon()
			"armor": item_id = ItemManager.get_random_armor()
			"equipment": item_id = ItemManager.get_random_equipment()
		
		if item_id != "":
			if not rewards.has(item_id):
				rewards[item_id] = 0
			rewards[item_id] += 1
