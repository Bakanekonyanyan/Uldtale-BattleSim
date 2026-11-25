# res://scripts/autoload/DramaManager.gd
# The Guild's drama (data/social.json "drama"; LIVING_WORLD.md A and F), built
# on RelationsManager and MemoryManager:
#   Companies   sworn companions form a named company (2-3), job together,
#               break up on a death, retirement or a quarrel inside.
#   Invitations a company with a friend of yours may invite you along: they
#               join your next expedition as guests.
#   Romance     sworn companions may become partners; a feud separates them.
#   Grief       a friend's death: 14-28 days of grief, then vengeance, withdrawing,
#               hardening or carrying on (by traits; twice for a partner).
#   Feuds       a feud may come to blows (a real AutoBattler duel); sometimes lethal.
#               The Guild punishes killers.
#   Jealousy    a Yandere in their Jealousy stage resents whoever you're closer to:
#               bad gossip, then an off-screen beating. Let go, or break into a nemesis.
extends Node

func _ready() -> void:
	if GameEvents.has_signal("floor_cleared"):
		GameEvents.floor_cleared.connect(_on_player_floor_cleared)

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("social")
	return d.get("drama", {}) if d is Dictionary else {}

func _c(section: String) -> Dictionary:
	return cfg().get(section, {})

func _range(v) -> int:
	return AdventurerManager._range(v)

func _traits(n: Dictionary) -> Array:
	return n.get("traits", [])

## Called from AdventurerManager.simulate_day after relations.
func daily(player: CharacterData, day: int) -> void:
	if player == null:
		return
	_tidy_companies(player, day)
	_grief_day(player, day)
	_invitation_day(player, day)
	if day % 7 == 0:
		_form_companies(player, day)
		_romance_week(player, day)
		_feud_week(player, day)
		_jealousy_week(player, day)

# ================================================================== COMPANIES

func companies(player: CharacterData) -> Array:
	var st = AdventurerManager.state(player)
	if not st.has("companies"):
		st["companies"] = []
	return st.companies

func company(player: CharacterData, id: int) -> Dictionary:
	for c in companies(player):
		if int(c.id) == id:
			return c
	return {}

func company_of(player: CharacterData, npc: Dictionary) -> Dictionary:
	return company(player, int(npc.get("company", -1))) if npc.has("company") else {}

func company_members(player: CharacterData, c: Dictionary) -> Array:
	var out: Array = []
	for id in c.get("members", []):
		var n = AdventurerManager.get_npc(player, int(id))
		if not n.is_empty() and AdventurerManager.is_active(n):
			out.append(n)
	return out

func _company_name(player: CharacterData) -> String:
	var c = _c("companies")
	var adj: Array = c.get("adjectives", ["Iron"])
	var noun: Array = c.get("nouns", ["Company"])
	var taken = companies(player).map(func(x): return String(x.name))
	for i in range(20):
		var n = "The %s %s" % [adj[RandomManager.randi() % adj.size()], noun[RandomManager.randi() % noun.size()]]
		if not n in taken:
			return n
	return "The %s Company %d" % [adj[0], companies(player).size() + 1]

func _new_company(player: CharacterData, a: Dictionary, b: Dictionary, day: int) -> Dictionary:
	var st = AdventurerManager.state(player)
	st["next_company"] = int(st.get("next_company", 1))
	var c := {"id": int(st.next_company), "name": _company_name(player), "members": [int(a.id), int(b.id)], "formed": day, "declines": 0}
	st.next_company = int(st.next_company) + 1
	companies(player).append(c)
	a["company"] = c.id
	b["company"] = c.id
	for n in [a, b]:
		AdventurerManager._history(n, day, "Founded %s with %s." % [c.name, (b if n == a else a).name])
	WorldClock.add_news(player, "%s and %s have formed a company: %s." % [a.name, b.name, c.name], "adventurer")
	return c

func _leave_company(player: CharacterData, npc: Dictionary, day: int, why := "") -> void:
	var c = company_of(player, npc)
	npc.erase("company")
	if c.is_empty():
		return
	c.members.erase(int(npc.id))
	if why != "":
		AdventurerManager._history(npc, day, why)
	if company_members(player, c).size() < 2:
		for n in company_members(player, c):
			n.erase("company")
			AdventurerManager._history(n, day, "%s is no more." % c.name)
		companies(player).erase(c)
		WorldClock.add_news(player, "%s has disbanded." % c.name, "adventurer")

## Sworn companions found companies (or join one with room).
func _form_companies(player: CharacterData, day: int) -> void:
	var max_size = int(_c("companies").get("max_size", 3))
	var need = int(_c("companies").get("join_min_affinity", 40))
	var store: Dictionary = AdventurerManager.state(player).get("relations", {})
	for k in store.keys():
		var r = store[k]
		if RelationsManager.status_of(int(r.aff)) != "sworn":
			continue
		var a = AdventurerManager.get_npc(player, int(r.a))
		var b = AdventurerManager.get_npc(player, int(r.b))
		if a.is_empty() or b.is_empty() or not AdventurerManager.is_active(a) or not AdventurerManager.is_active(b):
			continue
		var ca = company_of(player, a)
		var cb = company_of(player, b)
		if ca.is_empty() and cb.is_empty():
			_new_company(player, a, b, day)
		elif ca.is_empty() != cb.is_empty():
			var c = cb if ca.is_empty() else ca
			var joiner = a if ca.is_empty() else b
			var mem = company_members(player, c)
			if mem.size() < max_size and mem.all(func(m): return RelationsManager.affinity(player, m, joiner) >= need):
				c.members.append(int(joiner.id))
				joiner["company"] = c.id
				AdventurerManager._history(joiner, day, "Joined %s." % c.name)
				WorldClock.add_news(player, "%s joined %s." % [joiner.name, c.name], "adventurer")

## Drop the dead and retired; a quarrel inside splits a company.
func _tidy_companies(player: CharacterData, day: int) -> void:
	for c in companies(player).duplicate():
		for id in c.members.duplicate():
			var n = AdventurerManager.get_npc(player, int(id))
			if n.is_empty() or not AdventurerManager.is_active(n):
				c.members.erase(id)
		var mem = company_members(player, c)
		if mem.size() < 2:
			for n in mem:
				_leave_company(player, n, day)
			companies(player).erase(c)
			continue
		for i in range(mem.size()):
			for j in range(i + 1, mem.size()):
				if RelationsManager.affinity(player, mem[i], mem[j]) <= int(RelationsManager.cfg().get("thresholds", {}).get("rivals", -40)):
					var leaver = mem[j] if int(mem[i].points) >= int(mem[j].points) else mem[i]
					WorldClock.add_news(player, "%s walked out on %s after a falling-out." % [leaver.name, c.name], "adventurer")
					_leave_company(player, leaver, day, "Walked out on %s." % c.name)
					return

## Who goes on a job with `npc`: their idle company, else a friend (or partner).
func job_partners(player: CharacterData, npc: Dictionary) -> Array:
	var day = WorldClock.day(player)
	var c = company_of(player, npc)
	if not c.is_empty():
		return company_members(player, c).filter(func(m): return m != npc and String(m.status) == "idle" and int(m.get("back_day", -1)) != day)
	var p = RelationsManager.pick_partner(player, npc)
	return [] if p.is_empty() else [p]

# ================================================================== INVITATIONS

func invitation(player: CharacterData) -> Dictionary:
	var inv: Dictionary = player.town_state.get("invitation", {})
	if inv.is_empty():
		return {}
	var c = company(player, int(inv.company))
	if c.is_empty() or WorldClock.day(player) > int(inv.expires) or not company_members(player, c).all(func(m): return String(m.status) == "idle"):
		player.town_state.erase("invitation")
		return {}
	return inv

func _invitation_day(player: CharacterData, day: int) -> void:
	_send_guests_home(player, day)
	if not invitation(player).is_empty():
		return
	var ic = _c("invitations")
	if RandomManager.randf() >= float(ic.get("chance_per_day", 0.06)):
		return
	var room = int(ic.get("max_heroes", 3)) - 1 - PartyManager.members(player).size()
	var options = companies(player).filter(func(c):
		var mem = company_members(player, c)
		return mem.size() <= room and mem.all(func(m): return String(m.status) == "idle" and MemoryManager.grudge(m).is_empty()) \
			and mem.any(func(m): return int(m.rapport) >= int(ic.get("min_rapport", 40))))
	if options.is_empty():
		return
	var c: Dictionary = options[RandomManager.randi() % options.size()]
	player.town_state["invitation"] = {"company": int(c.id), "expires": day + int(ic.get("valid_days", 3))}
	WorldClock.add_news(player, "%s invite you to join them on their next job. (Tavern)" % c.name, "party")

## Join the inviting company's members as guests on your next expedition.
func accept_invitation(player: CharacterData) -> Dictionary:
	var inv = invitation(player)
	if inv.is_empty():
		return {"ok": false, "reason": "No one has invited you."}
	var c = company(player, int(inv.company))
	var mem = company_members(player, c)
	if mem.size() + PartyManager.members(player).size() > int(_c("invitations").get("max_heroes", 3)) - 1:
		return {"ok": false, "reason": "There isn't room for all of them beside your party."}
	var day = WorldClock.day(player)
	for m in mem:
		m.status = "party"
		m["guest"] = c.id
		m["guest_since"] = day
		PartyManager.party_ids(player).append(int(m.id))
		PartyManager._sync_level(player, m)
		AdventurerManager._history(m, day, "Took %s along with %s." % [player.name, c.name])
	player.town_state.erase("invitation")
	c.declines = 0
	return {"ok": true, "reason": "You join %s. They'll fight beside you on your next expedition." % c.name}

func decline_invitation(player: CharacterData) -> String:
	var inv = invitation(player)
	if inv.is_empty():
		return ""
	var c = company(player, int(inv.company))
	player.town_state.erase("invitation")
	c.declines = int(c.get("declines", 0)) + 1
	if int(c.declines) >= int(_c("invitations").get("decline_limit", 3)):
		c.declines = 0
		for m in company_members(player, c):
			AdventurerManager._set_rapport(m, int(_c("invitations").get("decline_rapport", -3)))
		return "%s have stopped asking for a while." % c.name
	return "You turn %s down. No hard feelings." % c.name

func is_guest(npc: Dictionary) -> bool:
	return npc.has("guest")

## After an expedition (PartyManager): guests go home with a memory of you.
func on_expedition_end(player: CharacterData, cleared: bool) -> void:
	var day = WorldClock.day(player)
	var ic = _c("invitations")
	for m in PartyManager.members(player).filter(func(n): return is_guest(n)):
		var c = company(player, int(m.guest))
		MemoryManager.add(m, "shared_victory" if cleared else "shared_hardship", "you", day)
		MemoryManager.add(player, "shared_victory" if cleared else "shared_hardship", MemoryManager.key_npc(m), day)
		AdventurerManager._set_rapport(m, int(ic.get("victory_rapport" if cleared else "hardship_rapport", 1)))
		_release_guest(player, m, day, "Went back to %s after a job with %s." % [c.get("name", "their company"), player.name])

func _release_guest(player: CharacterData, m: Dictionary, day: int, why: String) -> void:
	PartyManager.party_ids(player).erase(int(m.id))
	m.erase("guest")
	m.erase("guest_since")
	if String(m.status) == "party":
		m.status = "idle"
	AdventurerManager._history(m, day, why)

func _send_guests_home(player: CharacterData, day: int) -> void:
	for m in PartyManager.members(player).filter(func(n): return is_guest(n)):
		if day - int(m.get("guest_since", day)) > int(_c("invitations").get("guest_days", 4)):
			_release_guest(player, m, day, "Got tired of waiting for %s and went back to work." % player.name)

# ================================================================== ROMANCE

func partner_of(player: CharacterData, npc: Dictionary) -> Dictionary:
	return AdventurerManager.get_npc(player, int(npc.partner)) if npc.has("partner") else {}

func _romance_week(player: CharacterData, day: int) -> void:
	var rc = _c("romance")
	var aloof = String(rc.get("aloof_trait", "aloof"))
	var store: Dictionary = AdventurerManager.state(player).get("relations", {})
	for k in store.keys():
		var r = store[k]
		var a = AdventurerManager.get_npc(player, int(r.a))
		var b = AdventurerManager.get_npc(player, int(r.b))
		if a.is_empty() or b.is_empty() or not AdventurerManager.is_active(a) or not AdventurerManager.is_active(b):
			continue
		# separation: partners who've fallen out
		if int(a.get("partner", -1)) == int(b.id):
			if int(r.aff) <= int(RelationsManager.cfg().get("thresholds", {}).get("rivals", -40)):
				separate(player, a, b, day)
			continue
		if RelationsManager.status_of(int(r.aff)) != "sworn" or a.has("partner") or b.has("partner"):
			continue
		var chance = float(rc.get("weekly_chance", 0.1))
		if RelationsManager.chemistry(a, b) > 0:
			chance *= float(rc.get("compatible_mult", 2.0))
		if (aloof in _traits(a)) != (aloof in _traits(b)):   # one cold heart stops it; two may find each other
			chance = 0.0
		if RandomManager.randf() < chance:
			pair_up(player, a, b, day)

func pair_up(player: CharacterData, a: Dictionary, b: Dictionary, day: int) -> void:
	a["partner"] = int(b.id)
	b["partner"] = int(a.id)
	AdventurerManager._history(a, day, "Fell for %s." % b.name)
	AdventurerManager._history(b, day, "Fell for %s." % a.name)
	WorldClock.add_news(player, "Word at the Tavern: %s and %s are together now." % [a.name, b.name], "adventurer")

func separate(player: CharacterData, a: Dictionary, b: Dictionary, day: int) -> void:
	a.erase("partner")
	b.erase("partner")
	AdventurerManager._history(a, day, "Split up with %s." % b.name)
	AdventurerManager._history(b, day, "Split up with %s." % a.name)
	WorldClock.add_news(player, "%s and %s have split up - badly." % [a.name, b.name], "adventurer")

# ================================================================== DEATH AND GRIEF

## Someone died. `killer` (optional) is the adventurer who killed them.
func on_death(player: CharacterData, dead: Dictionary, day: int, killer: Dictionary = {}) -> void:
	if player == null:
		return
	TemperamentManager.note_death(player, dead, day)
	if not killer.is_empty():
		dead["died_at"] = {"by": int(killer.id)}
	var g = _c("grief")
	var close = RelationsManager.relations_of(player, dead).filter(func(r): return int(r.aff) >= int(g.get("min_affinity", 40)) and AdventurerManager.is_active(r.npc)).map(func(r): return r.npc)
	for m in close:
		MemoryManager.add(m, "lost_companion", MemoryManager.key_npc(dead), day)
		AdventurerManager._history(m, day, "Lost %s." % dead.name)
		if not killer.is_empty() and m != killer:
			MemoryManager.add(m, "killed_my_friend", MemoryManager.key_npc(killer), day)
			RelationsManager.change(player, m, killer, int(_c("feuds").get("killer_affinity", -50)), day)
		m["grief"] = {"about": int(dead.id), "until": day + _range(g.get("days", [14, 28])), "partner": int(m.get("partner", -1)) == int(dead.id)}
		TemperamentManager.tag(player, m, "friend_died", day)
	if int(dead.get("partner", -1)) >= 0:
		var p = partner_of(player, dead)
		if not p.is_empty():
			p.erase("partner")
			p["widowed"] = int(dead.id)
		dead.erase("partner")
	# you remember those you were close to
	if int(dead.get("rapport", 0)) >= int(MemoryManager.cfg().get("memory", {}).get("full_view_rapport", 40)):
		MemoryManager.add(player, "lost_companion", MemoryManager.key_npc(dead), day)
		if not killer.is_empty():
			MemoryManager.add(player, "killed_my_friend", MemoryManager.key_npc(killer), day)
	if dead.has("company"):
		_leave_company(player, dead, day)

## Someone retired: leave their company and partner (the partner may follow them out).
func on_retire(player: CharacterData, npc: Dictionary, day: int) -> void:
	if npc.has("company"):
		_leave_company(player, npc, day)
	var p = partner_of(player, npc)
	if not p.is_empty():
		npc.erase("partner")
		p.erase("partner")
		if String(p.status) == "idle" and RandomManager.randf() < 0.5:
			p.status = "retired"
			AdventurerManager._history(p, day, "Retired alongside %s." % npc.name)
			WorldClock.add_news(player, "%s retired alongside %s." % [p.name, npc.name], "adventurer")
			if p.has("company"):
				_leave_company(player, p, day)
		else:
			AdventurerManager._history(p, day, "Stayed on when %s retired." % npc.name)

func is_grieving(npc: Dictionary) -> bool:
	return npc.has("grief")

## Grieving adventurers take fewer jobs (AdventurerManager._maybe_start).
func job_chance_mult(npc: Dictionary) -> float:
	return float(_c("grief").get("job_chance_mult", 0.4)) if is_grieving(npc) else 1.0

func _grief_day(player: CharacterData, day: int) -> void:
	for n in AdventurerManager.active(player):
		if is_grieving(n) and day >= int(n.grief.until):
			var gr: Dictionary = n.grief
			n.erase("grief")
			var picks = 2 if gr.get("partner", false) else 1
			var done: Array = []
			for i in range(picks):
				var o = grief_outcome(n)
				if o in done:
					continue
				done.append(o)
				_apply_grief(player, n, o, AdventurerManager.get_npc(player, int(gr.about)), day)
				if not AdventurerManager.is_active(n):
					break
		elif n.has("vengeance") and day > int(n.vengeance.get("until", day)):
			AdventurerManager._history(n, day, "Gave up on vengeance and made peace with it.")
			n.erase("vengeance")

## Weighted by traits (data grief.outcomes).
func grief_outcome(npc: Dictionary) -> String:
	var outs: Dictionary = _c("grief").get("outcomes", {})
	var weights := {}
	var total := 0.0
	for o in outs:
		var w = float(outs[o].get("base", 1.0))
		for t in _traits(npc):
			w *= float(outs[o].get("traits", {}).get(t, 1.0))
		weights[o] = w
		total += w
	var roll = RandomManager.randf() * total
	for o in weights:
		roll -= weights[o]
		if roll <= 0.0:
			return o
	return "carries_on"

func _apply_grief(player: CharacterData, n: Dictionary, outcome: String, dead: Dictionary, day: int) -> void:
	var g = _c("grief")
	var who = String(dead.get("name", "a friend"))
	match outcome:
		"vengeance":
			var at: Dictionary = dead.get("died_at", {})
			if at.has("by"):
				var killer = AdventurerManager.get_npc(player, int(at.by))
				if not killer.is_empty() and AdventurerManager.is_active(killer):
					var cur = RelationsManager.affinity(player, n, killer)
					RelationsManager.change(player, n, killer, min(0, int(g.get("vengeance_feud", -80)) - cur), day)
					n["vengeance"] = {"npc": int(killer.id), "for": int(dead.get("id", -1)), "until": day + int(g.get("vengeance_days", 120))}
					AdventurerManager._history(n, day, "Swore vengeance on %s for %s." % [killer.name, who])
					WorldClock.add_news(player, "%s has sworn vengeance on %s for killing %s." % [n.name, killer.name, who], "rival")
					return
			elif at.has("location"):
				n["vengeance"] = {"location": String(at.location), "floor": int(at.floor), "for": int(dead.get("id", -1)), "until": day + int(g.get("vengeance_days", 120))}
				var where = LocationManager.get_display_name(String(at.location))
				AdventurerManager._history(n, day, "Swore to slay the boss of %s floor %d, where %s fell." % [where, int(at.floor), who])
				WorldClock.add_news(player, "%s has sworn to avenge %s in %s (floor %d)." % [n.name, who, where, int(at.floor)], "adventurer")
				return
			_apply_grief(player, n, "carries_on", dead, day)
		"withdraws":
			n.status = "retired"
			AdventurerManager._history(n, day, "Couldn't go on without %s. Left the Guild." % who)
			WorldClock.add_news(player, "%s has left the Guild, still grieving %s." % [n.name, who], "adventurer")
			_leave_company(player, n, day)
		"hardens":
			var pool: Array = g.get("harden_traits", ["aloof"]).filter(func(t): return not t in _traits(n))
			if pool.is_empty():
				_apply_grief(player, n, "carries_on", dead, day)
				return
			var t = String(pool[RandomManager.randi() % pool.size()])
			n.traits.append(t)
			AdventurerManager._history(n, day, "Something in them went cold after losing %s." % who)
			WorldClock.add_news(player, "%s hasn't been the same since %s died." % [n.name, who], "adventurer")
		_:
			AdventurerManager._history(n, day, "Raised a cup to %s and carried on." % who)

## Where an avenger wants to go (AdventurerManager._maybe_start), or {}.
func vengeance_job(npc: Dictionary) -> Dictionary:
	var v: Dictionary = npc.get("vengeance", {})
	if v.has("location") and RandomManager.randf() < float(_c("grief").get("vengeance_job_chance", 0.6)):
		return {"location": String(v.location), "floor": int(v.floor)}
	return {}

## A boss fell to an NPC (job result): vengeance fulfilled?
func on_npc_boss(player: CharacterData, npc: Dictionary, location: String, fl: int, day: int) -> void:
	var v: Dictionary = npc.get("vengeance", {})
	if v.has("location") and String(v.location) == location and fl >= int(v.floor):
		var dead = AdventurerManager.get_npc(player, int(v.get("for", -1)))
		npc.erase("vengeance")
		npc["avenged"] = int(npc.get("avenged", 0)) + 1
		AdventurerManager._history(npc, day, "Avenged %s." % dead.get("name", "a friend"))
		WorldClock.add_news(player, "%s avenged %s: the boss of %s floor %d is dead." % [npc.name, dead.get("name", "a friend"), LocationManager.get_display_name(location), fl], "adventurer")

## You killed a boss: anyone whose vengeance that was owes you.
func _on_player_floor_cleared(location_id: String, fl: int) -> void:
	var player = CharacterManager.get_current_character()
	if player == null:
		return
	var day = WorldClock.day(player)
	for n in AdventurerManager.active(player):
		var v: Dictionary = n.get("vengeance", {})
		if v.has("location") and String(v.location) == location_id and fl >= int(v.floor):
			var dead = AdventurerManager.get_npc(player, int(v.get("for", -1)))
			n.erase("vengeance")
			MemoryManager.add(n, "avenged_me", "you", day)
			AdventurerManager._set_rapport(n, int(_c("grief").get("avenged_rapport", 25)))
			AdventurerManager._history(n, day, "%s avenged %s for them." % [player.name, dead.get("name", "a friend")])
			WorldClock.add_news(player, "You killed the boss that took %s. %s won't forget it." % [dead.get("name", "a friend"), n.name], "adventurer")

# ================================================================== FEUDS

func _feud_week(player: CharacterData, day: int) -> void:
	var fc = _c("feuds")
	var store: Dictionary = AdventurerManager.state(player).get("relations", {})
	for k in store.keys():
		if not store.has(k):
			continue
		var r = store[k]
		if RelationsManager.status_of(int(r.aff)) != "feud":
			continue
		var a = AdventurerManager.get_npc(player, int(r.a))
		var b = AdventurerManager.get_npc(player, int(r.b))
		if a.is_empty() or b.is_empty() or String(a.status) != "idle" or String(b.status) != "idle":
			continue
		var chance = float(fc.get("weekly_chance", 0.05))
		for n in [a, b]:
			if "cruel" in _traits(n):
				chance *= float(fc.get("cruel_mult", 2.0))
			if _traits(n).any(func(t): return t in fc.get("gentle_traits", [])):
				chance *= float(fc.get("gentle_mult", 0.5))
			if int(n.get("vengeance", {}).get("npc", -1)) == int((b if n == a else a).id):
				chance *= 3.0   # an avenger goes looking for them
		if RandomManager.randf() < chance:
			confront(player, a, b, day)

## Two feuding adventurers come to blows (a real fight). Returns {winner, loser, lethal}.
func confront(player: CharacterData, a: Dictionary, b: Dictionary, day: int, force_lethal = null) -> Dictionary:
	var fc = _c("feuds")
	var hero = AutoBattler.build_hero(a)
	var foe = AutoBattler.build_hero(b)
	foe.is_player = false
	foe.calculate_secondary_attributes()
	foe.current_hp = foe.max_hp
	var a_won: bool = AutoBattler.fight(hero, [foe] as Array[CharacterData], max(1, int(min(int(a.level), int(b.level)) * 0.5)), false).won
	var winner = a if a_won else b
	var loser = b if a_won else a
	var lethal_possible = "cruel" in _traits(a) or "cruel" in _traits(b) or abs(int(a.level) - int(b.level)) >= int(fc.get("lethal_level_gap", 5))
	var lethal: bool = (RandomManager.randf() < float(fc.get("lethal_chance", 0.25))) if lethal_possible else false
	if force_lethal != null:
		lethal = bool(force_lethal)
	MemoryManager.add(loser, "beat_me", MemoryManager.key_npc(winner), day)
	TemperamentManager.tag(player, loser, "lost_spar", day)
	if lethal:
		loser.status = "dead"
		loser.died_day = day
		AdventurerManager._history(loser, day, "Killed by %s in a feud." % winner.name)
		AdventurerManager._history(winner, day, "Killed %s." % loser.name)
		winner["kills"] = int(winner.get("kills", 0)) + 1
		WorldClock.add_news(player, "Blood behind the Guild hall: %s killed %s." % [winner.name, loser.name], "death")
		on_death(player, loser, day, winner)
		_punish_killer(player, winner, day)
	else:
		var days = _range(fc.get("injury_days", [4, 9]))
		loser.status = "injured"
		loser.injured_until = day + days
		AdventurerManager._history(loser, day, "Beaten by %s in a brawl (%d days to recover)." % [winner.name, days])
		AdventurerManager._history(winner, day, "Beat %s in a brawl." % loser.name)
		WorldClock.add_news(player, "%s and %s finally came to blows. %s won." % [a.name, b.name, winner.name], "rival")
	return {"winner": winner, "loser": loser, "lethal": lethal}

func _punish_killer(player: CharacterData, killer: Dictionary, day: int) -> void:
	var fc = _c("feuds")
	if not bool(fc.get("honourable_conduct", true)):
		return
	killer["demerits"] = int(killer.get("demerits", 0)) + int(fc.get("killer_demerits", 3))
	var ids = RankManager.rank_ids()
	var i = max(0, RankManager.rank_index(String(killer.rank)) - int(fc.get("killer_rank_drop", 1)))
	if String(ids[i]) != String(killer.rank):
		killer.rank = String(ids[i])
		AdventurerManager._history(killer, day, "Stripped to %s by the Guild." % RankManager.display(killer.rank))
	WorldClock.add_news(player, "The Guild has punished %s: demerits and a lower rank." % killer.name, "guild")

# ================================================================== JEALOUSY

func _is_jealous(npc: Dictionary) -> bool:
	var jc = _c("jealousy")
	return String(PersonalityManager.p(npc).get("archetype", "")) == String(jc.get("archetype", "yandere")) \
		and String(PersonalityManager.stage_data(npc).get("id", "")) == String(jc.get("stage", "jealousy")) \
		and not npc.get("broken", false)

func _jealousy_week(player: CharacterData, day: int) -> void:
	var jc = _c("jealousy")
	for y in AdventurerManager.active(player):
		if not _is_jealous(y):
			continue
		# they broke: you let their devotion sour
		if int(y.rapport) < int(jc.get("break_below", 20)):
			y["broken"] = true
			y["rival"] = true
			y.rivalry = max(int(y.get("rivalry", 0)), int(jc.get("break_rivalry", 5)))
			AdventurerManager._history(y, day, "Something in them snapped.")
			WorldClock.add_news(player, "Something in %s has snapped. They've turned on you." % y.name, "rival")
			continue
		jealousy_step(player, y, day)

## One week of jealousy. Returns what happened: "", "resent", "gossip", "sabotage".
func jealousy_step(player: CharacterData, y: Dictionary, day: int) -> String:
	var jc = _c("jealousy")
	var target := {}
	for n in AdventurerManager.active(player):
		if n != y and int(n.rapport) >= int(y.rapport) - int(jc.get("margin", 0)) and (target.is_empty() or int(n.rapport) > int(target.rapport)):
			target = n
	if target.is_empty():
		return ""
	var key = MemoryManager.key_npc(target)
	MemoryManager.add(y, "jealous_of", key, day)
	RelationsManager.change(player, y, target, int(jc.get("affinity", -8)), day)
	var feeling = MemoryManager.opinion(y, key)
	var did = "resent"
	if feeling <= float(jc.get("gossip_at", -20)):
		var ears = AdventurerManager.active(player).filter(func(n): return n != y and n != target and AdventurerManager.in_town(n))
		for i in range(min(ears.size(), int(jc.get("gossip_listeners", 2)))):
			var ear: Dictionary = ears[RandomManager.randi() % ears.size()]
			MemoryManager.add(ear, "slandered", key, day, null, MemoryManager.key_npc(y))
			RelationsManager.change(player, ear, target, int(jc.get("gossip_affinity", -4)), day)
		did = "gossip"
	if feeling <= float(jc.get("sabotage_at", -40)) and String(target.status) == "idle" and RandomManager.randf() < float(jc.get("sabotage_chance", 0.25)):
		var days = _range(jc.get("injury_days", [3, 6]))
		target.status = "injured"
		target.injured_until = day + days
		AdventurerManager._history(target, day, "Jumped in an alley by someone they didn't see (%d days to recover)." % days)
		WorldClock.add_news(player, "%s was found beaten in an alley behind the Guild." % target.name, "adventurer")
		if RandomManager.randf() < float(jc.get("caught_chance", 0.5)):
			MemoryManager.add(target, "ambushed_me", MemoryManager.key_npc(y), day)
			RelationsManager.change(player, target, y, int(jc.get("caught_affinity", -30)), day)
		did = "sabotage"
	return did

# ================================================================== TEXT

## Tavern lines: company, partner, grief, vengeance.
func describe(player: CharacterData, npc: Dictionary) -> String:
	var t := ""
	var c = company_of(player, npc)
	if not c.is_empty():
		var others = company_members(player, c).filter(func(m): return m != npc).map(func(m): return String(m.name))
		t += "[b]Company:[/b] [color=#ffd166]%s[/color]%s\n" % [c.name, (" (with %s)" % ", ".join(others)) if not others.is_empty() else ""]
	var p = partner_of(player, npc)
	if not p.is_empty():
		t += "[color=#ff9fbf]Together with %s.[/color]\n" % p.name
	if is_grieving(npc):
		t += "[color=#9fb4ff]Grieving %s.[/color]\n" % AdventurerManager.get_npc(player, int(npc.grief.about)).get("name", "a friend")
	var v: Dictionary = npc.get("vengeance", {})
	if v.has("location"):
		t += "[color=#ff9f6b]Has sworn to slay the boss of %s floor %d.[/color]\n" % [LocationManager.get_display_name(String(v.location)), int(v.floor)]
	elif v.has("npc"):
		t += "[color=#ff6b6b]Has sworn vengeance on %s.[/color]\n" % AdventurerManager.get_npc(player, int(v.npc)).get("name", "someone")
	if is_guest(npc):
		t += "[color=#7bd389]Coming along on your next expedition (%s).[/color]\n" % company(player, int(npc.guest)).get("name", "their company")
	return t
