# res://scripts/autoload/AdventurerManager.gd
# NPC adventurers (data/adventurers.json, GAME_ROADMAP.md section 4).
#
# - A roster is generated per playthrough (names by race, any of the 12
#   classes, 2-3 traits, hidden Honor/Heart axes). Newcomers keep it between
#   roster_min and roster_max as adventurers die or retire.
# - Each day (WorldClock) idle adventurers may take a job. Everyday jobs are
#   abstract rolls; boss hunts and promotion trials are real battles
#   (AutoBattler). Failure: injury, retirement or death, weighted by traits.
# - Ambitious/greedy adventurers take bounties off your board. Rivals announce
#   when they out-rank you.
# - Tavern: chat (reveals traits), share a drink, give a gift -> rapport.
# State: player.town_state["adventurers"] = {list, next_id}.
extends Node

## A line for town screens (also written to the news ledger)
signal adventurer_news(text: String)

var cfg: Dictionary = {}
## Outcome counters per job kind, for balancing ({kind: [jobs, wins]})
var stats: Dictionary = {}

func _ready():
	var f = FileAccess.open("res://data/adventurers.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	cfg = d if d is Dictionary else {}
	if cfg.is_empty():
		push_error("AdventurerManager: data/adventurers.json missing or invalid")
	GameEvents.day_passed.connect(_on_day_passed)
	RankManager.rank_changed.connect(_on_player_promoted)

func _s(section: String) -> Dictionary:
	return cfg.get(section, {})

func _range(v, default_lo := 0, default_hi := 0) -> int:
	if v is Array and v.size() == 2:
		return RandomManager.randi_range(int(v[0]), int(v[1]))
	return int(v) if v != null else RandomManager.randi_range(default_lo, default_hi)

func _rangef(v) -> float:
	if v is Array and v.size() == 2:
		return RandomManager.randf_range(float(v[0]), float(v[1]))
	return float(v)

# ------------------------------------------------------------------ roster

func state(player: CharacterData) -> Dictionary:
	if not player.town_state.has("adventurers"):
		player.town_state["adventurers"] = {"list": [], "next_id": 1}
		_generate_roster(player)
	return player.town_state["adventurers"]

func all_adventurers(player: CharacterData) -> Array:
	return state(player).list

func active(player: CharacterData) -> Array:
	return state(player).list.filter(func(n): return is_active(n))

func is_active(npc: Dictionary) -> bool:
	return not String(npc.get("status", "")) in ["dead", "retired"]

func get_npc(player: CharacterData, id: int) -> Dictionary:
	for n in state(player).list:
		if int(n.id) == id:
			return n
	return {}

func _generate_roster(player: CharacterData) -> void:
	var st: Dictionary = _s("settings")
	var count = _range(st.get("roster_start", [15, 17]))
	var rivals = int(st.get("rivals_at_start", 2))
	for i in range(count):
		# rivals start close to a fresh adventurer: level 1-3
		var lv = st.get("newcomer_level", [1, 3]) if i < rivals else st.get("start_level", [1, 8])
		_add(player, generate(player, lv, i < rivals))

func _add(player: CharacterData, npc: Dictionary) -> Dictionary:
	var s = player.town_state["adventurers"]
	npc.id = int(s.next_id)
	s.next_id = int(s.next_id) + 1
	s.list.append(npc)
	return npc

## A new adventurer (not added to the roster).
func generate(player: CharacterData, level_range = [1, 3], rival := false) -> Dictionary:
	var races: Array = _s("names").keys().filter(func(k): return not String(k).begins_with("_"))
	var race: String = races[RandomManager.randi() % races.size()]
	var classes: Array = EnemyFactory.classes.get("playable", {}).keys()
	var cls: String = classes[RandomManager.randi() % classes.size()]
	var level = _range(level_range)
	var traits = _roll_traits(rival)
	var honor := RandomManager.randi_range(-25, 25)
	var heart := RandomManager.randi_range(-25, 25)
	for t in traits:
		honor += int(trait_data(t).get("honor", 0))
		heart += int(trait_data(t).get("heart", 0))
	var rank = _rank_for_level(level)
	var soc: Dictionary = _s("social")
	var npc := {
		"id": 0, "name": _unique_name(player, race), "race": race, "cls": cls,
		"level": level, "xp": 0, "rank": rank,
		"points": int(RankManager.info(rank).get("points", 0)) + RandomManager.randi_range(0, 15),
		"gear_floor": max(1, int(level * float(_s("jobs").get("gear_floor_per_level", 0.6)))),
		"branch": RandomManager.randi() % 3,
		"traits": traits, "known_traits": [], "chats": 0,
		"honor": clamp(honor, -100, 100), "heart": clamp(heart, -100, 100),
		"rapport": clamp(_range(soc.get("start_rapport", [-10, 15])) + heart / 10, -100, 100),
		"rivalry": int(soc.get("rival_at", 3)) if rival else 0, "rival": rival,
		"status": "idle", "job": {}, "injured_until": 0, "ahead_of_player": false,
		"record": {"jobs": 0, "wins": 0, "fails": 0}, "history": [],
		"drank_day": 0, "chat_day": 0, "gift_day": 0, "joined_day": 1
	}
	return npc

func _rank_for_level(level: int) -> String:
	# a rough guess for a pre-existing adventurer: one rank per ~3 levels, F..C
	var ids = RankManager.rank_ids()
	return String(ids[clamp((level - 1) / 3, 0, min(3, ids.size() - 1))])

func trait_data(id: String) -> Dictionary:
	return _s("traits").get(id, {})

func _roll_traits(rival: bool) -> Array:
	var all: Array = _s("traits").keys()
	var out: Array = []
	if rival:
		out.append("ambitious" if RandomManager.randf() < 0.6 else "boastful")
	var want = RandomManager.randi_range(2, 3)
	var guard := 0
	while out.size() < want and guard < 40:
		guard += 1
		var t: String = all[RandomManager.randi() % all.size()]
		if t in out:
			continue
		var clash := false
		for o in out:
			if t in trait_data(o).get("exclusive", []) or o in trait_data(t).get("exclusive", []):
				clash = true
		if not clash:
			out.append(t)
	return out

func _unique_name(player: CharacterData, race: String) -> String:
	var n: Dictionary = _s("names").get(race, {})
	var taken := {}
	if player.town_state.has("adventurers"):
		for x in player.town_state["adventurers"].list:
			taken[String(x.name)] = true
	taken[player.name] = true
	for i in range(30):
		var given = String(_pick(n.get("start", ["Al"]))) + String(_pick(n.get("end", ["an"])))
		var fam = String(_pick(n.get("family", [""])))
		var full = given if fam == "" else ("%s %s" % [given, fam])
		if not taken.has(full):
			return full
	return "%s %d" % [race, RandomManager.randi() % 1000]

func _pick(a: Array):
	return a[RandomManager.randi() % a.size()] if not a.is_empty() else ""

## Product of a trait multiplier (default 1) or sum of an additive field.
func trait_mult(npc: Dictionary, key: String) -> float:
	var m := 1.0
	for t in npc.get("traits", []):
		m *= float(trait_data(t).get(key, 1.0))
	return m

func trait_sum(npc: Dictionary, key: String) -> float:
	var s := 0.0
	for t in npc.get("traits", []):
		s += float(trait_data(t).get(key, 0.0))
	return s

func has_trait_flag(npc: Dictionary, key: String) -> bool:
	for t in npc.get("traits", []):
		if trait_data(t).get(key, false):
			return true
	return false

# ------------------------------------------------------------------ descriptions

func alignment_label(npc: Dictionary) -> String:
	var h = int(npc.honor)
	var k = int(npc.heart)
	var a = "Honorable" if h > 33 else ("Unscrupulous" if h < -33 else "Pragmatic")
	var b = "kind" if k > 33 else ("ruthless" if k < -33 else "reserved")
	return "%s and %s" % [a, b]

func alignment_known(npc: Dictionary) -> bool:
	return int(npc.get("chats", 0)) >= int(_s("social").get("alignment_known_after_chats", 3)) or int(npc.rapport) >= int(_s("social").get("friend_at", 40))

func title_line(npc: Dictionary) -> String:
	return "Level %d %s %s, %s-Rank" % [int(npc.level), npc.race, npc.cls, npc.rank]

func tags(npc: Dictionary) -> Array:
	var soc: Dictionary = _s("social")
	var out: Array = []
	var r = int(npc.rapport)
	if r >= int(soc.get("close_friend_at", 70)):
		out.append("Close friend")
	elif r >= int(soc.get("friend_at", 40)):
		out.append("Friend")
	elif r <= int(soc.get("enemy_at", -40)):
		out.append("Enemy")
	if int(npc.get("rivalry", 0)) >= int(soc.get("rival_at", 3)):
		out.append("Rival")
	return out

func status_text(player: CharacterData, npc: Dictionary) -> String:
	match String(npc.status):
		"job":
			var j: Dictionary = npc.job
			var what = {"boss": "hunting the boss of", "trial": "taking a promotion trial in", "job": "on a job in"}.get(String(j.get("kind", "job")), "on a job in")
			return "%s %s, floor %d (back on day %d)" % [what.capitalize(), LocationManager.get_display_name(String(j.location)), int(j.floor), int(j.ends)]
		"injured":
			return "Recovering from injuries (until day %d)" % int(npc.injured_until)
		"dead":
			return "Fell in battle"
		"retired":
			return "Retired"
		"party":
			if int(npc.get("injured_until", 0)) > WorldClock.day(player):
				return "In your party - recovering until day %d" % int(npc.injured_until)
			return "In your party (takes %d%% of the gold)" % int(round(PartyManager.share(npc) * 100))
	return "In town"

func in_town(npc: Dictionary) -> bool:
	return String(npc.status) in ["idle", "injured", "party"]

func _history(npc: Dictionary, day: int, text: String) -> void:
	npc.history.append({"day": day, "text": text})
	while npc.history.size() > int(_s("settings").get("history_max", 10)):
		npc.history.pop_front()

func _news(player: CharacterData, text: String, kind := "adventurer") -> void:
	WorldClock.add_news(player, text, kind)
	adventurer_news.emit(text)

# ------------------------------------------------------------------ daily simulation

func _on_day_passed(player: CharacterData, day: int) -> void:
	if player == null:
		return
	simulate_day(player, day)

func simulate_day(player: CharacterData, day: int) -> void:
	for npc in active(player).duplicate():
		match String(npc.status):
			"job":
				if day >= int(npc.job.ends):
					_resolve_job(player, npc, day)
			"injured":
				if day >= int(npc.injured_until):
					npc.status = "idle"
					_history(npc, day, "Recovered and back in town.")
			"idle":
				_maybe_start(player, npc, day)
	# newcomers keep the guild alive
	var st: Dictionary = _s("settings")
	var n_active = active(player).size()
	if n_active < int(st.get("roster_min", 14)) or (n_active < int(st.get("roster_max", 20)) and RandomManager.randf() < float(st.get("newcomer_chance_per_day", 0.15))):
		var npc = _add(player, generate(player, st.get("newcomer_level", [1, 3])))
		npc.joined_day = day
		_history(npc, day, "Signed up with the Guild.")
		_news(player, "A new adventurer joined the Guild: %s, a %s %s." % [npc.name, npc.race, npc.cls])

func _maybe_start(player: CharacterData, npc: Dictionary, day: int) -> void:
	var jobs: Dictionary = _s("jobs")
	# promotion trial first, when they qualify
	var nxt = _next_rank(npc)
	var t: Dictionary = RankManager.info(nxt).get("trial", {}) if nxt != "" else {}
	if nxt != "" and int(npc.points) >= int(RankManager.info(nxt).get("points", 0)) \
			and int(npc.level) >= int(ceil(int(t.get("min_floor", 1)) * float(jobs.get("trial_level_per_floor", 1.6)))) \
			and RandomManager.randf() < float(jobs.get("trial_chance", 0.5)):
		_start_job(npc, day, "trial", String(t.get("location", "the_dungeon")), int(t.get("min_floor", 1)))
		_history(npc, day, "Set out for the %s." % t.get("title", "promotion trial"))
		return
	if RandomManager.randf() >= float(jobs.get("take_chance", 0.45)) + trait_sum(npc, "job_chance"):
		return
	var ids = LocationManager.get_ids()
	var loc: String = ids[RandomManager.randi() % ids.size()]
	var cap = int(RankManager.info(String(npc.rank)).get("floor_cap", 0))
	var fl = max(1, int(round(int(npc.level) * 0.5)) + int(trait_sum(npc, "floor_bias")) + RandomManager.randi_range(-1, 0))
	if cap > 0:
		fl = min(fl, cap)
	var kind = "boss" if RandomManager.randf() < float(jobs.get("boss_hunt_chance", 0.2)) else "job"
	if kind == "boss":
		fl = max(1, fl - 1)
	_start_job(npc, day, kind, loc, fl)
	# competition: take a bounty off the player's board
	var board: Array = GuildManager.state(player).board
	if board.size() > 1 and RandomManager.randf() < float(jobs.get("compete_chance", 0.25)) * trait_mult(npc, "compete"):
		var b = board.pop_at(RandomManager.randi() % board.size())
		npc.job["bounty"] = String(b.title)
		npc.rivalry = int(npc.get("rivalry", 0)) + 1
		_history(npc, day, "Took the bounty \"%s\"." % b.title)
		_news(player, "%s took the bounty \"%s\" off the board." % [npc.name, b.title], "guild")
	else:
		_history(npc, day, "Left for %s (floor %d)." % [LocationManager.get_display_name(loc), fl])

func _start_job(npc: Dictionary, day: int, kind: String, loc: String, fl: int) -> void:
	var floors = _range(_s("jobs").get("floors", [1, 2]))
	npc.status = "job"
	npc.job = {"kind": kind, "location": loc, "floor": fl, "ends": day + WorldClock.expedition_days(loc, floors, false)}

func _next_rank(npc: Dictionary) -> String:
	var ids = RankManager.rank_ids()
	var i = RankManager.rank_index(String(npc.rank)) + 1
	return String(ids[i]) if i < ids.size() else ""

## Abstract success chance for an everyday job.
func job_success_chance(npc: Dictionary, fl: int) -> float:
	var j: Dictionary = _s("jobs")
	var power = int(npc.level) * 0.5 + int(npc.gear_floor) - fl * 1.5
	var c = float(j.get("success_base", 0.75)) + float(j.get("success_per_power", 0.06)) * power + trait_sum(npc, "success")
	return clamp(c, float(j.get("success_min", 0.15)), float(j.get("success_max", 0.97)))

func _resolve_job(player: CharacterData, npc: Dictionary, day: int) -> void:
	var j: Dictionary = npc.job
	var kind = String(j.get("kind", "job"))
	var fl = int(j.floor)
	var where = LocationManager.get_display_name(String(j.location))
	var won: bool
	if kind in ["boss", "trial"]:
		# the big moments are fought for real
		var hero = AutoBattler.build_hero(npc)
		won = AutoBattler.fight_floor(hero, String(j.location), fl, true).won
	else:
		won = RandomManager.randf() < job_success_chance(npc, fl)
	npc.record.jobs = int(npc.record.jobs) + 1
	if not stats.has(kind):
		stats[kind] = [0, 0]
	stats[kind][0] += 1
	stats[kind][1] += 1 if won else 0
	npc.status = "idle"
	npc.job = {}
	if won:
		npc.record.wins = int(npc.record.wins) + 1
		var jobs: Dictionary = _s("jobs")
		var mult = 2.0 if kind == "boss" else 1.0
		npc.points = int(npc.points) + int((int(jobs.get("points_base", 6)) + int(jobs.get("points_per_floor", 4)) * fl) * mult) * (0 if kind == "trial" else 1)
		_gain_xp(npc, int(int(jobs.get("xp_per_floor", 140)) * fl * mult))
		match kind:
			"trial":
				_promote(player, npc, day)
			"boss":
				_history(npc, day, "Slew the boss of %s floor %d." % [where, fl])
				if fl >= 5 or npc.get("rival", false) or not tags(npc).is_empty():
					_news(player, "%s (%s) slew the boss of %s floor %d." % [npc.name, npc.rank, where, fl])
			_:
				_history(npc, day, "Came back from %s with the job done." % where)
	else:
		npc.record.fails = int(npc.record.fails) + 1
		_fate(player, npc, day, kind != "job", where, fl)

func _gain_xp(npc: Dictionary, xp: int) -> void:
	npc.xp = int(npc.xp) + xp
	var need = LevelSystem.calculate_xp_for_level(int(npc.level))
	while int(npc.xp) >= need:
		npc.xp = int(npc.xp) - need
		npc.level = int(npc.level) + 1
		need = LevelSystem.calculate_xp_for_level(int(npc.level))
	npc.gear_floor = max(int(npc.gear_floor), int(int(npc.level) * float(_s("jobs").get("gear_floor_per_level", 0.6))))

func _promote(player: CharacterData, npc: Dictionary, day: int) -> void:
	var nxt = _next_rank(npc)
	if nxt == "":
		return
	npc.rank = nxt
	_history(npc, day, "Promoted to %s." % RankManager.display(nxt))
	var ahead = RankManager.rank_index(nxt) > RankManager.get_rank_index(player)
	if npc.get("rival", false) or "Rival" in tags(npc):
		if ahead and not npc.get("ahead_of_player", false):
			_news(player, "Your rival %s is now %s - ahead of you." % [npc.name, RankManager.display(nxt)], "rival")
		else:
			_news(player, "Your rival %s was promoted to %s." % [npc.name, RankManager.display(nxt)], "rival")
	else:
		_news(player, "%s was promoted to %s." % [npc.name, RankManager.display(nxt)], "rank")
	npc.ahead_of_player = ahead

## A failed job: death, retirement or injury, weighted by traits.
func _fate(player: CharacterData, npc: Dictionary, day: int, big: bool, where: String, fl: int) -> void:
	var f: Dictionary = _s("fates")
	var death = float(f.get("boss_death_chance" if big else "death_chance", 0.05)) * trait_mult(npc, "death")
	var retire = float(f.get("boss_retire_chance" if big else "retire_chance", 0.04)) * trait_mult(npc, "retire")
	var friend = "Friend" in tags(npc) or "Close friend" in tags(npc)
	var roll = RandomManager.randf()
	if roll < death:
		npc.status = "dead"
		npc.died_day = day
		_history(npc, day, "Fell in %s, floor %d." % [where, fl])
		_news(player, "%s (%s-Rank %s) fell in %s.%s" % [npc.name, npc.rank, npc.cls, where, " You lost a friend." if friend else ""], "death")
	elif roll < death + retire:
		npc.status = "retired"
		_history(npc, day, "Hung up their %s after a bad day in %s." % ["blade" if npc.cls in ["Paladin", "Samurai", "Berserker", "Myrmidon", "Shinobi"] else "gear", where])
		_news(player, "%s retired from adventuring after a narrow escape in %s." % [npc.name, where])
	else:
		var days = _range(f.get("injury_days", [3, 8]))
		npc.status = "injured"
		npc.injured_until = day + days
		_history(npc, day, "Dragged back from %s, injured (%d days)." % [where, days])
		if big and (friend or "Rival" in tags(npc)):
			_news(player, "%s was carried back from %s, badly hurt." % [npc.name, where])

# ------------------------------------------------------------------ player events

## Ambitious adventurers resent your promotion; friends celebrate it.
func _on_player_promoted(player: CharacterData, rank_id: String) -> void:
	var day = WorldClock.day(player)
	for npc in active(player):
		var their = RankManager.rank_index(String(npc.rank))
		if has_trait_flag(npc, "rival") and their <= RankManager.rank_index(rank_id):
			npc.rivalry = int(npc.get("rivalry", 0)) + 1
			npc.rapport = clamp(int(npc.rapport) - 3, -100, 100)
			_history(npc, day, "Scowled at news of %s's promotion." % player.name)
		elif int(npc.rapport) >= 20 and in_town(npc):
			npc.rapport = clamp(int(npc.rapport) + 3, -100, 100)
			_history(npc, day, "Raised a toast to %s's promotion." % player.name)
		if their < RankManager.rank_index(rank_id):
			npc.ahead_of_player = false

# ------------------------------------------------------------------ social (Tavern)

func drink_price(player: CharacterData) -> int:
	return int(_s("social").get("drink_copper_per_level", 8)) * max(1, player.level)

func _gain(npc: Dictionary, base: float, key: String) -> int:
	var g = base * trait_mult(npc, key)
	if int(npc.rapport) >= 20:
		g *= trait_mult(npc, "friend_bonus")
	return max(1, int(round(g)))

func _set_rapport(npc: Dictionary, delta: int) -> void:
	npc.rapport = clamp(int(npc.rapport) + delta, -100, 100)

## Reveal one unknown trait. Returns its name, or "".
func _reveal(npc: Dictionary) -> String:
	var hidden = npc.traits.filter(func(t): return not t in npc.known_traits)
	if hidden.is_empty():
		return ""
	var t = hidden[RandomManager.randi() % hidden.size()]
	npc.known_traits.append(t)
	return String(trait_data(t).get("name", t))

func chat(player: CharacterData, id: int) -> Dictionary:
	var npc = get_npc(player, id)
	var day = WorldClock.day(player)
	if npc.is_empty() or not in_town(npc):
		return {"ok": false, "reason": "They aren't in town."}
	if int(npc.chat_day) == day:
		return {"ok": false, "reason": "You've already talked with %s today." % npc.name}
	npc.chat_day = day
	npc.chats = int(npc.chats) + 1
	var g = _gain(npc, _rangef(_s("social").get("chat_rapport", [1, 3])), "chat")
	_set_rapport(npc, g)
	var r = "You trade stories with %s (+%d rapport)." % [npc.name, g]
	var t = _reveal(npc)
	if t != "":
		r += " You learn they are %s." % t
	if alignment_known(npc) and int(npc.chats) == int(_s("social").get("alignment_known_after_chats", 3)):
		r += " You have a sense of who they are: %s." % alignment_label(npc)
	return {"ok": true, "reason": r}

func drink(player: CharacterData, id: int) -> Dictionary:
	var npc = get_npc(player, id)
	var day = WorldClock.day(player)
	if npc.is_empty() or not in_town(npc):
		return {"ok": false, "reason": "They aren't in town."}
	if int(npc.drank_day) == day:
		return {"ok": false, "reason": "%s has had enough for one night." % npc.name}
	var cost = drink_price(player)
	if player.currency.copper < cost:
		return {"ok": false, "reason": "A round costs %s." % Currency.format_copper(cost)}
	player.currency.subtract(cost)
	npc.drank_day = day
	var g = _gain(npc, _rangef(_s("social").get("drink_rapport", [3, 7])), "drink")
	_set_rapport(npc, g)
	var r = "You buy %s a drink (%s, +%d rapport)." % [npc.name, Currency.format_copper(cost), g]
	if RandomManager.randf() < 0.3:
		var t = _reveal(npc)
		if t != "":
			r += " Loosened up, they let slip that they're %s." % t
	return {"ok": true, "reason": r}

## Give one of `inventory_key` from the pack. Value and taste decide the gain.
func gift(player: CharacterData, id: int, inventory_key: String) -> Dictionary:
	var npc = get_npc(player, id)
	var day = WorldClock.day(player)
	if npc.is_empty() or not in_town(npc):
		return {"ok": false, "reason": "They aren't in town."}
	if int(npc.gift_day) == day:
		return {"ok": false, "reason": "One gift a day is plenty."}
	if not player.inventory.items.has(inventory_key):
		return {"ok": false, "reason": "You don't have that."}
	var item: Item = player.inventory.items[inventory_key].item
	var soc: Dictionary = _s("social")
	var category = "equipment" if item is Equipment else ("material" if item.item_type == Item.ItemType.MATERIAL else "consumable")
	var likes := 1.0
	for t in npc.traits:
		likes *= float(trait_data(t).get("likes", {}).get(category, 1.0))
	var g = min(float(soc.get("gift_rapport_max", 15)), max(1.0, item.value * float(soc.get("gift_rapport_per_copper", 0.08)))) * likes * trait_mult(npc, "gift")
	g = max(1, int(round(g)))
	if player.equipment.values().has(item):
		return {"ok": false, "reason": "Unequip it first."}
	player.inventory.remove_item(inventory_key, 1)
	npc.gift_day = day
	_set_rapport(npc, g)
	_history(npc, day, "Received %s from %s." % [item.display_name, player.name])
	var react = "They love it!" if likes > 1.2 else ("They seem pleased." if likes >= 1.0 else "They accept it politely.")
	return {"ok": true, "reason": "You give %s to %s. %s (+%d rapport)" % [item.display_name, npc.name, react, g]}
