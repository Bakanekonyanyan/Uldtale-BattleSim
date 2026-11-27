# res://scripts/autoload/PartyManager.gd
# Your party (data/adventurers.json "party", GAME_ROADMAP.md B2).
#
# - From F-Rank: HIRE an adventurer for one expedition at the Tavern (a fee
#   by their level, half for friends; a bigger share of the gold; up to one
#   rank above yours). They go back to work when the expedition ends, or after
#   hire_days if you never set out.
# - From D-Rank: RECRUIT a permanent team at Friend rapport (rank
#   team_slots). Party size (you, team and hires) is the rank's party_size.
#   Team members stop taking Guild jobs while with you.
# - Recruits level with you (never below your level); gear and talents are
#   automatic (AutoBattler.build_hero). They share your pack.
# - Each Breather payout they take their share of the gold (by rank, traits).
# - Expeditions move rapport: a good one raises it, knock-outs lower it.
#   Below leave_below they may walk away (Loyal rarely do).
# - A knocked-out hero gets back up after a won fight, injured afterwards.
#   A full party defeat carries a small, personality-based chance of death.
# State: player.town_state["party"] = [npc ids]. Battle-time characters are
# rebuilt at the start of each expedition and keep their HP between waves.
extends Node

var cfg: Dictionary = {}
## Battle characters for the current expedition (CharacterData), in party order
var allies: Array[CharacterData] = []
## Knock-outs this expedition: npc id (or -1 for the player) -> count
var _kos: Dictionary = {}

func _ready():
	cfg = AdventurerManager.cfg.get("party", {})
	GameEvents.expedition_started.connect(_on_expedition_started)
	GameEvents.expedition_ended.connect(_on_expedition_ended)

func _c() -> Dictionary:
	if cfg.is_empty():
		cfg = AdventurerManager.cfg.get("party", {})
	return cfg

# ------------------------------------------------------------------ roster

func party_ids(player: CharacterData) -> Array:
	if not player.town_state.has("party"):
		player.town_state["party"] = []
	return player.town_state["party"]

func members(player: CharacterData) -> Array:
	var out: Array = []
	for id in party_ids(player):
		var n = AdventurerManager.get_npc(player, int(id))
		if not n.is_empty():
			out.append(n)
	return out

## Party slots besides you (rank party_size - 1): team members and hires.
func slots(player: CharacterData) -> int:
	return max(0, int(RankManager.perk(player, "party_size", 1)) - 1)

## Permanent team slots at your rank (0 below D-Rank).
func team_slots(player: CharacterData) -> int:
	return min(slots(player), int(RankManager.perk(player, "team_slots", 0)))

## Permanent team members (not hires or guests).
func team(player: CharacterData) -> Array:
	return members(player).filter(func(n): return not n.has("hired") and not n.has("guest"))

func is_hired(npc: Dictionary) -> bool:
	return npc.has("hired")

func is_member(player: CharacterData, id: int) -> bool:
	return party_ids(player).has(id)

## "" if `id` can join now, else why not.
func why_not_recruit(player: CharacterData, id: int) -> String:
	var n = AdventurerManager.get_npc(player, id)
	if n.is_empty() or not AdventurerManager.is_active(n):
		return "They're no longer with the Guild."
	if is_member(player, id):
		return "Already in your party."
	var g = MemoryManager.grudge(n)
	if not g.is_empty():
		return "%s won't travel with you. They remember: %s." % [n.name, String(MemoryManager.kind(g.kind).get("you_text", "something you did")).to_lower()]
	if team_slots(player) == 0:
		return "A permanent team comes at D-Rank. Until then, hire them for one expedition."
	if team(player).size() >= team_slots(player):
		return "Your team is full (%d at your rank)." % team_slots(player)
	if party_ids(player).size() >= slots(player):
		return "Your party is full (%d companion%s at your rank)." % [slots(player), "" if slots(player) == 1 else "s"]
	if String(n.status) != "idle":
		return "%s isn't free right now." % n.name
	if int(n.rapport) < int(_c().get("recruit_rapport", 40)):
		return "%s doesn't know you well enough (rapport %d / %d)." % [n.name, int(n.rapport), int(_c().get("recruit_rapport", 40))]
	return ""

## What hiring `npc` for one expedition costs you (copper).
func hire_fee(player: CharacterData, npc: Dictionary) -> int:
	var fee = int(_c().get("hire_copper_per_level", 20)) * max(1, int(npc.get("level", 1)))
	if int(npc.get("rapport", 0)) >= int(_c().get("recruit_rapport", 40)):
		fee = int(round(fee * (1.0 - float(_c().get("hire_friend_discount", 0.5)))))
	return fee

## "" if `id` can be hired for one expedition now, else why not.
func why_not_hire(player: CharacterData, id: int) -> String:
	var n = AdventurerManager.get_npc(player, id)
	if n.is_empty() or not AdventurerManager.is_active(n):
		return "They're no longer with the Guild."
	if is_member(player, id):
		return "Already with you."
	var g = MemoryManager.grudge(n)
	if not g.is_empty():
		return "%s won't take your coin. They remember: %s." % [n.name, String(MemoryManager.kind(g.kind).get("you_text", "something you did")).to_lower()]
	if party_ids(player).size() >= slots(player):
		return "No room: %d companion%s at your rank." % [slots(player), "" if slots(player) == 1 else "s"]
	if String(n.status) != "idle":
		return "%s isn't free right now." % n.name
	if RankManager.rank_index(String(n.rank)) > RankManager.rank_index(RankManager.get_rank(player)) + int(_c().get("hire_rank_above", 1)):
		return "%s is %s-Rank: out of your league for now." % [n.name, n.rank]
	if int(n.rapport) < int(_c().get("hire_rapport", -20)):
		return "%s won't work for you." % n.name
	if player.currency.copper < hire_fee(player, n):
		return "Hiring %s costs %s." % [n.name, Currency.format_copper(hire_fee(player, n))]
	return ""

## Hire `id` for your next expedition.
func hire(player: CharacterData, id: int) -> Dictionary:
	var why = why_not_hire(player, id)
	if why != "":
		return {"ok": false, "reason": why}
	var n = AdventurerManager.get_npc(player, id)
	var fee = hire_fee(player, n)
	player.currency.copper -= fee
	n.status = "party"
	n["hired"] = true
	n["hired_since"] = WorldClock.day(player)
	n["earned"] = int(n.get("earned", 0)) + fee
	party_ids(player).append(id)
	AdventurerManager._history(n, WorldClock.day(player), "Hired on by %s for an expedition." % player.name)
	var yes = PersonalityManager.say(n, "join")
	return {"ok": true, "reason": "%s is hired for your next expedition (%s, and %d%% of the gold).%s" % [n.name, Currency.format_copper(fee), int(round(share(n) * 100)), ("\n" + yes) if yes != "" else ""]}

## A hire goes back to their own work.
func release_hire(player: CharacterData, n: Dictionary, why: String) -> void:
	party_ids(player).erase(int(n.id))
	n.erase("hired")
	n.erase("hired_since")
	if String(n.get("status", "")) == "party":
		n.status = "idle"
	AdventurerManager._history(n, WorldClock.day(player), why)

## Hires kept waiting too long go back to work (the fee is theirs).
func release_stale_hires(player: CharacterData, day: int) -> void:
	for n in members(player).filter(func(m): return is_hired(m)):
		if day - int(n.get("hired_since", day)) > int(_c().get("hire_days", 4)):
			release_hire(player, n, "Got tired of waiting for %s's expedition and went back to work." % player.name)
			WorldClock.add_news(player, "%s gave up waiting and went back to work (the fee is theirs)." % n.name, "adventurer")

func recruit(player: CharacterData, id: int) -> Dictionary:
	var why = why_not_recruit(player, id)
	if why != "":
		var who = AdventurerManager.get_npc(player, id)
		var no = PersonalityManager.say(who, "refuse") if not who.is_empty() and int(who.get("rapport", 0)) < 20 else ""
		return {"ok": false, "reason": why + (("\n" + no) if no != "" else "")}
	var n = AdventurerManager.get_npc(player, id)
	n.status = "party"
	party_ids(player).append(id)
	_sync_level(player, n)
	var day = WorldClock.day(player)
	AdventurerManager._history(n, day, "Joined %s's party." % player.name)
	WorldClock.add_news(player, "%s joined %s's party." % [n.name, player.name], "adventurer")
	var yes = PersonalityManager.say(n, "join")
	return {"ok": true, "reason": "%s joins your party! They'll take %d%% of the gold.%s" % [n.name, int(round(share(n) * 100)), ("\n" + yes) if yes != "" else ""]}

func dismiss(player: CharacterData, id: int, reason := "") -> Dictionary:
	if not is_member(player, id):
		return {"ok": false, "reason": "They aren't in your party."}
	party_ids(player).erase(id)
	var n = AdventurerManager.get_npc(player, id)
	n.erase("guest")
	n.erase("guest_since")
	if not n.is_empty() and String(n.status) == "party":
		n.status = "idle"
	var day = WorldClock.day(player)
	AdventurerManager._history(n, day, reason if reason != "" else "Parted ways with %s." % player.name)
	return {"ok": true, "reason": "%s leaves your party." % n.get("name", "?")}

## Gold share this recruit takes (by rank, x trait 'share').
func share(npc: Dictionary) -> float:
	var table = "hire_share_by_rank" if is_hired(npc) else "share_by_rank"
	var base = float(_c().get(table, {}).get(String(npc.rank), 0.15))
	return clamp(base * AdventurerManager.trait_mult(npc, "share"), 0.0, 0.5)

## The share a hire would take (before hiring).
func hire_share(npc: Dictionary) -> float:
	var base = float(_c().get("hire_share_by_rank", {}).get(String(npc.rank), 0.2))
	return clamp(base * AdventurerManager.trait_mult(npc, "share"), 0.0, 0.5)

func total_share(player: CharacterData) -> float:
	var s := 0.0
	for n in members(player):
		s += share(n)
	return min(s, 0.6)

## Recruits level with you.
func _sync_level(player: CharacterData, npc: Dictionary) -> void:
	if int(npc.level) < player.level:
		npc.level = player.level
		npc.xp = 0
	npc.gear_floor = max(int(npc.gear_floor), int(int(npc.level) * float(AdventurerManager._s("jobs").get("gear_floor_per_level", 0.6))))

# ------------------------------------------------------------------ expedition

func _on_expedition_started(_location_id: String, _floor: int) -> void:
	var player = DungeonStateManager.active_player
	_kos.clear()
	allies.clear()
	if player == null:
		return
	for n in members(player):
		if int(n.get("injured_until", 0)) > WorldClock.day(player):
			continue    # still hurt: stays in town this time
		if not is_hired(n):   # hired hands fight at their own level
			_sync_level(player, n)
		var hero = AutoBattler.build_hero(n)
		hero.inventory = player.inventory          # one shared pack
		hero.set_meta("npc_id", int(n.id))
		hero.set_meta("auto", bool(n.get("auto", false)))
		allies.append(hero)

## Battle-time allies (the battle scene adds them beside the player).
func battle_allies() -> Array[CharacterData]:
	return allies

func npc_of(c: CharacterData, player: CharacterData) -> Dictionary:
	return AdventurerManager.get_npc(player, int(c.get_meta("npc_id"))) if c.has_meta("npc_id") else {}

## Breather: everyone recovers.
func restore_allies() -> void:
	for a in allies:
		a.current_hp = a.max_hp
		a.current_mp = a.max_mp
		a.current_sp = a.max_sp
		if a.status_manager:
			a.status_manager.clear_all_effects()

## Remember a party member's Auto toggle between battles.
func set_auto(c: CharacterData, on: bool) -> void:
	var player = DungeonStateManager.active_player
	if player == null:
		return
	var n = npc_of(c, player)
	if not n.is_empty():
		n["auto"] = on

func on_hero_knocked_out(c: CharacterData) -> void:
	var key = int(c.get_meta("npc_id")) if c.has_meta("npc_id") else -1
	_kos[key] = int(_kos.get(key, 0)) + 1

## Take the party's share out of a Breather payout. Returns the copper taken.
func take_share(player: CharacterData, rewards: Dictionary) -> int:
	if allies.is_empty() or not rewards.has("currency"):
		return 0
	var total := 0
	for a in allies:
		var n = npc_of(a, player)
		if n.is_empty():
			continue
		var cut = int(floor(int(rewards.currency) * share(n)))
		n["earned"] = int(n.get("earned", 0)) + cut
		total += cut
	rewards.currency = max(0, int(rewards.currency) - total)
	return total

func _on_expedition_ended(location_id: String, cleared: bool) -> void:
	var player = DungeonStateManager.active_player
	if player == null:
		return
	var c = _c()
	var day = WorldClock.day(player)
	var where = LocationManager.get_display_name(location_id)
	# you, knocked out but the party won: an injury
	if cleared and int(_kos.get(-1, 0)) > 0:
		DefeatManager.add_random_injury(player, false)
	for a in allies:
		var n = npc_of(a, player)
		if n.is_empty() or not is_member(player, int(n.id)):
			continue
		var kos = int(_kos.get(int(n.id), 0))
		var delta = int(c.get("rapport_good_expedition", 3)) if cleared else int(c.get("rapport_bad_expedition", -2))
		delta += kos * int(c.get("rapport_per_ko", -3))
		n.rapport = clamp(int(n.rapport) + delta, -100, 100)
		n.record.jobs = int(n.record.jobs) + 1
		n.record.wins = int(n.record.wins) + (1 if cleared else 0)
		n.record.fails = int(n.record.fails) + (0 if cleared else 1)
		# full party defeat: a small chance of death, by personality
		if not cleared and RandomManager.randf() < float(c.get("wipe_death_chance", 0.04)) * AdventurerManager.trait_mult(n, "death"):
			party_ids(player).erase(int(n.id))
			n.status = "dead"
			n.died_day = day
			AdventurerManager._history(n, day, "Fell beside %s in %s." % [player.name, where])
			WorldClock.add_news(player, "%s fell beside you in %s." % [n.name, where], "death")
			n["died_at"] = {"location": location_id, "floor": DungeonStateManager.current_floor}
			DramaManager.on_death(player, n, day)
			continue
		if kos > 0 or not cleared:
			var days = AdventurerManager._range(c.get("ko_injury_days", [2, 4]))
			n.injured_until = day + days
			AdventurerManager._history(n, day, "Hurt on an expedition with %s (%d days to recover)." % [player.name, days])
		else:
			AdventurerManager._history(n, day, "Came back from %s with %s." % [where, player.name])
		# unhappy companions may leave
		if int(n.rapport) < int(c.get("leave_below", 20)) and RandomManager.randf() < float(c.get("leave_chance", 0.35)) * AdventurerManager.trait_mult(n, "leave"):
			dismiss(player, int(n.id), "Left %s's party, unhappy." % player.name)
			WorldClock.add_news(player, "%s has left your party." % n.name, "guild")
	for n in members(player).filter(func(m): return is_hired(m)):   # hired hands go home
		release_hire(player, n, "Was paid off after an expedition with %s." % player.name)
	DramaManager.on_expedition_end(player, cleared)   # guests go home
	allies.clear()
	_kos.clear()
