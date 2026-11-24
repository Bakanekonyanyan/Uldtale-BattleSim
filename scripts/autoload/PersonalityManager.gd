# res://scripts/autoload/PersonalityManager.gd
# Personalities (data/personalities.json, docs/design/LIVING_WORLD.md section F).
# Every adventurer gets an archetype (anime/manga trope), a drive, a flaw and
# 1-2 quirks: npc.personality = {archetype, drive, flaw, quirks, place, stage,
# drive_done}. Their 'mods' use the same keys as traits, and
# AdventurerManager.trait_mult / trait_sum include them, so the daily sim,
# social actions and fates pick them up without special cases.
# Also: voice lines per context, arcs (stages reached by rapport), drive
# fulfilment, and the player's own voice drifting with their choices.
extends Node

func _ready() -> void:
	GameEvents.champion_crowned.connect(_on_crowned)

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("personalities")
	return d if d is Dictionary else {}

func archetypes() -> Dictionary:
	return cfg().get("archetypes", {})

func archetype(id: String) -> Dictionary:
	return archetypes().get(id, {})

# ------------------------------------------------------------------ generation

func _weighted(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += max(0.0, float(weights[k]))
	if total <= 0.0:
		return ""
	var r = RandomManager.randf() * total
	for k in weights:
		r -= max(0.0, float(weights[k]))
		if r <= 0.0:
			return k
	return weights.keys()[-1]

## Give `npc` a personality (archetype weighted by its traits). Idempotent.
func assign(npc: Dictionary) -> void:
	if npc.has("personality"):
		return
	var w := {}
	for id in archetypes():
		var a: Dictionary = archetypes()[id]
		var m = float(a.get("weight", 1.0))
		for t in npc.get("traits", []):
			m *= float(a.get("trait_bias", {}).get(t, 1.0))
		w[id] = m
	var arch = _weighted(w)
	var drives: Array = cfg().get("drives", {}).keys()
	var flaws: Array = cfg().get("flaws", {}).keys()
	var quirks: Array = cfg().get("quirks", [])
	var q: Array = []
	for i in range(RandomManager.randi_range(1, 2)):
		if quirks.is_empty():
			break
		var pick = quirks[RandomManager.randi() % quirks.size()]
		if not pick in q:
			q.append(pick)
	var locs = LocationManager.get_ids()
	npc["personality"] = {
		"archetype": arch,
		"drive": drives[RandomManager.randi() % drives.size()] if not drives.is_empty() else "",
		"flaw": flaws[RandomManager.randi() % flaws.size()] if not flaws.is_empty() else "",
		"quirks": q,
		"place": String(locs[RandomManager.randi() % locs.size()]) if not locs.is_empty() else "",
		"stage": 0,
		"drive_done": false,
	}

## Apply one-time generation effects (starting rapport, extra levels).
func apply_start(npc: Dictionary) -> void:
	var m = mods_sum(npc, "start_rapport")
	if m != 0.0:
		npc.rapport = clamp(int(npc.rapport) + int(m), -100, 100)
	var lv = int(mods_sum(npc, "level_bonus"))
	if lv > 0:
		npc.level = int(npc.level) + lv

func p(npc: Dictionary) -> Dictionary:
	if not npc.has("personality"):
		assign(npc)
	return npc.personality

# ------------------------------------------------------------------ modifiers

## The mod dictionaries from the personality (archetype, drive, flaw).
func mod_sources(npc: Dictionary) -> Array:
	if npc.is_empty():
		return []
	var pp = p(npc)
	var out: Array = []
	out.append(archetype(String(pp.archetype)).get("mods", {}))
	if not pp.get("drive_done", false):
		out.append(cfg().get("drives", {}).get(String(pp.drive), {}).get("mods", {}))
	out.append(cfg().get("flaws", {}).get(String(pp.flaw), {}).get("mods", {}))
	return out

func mods_sum(npc: Dictionary, key: String) -> float:
	var s := 0.0
	for m in mod_sources(npc):
		if m.has(key) and not (m[key] is Dictionary):
			s += float(m[key])
	return s

func mods_mult(npc: Dictionary, key: String) -> float:
	var x := 1.0
	for m in mod_sources(npc):
		if m.has(key) and not (m[key] is Dictionary):
			x *= float(m[key])
	return x

func likes_mult(npc: Dictionary, category: String) -> float:
	var x := 1.0
	for m in mod_sources(npc):
		x *= float(m.get("likes", {}).get(category, 1.0))
	return x

## Places this adventurer avoids (a phobia).
func avoids(npc: Dictionary, place: String) -> bool:
	var pp = p(npc)
	return cfg().get("flaws", {}).get(String(pp.flaw), {}).get("avoid_place", false) and String(pp.place) == place

## The place their drive points at (avenge), or "".
func drive_place(npc: Dictionary) -> String:
	var pp = p(npc)
	return String(pp.place) if String(cfg().get("drives", {}).get(String(pp.drive), {}).get("fulfil", "")) == "boss_at_place" and not pp.drive_done else ""

# ------------------------------------------------------------------ text

func _fmt(text: String, npc: Dictionary, you: String = "") -> String:
	var who = you if you != "" else _player_name()
	return text.format({"name": String(npc.get("name", "")), "you": who,
		"place": LocationManager.get_display_name(String(p(npc).get("place", "")))})

func _player_name() -> String:
	var c = CharacterManager.get_current_character()
	return c.name if c else "you"

func archetype_name(npc: Dictionary) -> String:
	return String(archetype(String(p(npc).archetype)).get("name", "?"))

func stage_data(npc: Dictionary) -> Dictionary:
	var arc: Array = archetype(String(p(npc).archetype)).get("arc", [])
	var i = clamp(int(p(npc).get("stage", 0)), 0, max(0, arc.size() - 1))
	return arc[i] if not arc.is_empty() else {}

## A voice line for `context` ("" if none). Arc stages may override lines.
func line(npc: Dictionary, context: String) -> String:
	if npc.is_empty():
		return ""
	var lines: Array = stage_data(npc).get("voice", {}).get(context, [])
	if lines.is_empty():
		lines = archetype(String(p(npc).archetype)).get("voice", {}).get(context, [])
	if lines.is_empty():
		return ""
	return _fmt(String(lines[RandomManager.randi() % lines.size()]), npc)

## "Kara: "Line."" or "".
func say(npc: Dictionary, context: String) -> String:
	var l = line(npc, context)
	return "%s: \"%s\"" % [String(npc.name).get_slice(" ", 0), l] if l != "" else ""

## How they seem towards you: a mood word from their rapport (a Tsundere
## seems colder than they are until their arc lets it show).
func mood(npc: Dictionary) -> String:
	var r = int(npc.get("rapport", 0))
	var a = archetype(String(p(npc).archetype))
	if a.has("mood_offset"):
		var until = String(a.get("mood_offset_until_stage", ""))
		if until == "" or String(stage_data(npc).get("id", "")) != until:
			r += int(a.mood_offset)
	if r >= 60: return "devoted"
	if r >= 35: return "warm"
	if r >= 10: return "friendly"
	if r > -10: return "neutral"
	if r > -35: return "wary"
	if r > -60: return "cold"
	return "hostile"

func drive_known(npc: Dictionary) -> bool:
	var rv: Dictionary = cfg().get("reveal", {})
	return int(npc.get("chats", 0)) >= int(rv.get("drive_after_chats", 3)) or int(npc.get("rapport", 0)) >= int(rv.get("drive_at_rapport", 30))

func flaw_known(npc: Dictionary) -> bool:
	return int(npc.get("rapport", 0)) >= int(cfg().get("reveal", {}).get("flaw_at_rapport", 50))

func drive_text(npc: Dictionary) -> String:
	var d: Dictionary = cfg().get("drives", {}).get(String(p(npc).drive), {})
	return "%s - %s%s" % [d.get("name", "?"), _fmt(String(d.get("description", "")), npc), " (fulfilled)" if p(npc).get("drive_done", false) else ""]

func flaw_text(npc: Dictionary) -> String:
	var f: Dictionary = cfg().get("flaws", {}).get(String(p(npc).flaw), {})
	return "%s - %s" % [f.get("name", "?"), _fmt(String(f.get("description", "")), npc)]

## BBCode block for the Tavern details panel.
func describe(npc: Dictionary) -> String:
	var a = archetype(String(p(npc).archetype))
	var t = "[b]Personality:[/b] [color=#c9b8ff]%s[/color] - %s\n" % [a.get("name", "?"), a.get("summary", "")]
	var st = stage_data(npc)
	if a.get("arc", []).size() > 1:
		t += "[color=gray]Arc: %s[/color]\n" % st.get("name", "")
	t += "[b]Seems:[/b] %s towards you\n" % mood(npc)
	for q in p(npc).get("quirks", []):
		t += "[color=gray]• %s[/color]\n" % q
	t += "[b]Drive:[/b] %s\n" % (drive_text(npc) if drive_known(npc) else "[color=gray]Talk with them more to find out.[/color]")
	t += "[b]Flaw:[/b] %s\n" % (flaw_text(npc) if flaw_known(npc) else "[color=gray]Only friends would know.[/color]")
	return t

# ------------------------------------------------------------------ arcs and drives

## Advance the arc as far as their rapport reaches. Returns the news line, or "".
func check_arc(npc: Dictionary, player: CharacterData = null) -> String:
	var arc: Array = archetype(String(p(npc).archetype)).get("arc", [])
	var pp = p(npc)
	var news := ""
	while int(pp.stage) + 1 < arc.size() and int(npc.get("rapport", 0)) >= int(arc[int(pp.stage) + 1].get("rapport", 999)):
		pp.stage = int(pp.stage) + 1
		var st: Dictionary = arc[int(pp.stage)]
		if st.has("news"):
			news = _fmt(String(st.news), npc, player.name if player else "")
	if news != "":
		var pl = player if player else CharacterManager.get_current_character()
		if pl:
			WorldClock.add_news(pl, news, "adventurer")
			AdventurerManager._history(npc, WorldClock.day(pl), "Arc: %s." % stage_data(npc).get("name", ""))
	return news

func _fulfil(npc: Dictionary, player: CharacterData) -> void:
	var pp = p(npc)
	if pp.get("drive_done", false):
		return
	pp.drive_done = true
	var d: Dictionary = cfg().get("drives", {}).get(String(pp.drive), {})
	if player:
		WorldClock.add_news(player, "%s achieved what they set out to do: %s." % [npc.name, String(d.get("name", "")).to_lower()], "adventurer")
		AdventurerManager._history(npc, WorldClock.day(player), "Fulfilled their drive: %s." % d.get("name", ""))

## A boss fell to this adventurer at `place` (AdventurerManager job results).
func on_boss(player: CharacterData, npc: Dictionary, place: String) -> void:
	if drive_place(npc) == place:
		_fulfil(npc, player)

func on_rank(player: CharacterData, npc: Dictionary, rank: String) -> void:
	if rank == "S" and String(cfg().get("drives", {}).get(String(p(npc).drive), {}).get("fulfil", "")) == "rank_s":
		_fulfil(npc, player)

func _on_crowned(champ_name: String, _year: int, is_player: bool) -> void:
	var pl = CharacterManager.get_current_character()
	if is_player or pl == null:
		return
	for n in AdventurerManager.active(pl):
		if String(n.name) == champ_name and String(cfg().get("drives", {}).get(String(p(n).drive), {}).get("fulfil", "")) == "crowned":
			_fulfil(n, pl)

# ------------------------------------------------------------------ the player's voice

func _voice_state(player: CharacterData) -> Dictionary:
	if not player.town_state.has("voice"):
		player.town_state["voice"] = {"points": {}}
	return player.town_state["voice"]

## A choice the player made: add its archetype points.
func player_event(player: CharacterData, event: String, times: int = 1) -> void:
	if player == null or times <= 0:
		return
	var table: Dictionary = cfg().get("player_voice", {}).get("events", {}).get(event, {})
	var pts: Dictionary = _voice_state(player).points
	for a in table:
		pts[a] = int(pts.get(a, 0)) + int(table[a]) * times

## The archetype the Guild sees you as, or "" while it's still forming.
func player_archetype(player: CharacterData) -> String:
	if player == null:
		return ""
	var pts: Dictionary = _voice_state(player).points
	var pv: Dictionary = cfg().get("player_voice", {})
	var ranked = pts.keys()
	ranked.sort_custom(func(a, b): return int(pts[a]) > int(pts[b]))
	if ranked.is_empty() or int(pts[ranked[0]]) < int(pv.get("threshold", 10)):
		return ""
	var second = int(pts[ranked[1]]) if ranked.size() > 1 else 0
	return String(ranked[0]) if int(pts[ranked[0]]) - second >= int(pv.get("lead", 3)) else ""

func player_reputation(player: CharacterData) -> String:
	var a = player_archetype(player)
	if a == "":
		return "Your reputation is still forming."
	var d = archetype(a)
	return "The Guild sees you as a %s: %s" % [String(d.get("name", a)), String(d.get("summary", "")).to_lower()]
