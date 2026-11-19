# res://scripts/autoload/EnemyFactory.gd
extends Node

# --- Difficulty tuning (see also BattleFormulas for combat math) ---
## Stat increase per wave within a floor: wave 1 = x1.00, wave 5 = x1.20, boss wave = x1.25
## Enemy tuning lives in data/enemy_archetypes.json "scaling" (Content Manager).
func _scale(key: String, default_value: float) -> float:
	return float(EnemyArchetypes.data().get("scaling", {}).get(key, default_value))

var races = {}
var classes = {}
var skills = {}
## Expedition location (LocationManager id) that decides which races spawn
var current_location: String = ""
## Single race of a themed location, or the race rolled for this floor's boss in a
## mixed location. Read by DungeonStateManager for flavor text.
var current_dungeon_race: String = ""
var current_floor: int = 0
## Testing/balance: when set, every regular enemy uses this archetype
var force_archetype: String = ""

func _ready():
	load_data()

func load_data():
	races = DataRegistry.get_data("races")
	classes = DataRegistry.get_data("classes")
	skills = DataRegistry.section("skills", "skills")

func get_dungeon_race() -> String:
	return current_dungeon_race

## Choose where the expedition takes place. Call when an expedition starts and
## when it advances to a new floor (mixed locations re-roll their headline race).
func set_location(location_id: String) -> void:
	if not LocationManager.has_location(location_id):
		push_warning("EnemyFactory: unknown location '%s', using %s" % [location_id, LocationManager.DEFAULT_LOCATION])
		location_id = LocationManager.DEFAULT_LOCATION
	current_location = location_id
	current_dungeon_race = _roll_race()
	Log.debug("enemies", "EnemyFactory: Location %s (headline race: %s)" % [
		LocationManager.get_display_name(location_id), current_dungeon_race
	])

func _location_races() -> Array:
	return LocationManager.get_races(current_location, races["non_playable"].keys())

func _roll_race() -> String:
	var pool = _location_races()
	return pool[RandomManager.randi() % pool.size()]

## Race for one regular enemy: per-enemy roll in mixed locations, otherwise the
## location's race.
func _race_for_enemy() -> String:
	if current_location == "":
		set_location(LocationManager.DEFAULT_LOCATION)
	if LocationManager.is_mixed(current_location):
		return _roll_race()
	return current_dungeon_race

func create_enemy(level: int = 1, floor: int = 1, wave: int = 1, momentum_level: int = 0) -> CharacterData:
	var enemy = CharacterData.new()
	level = floor
	var race_name = _race_for_enemy()
	if not races["non_playable"].has(race_name):
		push_error("EnemyFactory: Race '%s' not found in races['non_playable']" % race_name)
		return enemy
	
	# Archetype (role template): stats from classes.json, skills from hero-class
	# pools + monster skills, talents in one hero branch (EnemyArchetypes)
	var archetype = force_archetype if EnemyArchetypes.archetypes().has(force_archetype) else EnemyArchetypes.pick_archetype(race_name)
	var stats_class = String(EnemyArchetypes.get_archetype(archetype).get("stats_class", archetype))
	if not classes["non_playable"].has(stats_class):
		stats_class = classes["non_playable"].keys()[0]
	var race_data = races["non_playable"][race_name]
	setup_character(enemy, stats_class, "non_playable", race_name, race_data,
		EnemyArchetypes.roll_skills(archetype, race_name, skills, 0, floor))
	enemy.character_class = archetype
	enemy.name = "%s %s" % [race_name, archetype]
	_tag_archetype(enemy, archetype)

	#  ADD THIS: Initialize elemental resistances for enemies
	if enemy.elemental_resistances == null:
		enemy.elemental_resistances = ElementalResistanceManager.new(enemy)
	enemy.initialize_racial_elementals(true)

	enemy.level = level + 1
	for _i in range(level - 1):
		enemy.level_up()
	
	enemy.hp_multiplier = _scale("enemy_hp_mult", 0.5)
	enemy.damage_multiplier = _scale("enemy_damage_mult", 0.72)
	EnemyArchetypes.apply_talents(enemy, archetype, EnemyArchetypes.enemy_points(floor))
	apply_enemy_scaling(enemy, floor, wave, false, momentum_level)
	give_enemy_equipment(enemy, floor)
	give_enemy_items(enemy, floor, false, momentum_level)
	
	enemy.is_player = false
	enemy.calculate_secondary_attributes()
	enemy.current_hp = enemy.max_hp
	enemy.current_mp = enemy.max_mp
	enemy.current_sp = enemy.max_sp

	return enemy

func create_boss(floor: int = 1, wave: int = 1, momentum_level: int = 0) -> CharacterData:
	# Boss race: the location's race (themed) or this floor's rolled race (mixed)
	if current_location == "":
		set_location(LocationManager.DEFAULT_LOCATION)
	var boss_race = current_dungeon_race
	
	var boss = CharacterData.new()
	var king_data = classes["boss"]["King"]
	var bcfg = EnemyArchetypes.boss_cfg()
	
	# Named (hand-authored) boss for this location and floor overrides the roll
	var named = EnemyArchetypes.named_boss(current_location, floor)
	if named.has("race") and races["non_playable"].has(named.race):
		boss_race = named.race
	var archetype = String(named.get("archetype", EnemyArchetypes.pick_archetype(boss_race)))
	var stats_class = String(EnemyArchetypes.get_archetype(archetype).get("stats_class", archetype))
	if not classes["non_playable"].has(stats_class):
		stats_class = "Brute"
	var minion_data = classes["non_playable"][stats_class]
	var race_data = races["non_playable"][boss_race]
	
	boss.name = String(named.get("name", "%s %s King" % [boss_race, archetype]))
	boss.race = boss_race
	boss.character_class = "King (%s)" % archetype
	
	var minion_contribution = _scale("boss_minion_stat_share", 0.25)
	boss.vitality = int((king_data["base_vit"] + race_data["vit_mod"]) + (minion_data["base_vit"] * minion_contribution))
	boss.strength = int((king_data["base_str"] + race_data["str_mod"]) + (minion_data["base_str"] * minion_contribution))
	boss.dexterity = int((king_data["base_dex"] + race_data["dex_mod"]) + (minion_data["base_dex"] * minion_contribution))
	boss.intelligence = int((king_data["base_int"] + race_data["int_mod"]) + (minion_data["base_int"] * minion_contribution))
	boss.faith = int((king_data["base_fai"] + race_data["fai_mod"]) + (minion_data["base_fai"] * minion_contribution))
	boss.mind = int((king_data["base_mnd"] + race_data["mnd_mod"]) + (minion_data["base_mnd"] * minion_contribution))
	boss.endurance = int((king_data["base_end"] + race_data["end_mod"]) + (minion_data["base_end"] * minion_contribution))
	boss.arcane = int((king_data["base_arc"] + race_data["arc_mod"]) + (minion_data["base_arc"] * minion_contribution))
	boss.agility = int((king_data["base_agi"] + race_data["agi_mod"]) + (minion_data["base_agi"] * minion_contribution))
	boss.fortitude = int((king_data["base_for"] + race_data["for_mod"]) + (minion_data["base_for"] * minion_contribution))
	
	# Bosses get a bigger HP pool via BOSS_HP_MULT below. (Previously VIT x2 and
	# STR/INT/FAI/END x1.5, then the whole block x1.5 again in apply_enemy_scaling,
	# then x1.9 for wave 6 - a floor-1 boss had ~1400 HP and ~8x the player's attack.)
	
	boss.attack_power_type = minion_data.get("attack_power_type", king_data["attack_power_type"])
	boss.spell_power_type = minion_data.get("spell_power_type", king_data["spell_power_type"])
	
	# Skills: archetype roll (+extra), a royal skill or two, the race signature
	var combined_skills: Array = EnemyArchetypes.roll_skills(archetype, boss_race, skills, int(bcfg.get("extra_skills", 0)), floor)
	var king_pool: Array = (bcfg.get("king_pool", []) as Array).filter(func(n): return skills.has(n) and not n in combined_skills)
	for i in range(min(int(bcfg.get("king_picks", 1)), king_pool.size())):
		combined_skills.append(king_pool.pop_at(RandomManager.randi() % king_pool.size()))
	var signature = String(named.get("signature", bcfg.get("signatures", {}).get(boss_race, "")))
	if skills.has(signature) and not signature in combined_skills:
		combined_skills.append(signature)
	for extra in named.get("skills", []):
		if skills.has(extra) and not extra in combined_skills:
			combined_skills.append(extra)
	if combined_skills.size() > 0:
		boss.add_skills(combined_skills)
	_tag_archetype(boss, archetype)
	boss.set_meta("boss_signature", signature if skills.has(signature) else "")
	
	#  ADD THIS: Initialize elemental resistances for boss
	if boss.elemental_resistances == null:
		boss.elemental_resistances = ElementalResistanceManager.new(boss)
	boss.initialize_racial_elementals(true)
	
	boss.hp_multiplier = _scale("boss_hp_mult", 1.0)
	boss.damage_multiplier = _scale("boss_damage_mult", 0.65)
	# A full branch: the ultimate is learned as soon as it is reachable
	var branch = String(named.get("branch", ""))
	EnemyArchetypes.apply_talents(boss, archetype, EnemyArchetypes.boss_points(floor), true, branch)
	boss.set_meta("boss_ultimate", EnemyArchetypes.ultimate_skill(boss, archetype, branch, bool(bcfg.get("grant_ultimate", true))))
	apply_enemy_scaling(boss, floor, wave, true, momentum_level)
	give_enemy_equipment(boss, floor, true)
	give_enemy_items(boss, floor, true, momentum_level)
	
	boss.is_player = false
	boss.calculate_secondary_attributes()
	boss.current_hp = boss.max_hp
	boss.current_mp = boss.max_mp
	boss.current_sp = boss.max_sp
	
	return boss

func apply_enemy_scaling(enemy: CharacterData, floor: int, wave: int, is_boss: bool = false, momentum_level: int = 0):
	# Progressive difficulty curve with breakpoints
	var difficulty_tier = get_difficulty_tier(floor)
	var base_multiplier = get_base_multiplier(floor)
	var wave_multiplier = 1.0 + _scale("wave_scaling", 0.05) * (wave - 1)
	
	var momentum_multiplier = 1.0
	if momentum_level > 0:
		momentum_multiplier = 1.0 + (momentum_level * 0.10)
	
	# Boss scaling
	var boss_multiplier = _scale("boss_stat_mult", 1.0) if is_boss else 1.0
	
	# World event in this location (e.g. a Monster Surge)
	var event_multiplier = WorldClock.current_modifier("enemy_power", current_location)
	var total_multiplier = base_multiplier * wave_multiplier * momentum_multiplier * boss_multiplier * event_multiplier
	
	# Apply scaling
	enemy.vitality = int(enemy.vitality * total_multiplier)
	enemy.strength = int(enemy.strength * total_multiplier)
	enemy.dexterity = int(enemy.dexterity * total_multiplier)
	enemy.intelligence = int(enemy.intelligence * total_multiplier)
	enemy.faith = int(enemy.faith * total_multiplier)
	enemy.mind = int(enemy.mind * total_multiplier)
	enemy.endurance = int(enemy.endurance * total_multiplier)
	enemy.arcane = int(enemy.arcane * total_multiplier)
	enemy.agility = int(enemy.agility * total_multiplier)
	enemy.fortitude = int(enemy.fortitude * total_multiplier)
	
	if momentum_level > 0:
		Log.debug("enemies", "Enemy scaled with momentum x%d: +%d%% stats" % [momentum_level, int((momentum_multiplier - 1.0) * 100)])
	
	Log.debug("enemies", "Floor %d (Tier %d): Base multiplier %.2f, Total multiplier: %.2f" % [floor, difficulty_tier, base_multiplier, total_multiplier])

func get_difficulty_tier(floor: int) -> int:
	"""Returns difficulty tier 1-8 based on floor"""
	if floor <= 2:
		return 1  # Tutorial/Easy
	elif floor <= 5:
		return 2  # Normal
	elif floor <= 8:
		return 3  # Challenging
	elif floor <= 11:
		return 4  # Hard
	elif floor <= 14:
		return 5  # Very Hard
	elif floor <= 17:
		return 6  # Expert
	elif floor <= 20:
		return 7  # Master
	else:
		return 8  # Legendary

func get_base_multiplier(floor: int) -> float:
	"""Returns stat multiplier based on floor with smooth progression"""
	if floor <= 2:
		# Floors 1-2: Easy introduction (1.0x - 1.1x)
		return 1.0 + (floor - 1) * 0.05
	elif floor <= 5:
		# Floors 3-5: Gradual increase (1.15x - 1.45x)
		return 1.1 + (floor - 2) * 0.15
	elif floor <= 8:
		# Floors 6-8: Moderate scaling (1.6x - 2.05x)
		return 1.45 + (floor - 5) * 0.20
	elif floor <= 11:
		# Floors 9-11: Steeper curve (2.3x - 3.05x)
		return 2.05 + (floor - 8) * 0.35
	elif floor <= 14:
		# Floors 12-14: (3.4x - 4.5x)
		return 3.05 + (floor - 11) * 0.45
	elif floor <= 17:
		# Floors 15-17: (5.0x - 6.5x)
		return 4.5 + (floor - 14) * 0.60
	elif floor <= 20:
		# Floors 18-20: (7.2x - 9.0x)
		return 6.5 + (floor - 17) * 0.75
	else:
		# Floors 21-25: End game (9.9x - 13.5x)
		return 9.0 + (floor - 20) * 0.90

func get_available_equipment_slots(floor: int, is_boss: bool) -> Array:
	"""Equipment slots scale better with floor progression"""
	var slots = ["main_hand", "chest"]  # Always have weapon + chest
	
	# Floor 1-2: Main hand + chest only
	
	# Floor 3+: Add head
	if floor >= 3:
		slots.append("head")
	
	# Floor 5+: Add legs
	if floor >= 5:
		slots.append("legs")
	
	# Floor 7+: Add hands
	if floor >= 7:
		slots.append("hands")
	
	# Floor 9+: Add feet (full armor)
	if floor >= 9:
		slots.append("feet")
	
	# Bosses always have full equipment
	if is_boss:
		slots = ["main_hand", "chest", "head", "legs", "hands", "feet"]
	
	return slots

func give_enemy_equipment(enemy: CharacterData, floor: int, is_boss: bool = false):
	var available_slots = get_available_equipment_slots(floor, is_boss)
	var difficulty_tier = get_difficulty_tier(floor)
	
	# Equipment chance scales with floor - guarantee most slots filled on higher floors
	var base_equipment_chance = min(0.70 + (difficulty_tier * 0.05), 1.0)
	var equipment_chance = base_equipment_chance if not is_boss else 1.0
	
	# Guarantee at least 3 armor pieces on floor 5+
	var guaranteed_armor_pieces = 0
	if floor >= 5:
		guaranteed_armor_pieces = 3
	if floor >= 10:
		guaranteed_armor_pieces = 4
	if floor >= 15:
		guaranteed_armor_pieces = 5
	
	# Rarity improves every 3 floors
	var min_rarity_tier = int(floor / 3)
	
	if not enemy.has_meta("equipped_items"):
		enemy.set_meta("equipped_items", [])
	
	var armor_equipped_count = 0
	
	for slot in available_slots:
		var should_equip = is_boss or RandomManager.randf() < equipment_chance
		
		# Force equip armor if we haven't met minimum yet
		if slot != "main_hand" and armor_equipped_count < guaranteed_armor_pieces:
			should_equip = true
		
		if should_equip:
			var item = null
			
			if slot == "main_hand":
				var weapon_id = ItemManager.get_random_weapon()
				if weapon_id:
					item = ItemManager.create_equipment_for_floor(weapon_id, floor, min_rarity_tier)
			else:
				var armor_id = ItemManager.get_random_armor("", slot)
				if armor_id:
					item = ItemManager.create_equipment_for_floor(armor_id, floor, min_rarity_tier)
					if item:
						armor_equipped_count += 1
			
			if item and item is Equipment:
				enemy.equip_item(item)
				
				var rarity_tier = get_rarity_tier(item.rarity)
				if rarity_tier >= 1:
					var equipped_items = enemy.get_meta("equipped_items")
					equipped_items.append(item)
					enemy.set_meta("equipped_items", equipped_items)
				
				Log.debug("enemies", "%s equipped ilvl %d %s: %s (%s)" % [
					enemy.name, 
					item.item_level, 
					slot, 
					item.display_name,
					item.rarity
				])
	
	Log.debug("enemies", "Enemy %s equipped %d armor pieces (minimum: %d)" % [
		enemy.name, armor_equipped_count, guaranteed_armor_pieces
	])

func give_enemy_items(enemy: CharacterData, floor: int, is_boss: bool = false, momentum_level: int = 0):
	var difficulty_tier = get_difficulty_tier(floor)
	var base_item_chance = 0.3 + (difficulty_tier * 0.08)
	var momentum_bonus = momentum_level * 0.1
	var boss_multiplier = 3.0 if is_boss else 1.5
	var total_chance = (base_item_chance + momentum_bonus) * boss_multiplier
	
	var item_count = 0
	if RandomManager.randf() < total_chance:
		item_count = 1
	if RandomManager.randf() < total_chance * 0.5:
		item_count += 1
	if RandomManager.randf() < total_chance * 0.25:
		item_count += 1
	
	# Item pool expands with difficulty tiers
	var available_items = []
	available_items.append_array(["health_potion", "stone_shard"])
	
	if difficulty_tier >= 2:  # Floor 3+
		available_items.append_array(["mana_potion", "stamina_potion"])
	
	if difficulty_tier >= 3:  # Floor 6+
		available_items.append_array(["flame_flask", "venom_vial", "rotten_dung"])
	
	if difficulty_tier >= 5:  # Floor 12+
		available_items.append_array(["frost_crystal", "thunder_orb", "smoke_bomb"])
	
	if difficulty_tier >= 6:  # Floor 15+
		available_items.append_array(["berserker_brew"])
	
	if difficulty_tier >= 7:  # Floor 18+
		available_items.append_array(["holy_water"])
	
	for i in range(item_count):
		if available_items.size() > 0:
			var item_id = available_items[RandomManager.randi() % available_items.size()]
			var item = ItemManager.get_item(item_id)
			if item:
				var quantity = 1 + int(difficulty_tier / 2)
				if is_boss:
					quantity += 1
				enemy.inventory.add_item(item, quantity)
				Log.debug("enemies", "Enemy received %dx %s" % [quantity, item.display_name])

## Stats from race + class data. `skill_list` replaces the class's own skills
## (archetype enemies roll theirs); empty uses class_data["skills"].
func setup_character(character: CharacterData, character_class: String, class_type: String, race_name: String, race_data: Dictionary, skill_list: Array = []):
	if not classes[class_type].has(character_class):
		push_error("ERROR: Class '%s' not found in classes['%s']!" % [character_class, class_type])
		return
	var class_data = classes[class_type][character_class]

	character.name = "%s %s" % [race_name, character_class]
	character.race = race_name
	character.character_class = character_class

	character.vitality = class_data["base_vit"] + race_data["vit_mod"]
	character.strength = class_data["base_str"] + race_data["str_mod"]
	character.dexterity = class_data["base_dex"] + race_data["dex_mod"]
	character.intelligence = class_data["base_int"] + race_data["int_mod"]
	character.faith = class_data["base_fai"] + race_data["fai_mod"]
	character.mind = class_data["base_mnd"] + race_data["mnd_mod"]
	character.endurance = class_data["base_end"] + race_data["end_mod"]
	character.arcane = class_data["base_arc"] + race_data["arc_mod"]
	character.agility = class_data["base_agi"] + race_data["agi_mod"]
	character.fortitude = class_data["base_for"] + race_data["for_mod"]

	character.attack_power_type = class_data["attack_power_type"]
	character.spell_power_type = class_data["spell_power_type"]
	character.calculate_secondary_attributes()

	var valid_skills: Array = []
	for skill_name in (skill_list if not skill_list.is_empty() else class_data["skills"]):
		if skills.has(skill_name):
			valid_skills.append(skill_name)

	if valid_skills.size() > 0:
		character.add_skills(valid_skills)

## Remember the archetype and AI role on the character (read by EnemyAI).
func _tag_archetype(c: CharacterData, archetype: String) -> void:
	c.set_meta("archetype", archetype)
	c.set_meta("ai_role", String(EnemyArchetypes.get_archetype(archetype).get("ai_role", "")))

func get_rarity_tier(rarity: String) -> int:
	match rarity:
		"common": return 0
		"uncommon": return 1
		"magic": return 2
		"rare": return 3
		"epic": return 4
		"legendary": return 5
		_: return 0
