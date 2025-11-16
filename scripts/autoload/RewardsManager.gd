# RewardsManager.gd
# Autoload: Add to project.godot as RewardsManager
# FIXED: Proper momentum accumulation and bonus rewards

extends Node


signal rewards_calculated(rewards: Dictionary)

func calculate_battle_rewards(battle_data: Dictionary) -> Dictionary:
	var current_wave = battle_data.get("current_wave", 1)
	var current_floor = battle_data.get("current_floor", 1)
	var is_boss = battle_data.get("is_boss_fight", false)
	var xp_gained = battle_data.get("xp_gained", 0)
	var enemy = battle_data.get("enemy")
	var momentum_level = battle_data.get("momentum_level", 0)
	
	var rewards = {
		"currency": (50 + (current_wave * 10)) * current_floor,
		"xp": xp_gained,
		"equipment_instances": []
	}
	
	var momentum_bonus = 1.0
	if momentum_level >= 3:
		momentum_bonus = 1.0 + ((momentum_level - 2) * 0.25)
	
	var drop_chance_multiplier = (1 + (current_floor * 0.1)) * momentum_bonus
	
	# Store actual Equipment instances from enemy drops
	if enemy and enemy.has_meta("equipped_items"):
		var equipped_items = enemy.get_meta("equipped_items")
		for item in equipped_items:
			if item is Equipment:
				var drop_chance = get_equipment_drop_chance(item.rarity, is_boss, momentum_level)
				if RandomManager.randf() < drop_chance:
					rewards["equipment_instances"].append(item)
					print("RewardsManager: Dropped equipment - %s (ilvl %d)" % [item.name, item.item_level])
	
	# Regular loot drops (consumables/materials)
	if is_boss:
		rewards["currency"] *= 2
		add_random_item_to_rewards(rewards, "consumable", 1.0 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "material", 1.0 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "weapon", 0.5 * drop_chance_multiplier, current_floor)
		add_random_item_to_rewards(rewards, "armor", 0.5 * drop_chance_multiplier, current_floor)
	else:
		add_random_item_to_rewards(rewards, "consumable", 0.7 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "material", 0.3 * drop_chance_multiplier)
		add_random_item_to_rewards(rewards, "equipment", 0.1 * drop_chance_multiplier, current_floor)
	
	# CRITICAL: Accumulate loot during momentum runs
	if momentum_level >= 1:
		MomentumSystem.accumulate_loot(rewards)
	
	# CRITICAL: Add bonus rewards on boss defeats during momentum >= 3
	if is_boss and momentum_level >= 3:
		var bonus_rewards = MomentumSystem.get_momentum_bonus_rewards(current_floor)
		
		if bonus_rewards.has("currency"):
			rewards["currency"] += bonus_rewards["currency"]
			print("RewardsManager: Added %d bonus currency" % bonus_rewards["currency"])
		
		if bonus_rewards.has("equipment_instances"):
			for equip in bonus_rewards["equipment_instances"]:
				rewards["equipment_instances"].append(equip)
			print("RewardsManager: Added %d bonus equipment pieces" % bonus_rewards["equipment_instances"].size())
	
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
	
	if momentum_level >= 3:
		base_chance = min(1.0, base_chance + ((momentum_level - 2) * 0.10))
	
	return base_chance

func add_random_item_to_rewards(rewards: Dictionary, item_type: String, chance: float, floor: int = 1):
	"""Add random items - for equipment, creates instances; for consumables, stores keys"""
	if RandomManager.randf() < chance:
		var item_id = ""
		match item_type:
			"consumable": 
				item_id = ItemManager.get_random_consumable()
				if item_id != "":
					if not rewards.has(item_id):
						rewards[item_id] = 0
					rewards[item_id] += 1
			"material": 
				item_id = ItemManager.get_random_material()
				if item_id != "":
					if not rewards.has(item_id):
						rewards[item_id] = 0
					rewards[item_id] += 1
			"weapon":
				item_id = ItemManager.get_random_weapon()
				if item_id != "":
					# Create instance with floor scaling
					var equipment = ItemManager.create_equipment_for_floor(item_id, floor)
					if equipment:
						rewards["equipment_instances"].append(equipment)
						print("RewardsManager: Generated weapon drop - %s (ilvl %d)" % [equipment.name, equipment.item_level])
			"armor":
				item_id = ItemManager.get_random_armor()
				if item_id != "":
					var equipment = ItemManager.create_equipment_for_floor(item_id, floor)
					if equipment:
						rewards["equipment_instances"].append(equipment)
						print("RewardsManager: Generated armor drop - %s (ilvl %d)" % [equipment.name, equipment.item_level])
			"equipment":
				item_id = ItemManager.get_random_equipment()
				if item_id != "":
					var equipment = ItemManager.create_equipment_for_floor(item_id, floor)
					if equipment:
						rewards["equipment_instances"].append(equipment)
						print("RewardsManager: Generated equipment drop - %s (ilvl %d)" % [equipment.name, equipment.item_level])
