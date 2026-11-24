# res://tests/world_sim.gd
# Long-run world simulation: the Guild left to live for years while you stay in
# town. Runs the real daily loop (WorldClock.advance -> every manager's daily
# tick) and reports, per year:
#   roster  - active adventurers, levels, ranks, deaths, retirements, newcomers
#   social  - relations by status, companies, couples, grieving, avengers,
#             memories held, jealousy
#   events  - drama counted from the news (companies, romances, feuds, brawls,
#             killings, vengeance, grief, rescues, crownings)
#   cost    - milliseconds per simulated day, size of the saved world state
#
#   godot --headless res://tests/world_sim.tscn -- [--years=5] [--seed=1] [--social=0.0]
#
# --social: the chance each week that you befriend a random adventurer
# (rapport set to 50) - a stand-in for a player who visits the Tavern, so
# invitations, ripples and jealousy have someone to point at.
extends Node

const DAYS_PER_YEAR := 112
const EVENTS := {
	"company": "formed a company", "joined_co": "joined The", "disband": "has disbanded", "walkout": "walked out on",
	"sworn": "swore to fight", "romance": "are together now", "split": "have split up",
	"feud": "are feuding", "brawl": "came to blows", "killing": "Blood behind", "punished": "punished",
	"vow_boss": "sworn to avenge", "vow_killer": "sworn vengeance on", "avenged": "avenged",
	"withdrew": "still grieving", "hardened": "hasn't been the same", "rescue": "carried a dying",
	"died": "fell in", "beaten": "found beaten", "snapped": "has snapped", "invite": "invite you",
	"retired": "retired from adventuring", "promoted": "was promoted", "joined_guild": "new adventurer joined"}

var years := 5
var social := 0.0
var crowns: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = String(a).trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"years": years = int(kv[1])
			"seed": RandomManager._init_rng(int(kv[1]))
			"social": social = float(kv[1])
	GameEvents.champion_crowned.connect(func(n, y, _you): crowns.append("%d:%s" % [y, n]))
	var p = CharacterFactory.create_character("Hero", "Hume", "Paladin", true)
	CharacterManager.current_character_resource.set_meta("current_character", p)
	AdventurerManager.state(p)
	print("WORLD|year|active|avg lvl|max lvl|ranks|relations|friends|sworn|rivals|feud|companies|couples|grieving|avengers|mem/npc|ms/day|state KB")
	var tally := {}
	var year_tally := {}
	var t_total := 0
	for d in range(1, years * DAYS_PER_YEAR + 1):
		var t0 = Time.get_ticks_usec()
		WorldClock.advance(p, 1)
		t_total += Time.get_ticks_usec() - t0
		var news: Array = WorldClock.state(p).news
		for e in news:
			for k in EVENTS:
				if String(e.text).contains(EVENTS[k]):
					tally[k] = int(tally.get(k, 0)) + 1
					year_tally[k] = int(year_tally.get(k, 0)) + 1
		news.clear()
		p.town_state.erase("invitation")   # you never answer
		if social > 0.0 and d % 7 == 0 and RandomManager.randf() < social:
			var act = AdventurerManager.active(p)
			if not act.is_empty():
				act[RandomManager.randi() % act.size()].rapport = 50
		if d % DAYS_PER_YEAR == 0:
			_year(p, d / DAYS_PER_YEAR, t_total / float(DAYS_PER_YEAR) / 1000.0)
			print("WORLD YEAR EVENTS|%d|%s" % [d / DAYS_PER_YEAR, JSON.stringify(year_tally)])
			year_tally.clear()
			t_total = 0
	print("WORLD EVENTS|", JSON.stringify(tally))
	print("WORLD CROWNS|", ", ".join(crowns))
	print("WORLD DONE")
	get_tree().quit()

func _year(p: CharacterData, y: int, ms: float) -> void:
	var act = AdventurerManager.active(p)
	var lv = act.map(func(n): return int(n.level))
	var ranks := {}
	for n in act:
		ranks[String(n.rank)] = int(ranks.get(String(n.rank), 0)) + 1
	var rk = RankManager.rank_ids().filter(func(r): return ranks.has(r)).map(func(r): return "%s%d" % [r, ranks[r]])
	var st = AdventurerManager.state(p)
	var c := {"friends": 0, "sworn": 0, "rivals": 0, "feud": 0}
	for k in st.get("relations", {}):
		var s = RelationsManager.status_of(int(st.relations[k].aff))
		if s != "":
			c[s] += 1
	var mem := 0
	for n in act:
		mem += n.get("memories", []).size()
	var couples = act.filter(func(n): return n.has("partner")).size() / 2
	var grieving = act.filter(func(n): return n.has("grief")).size()
	var avengers = act.filter(func(n): return n.has("vengeance")).size()
	var kb = JSON.stringify(p.town_state).length() / 1024.0
	print("WORLD|%d|%d|%.1f|%d|%s|%d|%d|%d|%d|%d|%d|%d|%d|%d|%.1f|%.2f|%.0f" % [y, act.size(),
		lv.reduce(func(a, b): return a + b, 0) / float(max(1, lv.size())), lv.max() if not lv.is_empty() else 0, " ".join(rk),
		st.get("relations", {}).size(), c.friends, c.sworn, c.rivals, c.feud, DramaManager.companies(p).size(), couples, grieving, avengers,
		mem / float(max(1, act.size())), ms, kb])
