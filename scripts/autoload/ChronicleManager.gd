# res://scripts/autoload/ChronicleManager.gd
# The Chronicle (data/chronicle.json; LIVING_WORLD.md C): the world's history.
# Every news line (WorldClock.add_news) is weighed - importance by news kind
# plus keyword boosts - and kept if important enough, with the adventurers it
# names (names are unique) and "you". player.town_state["chronicle"] =
#   [{day, kind, text, imp, who: ["npc:<id>" | "you"]}]
# Also: epithets earned from deeds, generated biographies, epitaphs.
extends Node

func _ready() -> void:
	GameEvents.floor_cleared.connect(_on_floor_cleared)

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("chronicle")
	return d if d is Dictionary else {}

func entries(player: CharacterData) -> Array:
	if player == null:
		return []
	if not player.town_state.has("chronicle"):
		player.town_state["chronicle"] = []
	return player.town_state["chronicle"]

# ------------------------------------------------------------------ recording

## How much a line matters (news kind + keyword boosts).
func importance(text: String, kind: String) -> int:
	var imp = int(cfg().get("kind_importance", {}).get(kind, 2))
	for b in cfg().get("boosts", []):
		if text.contains(String(b.contains)):
			imp += int(b.get("add", 0))
	return imp

## Who a line is about: adventurers named in it, and "you".
func subjects(player: CharacterData, text: String) -> Array:
	var who: Array = []
	if text.contains("You ") or text.contains(" you") or text.contains("Your ") or (player and player.name != "" and text.contains(player.name)):
		who.append("you")
	if player:
		for n in AdventurerManager.all_adventurers(player):
			if text.contains(String(n.name)):
				who.append(MemoryManager.key_npc(n))
	return who

## Keep a line if it matters. Returns the entry ({} if not kept).
func record(player: CharacterData, text: String, kind := "chronicle", imp := -1, day := -1) -> Dictionary:
	if player == null or text == "":
		return {}
	if imp < 0:
		imp = importance(text, kind)
	if imp < int(cfg().get("min_importance", 3)):
		return {}
	var e := {"day": day if day >= 0 else WorldClock.day(player), "kind": kind, "text": text, "imp": imp, "who": subjects(player, text)}
	var list = entries(player)
	list.append(e)
	var cap = int(cfg().get("max_entries", 500))
	if list.size() > cap:
		# prune the least important, oldest first
		var idx := 0
		for i in range(list.size()):
			if int(list[i].imp) < int(list[idx].imp):
				idx = i
		list.remove_at(idx)
	return e

## WorldClock.add_news calls this for every line.
func on_news(player: CharacterData, text: String, kind: String) -> void:
	record(player, text, kind)

func _on_floor_cleared(location_id: String, fl: int) -> void:
	var p = CharacterManager.get_current_character()
	if p == null or fl < p.get_max_floor(location_id):
		return   # only new ground
	record(p, "%s cleared floor %d of %s." % [p.name, fl, LocationManager.get_display_name(location_id)], "chronicle", 5 if fl % 5 == 0 else 3)

## Entries about someone ("you" or "npc:<id>"), oldest first.
func about(player: CharacterData, key: String) -> Array:
	return entries(player).filter(func(e): return key in e.get("who", []))

# ------------------------------------------------------------------ dates

## "Week 2 of Bloomtide, Year 1" for a day.
func date_for(day: int) -> String:
	var c: Dictionary = WorldClock.cfg.get("calendar", {})
	var d = max(0, day - 1)
	var dpw = WorldClock.days_per_week()
	var wps = int(c.get("weeks_per_season", 4))
	var seasons: Array = c.get("seasons", ["Spring"])
	var week = d / dpw
	return "Week %d of %s, Year %d" % [week % wps + 1, seasons[(week / wps) % seasons.size()], week / (wps * seasons.size()) + 1]

func year_of(day: int) -> int:
	return LedgerManager.year_of(day)

# ------------------------------------------------------------------ epithets

## Deeds an epithet can be earned from.
func metrics_npc(npc: Dictionary) -> Dictionary:
	var d = LedgerManager._deeds(npc)
	var ex: Dictionary = npc.get("experience", {})
	return {"crowns": int(d.get("crowns", 0)), "bosses": int(d.get("bosses", 0)), "deepest": int(d.get("deepest", 0)),
		"firsts": int(d.get("firsts", 0)), "kills": int(npc.get("kills", 0)), "avenged": int(npc.get("avenged", 0)),
		"rescues": int(ex.get("rescuer", 0)), "near_death": int(ex.get("near_death", 0)),
		"top_rank": 1 if RankManager.rank_index(String(npc.get("rank", ""))) >= RankManager.rank_ids().size() - 1 else 0}

func metrics_player(player: CharacterData) -> Dictionary:
	var pr = LedgerManager.profile_player(player)
	var ex: Dictionary = player.town_state.get("experience", {})
	return {"crowns": int(pr.crowns), "bosses": int(pr.bosses), "deepest": int(pr.deepest), "firsts": int(pr.firsts),
		"kills": 0, "avenged": int(ex.get("avenged", 0)), "rescues": int(ex.get("rescuer", 0)), "near_death": int(ex.get("near_death", 0)),
		"top_rank": 1 if RankManager.get_rank_index(player) >= RankManager.rank_ids().size() - 1 else 0}

## The first epithet whose every requirement the deeds meet ("" if none).
func epithet_from(m: Dictionary) -> String:
	for e in cfg().get("epithets", []):
		var ok := true
		for k in e:
			if k in ["id", "text"]:
				continue
			if int(m.get(k, 0)) < int(e[k]):
				ok = false
				break
		if ok:
			return String(e.text)
	return ""

func epithet(npc: Dictionary) -> String:
	return epithet_from(metrics_npc(npc))

func player_epithet(player: CharacterData) -> String:
	return epithet_from(metrics_player(player))

## "Kara Ashpelt the Unbroken"
func full_name(npc: Dictionary) -> String:
	var e = epithet(npc)
	return String(npc.name) + ((" " + e) if e != "" else "")

# ------------------------------------------------------------------ biographies

func epitaph(npc: Dictionary) -> String:
	var ep: Dictionary = cfg().get("epitaphs", {})
	for t in npc.get("traits", []):
		if ep.has(t):
			return String(ep[t])
	return String(ep.get("default", ""))

## A short generated biography (BBCode).
func bio(player: CharacterData, npc: Dictionary) -> String:
	var t := "[b][font_size=18]%s[/font_size][/b]\n" % full_name(npc)
	t += "[color=gray]%s %s, %s-Rank, level %d. Joined %s.[/color]\n" % [npc.race, npc.cls, npc.rank, int(npc.level), date_for(int(npc.get("joined_day", 1)))]
	match String(npc.status):
		"dead": t += "[color=#ff9f6b]Fell %s. %s[/color]\n" % [date_for(int(npc.get("died_day", 1))), epitaph(npc)]
		"retired": t += "[color=#9fb4ff]Retired.[/color]\n"
	var c = DramaManager.company_of(player, npc)
	if not c.is_empty():
		t += "Of %s. " % c.name
	var p = DramaManager.partner_of(player, npc)
	if not p.is_empty():
		t += "Together with %s. " % p.name
	var rels = RelationsManager.relations_of(player, npc).filter(func(r): return r.status != "")
	if not rels.is_empty():
		t += "; ".join(rels.slice(0, 3).map(func(r): return "%s %s" % [{"sworn": "Sworn to", "friends": "Friends with", "rivals": "Rival of", "feud": "Feuding with"}[r.status], r.npc.name])) + "."
	t += "\n\n"
	var mine = about(player, MemoryManager.key_npc(npc))
	if mine.is_empty():
		t += "[i]The Chronicle has little to say about them yet.[/i]\n"
	for e in mine.slice(max(0, mine.size() - 12)):
		t += "[color=gray]%s[/color]  %s\n" % [date_for(int(e.day)), e.text]
	return t
