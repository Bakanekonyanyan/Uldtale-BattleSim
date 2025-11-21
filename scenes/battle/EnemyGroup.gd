# res://scripts/battle/EnemyGroup.gd
# Manages multiple enemies in a wave battle

class_name EnemyGroup
extends RefCounted

signal enemy_died(enemy: CharacterData)
signal all_enemies_defeated()

var enemies: Array[CharacterData] = []
var current_floor: int = 1
var current_wave: int = 1
var is_boss_wave: bool = false

func initialize(floor: int, wave: int, boss_wave: bool = false):
	"""Initialize enemy group for a wave"""
	current_floor = floor
	current_wave = wave
	is_boss_wave = boss_wave
	
	_generate_enemies()
	
	print("EnemyGroup: Generated %d enemies for Floor %d, Wave %d" % [
		enemies.size(), floor, wave
	])

func _generate_enemies():
	"""Generate appropriate number of enemies for this wave"""
	var enemy_count = _calculate_enemy_count()
	var momentum = MomentumSystem.get_momentum()
	
	if is_boss_wave:
		# Boss wave: 1 boss + possible minions
		var boss = EnemyFactory.create_boss(current_floor, current_wave, momentum)
		enemies.append(boss)
		
		# 30% chance for 1-2 minions with boss (floor 5+)
		if current_floor >= 5 and RandomManager.randf() < 0.3:
			var minion_count = 1 if RandomManager.randf() < 0.7 else 2
			for i in range(minion_count):
				var minion = EnemyFactory.create_enemy(1, current_floor, current_wave, momentum)
				minion.name = "Minion %d" % (i + 1)
				# Scale minions down
				_scale_minion(minion)
				enemies.append(minion)
	else:
		# Regular wave: multiple enemies
		for i in range(enemy_count):
			var enemy = EnemyFactory.create_enemy(1, current_floor, current_wave, momentum)
			
			# Give unique names if multiple of same type
			if enemy_count > 1:
				enemy.name = "%s %d" % [enemy.name, i + 1]
			
			enemies.append(enemy)
	
	# Scale stats if multiple enemies
	if enemies.size() > 1 and not is_boss_wave:
		_scale_enemy_group()

func _calculate_enemy_count() -> int:
	"""Determine how many enemies based on floor/wave"""
	if is_boss_wave:
		return 1  # Base boss count (minions added separately)
	
	# Base count: 1-2 early, 2-3 mid, 2-4 late
	var base_count = 1
	var max_count = 2
	
	if current_floor >= 5:
		max_count = 3
	if current_floor >= 10:
		max_count = 4
	if current_floor >= 15:
		base_count = 2
	
	# Wave progression: later waves in floor have slightly higher chance of more enemies
	var wave_bonus = 0.1 * (current_wave - 1)  # +10% per wave
	
	var roll = RandomManager.randf() + wave_bonus
	
	if roll < 0.4:
		return base_count
	elif roll < 0.75:
		return base_count + 1
	else:
		return max_count

func _scale_enemy_group():
	"""Scale enemy stats when fighting multiple (prevent overwhelming player)"""
	var count = enemies.size()
	if count <= 1:
		return
	
	# Reduce stats by 15% per additional enemy (max 45% reduction for 4 enemies)
	var reduction = 1.0 - (min(count - 1, 3) * 0.15)
	
	print("EnemyGroup: Scaling %d enemies by %.2f" % [count, reduction])
	
	for enemy in enemies:
		enemy.vitality = int(enemy.vitality * reduction)
		enemy.strength = int(enemy.strength * reduction)
		enemy.dexterity = int(enemy.dexterity * reduction)
		enemy.intelligence = int(enemy.intelligence * reduction)
		enemy.faith = int(enemy.faith * reduction)
		enemy.endurance = int(enemy.endurance * reduction)
		
		enemy.calculate_secondary_attributes()

func _scale_minion(minion: CharacterData):
	"""Scale down boss minions to support role"""
	minion.vitality = int(minion.vitality * 0.6)
	minion.strength = int(minion.strength * 0.7)
	minion.dexterity = int(minion.dexterity * 0.7)
	minion.intelligence = int(minion.intelligence * 0.7)
	minion.faith = int(minion.faith * 0.7)
	
	minion.calculate_secondary_attributes()

func remove_dead_enemies():
	"""Remove defeated enemies from group"""
	var initial_count = enemies.size()
	enemies = enemies.filter(func(e): return e.is_alive())
	
	var removed_count = initial_count - enemies.size()
	if removed_count > 0:
		print("EnemyGroup: Removed %d defeated enemies" % removed_count)
		
		if enemies.is_empty():
			emit_signal("all_enemies_defeated")

func get_living_enemies() -> Array[CharacterData]:
	"""Get all alive enemies"""
	return enemies.filter(func(e): return e.is_alive())

func get_random_living_enemy() -> CharacterData:
	"""Get random alive enemy (for AI targeting)"""
	var living = get_living_enemies()
	if living.is_empty():
		return null
	return living[RandomManager.randi() % living.size()]

func get_weakest_enemy() -> CharacterData:
	"""Get enemy with lowest current HP (for smart AI)"""
	var living = get_living_enemies()
	if living.is_empty():
		return null
	
	living.sort_custom(func(a, b): return a.current_hp < b.current_hp)
	return living[0]

func get_strongest_enemy() -> CharacterData:
	"""Get enemy with highest attack power (for threat assessment)"""
	var living = get_living_enemies()
	if living.is_empty():
		return null
	
	living.sort_custom(func(a, b): return a.get_attack_power() > b.get_attack_power())
	return living[0]

func is_group_alive() -> bool:
	"""Check if any enemies still alive"""
	return get_living_enemies().size() > 0

func get_total_xp() -> int:
	"""Calculate total XP reward for defeating all enemies"""
	var total = 0
	for enemy in enemies:
		total += enemy.level * 50 * current_floor
	return total
