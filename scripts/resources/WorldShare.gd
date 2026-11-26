# res://scripts/resources/WorldShare.gd
# Shared worlds. A world lives in its own file (user://worlds/<id>.json) and
# any number of characters can live in it: the clock, the Guild's
# adventurers and their bonds, rumours, the Chronicle, the champions - and a
# register of the player characters who live there. Each character's save
# keeps only what is theirs: bounties, party, injuries, bestiary, their own
# memories - and what every adventurer feels about *them* (rapport, rivalry,
# memories of them, arc stage), kept per character.
#
#   save:  save_split(player) writes the world file, returns the personal part
#   load:  load_merge(player) puts the world back together around the character
#
# When one character plays, the world moves on for all of them: the next one
# to log in finds the days passed, people promoted, maybe someone dead. Lines
# in the Chronicle and town news about another character carry their name.
# Other characters stand on the Guild Ledger with everyone else.
class_name WorldShare
extends RefCounted

## The parts of town_state that belong to the world.
const WORLD_KEYS := ["world", "adventurers", "rumours", "chronicle", "world_meta"]
## The Ledger's shared part (the rest - your deeds and weekly snapshot - is yours).
const LEDGER_WORLD := ["year", "crownings", "champion"]
const LEDGER_DEFAULTS := {"bosses": 0, "firsts": 0, "crowns": 0, "last_week": -1, "last": {}, "year": 0, "crownings": [], "champion": ""}
## What an adventurer feels about the character playing (kept per character).
const NPC_PERSONAL := ["rapport", "rivalry", "rival", "nemesis", "ahead_of_player", "known_traits", "chats", "bond_seen", "drank_day", "chat_day", "gift_day"]

static var dir := "user://worlds/"

## Tests use their own folder.
static func use_dir(d: String) -> void:
	dir = d

static func path(id: String) -> String:
	return dir + id + ".json"

static func world_id(player: CharacterData) -> String:
	return String(player.town_state.get("world_id", "")) if player else ""

static func read(id: String) -> Dictionary:
	if id == "" or not FileAccess.file_exists(path(id)):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path(id)))
	return d if d is Dictionary else {}

static func _write(id: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f = FileAccess.open(path(id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

## A new world for `player` (after its history is written).
static func found(player: CharacterData) -> void:
	var ts = player.town_state
	var slug = player.name.to_lower().validate_filename().replace(" ", "_")
	ts["world_id"] = "%s_%d_%04x" % [slug, int(Time.get_unix_time_from_system()), randi() % 65536]
	ts["world_meta"] = {"name": "%s's world" % player.name, "founded_day": WorldClock.day(player), "pcs": {}}

## Worlds that can be joined: [{id, name, day, adventurers, pcs: [names]}].
static func joinable(exclude_id := "") -> Array:
	var out: Array = []
	var d = DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json") or f.get_basename() == exclude_id:
			continue
		var w = read(f.get_basename())
		if w.is_empty():
			continue
		var meta: Dictionary = w.get("world_meta", {})
		var pcs: Array = []
		for n in meta.get("pcs", {}):
			if String(meta.pcs[n].get("status", "active")) == "active":
				pcs.append(String(n))
		out.append({"id": f.get_basename(), "name": String(meta.get("name", f.get_basename())),
			"day": int(w.get("world", {}).get("day", 1)), "adventurers": w.get("adventurers", {}).get("list", []).size(), "pcs": pcs})
	out.sort_custom(func(a, b): return a.name < b.name)
	return out

## Move `player` into world `id`. Returns false if there's no such world.
static func join(player: CharacterData, id: String) -> bool:
	if read(id).is_empty():
		return false
	var ts = player.town_state
	for k in WORLD_KEYS + ["ledger", "npc_me"]:
		ts.erase(k)
	ts["world_id"] = id
	load_merge(player)
	ts.erase("world_pending")
	ts["world_ready"] = true
	WorldGen._finish(player)   # your rivals sign up the day you do
	return true

# === SAVE: split the world from the character ===

static func save_split(player: CharacterData) -> Dictionary:
	var ts: Dictionary = player.town_state
	var id = world_id(player)
	if id == "" or not ts.has("adventurers"):
		return ts
	var me = player.name
	var world := {}
	for k in WORLD_KEYS:
		if ts.has(k):
			world[k] = ts[k].duplicate(true) if (ts[k] is Dictionary or ts[k] is Array) else ts[k]
	var personal := {}
	for k in ts:
		if not (k in WORLD_KEYS) and k != "ledger":
			personal[k] = ts[k]
	# the Ledger
	var led: Dictionary = ts.get("ledger", {})
	var wled := {}
	var pled := {}
	for k in led:
		if k in LEDGER_WORLD:
			wled[k] = led[k].duplicate(true) if led[k] is Array or led[k] is Dictionary else led[k]
		else:
			pled[k] = led[k]
	for rec in wled.get("crownings", []):
		if String(rec.get("key", "")) == "you":
			rec["key"] = "pc:" + me
			rec["is_player"] = false
	world["ledger"] = wled
	personal["ledger_me"] = pled
	# what everyone feels about this character
	var party: Array = ts.get("party", [])
	var overlay := {}
	for key in ["list", "departed"]:
		for npc in world.get("adventurers", {}).get(key, []):
			if not npc is Dictionary:
				continue
			var o := {}
			for f in NPC_PERSONAL:
				if npc.has(f):
					o[f] = npc[f]
					npc.erase(f)
			if npc.get("personality") is Dictionary and npc.personality.has("stage"):
				o["stage"] = npc.personality.stage
				npc.personality.erase("stage")
			if npc.has("memories"):
				var mine: Array = npc.memories.filter(func(m): return String(m.get("about", "")) == "you")
				if not mine.is_empty():
					o["memories"] = mine
				npc.memories = npc.memories.filter(func(m): return String(m.get("about", "")) != "you")
			if not o.is_empty():
				overlay[str(int(npc.get("id", -1)))] = o
			# your companions are free to come and go while you're away
			if String(npc.get("status", "")) == "party" and party.has(int(npc.get("id", -1))):
				npc.status = "idle"
	personal["npc_me"] = overlay
	# lines about this character carry their name for everyone else
	for e in world.get("chronicle", []):
		_unprefix(e)
		var who: Array = e.get("who", [])
		if who.has("you"):
			who.erase("you")
			who.append("pc:" + me)
			e["pc"] = me
	for n in world.get("world", {}).get("news", []):
		_unprefix(n)
	# the register of characters in this world
	if not world.has("world_meta"):
		world["world_meta"] = {"name": "%s's world" % me, "pcs": {}}
	var pcs: Dictionary = world.world_meta.get("pcs", {})
	pcs[me] = _pc_entry(player, pled)
	world.world_meta["pcs"] = pcs
	ts["world_meta"] = world.world_meta.duplicate(true)
	_write(id, world)
	return personal

static func _pc_entry(p: CharacterData, led: Dictionary) -> Dictionary:
	var status = "fallen" if p.town_state.get("dead", false) else ("retired" if p.town_state.get("retired", false) else "active")
	return {"level": p.level, "race": p.race, "cls": p.character_class, "rank": RankManager.get_rank(p),
		"points": GuildManager.get_points(p), "deepest": p.deepest_floor_cleared(),
		"bosses": int(led.get("bosses", 0)), "firsts": int(led.get("firsts", 0)), "crowns": int(led.get("crowns", 0)),
		"status": status, "day": WorldClock.day(p)}

# === LOAD: put the world back around the character ===

static func load_merge(player: CharacterData) -> void:
	var ts = player.town_state
	var id = world_id(player)
	if id == "":
		if ts.has("adventurers"):   # an older save: its world becomes a world file on the next save
			found(player)
		return
	var data = read(id)
	if data.is_empty():
		# the world file is gone: a new world will be written on arrival
		for k in ["world_id", "world_ready", "npc_me", "ledger_me"]:
			ts.erase(k)
		ts["world_pending"] = true
		return
	for k in WORLD_KEYS:
		if data.has(k):
			ts[k] = data[k]
	var me = player.name
	# the Ledger
	var led: Dictionary = ts.get("ledger_me", {})
	ts.erase("ledger_me")
	for k in LEDGER_DEFAULTS:
		if not led.has(k):
			led[k] = LEDGER_DEFAULTS[k].duplicate() if LEDGER_DEFAULTS[k] is Dictionary or LEDGER_DEFAULTS[k] is Array else LEDGER_DEFAULTS[k]
	for k in LEDGER_WORLD:
		if data.get("ledger", {}).has(k):
			led[k] = data.ledger[k]
	for rec in led.get("crownings", []):
		if String(rec.get("key", "")) == "pc:" + me:
			rec["key"] = "you"
			rec["is_player"] = true
	ts["ledger"] = led
	# what everyone feels about this character
	var overlay: Dictionary = ts.get("npc_me", {})
	ts.erase("npc_me")
	for key in ["list", "departed"]:
		for npc in ts.get("adventurers", {}).get(key, []):
			if not npc is Dictionary:
				continue
			var o = overlay.get(str(int(npc.get("id", -1))), null)
			if o == null:
				_fresh(player, npc)
				continue
			for f in o:
				if f == "stage":
					if npc.get("personality") is Dictionary:
						npc.personality["stage"] = o.stage
				elif f == "memories":
					if not npc.has("memories"):
						npc["memories"] = []
					npc.memories.append_array(o.memories)
				else:
					npc[f] = o[f]
			for f in NPC_PERSONAL:
				if not npc.has(f):
					npc[f] = _default(f)
	# companions who moved on while you were away
	var party: Array = ts.get("party", [])
	for pid in party.duplicate():
		var n = _find(ts, int(pid))
		if n.is_empty() or not String(n.get("status", "")) in ["idle", "party"]:
			party.erase(pid)
			if not n.is_empty():
				ts.world.news.append({"day": int(ts.world.get("day", 1)), "text": "%s moved on while you were away." % n.name, "kind": "adventurer"})
		else:
			n.status = "party"
	# lines about other characters carry their name
	for e in ts.get("chronicle", []):
		var pc = String(e.get("pc", ""))
		if pc == me:
			var who: Array = e.get("who", [])
			who.erase("pc:" + me)
			who.append("you")
		elif pc != "":
			_prefix(e, pc)
	for n in ts.get("world", {}).get("news", []):
		var pc = String(n.get("pc", ""))
		if pc != "" and pc != me and _mentions_you(String(n.get("text", ""))):
			_prefix(n, pc)

static func _fresh(player: CharacterData, npc: Dictionary) -> void:
	var soc: Dictionary = AdventurerManager._s("social")
	for f in NPC_PERSONAL:
		npc[f] = _default(f)
	var heart = int(npc.get("heart", 0))
	var r = AdventurerManager._range(soc.get("start_rapport", [-10, 15])) + heart / 10
	if Regions.same_region(player, npc):
		r += int(Regions.cfg().get("same_region_rapport", 5))
	npc["rapport"] = clamp(r + Backgrounds.rapport_for(player, npc), -100, 100)
	if npc.get("personality") is Dictionary:
		npc.personality["stage"] = 0

static func _default(f: String):
	match f:
		"rival", "nemesis", "ahead_of_player":
			return false
		"known_traits":
			return []
	return 0

static func _find(ts: Dictionary, id: int) -> Dictionary:
	for n in ts.get("adventurers", {}).get("list", []):
		if int(n.get("id", -1)) == id:
			return n
	return {}

static func _mentions_you(t: String) -> bool:
	return t.begins_with("You") or t.contains(" you") or t.contains(" You") or t.contains("Your ")

static func _prefix(e: Dictionary, name: String) -> void:
	if e.has("_pfx"):
		return
	e["_pfx"] = name + ": "
	e["text"] = e._pfx + String(e.get("text", ""))

static func _unprefix(e: Dictionary) -> void:
	if e.has("_pfx"):
		e["text"] = String(e.get("text", "")).trim_prefix(String(e._pfx))
		e.erase("_pfx")

# === OTHER CHARACTERS ===

## The other characters living in `player`'s world: {name: entry}.
static func others(player: CharacterData, active_only := true) -> Dictionary:
	var out := {}
	var pcs: Dictionary = player.town_state.get("world_meta", {}).get("pcs", {})
	for n in pcs:
		if String(n) == player.name:
			continue
		if active_only and String(pcs[n].get("status", "active")) != "active":
			continue
		out[n] = pcs[n]
	return out

## A character's save is deleted: they leave the world's register (the
## fallen stay, as history), and a world no one lives in any more is removed.
static func on_delete(save_town: Dictionary, name: String, other_saves: Array) -> void:
	var id = String(save_town.get("world_id", ""))
	var data = read(id)
	if data.is_empty():
		return
	var pcs: Dictionary = data.get("world_meta", {}).get("pcs", {})
	if save_town.get("dead", false) and pcs.has(name):
		pcs[name]["status"] = "fallen"
	else:
		pcs.erase(name)
	if not other_saves.any(func(t): return String(t.get("world_id", "")) == id):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path(id)))
		return
	_write(id, data)
