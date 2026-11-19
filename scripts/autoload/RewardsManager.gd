# RewardsManager.gd - REFACTORED
# Now handles BOTH reward calculation AND state persistence

extends Node

signal rewards_calculated(rewards: Dictionary)
signal rewards_state_changed()

# ===== REWARD STATE (moved from SceneManager) =====
var saved_reward_state: Dictionary = {}
var is_reward_session_active: bool = false

# ===== REWARD CALCULATION =====

## Rewards for ONE won wave, before the momentum payout bonus.
## Equipment drop chances are already boosted by the streak's momentum.
func roll_wave_rewards(battle_data: Dictionary) -> Dictionary:
	var current_wave = battle_data.get("current_wave", 1)
	var current_floor = battle_data.get("current_floor", 1)
	var is_boss = battle_data.get("is_boss_fight", false)
	var momentum_level = battle_data.get("momentum_level", 0)
	var player_class = battle_data.get("player_class", "")
	
	var rewards = {
		"currency": (50 + (current_wave * 10)) * current_floor,
		"equipment_instances": []
	}
	
	var momentum_mult = 1.0 + MomentumSystem.get_reward_bonus(momentum_level)
	var drop_chance_multiplier = (1 + (current_floor * 0.1)) * momentum_mult
	
	# Gear the defeated enemies were wearing. (This read a single
	# battle_data["enemy"], which multi-enemy waves never set, so enemy gear
	# had stopped dropping entirely.)
	for enemy in battle_data.get("enemies", []):
		if not (enemy is CharacterData and enemy.has_meta("equipped_items")):
			continue
		for item in enemy.get_meta("equipped_items"):
			if item is Equipment and RandomManager.randf() < min(1.0, get_equipment_drop_chance(item.rarity, is_boss) * momentum_mult):
				rewards["equipment_instances"].append(item)
				print("RewardsManager: %s dropped %s (%s, ilvl %d)" % [enemy.name, item.display_name, item.rarity, item.item_level])
	
	# Regular loot drops
	if is_boss:
		rewards["currency"] *= 2
		add_random_item_to_rewards(rewards, "consumable", 1.0 * drop_chance_multiplier, current_floor)
		add_random_item_to_rewards(rewards, "weapon", 0.5 * drop_chance_multiplier, current_floor, player_class)
		add_random_item_to_rewards(rewards, "armor", 0.5 * drop_chance_multiplier, current_floor, player_class)
	else:
		add_random_item_to_rewards(rewards, "consumable", 0.7 * drop_chance_multiplier, current_floor)
		add_random_item_to_rewards(rewards, "equipment", 0.1 * drop_chance_multiplier, current_floor, player_class)
	
	# Location reward multiplier x world event (e.g. a Monster Surge)
	var loc = DungeonStateManager.current_location
	rewards["currency"] = int(round(rewards["currency"] * LocationManager.get_reward_mult(loc) * WorldClock.current_modifier("reward_mult", loc)))
	
	# Materials: from the races of the enemies just defeated (data/loot/material_tables.json)
	_merge_counts(rewards, roll_material_drops(battle_data))
	return rewards

## Press On: no reward screen, so bank this wave's rewards for the next Breather.
## Banked rewards are lost if the player dies.
func bank_wave_rewards(battle_data: Dictionary) -> void:
	MomentumSystem.bank_rewards(roll_wave_rewards(battle_data))

## Momentum bonus applied to the last Breather payout (for the reward screen).
var last_momentum_bonus: float = 0.0

## Breather: this wave + everything banked during the Press-On streak, with gold
## and item quantities boosted by the momentum reached (+10%/level, max +50%).
## battle_data["momentum_level"] must be read BEFORE momentum is reset.
func calculate_battle_rewards(battle_data: Dictionary) -> Dictionary:
	var rewards = roll_wave_rewards(battle_data)
	rewards["xp"] = battle_data.get("xp_gained", 0)
	
	var banked = MomentumSystem.take_banked_rewards()
	rewards["currency"] += banked.currency
	rewards["equipment_instances"].append_array(banked.equipment_instances)
	for key in banked:
		if key not in ["currency", "equipment_instances"]:
			rewards[key] = rewards.get(key, 0) + banked[key]
	
	var bonus = MomentumSystem.get_reward_bonus(battle_data.get("momentum_level", 0))
	last_momentum_bonus = bonus
	if bonus > 0.0:
		rewards["currency"] = int(round(rewards["currency"] * (1.0 + bonus)))
		for key in rewards.keys():
			if key not in ["currency", "xp", "equipment_instances"]:
				rewards[key] = _boost_count(rewards[key], bonus)
		print("RewardsManager: Breather payout with +%d%% momentum bonus" % int(bonus * 100))
	
	emit_signal("rewards_calculated", rewards)
	return rewards

## Boost an item count by `bonus` using probabilistic rounding (3 x +50% = 4 or 5).
func _boost_count(count: int, bonus: float) -> int:
	var exact = count * (1.0 + bonus)
	var whole = int(exact)
	return whole + (1 if RandomManager.randf() < exact - whole else 0)

# ===== STATE MANAGEMENT (NEW - moved from SceneManager) =====

func save_state(rewards: Dictionary, xp_gained: int, rewards_collected: bool, collected_items: Dictionary, auto_rewards_given: bool = false) -> void:
	"""Save reward session state for navigation persistence"""
	saved_reward_state = {
		"rewards": rewards.duplicate(true),
		"xp_gained": xp_gained,
		"rewards_collected": rewards_collected,
		"collected_items": collected_items.duplicate(),
		"auto_rewards_given": auto_rewards_given,
		"is_boss_fight": DungeonStateManager.is_boss_fight,
		"current_floor": DungeonStateManager.current_floor,
		"current_wave": DungeonStateManager.current_wave,
		"max_floor": DungeonStateManager.max_floor
	}
	
	is_reward_session_active = true
	emit_signal("rewards_state_changed")
	
	print("RewardsManager: Saved state - Wave %d, Boss: %s, Items: %d" % [
		DungeonStateManager.current_wave,
		DungeonStateManager.is_boss_fight,
		collected_items.size()
	])

func get_saved_state() -> Dictionary:
	"""Retrieve saved reward state"""
	return saved_reward_state if not saved_reward_state.is_empty() else {}

func clear_saved_state() -> void:
	"""Clear saved reward state"""
	saved_reward_state.clear()
	is_reward_session_active = false
	emit_signal("rewards_state_changed")
	print("RewardsManager: Cleared saved state")

func has_saved_state() -> bool:
	"""Check if there's a saved reward session"""
	return not saved_reward_state.is_empty()

func is_session_active() -> bool:
	"""Check if reward session is active"""
	return is_reward_session_active

# ===== HELPER METHODS =====

func get_equipment_drop_chance(rarity: String, is_boss: bool) -> float:
	"""Chance an enemy's equipped item drops (common gear never drops)."""
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
	return base_chance

# ===== MATERIAL DROPS =====

var _material_tables: Dictionary = {}

func _get_material_tables() -> Dictionary:
	if _material_tables.is_empty():
		var file = FileAccess.open("res://data/loot/material_tables.json", FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_material_tables = parsed
		if _material_tables.is_empty():
			push_error("RewardsManager: data/loot/material_tables.json missing or invalid")
	return _material_tables

## Roll material drops for one won battle. Returns {material_id: quantity}.
## Uses battle_data["enemies"] (the defeated enemies) for race tables.
func roll_material_drops(battle_data: Dictionary) -> Dictionary:
	var tables = _get_material_tables()
	var drops := {}
	if tables.is_empty():
		return drops
	
	var floor_num: int = battle_data.get("current_floor", 1)
	var is_boss: bool = battle_data.get("is_boss_fight", false)
	var enemies: Array = battle_data.get("enemies", [])
	var races: Array = []
	for e in enemies:
		if e is CharacterData and tables.races.has(e.race):
			races.append(e.race)
	if races.is_empty():
		races = tables.races.keys()  # fallback: any table
	
	var rolls: int
	if is_boss:
		rolls = int(tables.get("boss_rolls", 3))
	else:
		rolls = RandomManager.randi_range(int(tables.get("per_wave_min", 1)), int(tables.get("per_wave_max", 2)))
	rolls += int((floor_num - 1) / max(1, int(tables.get("floor_bonus_every", 5))))
	
	for i in range(rolls):
		var table: Dictionary = tables.races[races[RandomManager.randi() % races.size()]]
		var pool: Array = table.uncommon if RandomManager.randf() < float(tables.get("uncommon_chance", 0.25)) else table.common
		if not pool.is_empty():
			var id: String = pool[RandomManager.randi() % pool.size()]
			drops[id] = drops.get(id, 0) + 1
	
	for entry in tables.get("floor_materials", []):
		if floor_num >= int(entry.min_floor) and RandomManager.randf() < float(entry.chance_per_wave):
			drops[entry.id] = drops.get(entry.id, 0) + 1
	
	if is_boss:
		var boss_drops: Dictionary = tables.get("boss_drops", {})
		for id in boss_drops:
			if RandomManager.randf() < float(boss_drops[id]):
				drops[id] = drops.get(id, 0) + 1
	
	return drops

func _merge_counts(into: Dictionary, counts: Dictionary) -> void:
	for id in counts:
		into[id] = into.get(id, 0) + counts[id]

func add_random_item_to_rewards(rewards: Dictionary, item_type: String, chance: float, floor: int = 1, player_class: String = "") -> void:
	"""Add random items to rewards dictionary"""
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
				# Use class-biased selection if player_class provided
				if player_class != "":
					item_id = ItemManager.get_random_weapon_biased(player_class)
				else:
					item_id = ItemManager.get_random_weapon()
				
				if item_id != "":
					var equipment = ItemManager.create_equipment_for_floor(item_id, floor)
					if equipment:
						rewards["equipment_instances"].append(equipment)
			
			"armor":
				# Use class-biased selection if player_class provided
				if player_class != "":
					item_id = ItemManager.get_random_armor_biased(player_class)
				else:
					item_id = ItemManager.get_random_armor()
				
				if item_id != "":
					var equipment = ItemManager.create_equipment_for_floor(item_id, floor)
					if equipment:
						rewards["equipment_instances"].append(equipment)
			
			"equipment":
				# Use class-biased selection if player_class provided
				if player_class != "":
					item_id = ItemManager.get_random_equipment_biased(player_class)
				else:
					item_id = ItemManager.get_random_equipment()
				
				if item_id != "":
					var equipment = ItemManager.create_equipment_for_floor(item_id, floor)
					if equipment:
						rewards["equipment_instances"].append(equipment)
