# RewardsManager.gd
# Autoload: Add to project.godot as RewardsManager
# FIXED: Apply momentum bonus on ANY battle when taking breather (not just bosses)

extends Node

signal rewards_calculated(rewards: Dictionary)

func calculate_battle_rewards(battle_data: Dictionary) -> Dictionary:
	var current_wave = battle_data.get("current_wave", 1)
	var current_floor = battle_data.get("current_floor", 1)
	var is_boss = battle_data.get("is_boss_fight", false)
	var xp_gained = battle_data.get("xp_gained", 0)
	var enemy = battle_data.get("enemy")
	var momentum_level = battle_data.get("momentum_level", 0)
	var taking_breather = battle_data.get("taking_breather", false)
	var player_class = battle_data.get("player_class", "")  # NEW: Player class for biased drops
	
	var rewards = {
		"currency": (50 + (current_wave * 10)) * current_floor,
		"xp": xp_gained,
		"equipment_instances": []
	}
	
	var momentum_bonus = 1.0
	if momentum_level >= 3:
		momentum_bonus = 1.0 + ((momentum_level - 2) * 0.25)
	
	var drop_chance_multiplier = (1 + (current_floor * 0.1)) * momentum_bonus
	
	# Enemy equipment drops (always random, no bias)
	if enemy and enemy.has_meta("equipped_items"):
		var equipped_items = enemy.get_meta("equipped_items")
		for item in equipped_items:
			if item is Equipment:
				var drop_chance = get_equipment_drop_chance(item.rarity, is_boss, momentum_level)
				if RandomManager.randf() < drop_chance:
					rewards["equipment_instances"].append(item)
					print("RewardsManager: Dropped enemy equipment - %s (ilvl %d)" % [item.display_name, item.item_level])
	
	# Regular loot drops (uses class bias for player)
	if is_boss:
		rewards["currency"] *= 2
		add_random_item_to_rewards(rewards, "consumable", 1.0 * drop_chance_multiplier, current_floor)
		add_random_item_to_rewards(rewards, "material", 1.0 * drop_chance_multiplier, current_floor)
		add_random_item_to_rewards(rewards, "weapon", 0.5 * drop_chance_multiplier, current_floor, player_class)
		add_random_item_to_rewards(rewards, "armor", 0.5 * drop_chance_multiplier, current_floor, player_class)
	else:
		add_random_item_to_rewards(rewards, "consumable", 0.7 * drop_chance_multiplier, current_floor)
		add_random_item_to_rewards(rewards, "material", 0.3 * drop_chance_multiplier, current_floor)
		add_random_item_to_rewards(rewards, "equipment", 0.1 * drop_chance_multiplier, current_floor, player_class)
	
	# Accumulate loot during momentum runs
	if momentum_level >= 1 and not taking_breather:
		MomentumSystem.accumulate_loot(rewards)
		print("RewardsManager: Accumulated loot for momentum run")
	
	# Apply momentum bonus rewards on breather
	if taking_breather and momentum_level >= 3:
		print("RewardsManager: Player taking breather at momentum %d - applying bonus rewards" % momentum_level)
		var bonus_rewards = MomentumSystem.get_momentum_bonus_rewards(current_floor)
		
		if bonus_rewards.has("currency"):
			rewards["currency"] += bonus_rewards["currency"]
			print("RewardsManager: Added %d bonus currency (total: %d)" % [bonus_rewards["currency"], rewards["currency"]])
		
		if bonus_rewards.has("equipment_instances"):
			for equip in bonus_rewards["equipment_instances"]:
				rewards["equipment_instances"].append(equip)
			print("RewardsManager: Added %d bonus equipment pieces" % bonus_rewards["equipment_instances"].size())
		
		MomentumSystem.clear_accumulated_loot()
	
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

func add_random_item_to_rewards(rewards: Dictionary, item_type: String, chance: float, floor: int = 1, character_class: String = ""):
	"""
	Add random items with class bias and floor-scaled rarity
	- equipment creates instances with floor context
	- consumables/materials store keys
	- character_class enables class-biased drops (65% preferred)
	"""
	if RandomManager.randf() >= chance:
		return
	
	var item_id = ""
	
	match item_type:
		"consumable":
			item_id = ItemManager.get_random_consumable()
			if item_id != "":
				rewards[item_id] = rewards.get(item_id, 0) + 1
		
		"material":
			item_id = ItemManager.get_random_material()
			if item_id != "":
				rewards[item_id] = rewards.get(item_id, 0) + 1
		
		"weapon":
			# Use class bias if character_class provided
			if character_class != "":
				item_id = ItemManager.get_random_weapon_biased(character_class)
			else:
				item_id = ItemManager.get_random_weapon()
			
			if item_id != "":
				var equipment = ItemManager.create_equipment_for_floor(item_id, floor)
				if equipment:
					rewards["equipment_instances"].append(equipment)
					print("RewardsManager: Weapon drop - %s (ilvl %d, %s)%s" % [
						equipment.display_name, 
						equipment.item_level, 
						equipment.rarity,
						" [CLASS BIASED]" if character_class != "" else ""
					])
		
		"armor":
			# Use class bias if character_class provided
			if character_class != "":
				item_id = ItemManager.get_random_armor_biased(character_class)
			else:
				item_id = ItemManager.get_random_armor()
			
			if item_id != "":
				var equipment = ItemManager.create_equipment_for_floor(item_id, floor)
				if equipment:
					rewards["equipment_instances"].append(equipment)
					print("RewardsManager: Armor drop - %s (ilvl %d, %s)%s" % [
						equipment.display_name, 
						equipment.item_level, 
						equipment.rarity,
						" [CLASS BIASED]" if character_class != "" else ""
					])
		
		"equipment":
			# Use class bias if character_class provided
			if character_class != "":
				item_id = ItemManager.get_random_equipment_biased(character_class)
			else:
				item_id = ItemManager.get_random_equipment()
			
			if item_id != "":
				var equipment = ItemManager.create_equipment_for_floor(item_id, floor)
				if equipment:
					rewards["equipment_instances"].append(equipment)
					print("RewardsManager: Equipment drop - %s (ilvl %d, %s)%s" % [
						equipment.display_name, 
						equipment.item_level, 
						equipment.rarity,
						" [CLASS BIASED]" if character_class != "" else ""
					])
