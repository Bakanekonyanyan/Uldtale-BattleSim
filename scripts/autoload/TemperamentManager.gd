# res://scripts/autoload/TemperamentManager.gd
# Temperament: personality traits played out (data/temperament.json;
# docs/design/LIVING_WORLD.md I).
#   Scenes  each day a few adventurers in town act on a trait: the Kind tend the
#           injured, the Greedy pick pockets, the Boastful brag, the Scholarly
#           teach, the Devout hold vigils, the Cheerful throw parties, the Cruel
#           bully (and the decent stand up to them), the Honorable mediate, the
#           Loyal defend a friend's name, the Ambitious spar... Some involve you.
#           Each leaves memories and affinity behind, and sometimes news.
#   Growth  experiences are counted (npc.experience[tag]); enough of the right
#           ones can change a trait (a coward who rescues a friend; a kind soul
#           wronged too often).
#   Voice   lines by trait, mixed into archetype lines (PersonalityManager.line).
#   Battle  companions fight by temperament (AutoBattler.hero_policy).
extends Node

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("temperament")
	return d if d is Dictionary else {}

func _sc(id: String) -> Dictionary:
	return cfg().get("scenes", {}).get(id, {})

func _state(player: CharacterData) -> Dictionary:
	var st = AdventurerManager.state(player)
	if not st.has("temperament"):
		st["temperament"] = {"deaths": [], "celebrations": [], "vigils": []}
	return st.temperament

func _traits(n: Dictionary) -> Array:
	return n.get("traits", [])

func _first(n: Dictionary) -> String:
	return String(n.get("name", "someone")).get_slice(" ", 0)

func _pick(a: Array):
	return a[RandomManager.randi() % a.size()] if not a.is_empty() else null

## Tavern talk (shown at the Tavern); headline scenes also reach the town news.
func _news(player: CharacterData, s: Dictionary, text: String) -> void:
	if text == "":
		return
	var st = _state(player)
	if not st.has("talk"):
		st["talk"] = []
	st.talk.append({"day": WorldClock.day(player), "text": text})
	while st.talk.size() > int(cfg().get("talk_keep", 30)):
		st.talk.pop_front()
	if bool(s.get("headline", false)):
		WorldClock.add_news(player, text, "tavern")

## Recent Tavern talk, newest first.
func talk(player: CharacterData, count := 12) -> Array:
	var t: Array = _state(player).get("talk", []).duplicate()
	t.reverse()
	return t.slice(0, count)

# ================================================================== daily scenes

## Called by AdventurerManager.simulate_day. Returns the scene ids that played.
func daily(player: CharacterData, day: int) -> Array:
	var played: Array = []
	if player == null:
		return played
	var town = AdventurerManager.active(player).filter(func(n): return String(n.status) in ["idle", "injured"])
	if town.size() < 2:
		return played
	town.shuffle()
	var want = int(cfg().get("scenes_per_day", 3))
	for actor in town:
		if played.size() >= want:
			break
		var options: Array = []
		for id in cfg().get("scenes", {}):
			if String(_sc(id).get("trait", "")) in _traits(actor):
				options.append(id)
		# weighted random order: each option draws a key once (weight x roll)
		var keyed: Array = options.map(func(o): return [float(_sc(o).get("weight", 1)) * RandomManager.randf(), o])
		keyed.sort_custom(func(a, b): return a[0] > b[0])
		options = keyed.map(func(k): return k[1])
		for id in options:
			if play(player, String(id), actor, day):
				played.append(id)
				break
	if day % 7 == 0:
		_weekly(player, day)
	return played

## Run one scene for `actor`. Returns true if it happened.
func play(player: CharacterData, id: String, actor: Dictionary, day: int) -> bool:
	if not has_method("_scene_" + id):
		return false
	return bool(call("_scene_" + id, player, actor, _sc(id), day))

func _town_others(player: CharacterData, actor: Dictionary) -> Array:
	return AdventurerManager.active(player).filter(func(n): return n != actor and String(n.status) in ["idle", "injured"])

func _scene_tend_wounded(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var hurt = _town_others(player, a).filter(func(n): return String(n.status) == "injured" and int(n.get("injured_until", 0)) > day + 1)
	if hurt.is_empty():
		return false
	hurt.sort_custom(func(x, y): return RelationsManager.affinity(player, a, x) > RelationsManager.affinity(player, a, y))
	var t: Dictionary = hurt[0]
	t.injured_until = max(day + 1, int(t.injured_until) - AdventurerManager._range(s.get("days_off", [1, 2])))
	RelationsManager.change(player, t, a, int(s.get("affinity", 6)), day)
	MemoryManager.add(t, "helped_me", MemoryManager.key_npc(a), day)
	AdventurerManager._history(t, day, "Nursed back on their feet by %s." % a.name)
	_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "target": _first(t)}))
	return true

func _scene_tend_you(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	if int(a.get("rapport", 0)) < int(s.get("min_rapport", 25)):
		return false
	var inj = DefeatManager.get_injuries(player).filter(func(i): return int(i.get("remaining", 0)) > 1)
	if inj.is_empty():
		return false
	inj[0].remaining = int(inj[0].remaining) - 1
	MemoryManager.add(player, "helped_me", MemoryManager.key_npc(a), day)
	_news(player, s, String(s.get("news", "")).format({"actor": a.name}))
	return true

func _scene_pickpocket(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var marks = _town_others(player, a).filter(func(n): return RelationsManager.affinity(player, a, n) < 20)
	if marks.is_empty():
		return false
	var t: Dictionary = _pick(marks)
	if RandomManager.randf() < float(s.get("caught_chance", 0.4)):
		MemoryManager.add(t, "robbed_me", MemoryManager.key_npc(a), day)
		RelationsManager.change(player, t, a, int(s.get("affinity_caught", -25)), day)
		AdventurerManager._history(t, day, "Caught %s picking their pocket." % a.name)
		_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "target": _first(t)}))
	return true

func _scene_pickpocket_you(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	if int(a.get("rapport", 0)) > int(s.get("max_rapport", -10)):
		return false
	var amount = min(int(player.currency.copper * float(s.get("take_pct", 0.02))), int(s.get("take_max_per_level", 40)) * max(1, player.level))
	if amount <= 0:
		return false
	player.currency.subtract(amount)
	if RandomManager.randf() < float(s.get("notice_chance", 0.5)):
		MemoryManager.add(player, "robbed_me", MemoryManager.key_npc(a), day)
		_news(player, s, String(s.get("news", "")).format({"actor": a.name, "amount": Currency.format_copper(amount)}))
	return true

func _scene_brag(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var ears = _town_others(player, a)
	if ears.is_empty():
		return false
	ears.shuffle()
	for e in ears.slice(0, int(s.get("listeners", 3))):
		if _traits(e).any(func(t): return t in s.get("annoyed", [])):
			RelationsManager.change(player, e, a, int(s.get("annoyed_affinity", -3)), day)
		elif _traits(e).any(func(t): return t in s.get("amused", [])):
			RelationsManager.change(player, e, a, int(s.get("amused_affinity", 2)), day)
	_news(player, s, String(s.get("news", "")).format({"actor": _first(a)}))
	return true

func _scene_teach(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var pupils = _town_others(player, a).filter(func(n): return int(n.level) < int(a.level) and RelationsManager.affinity(player, a, n) >= 0)
	if pupils.is_empty():
		return false
	pupils.sort_custom(func(x, y): return RelationsManager.affinity(player, a, x) > RelationsManager.affinity(player, a, y))
	var t: Dictionary = pupils[0]
	AdventurerManager._gain_xp(t, int(s.get("xp_per_level", 30)) * int(a.level))
	RelationsManager.change(player, t, a, int(s.get("affinity", 5)), day)
	MemoryManager.add(t, "taught_me", MemoryManager.key_npc(a), day)
	tag(player, t, "taught", day)
	_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "target": _first(t)}))
	return true

func _scene_vigil(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var st = _state(player)
	var recent = st.deaths.filter(func(d): return day - int(d.day) <= int(s.get("recent_days", 14)) and not int(d.id) in st.vigils)
	if recent.is_empty():
		return false
	var dead = AdventurerManager.get_npc(player, int(recent[0].id))
	if dead.is_empty():
		return false
	st.vigils.append(int(dead.id))
	var came: Array = []
	for r in RelationsManager.relations_of(player, dead):
		var m: Dictionary = r.npc
		if m == a or not AdventurerManager.in_town(m) or int(r.aff) <= 0:
			continue
		came.append(m)
		RelationsManager.change(player, m, a, int(s.get("affinity", 4)), day)
		if m.has("grief"):
			m.grief.until = int(m.grief.until) - int(s.get("grief_days_off", 3))
	_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "dead": dead.name, "count": "%d %s" % [came.size() + 1, "mourner" if came.is_empty() else "mourners"]}))
	return true

func _scene_celebrate(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var st = _state(player)
	var recent = st.celebrations.filter(func(c): return day - int(c.day) <= int(s.get("recent_days", 3)) and not c.get("done", false))
	if recent.is_empty():
		return false
	var c: Dictionary = recent[0]
	c["done"] = true
	var hon = AdventurerManager.get_npc(player, int(c.id))
	if hon.is_empty():
		return false
	var guests = _town_others(player, a).filter(func(n): return n != hon)
	guests.shuffle()
	guests = guests.slice(0, int(s.get("attendees", 4)))
	guests.append(a)
	for i in range(guests.size()):
		for j in range(i + 1, guests.size()):
			RelationsManager.change(player, guests[i], guests[j], int(s.get("affinity", 2)), day)
	if hon != a:
		RelationsManager.change(player, hon, a, int(s.get("honoree_affinity", 4)), day)
	_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "honoree": hon.name}))
	return true

func _scene_bully(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var weak = _town_others(player, a).filter(func(n): return int(n.level) < int(a.level) and RelationsManager.affinity(player, a, n) < 40)
	if weak.is_empty():
		return false
	weak.sort_custom(func(x, y): return int(x.level) < int(y.level))
	var t: Dictionary = weak[0]
	RelationsManager.change(player, t, a, int(s.get("affinity", -10)), day)
	MemoryManager.add(t, "bullied_me", MemoryManager.key_npc(a), day)
	tag(player, t, "bullied", day)
	var text = String(s.get("news", "")).format({"actor": _first(a), "target": _first(t)})
	# someone decent may stand up to them
	var witnesses = _town_others(player, a).filter(func(n): return n != t and _traits(n).any(func(x): return x in s.get("stand_up_traits", [])))
	if not witnesses.is_empty() and RandomManager.randf() < float(s.get("stand_up_chance", 0.5)):
		var w: Dictionary = _pick(witnesses)
		RelationsManager.change(player, w, a, int(s.get("stand_up_affinity", -10)), day)
		RelationsManager.change(player, t, w, int(s.get("stood_for_affinity", 8)), day)
		MemoryManager.add(t, "stood_up_for_me", MemoryManager.key_npc(w), day)
		AdventurerManager._history(w, day, "Stood up to %s for %s." % [a.name, t.name])
		text = String(s.get("stand_up_news", text)).format({"actor": _first(a), "target": _first(t), "witness": _first(w)})
		_news(player, {"headline": true}, text)
		return true
	_news(player, s, text)
	return true

func _scene_mediate(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var rivals_at = int(s.get("below", RelationsManager.cfg().get("thresholds", {}).get("rivals", -40)))
	var others = _town_others(player, a)
	for i in range(others.size()):
		for j in range(i + 1, others.size()):
			var x: Dictionary = others[i]
			var y: Dictionary = others[j]
			if RelationsManager.affinity(player, x, y) <= rivals_at and RelationsManager.affinity(player, a, x) >= 0 and RelationsManager.affinity(player, a, y) >= 0:
				RelationsManager.change(player, x, y, int(s.get("affinity", 15)), day)
				AdventurerManager._history(a, day, "Made peace between %s and %s." % [x.name, y.name])
				_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "a": _first(x), "b": _first(y)}))
				return true
	return false

func _scene_defend_name(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	for f in RelationsManager.friends(player, a):
		var key = MemoryManager.key_npc(f)
		for l in _town_others(player, a):
			if l == f:
				continue
			var bad = MemoryManager.list(l).filter(func(m): return m.about == key and m.has("heard_from") and float(m.w) < 0)
			if bad.is_empty():
				continue
			for m in bad:
				MemoryManager.list(l).erase(m)
			RelationsManager.change(player, l, f, int(s.get("affinity", 5)), day)
			_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "listener": _first(l), "friend": _first(f)}))
			return true
	return false

func _scene_spar(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var st = LedgerManager.standings(player)
	var me := -1
	for i in range(st.size()):
		if not st[i].is_player and st[i].npc == a:
			me = i
	if me <= 0:
		return false
	var cands: Array = []
	for i in range(max(0, me - int(s.get("ledger_reach", 4))), me):
		if not st[i].is_player and String(st[i].npc.status) == "idle":
			cands.append(st[i].npc)
	if cands.is_empty():
		return false
	var t: Dictionary = _pick(cands)
	var pa = int(a.level) + int(a.get("gear_floor", 0)) + RandomManager.randf() * 8.0
	var pt = int(t.level) + int(t.get("gear_floor", 0)) + RandomManager.randf() * 8.0
	var win = a if pa >= pt else t
	var lose = t if win == a else a
	win.points = int(win.points) + int(s.get("points", 3))
	tag(player, lose, "lost_spar", day)
	var d = int(s.get("respect_affinity", 3)) if "honorable" in _traits(lose) or not _traits(lose).any(func(x): return x in ["boastful", "ambitious", "cruel"]) else int(s.get("sore_affinity", -5))
	RelationsManager.change(player, lose, win, d, day)
	_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "target": _first(t), "winner": _first(win)}))
	return true

func _scene_carouse(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var mates = _town_others(player, a).filter(func(n): return String(n.status) == "idle" and _traits(n).any(func(x): return x in s.get("partners", [])))
	if mates.is_empty():
		return false
	var t: Dictionary = _pick(mates)
	RelationsManager.change(player, a, t, int(s.get("affinity", 5)), day)
	var tail := ""
	if RandomManager.randf() < float(s.get("hangover_chance", 0.25)):
		var loser = _pick([a, t])
		loser.status = "injured"
		loser.injured_until = day + 1
		tail = " %s lost - and won't be fit for work tomorrow." % _first(loser)
	_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "target": _first(t), "tail": tail}))
	return true

func _scene_freeload(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var marks = _town_others(player, a)
	if marks.is_empty():
		return false
	var t: Dictionary = _pick(marks)
	if _traits(t).any(func(x): return x in s.get("stingy", [])):
		RelationsManager.change(player, t, a, int(s.get("stingy_affinity", -4)), day)
	elif _traits(t).any(func(x): return x in s.get("generous", [])):
		RelationsManager.change(player, t, a, int(s.get("generous_affinity", 1)), day)
	else:
		return false
	_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "target": _first(t)}))
	return true

func _scene_seek_protection(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var big = _town_others(player, a).filter(func(n): return int(n.level) > int(a.level) and RelationsManager.affinity(player, a, n) >= 0)
	if big.is_empty():
		return false
	big.sort_custom(func(x, y): return int(x.level) > int(y.level))
	RelationsManager.change(player, a, big[0], int(s.get("affinity", 4)), day)
	_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "target": _first(big[0])}))
	return true

func _scene_fuss(player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	var t = _pick(_town_others(player, a).filter(func(n): return _traits(n).any(func(x): return x in s.get("targets", ["reckless"]))))
	if t == null:
		return false
	var friends = RelationsManager.affinity(player, a, t) >= int(RelationsManager.cfg().get("thresholds", {}).get("friends", 40))
	RelationsManager.change(player, a, t, int(s.get("friend_affinity" if friends else "stranger_affinity", 0)), day)
	_news(player, s, String(s.get("news", "")).format({"actor": _first(a), "target": _first(t)}))
	return true

func _scene_lone_training(_player: CharacterData, a: Dictionary, s: Dictionary, day: int) -> bool:
	if String(a.status) != "idle":
		return false
	AdventurerManager._gain_xp(a, int(s.get("xp_per_level", 15)) * int(a.level))
	AdventurerManager._history(a, day, "Trained alone until dark.")
	return true

# ================================================================== notes from other systems

func note_death(player: CharacterData, dead: Dictionary, day: int) -> void:
	var st = _state(player)
	st.deaths.append({"id": int(dead.id), "day": day})
	while st.deaths.size() > 12:
		st.deaths.pop_front()

## Something to celebrate (a promotion, a boss kill).
func note_celebration(player: CharacterData, npc: Dictionary, day: int, why := "") -> void:
	var st = _state(player)
	st.celebrations.append({"id": int(npc.id), "day": day, "why": why})
	while st.celebrations.size() > 12:
		st.celebrations.pop_front()

# ================================================================== growth

## Count an experience; may change a trait (data growth rules).
func tag(player: CharacterData, npc: Dictionary, t: String, day: int = -1) -> String:
	if npc.is_empty() or not AdventurerManager.is_active(npc):
		return ""
	if not npc.has("experience"):
		npc["experience"] = {}
	npc.experience[t] = int(npc.experience.get(t, 0)) + 1
	for r in cfg().get("growth", []):
		if String(r.tag) != t or int(npc.experience[t]) < int(r.get("count", 1)):
			continue
		if r.has("has") and not String(r.has) in _traits(npc):
			continue
		if r.has("lacks") and String(r.lacks) in _traits(npc):
			continue
		if RandomManager.randf() < float(r.get("chance", 1.0)):
			grow(player, npc, r, day)
			return String(r.id)
	return ""

## Apply a growth rule: remove / add traits (respecting exclusives).
func grow(player: CharacterData, npc: Dictionary, r: Dictionary, day: int = -1) -> void:
	if day < 0 and player:
		day = WorldClock.day(player)
	var known_before = npc.get("known_traits", []).duplicate()
	var was: Array = _traits(npc).duplicate()
	if r.has("remove"):
		npc.traits.erase(String(r.remove))
		npc.known_traits.erase(String(r.remove))
	if r.has("add") and not String(r.add) in npc.traits:
		var nt = String(r.add)
		for x in AdventurerManager.trait_data(nt).get("exclusive", []):
			npc.traits.erase(x)
			npc.known_traits.erase(x)
		for x in npc.traits.duplicate():
			if nt in AdventurerManager.trait_data(x).get("exclusive", []):
				npc.traits.erase(x)
				npc.known_traits.erase(x)
		npc.traits.append(nt)
		if r.has("remove") and String(r.remove) in known_before:
			npc.known_traits.append(nt)   # you knew the old them, you notice the new
	npc["growth"] = npc.get("growth", []) + [String(r.id)]
	var lost = was.filter(func(x): return not x in npc.traits).map(func(x): return String(AdventurerManager.trait_data(x).get("name", x)))
	var gained = npc.traits.filter(func(x): return not x in was).map(func(x): return String(AdventurerManager.trait_data(x).get("name", x)))
	var bits: Array = []
	if not lost.is_empty(): bits.append("no longer %s" % "/".join(lost))
	if not gained.is_empty(): bits.append("now %s" % "/".join(gained))
	AdventurerManager._history(npc, day, "Changed: %s." % ", ".join(bits))
	if player:
		WorldClock.add_news(player, String(r.get("news", "{name} has changed.")).format({"name": npc.name}), "adventurer")

func _weekly(player: CharacterData, day: int) -> void:
	for n in AdventurerManager.active(player):
		if n.has("company"):
			tag(player, n, "company_week", day)

# ================================================================== voice

## A trait line for `context` ("" if none): one of their traits, at random.
func trait_line(npc: Dictionary, context: String) -> String:
	var opts: Array = []
	for t in _traits(npc):
		opts.append_array(cfg().get("voice", {}).get(t, {}).get(context, []))
	return String(_pick(opts)) if not opts.is_empty() else ""
