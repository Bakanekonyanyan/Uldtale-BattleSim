# res://scripts/autoload/WorldClock.gd
# The world clock (data/world.json, GAME_ROADMAP.md section 5).
#
# Not real time: a day counter that moves on actions.
#   - An expedition costs travel + floors days (+1 if you were carried back).
#   - Resting at the Inn passes 1+ days.
# Each day passed emits GameEvents.day_passed (bounty deadlines, injuries and
# Lost & Found count down); once per advance GameEvents.days_advanced fires
# (the Guild board refreshes). Weekly: the shop restocks and a world event may
# start. Everything notable goes to the news ledger shown in town.
#
# State lives in player.town_state["world"]: {day, event, news, last_restock}.
extends Node

var cfg: Dictionary = {}

func _ready():
	var d = DataRegistry.get_data("world")
	cfg = d if d is Dictionary else {}
	if cfg.is_empty():
		push_error("WorldClock: data/world.json missing or invalid")
	GameEvents.expedition_ended.connect(_on_expedition_ended)

# ------------------------------------------------------------------ state

func state(player: CharacterData) -> Dictionary:
	if not player.town_state.has("world"):
		player.town_state["world"] = {"day": 1, "event": {}, "news": [], "last_restock": 1}
	return player.town_state["world"]

## SaveManager: a save from before the world clock counted its timers in
## expeditions. One expedition is roughly two days, so double what is left.
func migrate_old_save(player: CharacterData) -> void:
	for b in player.town_state.get("guild", {}).get("active", []):
		if not b.get("trial", false):
			b.deadline = int(b.get("deadline", 0)) * 2
	for inj in player.town_state.get("injuries", []):
		inj.remaining = int(inj.get("remaining", 0)) * 2
	for e in player.town_state.get("lost_found", []):
		e.expires_in = int(e.get("expires_in", 0)) * 2

func day(player: CharacterData) -> int:
	return int(state(player).day)

func days_per_week() -> int:
	return int(cfg.get("calendar", {}).get("days_per_week", 7))

## "Tideday, Day 12 - Week 2 of Bloomtide, Year 1"
func date_text(player: CharacterData) -> String:
	var c: Dictionary = cfg.get("calendar", {})
	var d = day(player) - 1
	var dpw = days_per_week()
	var wps = int(c.get("weeks_per_season", 4))
	var seasons: Array = c.get("seasons", ["Spring"])
	var weekdays: Array = c.get("weekdays", [])
	var week = d / dpw
	var season = (week / wps) % seasons.size()
	var year = week / (wps * seasons.size()) + 1
	var wd = (String(weekdays[d % weekdays.size()]) + ", ") if not weekdays.is_empty() else ""
	return "%sDay %d - Week %d of %s, Year %d" % [wd, d + 1, week % wps + 1, seasons[season], year]

## Short form for headers: "Day 12 (Bloomtide)"
func short_date(player: CharacterData) -> String:
	var c: Dictionary = cfg.get("calendar", {})
	var seasons: Array = c.get("seasons", ["Spring"])
	var week = (day(player) - 1) / days_per_week()
	return "Day %d, %s" % [day(player), seasons[(week / int(c.get("weeks_per_season", 4))) % seasons.size()]]

# ------------------------------------------------------------------ time costs

## Days an expedition takes: travel + base + per extra floor (+ defeat).
func expedition_days(location_id: String, floors_entered: int, defeated: bool) -> int:
	var tc: Dictionary = cfg.get("time_costs", {})
	var days = int(LocationManager.get_location(location_id).get("travel_days", 0)) + int(tc.get("expedition_base_days", 1))
	days += int(floor(max(0, floors_entered - 1) * float(tc.get("days_per_extra_floor", 0.5))))
	if defeated:
		days += int(tc.get("defeat_extra_days", 1))
	return max(1, days)

func _on_expedition_ended(location_id: String, cleared: bool) -> void:
	var player = DungeonStateManager.active_player
	if player == null:
		return
	var floors = max(1, DungeonStateManager.floors_entered)
	var days = expedition_days(location_id, floors, not cleared)
	advance(player, days, "%s (%d floor%s)" % [LocationManager.get_display_name(location_id), floors, "" if floors == 1 else "s"])

# ------------------------------------------------------------------ inn

func inn_price(player: CharacterData, nights: int = 1) -> int:
	var per = int(cfg.get("inn", {}).get("copper_per_level", 5)) * max(1, player.level)
	return int(ceil(per * nights * modifier(player, "inn_price")))

## Rest at the Inn for `nights` days. Returns {ok, reason}.
func rest(player: CharacterData, nights: int = 1) -> Dictionary:
	nights = max(1, nights)
	var cost = inn_price(player, nights)
	if player.currency.copper < cost:
		return {"ok": false, "reason": "A room for %d night%s costs %s." % [nights, "" if nights == 1 else "s", Currency.format_copper(cost)]}
	player.currency.subtract(cost)
	advance(player, nights, "rested at the Inn")
	# after the days pass: a healed injury raises max HP
	player.calculate_secondary_attributes()
	player.current_hp = player.max_hp
	player.current_mp = player.max_mp
	player.current_sp = player.max_sp
	SaveManager.save_game(player)
	return {"ok": true, "reason": "You rest at the Inn for %d night%s (%s). It is now %s." % [
		nights, "" if nights == 1 else "s", Currency.format_copper(cost), date_text(player)]}

# ------------------------------------------------------------------ advancing

## Pass `days` days. `why` is a short phrase for the news ledger.
func advance(player: CharacterData, days: int, why: String = "") -> void:
	if days <= 0:
		return
	var s = state(player)
	var from = int(s.day)
	for i in range(days):
		s.day = int(s.day) + 1
		_daily(player)
		GameEvents.day_passed.emit(player, int(s.day))
	if why != "":
		add_news(player, "%s (%d day%s)." % [why.substr(0, 1).to_upper() + why.substr(1), days, "" if days == 1 else "s"], "time")
	GameEvents.days_advanced.emit(player, from, int(s.day))
	SaveManager.save_game(player)

func _daily(player: CharacterData) -> void:
	var s = state(player)
	var d = int(s.day)
	# event ends
	var ev: Dictionary = s.get("event", {})
	if not ev.is_empty() and d >= int(ev.get("ends_day", 0)):
		var e = _event_data(String(ev.id))
		if String(e.get("end_news", "")) != "":
			add_news(player, _fmt(String(e.end_news), ev), "event")
		s.event = {}
	# weekly: restock, maybe a new event
	if (d - 1) % days_per_week() == 0:
		_restock(player, "The shop has restocked for the new week.")
		if s.event.is_empty():
			_roll_event(player)

func _restock(player: CharacterData, news: String) -> void:
	state(player).last_restock = day(player)
	ShopManager.restock()
	add_news(player, news, "shop")

# ------------------------------------------------------------------ events

func _event_data(id: String) -> Dictionary:
	return cfg.get("events", {}).get("list", {}).get(id, {})

func _roll_event(player: CharacterData) -> void:
	var ev_cfg: Dictionary = cfg.get("events", {})
	if RandomManager.randf() >= float(ev_cfg.get("chance_per_week", 0.0)):
		return
	var list: Dictionary = ev_cfg.get("list", {})
	var total := 0.0
	for id in list:
		total += float(list[id].get("weight", 1))
	if total <= 0.0:
		return
	var roll = RandomManager.randf() * total
	for id in list:
		roll -= float(list[id].get("weight", 1))
		if roll <= 0.0:
			start_event(player, id)
			return

## Start event `id` now (also used by tests and debugging).
func start_event(player: CharacterData, id: String, location := "") -> void:
	var e = _event_data(id)
	if e.is_empty():
		return
	var loc = location
	if loc == "" and String(e.get("location", "")) == "random_themed":
		var themed = LocationManager.get_ids().filter(func(l): return not LocationManager.is_mixed(l))
		loc = themed[RandomManager.randi() % themed.size()] if not themed.is_empty() else ""
	var ev = {"id": id, "location": loc, "ends_day": day(player) + int(e.get("duration_days", 7))}
	state(player).event = ev
	add_news(player, _fmt(String(e.get("news", e.get("name", id))), ev), "event")
	if e.get("restock", false):
		_restock(player, "Fresh stock from the caravan is on the shelves.")

func current_event(player: CharacterData) -> Dictionary:
	if player == null:
		return {}
	var ev: Dictionary = state(player).get("event", {})
	if ev.is_empty():
		return {}
	var out = _event_data(String(ev.id)).duplicate()
	out.merge(ev, true)
	return out

## Multiplier from the current event, 1.0 if none applies. Location-bound
## effects (enemy_power, reward_mult) only apply in the event's location.
func modifier(player: CharacterData, key: String, location_id := "") -> float:
	var ev = current_event(player)
	if ev.is_empty():
		return 1.0
	if key in ["enemy_power", "reward_mult"] and String(ev.get("location", "")) != "" and ev.location != location_id:
		return 1.0
	return float(ev.get("effects", {}).get(key, 1.0))

## The current character (town screens and global managers like the shop).
func _current() -> CharacterData:
	var p = DungeonStateManager.active_player
	return p if p != null else CharacterManager.get_current_character()

func current_modifier(key: String, location_id := "") -> float:
	var p = _current()
	return modifier(p, key, location_id) if p != null else 1.0

## Weekly consumable price drift (deterministic per item and week).
func price_drift(item_id: String) -> float:
	var p = _current()
	if p == null:
		return 1.0
	var week = (day(p) - 1) / days_per_week()
	var amp = float(cfg.get("shop", {}).get("price_drift", 0.0))
	var h = abs(hash("%s:%d" % [item_id, week]))
	return 1.0 + amp * (float(h % 2001) / 1000.0 - 1.0)

# ------------------------------------------------------------------ news

func add_news(player: CharacterData, text: String, kind := "info") -> void:
	var s = state(player)
	s.news.append({"day": int(s.day), "text": text, "kind": kind})
	ChronicleManager.on_news(player, text, kind)   # the world's history
	var cap = int(cfg.get("news", {}).get("max_entries", 40))
	while s.news.size() > cap:
		s.news.pop_front()

## Newest first.
func get_news(player: CharacterData, count := 10) -> Array:
	var n: Array = state(player).news.duplicate()
	n.reverse()
	return n.slice(0, count)

func _fmt(text: String, ev: Dictionary) -> String:
	return text.format({"location": LocationManager.get_display_name(String(ev.get("location", ""))) if String(ev.get("location", "")) != "" else "the wilds"})
