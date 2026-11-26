# res://scripts/autoload/LedgerManager.gd
# The Guild Ledger (data/ledger.json): renown standings for the player and every
# active Guild adventurer, scored by the same formula for both:
#   rank, guild points, deepest floor cleared, bosses slain, level, world firsts.
# Deeds are tracked as they happen: the player's in town_state["ledger"], an
# NPC's in npc.deeds (AdventurerManager job results call record_npc_*).
# Each new week the standings are snapshotted for the "movers" arrows, and the
# news reports changes at the top and your own climb.
extends Node

func _ready() -> void:
	GameEvents.floor_cleared.connect(_on_floor_cleared)
	GameEvents.day_passed.connect(_on_day)

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("ledger")
	return d if d is Dictionary else {}

func _w(key: String, default_value: float) -> float:
	return float(cfg().get("weights", {}).get(key, default_value))

# === DEEDS ===

func _state(player: CharacterData) -> Dictionary:
	if not player.town_state.has("ledger"):
		player.town_state["ledger"] = {"bosses": 0, "firsts": 0, "crowns": 0, "last_week": -1, "last": {}, "year": 0, "crownings": [], "champion": ""}
	return player.town_state["ledger"]

func _on_floor_cleared(_location: String, _floor_num: int) -> void:
	var p = DungeonStateManager.active_player
	if p:
		_state(p).bosses = int(_state(p).bosses) + 1

func _deeds(npc: Dictionary) -> Dictionary:
	if not npc.has("deeds"):   # older saves / fresh rosters: their gear tells how deep they've been
		npc["deeds"] = {"bosses": 0, "deepest": max(0, int(npc.get("gear_floor", 1)) - 1), "firsts": 0, "crowns": 0}
	return npc.deeds

## An NPC finished a job on `fl` (AdventurerManager._resolve_job).
func record_npc_job(npc: Dictionary, fl: int, won: bool, boss: bool) -> void:
	if not won:
		return
	var d = _deeds(npc)
	if boss:
		d.bosses = int(d.bosses) + 1
		d.deepest = max(int(d.deepest), fl)
	else:
		d.deepest = max(int(d.deepest), fl - 1)

## A World First (first clear of a key floor/boss) - later systems call this.
func record_first(player: CharacterData, npc: Dictionary = {}) -> void:
	if npc.is_empty():
		_state(player).firsts = int(_state(player).firsts) + 1
	else:
		_deeds(npc).firsts = int(_deeds(npc).firsts) + 1

# === PROFILES & RENOWN ===

## Everyone in the same shape: {key, name, is_player, rank, points, level,
## deepest, bosses, firsts, renown, npc}
func profile_player(player: CharacterData) -> Dictionary:
	var deepest = player.deepest_floor_cleared()
	var s = _state(player)
	var p := {"key": "you", "name": player.name, "is_player": true, "rank": RankManager.get_rank(player),
		"points": GuildManager.get_points(player), "level": player.level, "deepest": deepest,
		"bosses": int(s.bosses), "firsts": int(s.firsts), "crowns": int(s.get("crowns", 0)), "npc": {}}
	p.renown = renown(p)
	return p

func profile_npc(npc: Dictionary) -> Dictionary:
	var d = _deeds(npc)
	var p := {"key": "npc_%d" % int(npc.id), "name": String(npc.name), "is_player": false, "rank": String(npc.rank),
		"points": int(npc.points), "level": int(npc.level), "deepest": int(d.deepest),
		"bosses": int(d.bosses), "firsts": int(d.firsts), "crowns": int(d.get("crowns", 0)), "npc": npc}
	p.renown = renown(p)
	return p

## Another player character of this world (from the world's register).
func profile_pc(pc_name: String, e: Dictionary) -> Dictionary:
	var p := {"key": "pc:" + pc_name, "name": pc_name, "is_player": false, "is_pc": true, "rank": String(e.get("rank", "F")),
		"points": int(e.get("points", 0)), "level": int(e.get("level", 1)), "deepest": int(e.get("deepest", 0)),
		"bosses": int(e.get("bosses", 0)), "firsts": int(e.get("firsts", 0)), "crowns": int(e.get("crowns", 0)), "npc": {}}
	p.renown = renown(p)
	return p

func renown(p: Dictionary) -> int:
	return int(round(RankManager.rank_index(String(p.rank)) * _w("per_rank", 120) + int(p.points) * _w("per_point", 1.0)
		+ int(p.deepest) * _w("per_floor", 25) + int(p.bosses) * _w("per_boss", 15)
		+ int(p.level) * _w("per_level", 10) + int(p.firsts) * _w("per_first", 150)
		+ int(p.get("crowns", 0)) * _w("per_crown", 100)))

## The standings, best first. Each profile gets "pos" (1-based) and "move"
## (places gained since the week's snapshot; 0 = same or new).
func standings(player: CharacterData) -> Array:
	var out: Array = [] if WorldGen.is_prehistory(player) else [profile_player(player)]
	for n in AdventurerManager.active(player):
		out.append(profile_npc(n))
	if not WorldGen.is_prehistory(player):
		for pc in WorldShare.others(player):   # other characters in this shared world
			out.append(profile_pc(String(pc), WorldShare.others(player)[pc]))
	out.sort_custom(func(a, b): return a.renown > b.renown if a.renown != b.renown else (a.is_player and not b.is_player))
	var last: Dictionary = _state(player).last
	for i in range(out.size()):
		out[i].pos = i + 1
		out[i].move = int(last[out[i].key]) - (i + 1) if last.has(out[i].key) else 0
	return out

func position(player: CharacterData) -> int:
	for p in standings(player):
		if p.is_player:
			return int(p.pos)
	return 0

## "#4 of 19 - 120 renown behind Mara Thorne (#3)" for the HUD / news.
func summary(player: CharacterData) -> String:
	var st = standings(player)
	for i in range(st.size()):
		if st[i].is_player:
			if i == 0:
				return "#1 of %d on the Guild Ledger" % st.size()
			return "#%d of %d - %d renown behind %s (#%d)" % [i + 1, st.size(), int(st[i - 1].renown - st[i].renown), st[i - 1].name, i]
	return ""

# === WEEKLY SNAPSHOT & NEWS ===

func _on_day(player: CharacterData, day: int) -> void:
	if player == null:
		return
	_crowning_tick(player, day)
	var week = int((day - 1) / 7)
	var s = _state(player)
	if int(s.last_week) == week:
		return
	var before: Dictionary = s.last
	var st = standings(player)
	if not before.is_empty():
		_report(player, st, before)
	var snap := {}
	for p in st:
		snap[p.key] = int(p.pos)
	s.last = snap
	s.last_week = week

func _report(player: CharacterData, st: Array, before: Dictionary) -> void:
	var top = int(cfg().get("news_top", 5))
	for p in st.slice(0, top):
		var was = int(before.get(p.key, 999))
		if p.is_player:
			if p.pos < was:
				WorldClock.add_news(player, "You climbed to #%d on the Guild Ledger." % p.pos, "rank")
		elif p.pos == 1 and was != 1:
			WorldClock.add_news(player, "%s now tops the Guild Ledger." % p.name, "rank")
		elif p.pos < was and was > top:
			WorldClock.add_news(player, "%s broke into the Ledger's top %d (#%d)." % [p.name, top, p.pos], "rank")
	var me = st.filter(func(p): return p.is_player)
	if not me.is_empty() and int(before.get("you", 999)) < int(me[0].pos):
		WorldClock.add_news(player, "You slipped to #%d on the Guild Ledger." % me[0].pos, "rank")

# === THE YEARLY CROWNING ===

func _crown_cfg() -> Dictionary:
	return cfg().get("crowning", {})

func days_per_year() -> int:
	var c: Dictionary = WorldClock.cfg.get("calendar", {})
	return int(c.get("days_per_week", 7)) * int(c.get("weeks_per_season", 4)) * max(1, (c.get("seasons", ["", "", "", ""]) as Array).size())

func year_of(day: int) -> int:
	return int((max(1, day) - 1) / days_per_year()) + 1

## Days until the next crowning (the first day of next year).
func days_to_crowning(player: CharacterData) -> int:
	var d = WorldClock.day(player)
	return year_of(d) * days_per_year() + 1 - d

## The reigning Champion: {"name", "year", "is_player", "key"} or {}.
func champion(player: CharacterData) -> Dictionary:
	var c: Array = _state(player).get("crownings", [])
	return c[-1] if not c.is_empty() else {}

func is_champion_npc(player: CharacterData, npc: Dictionary) -> bool:
	return String(champion(player).get("key", "")) == "npc_%d" % int(npc.get("id", -1))

func _crowning_tick(player: CharacterData, day: int) -> void:
	var s = _state(player)
	var y = year_of(day)
	if int(s.get("year", 0)) == 0:
		s.year = y
	if y > int(s.year):
		for past in range(int(s.year), y):
			crown(player, past)
		s.year = y
	elif days_to_crowning(player) == int(_crown_cfg().get("warning_days", 7)):
		var st = standings(player)
		if not st.is_empty():
			var lead = st[0]
			var me = st.filter(func(x): return x.is_player)
			var tail = "you lead it" if lead.is_player else ("%s leads; you're #%d" % [lead.name, me[0].pos] if not me.is_empty() else "%s leads" % lead.name)
			WorldClock.add_news(player, "The Crowning is in %d days: %s." % [days_to_crowning(player), tail], "rank")

## Crown the Ledger's #1 as Champion of `year`. Returns the crowning record.
func crown(player: CharacterData, year: int) -> Dictionary:
	var st = standings(player)
	if st.is_empty():
		return {}
	var top: Dictionary = st[0]
	var cc = _crown_cfg()
	var rec := {"year": year, "key": top.key, "name": top.name, "is_player": top.is_player, "renown": int(top.renown), "rank": top.rank}
	var s = _state(player)
	var prev = champion(player)
	s.crownings.append(rec)
	if top.is_player:
		s.crowns = int(s.get("crowns", 0)) + 1
		var gold = int(cc.get("player_gold", 2000)) + int(cc.get("player_gold_per_floor", 150)) * player.deepest_floor_cleared()
		player.currency.add(gold)
		GuildManager.state(player).points = int(GuildManager.state(player).points) + int(cc.get("player_points", 50))
		var again = String(prev.get("key", "")) == "you"
		WorldClock.add_news(player, ("You keep the crown: Champion of Year %d!" if again else "You are crowned Champion of Year %d!") % year
			+ " The Guild awards you %s." % Currency.format_copper(gold), "rank")
	elif top.get("is_pc", false):
		var pcs: Dictionary = player.town_state.get("world_meta", {}).get("pcs", {})
		if pcs.has(top.name):
			pcs[top.name]["crowns"] = int(pcs[top.name].get("crowns", 0)) + 1
		var me_pc = st.filter(func(x): return x.is_player)
		WorldClock.add_news(player, "%s is crowned Champion of Year %d.%s" % [top.name, year, (" You finished #%d." % me_pc[0].pos) if not me_pc.is_empty() else ""], "rank")
	else:
		var npc: Dictionary = top.npc
		_deeds(npc).crowns = int(_deeds(npc).get("crowns", 0)) + 1
		AdventurerManager._history(npc, WorldClock.day(player), "Crowned Champion of Year %d." % year)
		var line = "%s is crowned Champion of Year %d." % [top.name, year]
		if String(prev.get("key", "")) == top.key:
			line = "%s keeps the crown: Champion of Year %d." % [top.name, year]
		elif prev.get("is_player", false):
			line = "%s takes your crown: Champion of Year %d." % [top.name, year]
		var me = st.filter(func(x): return x.is_player)
		WorldClock.add_news(player, line + ((" You finished #%d." % me[0].pos) if not me.is_empty() else ""), "rank")
	GameEvents.champion_crowned.emit(String(top.name), year, bool(top.is_player))
	return rec
