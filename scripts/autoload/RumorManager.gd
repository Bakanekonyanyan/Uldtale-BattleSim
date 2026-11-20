# res://scripts/autoload/RumorManager.gd
# Tavern rumours (data/rumours.json): tips that point at a floor of a location
# for a while. "elite" puts a named Elite in that floor's first regular wave;
# "cache" pays out when you clear that floor's boss. Either banks a bonus
# (gold, materials, maybe gear) with your expedition loot.
# State: player.town_state["rumours"] = [{id, type, location, floor, affix,
#   expires, spawned}]
extends Node

var _next_id := 1

func _ready() -> void:
	GameEvents.day_passed.connect(_on_day)
	GameEvents.floor_cleared.connect(_on_floor_cleared)

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("rumours")
	return d if d is Dictionary else {}

func list(player: CharacterData) -> Array:
	if player == null:
		return []
	if not player.town_state.has("rumours"):
		player.town_state["rumours"] = []
	return player.town_state["rumours"]

func _on_day(player: CharacterData, _day: int) -> void:
	if RandomManager.randf() < float(cfg().get("new_chance_per_day", 0.5)):
		refresh(player, true)
	else:
		refresh(player, false)

## Drop expired rumours; with `add`, fill up to max_active.
func refresh(player: CharacterData, add := true) -> void:
	if player == null:
		return
	var today = WorldClock.day(player)
	var l = list(player)
	for r in l.duplicate():
		if today > int(r.get("expires", 0)):
			l.erase(r)
	while add and l.size() < int(cfg().get("max_active", 2)):
		var r = _make(player, today)
		if r.is_empty():
			break
		l.append(r)
		WorldClock.add_news(player, "Rumour at the Tavern: " + text(r), "info")

func _make(player: CharacterData, today: int) -> Dictionary:
	var types: Dictionary = cfg().get("types", {})
	if types.is_empty():
		return {}
	var locs = LocationManager.get_ids()
	if locs.is_empty():
		return {}
	var loc = String(locs[RandomManager.randi() % locs.size()])
	var top = RankManager.start_floor_limit(player, loc)
	var fl = RandomManager.randi_range(1, max(1, top))
	var type = String(types.keys()[RandomManager.randi() % types.size()])
	var id = int(player.town_state.get("rumour_next_id", 1))
	player.town_state["rumour_next_id"] = id + 1
	return {"id": id, "type": type, "location": loc, "floor": fl, "affix": EliteAffixes.roll_affix() if type == "elite" else "",
		"expires": today + int(cfg().get("days_valid", 6)), "spawned": false}

func text(r: Dictionary) -> String:
	var t = String(cfg().get("types", {}).get(String(r.type), {}).get("text", "Something stirs on floor {floor} of {location}."))
	var aff = EliteAffixes.affix(String(r.get("affix", "")))
	return t.format({"floor": int(r.floor), "location": LocationManager.get_display_name(String(r.location)), "affix": String(aff.get("name", "fearsome"))})

# === EFFECTS ===

## An elite rumour for this floor not yet spawned: returns it (marked spawned).
func take_elite(player: CharacterData, location: String, fl: int) -> Dictionary:
	for r in list(player):
		if String(r.type) == "elite" and String(r.location) == location and int(r.floor) == fl and not r.spawned:
			r.spawned = true
			return r
	return {}

## The rumoured elite was beaten: bank the bonus. Returns a log line.
func claim(player: CharacterData, rumour_id: int, enemies: Array = []) -> String:
	for r in list(player).duplicate():
		if int(r.id) == rumour_id:
			list(player).erase(r)
			return _pay(player, r, enemies)
	return ""

func _on_floor_cleared(location: String, fl: int) -> void:
	var player = DungeonStateManager.active_player
	for r in list(player).duplicate():
		if String(r.type) == "cache" and String(r.location) == location and int(r.floor) == fl:
			list(player).erase(r)
			var line = _pay(player, r, [])
			WorldClock.add_news(player, line, "info")

func _pay(player: CharacterData, r: Dictionary, enemies: Array) -> String:
	var rw: Dictionary = cfg().get("reward", {})
	var fl = int(r.floor)
	var bank: Dictionary = {"currency": int(round(float(rw.get("gold_per_floor", 60)) * fl)), "equipment_instances": []}
	for i in range(int(rw.get("material_rolls", 3))):
		var drops = RewardsManager.roll_material_drops({"current_floor": fl, "is_boss_fight": false, "enemies": enemies})
		for id in drops:
			bank[id] = int(bank.get(id, 0)) + int(drops[id])
	if RandomManager.randf() < float(rw.get("gear_chance", 0.5)):
		var g = ItemManager.create_equipment_for_floor(ItemManager.get_random_weapon() if RandomManager.randf() < 0.5 else ItemManager.get_random_armor(), fl, 2)
		if g:
			bank.equipment_instances.append(g)
	MomentumSystem.bank_rewards(bank)
	return "The rumour was true! %s%s banked with your loot." % [Currency.format_copper(bank.currency), " and gear" if not bank.equipment_instances.is_empty() else ""]
