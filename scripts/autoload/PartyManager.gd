# res://scripts/autoload/PartyManager.gd
# Your party (data/adventurers.json "party", GAME_ROADMAP.md B2).
#
# - Recruit an adventurer at Friend rapport into a free slot (your rank's
#   party_size - 1). They stop taking Guild jobs while with you.
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

## Party slots besides you (rank party_size - 1).
func slots(player: CharacterData) -> int:
	return max(0, int(RankManager.perk(player, "party_size", 1)) - 1)

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
	if slots(player) == 0:
		return "Your rank allows no companions yet (D-Rank opens a slot)."
	if party_ids(player).size() >= slots(player):
		return "Your party is full (%d companion%s at your rank)." % [slots(player), "" if slots(player) == 1 else "s"]
	if String(n.status) != "idle":
		return "%s isn't free right now." % n.name
	if int(n.rapport) < int(_c().get("recruit_rapport", 40)):
		return "%s doesn't know you well enough (rapport %d / %d)." % [n.name, int(n.rapport), int(_c().get("recruit_rapport", 40))]
	return ""

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
	if not n.is_empty() and String(n.status) == "party":
		n.status = "idle"
	var day = WorldClock.day(player)
	AdventurerManager._history(n, day, reason if reason != "" else "Parted ways with %s." % player.name)
	return {"ok": true, "reason": "%s leaves your party." % n.get("name", "?")}

## Gold share this recruit takes (by rank, x trait 'share').
func share(npc: Dictionary) -> float:
	var base = float(_c().get("share_by_rank", {}).get(String(npc.rank), 0.15))
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
	allies.clear()
	_kos.clear()
