# res://scripts/autoload/RelationsManager.gd
# NPC-to-NPC relationships (data/social.json "relations"; LIVING_WORLD.md A).
# A relation exists once two adventurers have interacted:
#   town_state.adventurers.relations["<lo>:<hi>"] = {a, b, aff, since}
# Affinity moves with shared jobs (and blame), rescues, trait chemistry while
# both are in town, Ledger competition and promotions. Thresholds: friends,
# sworn companions, rivals, feud. Friends pair up for jobs; your rapport
# changes ripple to someone's friends (and the other way to their rivals).
extends Node

signal relation_changed(a_id: int, b_id: int, status: String)

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("social")
	return d.get("relations", {}) if d is Dictionary else {}

func _ev(k: String) -> int:
	return int(cfg().get("events", {}).get(k, 0))

func _store(player: CharacterData) -> Dictionary:
	var st = AdventurerManager.state(player)
	if not st.has("relations"):
		st["relations"] = {}
	return st.relations

func _key(x: Dictionary, y: Dictionary) -> String:
	var a = int(x.id)
	var b = int(y.id)
	return "%d:%d" % [min(a, b), max(a, b)]

# ------------------------------------------------------------------ queries

func affinity(player: CharacterData, x: Dictionary, y: Dictionary) -> int:
	if player == null or x.is_empty() or y.is_empty() or x == y:
		return 0
	return int(_store(player).get(_key(x, y), {}).get("aff", 0))

func status_of(aff: int) -> String:
	var t: Dictionary = cfg().get("thresholds", {})
	if aff >= int(t.get("sworn", 70)): return "sworn"
	if aff >= int(t.get("friends", 40)): return "friends"
	if aff <= int(t.get("feud", -70)): return "feud"
	if aff <= int(t.get("rivals", -40)): return "rivals"
	return ""

func status(player: CharacterData, x: Dictionary, y: Dictionary) -> String:
	return status_of(affinity(player, x, y))

## [{npc, aff, status}] for `npc`, strongest first (active adventurers only).
func relations_of(player: CharacterData, npc: Dictionary) -> Array:
	var out: Array = []
	var my = int(npc.id)
	for k in _store(player):
		var r: Dictionary = _store(player)[k]
		if int(r.a) != my and int(r.b) != my:
			continue
		var other = AdventurerManager.get_npc(player, int(r.b) if int(r.a) == my else int(r.a))
		if other.is_empty():
			continue
		out.append({"npc": other, "aff": int(r.aff), "status": status_of(int(r.aff))})
	out.sort_custom(func(p, q): return abs(int(p.aff)) > abs(int(q.aff)))
	return out

func friends(player: CharacterData, npc: Dictionary) -> Array:
	return relations_of(player, npc).filter(func(r): return r.status in ["friends", "sworn"] and AdventurerManager.is_active(r.npc)).map(func(r): return r.npc)

func rivals(player: CharacterData, npc: Dictionary) -> Array:
	return relations_of(player, npc).filter(func(r): return r.status in ["rivals", "feud"] and AdventurerManager.is_active(r.npc)).map(func(r): return r.npc)

# ------------------------------------------------------------------ changes

## Change affinity between two adventurers. Returns the new status if it
## crossed a threshold, else "".
func change(player: CharacterData, x: Dictionary, y: Dictionary, delta: int, day: int = -1) -> String:
	if player == null or x.is_empty() or y.is_empty() or x == y or delta == 0:
		return ""
	var store = _store(player)
	var k = _key(x, y)
	if not store.has(k):
		store[k] = {"a": min(int(x.id), int(y.id)), "b": max(int(x.id), int(y.id)), "aff": 0, "since": day if day >= 0 else WorldClock.day(player)}
	var r: Dictionary = store[k]
	var before = status_of(int(r.aff))
	r.aff = clamp(int(r.aff) + delta, -100, 100)
	var after = status_of(int(r.aff))
	_cap(player, x, k)
	_cap(player, y, k)
	if after != before:
		_announce(player, x, y, after, before, day if day >= 0 else WorldClock.day(player))
		relation_changed.emit(int(x.id), int(y.id), after)
		return after
	return ""

## Keep each adventurer's relations to max_per_npc (forget the weakest, never
## the one that just changed).
func _cap(player: CharacterData, npc: Dictionary, keep := "") -> void:
	var cap = int(cfg().get("max_per_npc", 8))
	var store = _store(player)
	var my = int(npc.id)
	var mine: Array = []
	for k in store:
		if k != keep and (int(store[k].a) == my or int(store[k].b) == my):
			mine.append(k)
	if mine.size() <= cap - (1 if keep != "" else 0):
		return
	mine.sort_custom(func(p, q): return abs(int(store[p].aff)) < abs(int(store[q].aff)))
	for k in mine.slice(0, mine.size() - cap + (1 if keep != "" else 0)):
		store.erase(k)

func _announce(player: CharacterData, x: Dictionary, y: Dictionary, now: String, was: String, day: int) -> void:
	var names = "%s and %s" % [x.name, y.name]
	match now:
		"friends":
			if was == "":
				AdventurerManager._history(x, day, "Became friends with %s." % y.name)
				AdventurerManager._history(y, day, "Became friends with %s." % x.name)
		"sworn":
			AdventurerManager._history(x, day, "Swore to stand by %s." % y.name)
			AdventurerManager._history(y, day, "Swore to stand by %s." % x.name)
			WorldClock.add_news(player, "%s swore to fight side by side." % names, "adventurer")
		"rivals":
			if was == "":
				AdventurerManager._history(x, day, "Fell out with %s." % y.name)
				AdventurerManager._history(y, day, "Fell out with %s." % x.name)
		"feud":
			AdventurerManager._history(x, day, "Started a feud with %s." % y.name)
			AdventurerManager._history(y, day, "Started a feud with %s." % x.name)
			WorldClock.add_news(player, "Bad blood in the Guild: %s are feuding." % names, "rival")

# ------------------------------------------------------------------ daily simulation

func _pair_has(x: Dictionary, y: Dictionary, a: String, b: String) -> bool:
	var tx: Array = x.get("traits", [])
	var ty: Array = y.get("traits", [])
	return (a in tx and b in ty) or (b in tx and a in ty)

## Trait chemistry between two adventurers (+1 per compatible pair, -1 per clash).
func chemistry(x: Dictionary, y: Dictionary) -> int:
	return _chem(x, y, 1, 1)

## A town meeting: compatible pairs x chemistry_mult, clashes x clash_mult.
func meeting(x: Dictionary, y: Dictionary) -> int:
	return _chem(x, y, int(cfg().get("chemistry_mult", 1)), int(cfg().get("clash_mult", 1)))

func _chem(x: Dictionary, y: Dictionary, good: int, bad: int) -> int:
	var c := 0
	for pr in cfg().get("compatible", []):
		if _pair_has(x, y, String(pr[0]), String(pr[1])):
			c += good
	for pr in cfg().get("clashing", []):
		if _pair_has(x, y, String(pr[0]), String(pr[1])):
			c -= bad
	return c

## Adventurers in town spend time together: chemistry, and the generous buy rounds.
func town_day(player: CharacterData, day: int) -> void:
	var town = AdventurerManager.active(player).filter(func(n): return String(n.status) in ["idle", "injured"])
	if town.size() < 2:
		return
	var gen: Array = cfg().get("generous_traits", [])
	for i in range(int(cfg().get("town_pairs_per_day", 6))):
		var x: Dictionary = town[RandomManager.randi() % town.size()]
		var y: Dictionary = town[RandomManager.randi() % town.size()]
		# people mostly seek out (or run into) those they already know
		if RandomManager.randf() < float(cfg().get("familiar_share", 0.5)):
			var known = relations_of(player, x).filter(func(r): return r.npc in town)
			if not known.is_empty():
				y = known[RandomManager.randi() % known.size()].npc
		if x == y:
			continue
		var d = meeting(x, y)
		if x.get("traits", []).any(func(t): return t in gen) or y.get("traits", []).any(func(t): return t in gen):
			d += _ev("generous")
		if d != 0:
			change(player, x, y, d, day)
	# weekly: bonds that aren't tended drift back toward indifference; the
	# ambitious resent whoever is close to them on the Ledger
	if day % 7 == 0:
		var drift = int(cfg().get("weekly_drift", 0))
		var store = _store(player)
		for k in store.keys():
			var aff = int(store[k].aff)
			store[k].aff = aff - sign(aff) * min(drift, abs(aff))
			if int(store[k].aff) == 0:
				store.erase(k)
		var st = LedgerManager.standings(player).filter(func(p): return not p.is_player)
		for i in range(st.size()):
			for j in range(i + 1, min(st.size(), i + 4)):
				var a: Dictionary = st[i].npc
				var b: Dictionary = st[j].npc
				if "ambitious" in a.get("traits", []) and "ambitious" in b.get("traits", []):
					change(player, a, b, _ev("ledger_rivalry_week"), day)
				elif j <= i + 2:   # close neighbours on the Ledger grate a little
					change(player, a, b, _ev("ledger_neighbour_week"), day)

## Someone was promoted: the ambitious and boastful they just left behind
## (one rank below, the rank they shared) resent it.
func on_promoted(player: CharacterData, npc: Dictionary, day: int) -> void:
	var peer = RankManager.rank_index(String(npc.rank)) - 1
	for o in AdventurerManager.active(player):
		if o != npc and RankManager.rank_index(String(o.rank)) == peer \
				and ("ambitious" in o.get("traits", []) or "boastful" in o.get("traits", [])):
			change(player, o, npc, _ev("passed_over"), day)
			TemperamentManager.tag(player, o, "passed_over", day)

## An idle friend to bring along on a job (sworn companions almost always
## come; acquaintances sometimes do, which is how friendships start).
func pick_partner(player: CharacterData, npc: Dictionary) -> Dictionary:
	var best := {}
	var acq = int(cfg().get("acquainted_at", 15))
	for r in relations_of(player, npc):
		var f: Dictionary = r.npc
		if int(r.aff) < acq or String(f.status) != "idle" or int(f.get("back_day", -1)) == WorldClock.day(player):
			continue
		var key = "pair_with_sworn" if r.status == "sworn" else ("pair_with_friend" if r.status == "friends" else "pair_with_acquaintance")
		var p = float(cfg().get(key, 0.5))
		if int(npc.get("partner", -1)) == int(f.id):
			p = min(1.0, p * float(DramaManager.cfg().get("romance", {}).get("pair_mult", 1.5)))
		if RandomManager.randf() < p:
			if best.is_empty() or affinity(player, npc, f) > affinity(player, npc, best):
				best = f
	return best

## After a job done together: success binds, failure binds too (or breeds blame).
func after_group_job(player: CharacterData, members: Array, won: bool, day: int) -> void:
	var blame: Array = cfg().get("blame_traits", [])
	for i in range(members.size()):
		for j in range(i + 1, members.size()):
			var x: Dictionary = members[i]
			var y: Dictionary = members[j]
			var d = _ev("job_success")
			if not won:
				d = _ev("job_fail_blame") if (x.get("traits", []).any(func(t): return t in blame) or y.get("traits", []).any(func(t): return t in blame)) else _ev("job_fail")
			change(player, x, y, d, day)
			MemoryManager.add(x, "fought_beside", MemoryManager.key_npc(y), day)
			MemoryManager.add(y, "fought_beside", MemoryManager.key_npc(x), day)

## `rescuer` dragged `rescued` out alive.
func on_rescue(player: CharacterData, rescuer: Dictionary, rescued: Dictionary, day: int) -> void:
	change(player, rescued, rescuer, _ev("rescued"), day)
	change(player, rescuer, rescued, _ev("rescuer"), day)
	MemoryManager.add(rescued, "saved_me", MemoryManager.key_npc(rescuer), day)
	AdventurerManager._history(rescued, day, "Was dragged out alive by %s." % rescuer.name)
	AdventurerManager._history(rescuer, day, "Carried %s out of danger." % rescued.name)
	WorldClock.add_news(player, "%s carried a dying %s out of the depths." % [rescuer.name, rescued.name], "adventurer")
	TemperamentManager.tag(player, rescuer, "rescuer", day)
	TemperamentManager.tag(player, rescued, "saved_by", day)
	TemperamentManager.tag(player, rescued, "near_death", day)

# ------------------------------------------------------------------ you in the web

## Your rapport with `npc` changed by `delta`: their friends follow a little,
## their rivals the other way.
func ripple(player: CharacterData, npc: Dictionary, delta: int) -> void:
	if player == null or abs(delta) < int(cfg().get("ripple_min", 4)):
		return
	var share = float(cfg().get("ripple", 0.25))
	for r in relations_of(player, npc):
		var d = 0
		if r.status in ["friends", "sworn"]:
			d = int(round(delta * share))
		elif r.status in ["rivals", "feud"]:
			d = -int(round(delta * share))
		if d != 0:
			r.npc.rapport = clamp(int(r.npc.rapport) + d, -100, 100)

## Drop relations to adventurers no longer on the roster.
func prune(player: CharacterData) -> void:
	var store = _store(player)
	for k in store.keys():
		var r = store[k]
		if AdventurerManager.get_npc(player, int(r.a)).is_empty() or AdventurerManager.get_npc(player, int(r.b)).is_empty():
			store.erase(k)

## BBCode for the Tavern: their bonds and quarrels.
func describe(player: CharacterData, npc: Dictionary) -> String:
	var rels = relations_of(player, npc).filter(func(r): return r.status != "")
	if rels.is_empty():
		return ""
	var names := {"sworn": "Sworn companion of", "friends": "Friends with", "rivals": "Rival of", "feud": "Feuding with"}
	var cols := {"sworn": "#ffd166", "friends": "#7bd389", "rivals": "#ff9f6b", "feud": "#ff6b6b"}
	var t = "[b]Bonds:[/b] "
	var parts: Array = []
	for r in rels.slice(0, 5):
		parts.append("[color=%s]%s %s[/color]%s" % [cols[r.status], names[r.status], r.npc.name, "" if AdventurerManager.is_active(r.npc) else " (gone)"])
	return t + "; ".join(parts) + "\n"
