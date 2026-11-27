# DungeonStateManager.gd - Multi-Enemy Support
# Autoload: Add to project.godot as DungeonStateManager

extends Node

signal floor_changed(new_floor: int)
signal wave_changed(new_wave: int)
signal boss_spawned()

# Dungeon state
var current_location: String = "the_dungeon"
var current_floor: int = 1
var current_wave: int = 0
var waves_per_floor: int = 5
var max_floor: int = 25
var is_boss_fight: bool = false
var dungeon_description: String

# Battle context
var active_player: CharacterData
var active_enemies: Array[CharacterData] = []
var enemy_group: EnemyGroup

# Persistent state
var dungeon_active: bool = false
## Floors entered this expedition (the world clock charges days for them)
var floors_entered: int = 0

func start_dungeon(player: CharacterData, start_floor: int = 1, location_id: String = "the_dungeon"):
	"""Initialize a new expedition at a location"""
	active_player = player
	current_location = location_id if LocationManager.has_location(location_id) else LocationManager.DEFAULT_LOCATION
	player.last_location = current_location
	current_floor = start_floor
	floors_entered = 1
	current_wave = 0  # Start at 0, first advance_wave() makes it 1
	is_boss_fight = false
	dungeon_active = true
	
	# Sync player's floor
	player.current_floor = start_floor
	
	EnemyFactory.set_location(current_location)
	MomentumSystem.clear_accumulated_loot()  # no leftovers from a previous expedition
	
	Log.debug("dungeon_state", "DungeonState: Started %s at floor %d" % [LocationManager.get_display_name(current_location), current_floor])
	floor_changed.emit(current_floor)
	GameEvents.expedition_started.emit(current_location, current_floor)

func advance_wave() -> Dictionary:
	"""Move to next wave and return battle data"""
	current_wave += 1
	
	# Boss is wave 6 (after 5 regular waves)
	if current_wave == waves_per_floor + 1:
		is_boss_fight = true
		boss_spawned.emit()
		Log.debug("dungeon_state", "DungeonState: Boss wave! (Wave %d)" % current_wave)
	else:
		is_boss_fight = false
		wave_changed.emit(current_wave)
		Log.debug("dungeon_state", "DungeonState: Wave %d/%d" % [current_wave, waves_per_floor])
	
	# Generate enemy group
	enemy_group = EnemyGroup.new()
	enemy_group.initialize(current_floor, current_wave, is_boss_fight)
	active_enemies = enemy_group.enemies.duplicate()
	
	Log.debug("dungeon_state", "DungeonState: Generated %d enemies for battle" % active_enemies.size())
	
	return get_battle_data()

func advance_floor() -> bool:
	"""Move to next floor. Returns false if max floor reached."""
	if current_floor >= max_floor:
		Log.debug("dungeon_state", "DungeonState: Max floor reached!")
		return false
	if active_player and active_player.is_player and RankManager.is_floor_capped(active_player, current_floor + 1):
		Log.debug("dungeon_state", "DungeonState: floor %d needs a higher Adventurer rank" % (current_floor + 1))
		return false
	
	current_floor += 1
	floors_entered += 1
	current_wave = 0  # Reset to 0, next advance_wave() will make it 1
	is_boss_fight = false
	
	# Sync player's floor
	if active_player:
		active_player.current_floor = current_floor
	
	EnemyFactory.set_location(current_location)  # mixed locations re-roll the boss race
	
	Log.debug("dungeon_state", "DungeonState: Advanced to floor %d, wave reset to 0" % current_floor)
	floor_changed.emit(current_floor)
	return true

func get_battle_data() -> Dictionary:
	"""Get current battle context"""
	return {
		"player_character": active_player,
		"enemies": active_enemies,
		"current_wave": current_wave,
		"current_floor": current_floor,
		"location_id": current_location,
		"player_class": active_player.character_class if active_player else "",
		"is_boss_fight": is_boss_fight,
		"max_floor": max_floor,
		"waves_per_floor": waves_per_floor,
		"momentum_level": MomentumSystem.get_momentum(),
		"description": get_dungeon_description()
	}

func get_dungeon_description() -> String:
	"""Get flavor text for current dungeon"""
	var base = "%s: " % LocationManager.get_display_name(current_location)
	if LocationManager.is_mixed(current_location):
		base += "Creatures of every kind stalk these halls."
	else:
		match EnemyFactory.current_dungeon_race:
			"Goblin": base += "The air is thick with the stench of goblins."
			"Troll": base += "The ground trembles beneath your feet. You've stumbled into troll territory."
			"Orc": base += "War drums echo across the grass. An orc warband is near."
			"Fairy": base += "Glowing lights dance in the air. You've wandered into an enchanted glade."
			_: base += "Something stirs in the dark."
	
	if is_boss_fight:
		base += " [color=red][b]BOSS BATTLE![/b][/color]"
	var mods = RunState.describe()
	if mods != "":
		base += "\n[color=#c77dff]%s[/color]" % mods
	
	dungeon_description = base
	return base

func end_dungeon(cleared: bool = false):
	"""Clean up dungeon state. cleared = returned alive (false = died)."""
	if dungeon_active:
		GameEvents.expedition_ended.emit(current_location, cleared)
	dungeon_active = false
	current_wave = 0
	current_floor = 1
	is_boss_fight = false
	active_enemies.clear()
	enemy_group = null
	Log.debug("dungeon_state", "DungeonState: Dungeon ended")
