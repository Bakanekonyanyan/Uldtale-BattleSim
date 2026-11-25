# res://scripts/autoload/LegendManager.gd
# Legends (data/chronicle.json "legend"; LIVING_WORLD.md H). When you retire,
# your Chronicle is distilled into a Legend - your story in a mythic voice -
# and kept across worlds in user://legends.json. In later worlds:
#   bards at the Tavern tell past Legends; the Chronicle's Legends tab is the
#   Hall of Legends; new adventurers are sometimes heirs of a legend; a legend's
#   signature weapon can turn up as a relic on a boss floor.
extends Node

var path := "user://legends.json"
var _cache = null

func _ready() -> void:
	GameEvents.floor_cleared.connect(_on_floor_cleared)

func cfg() -> Dictionary:
	return ChronicleManager.cfg().get("legend", {})

# ------------------------------------------------------------------ storage

func all() -> Array:
	if _cache == null:
		_cache = []
		if FileAccess.file_exists(path):
			var f = FileAccess.open(path, FileAccess.READ)
			var d = JSON.parse_string(f.get_as_text()) if f else null
			if d is Dictionary:
				_cache = d.get("legends", [])
	return _cache

func _save() -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"legends": all()}, "\t"))

## Tests point this elsewhere.
func use_path(p: String) -> void:
	path = p
	_cache = null

# ------------------------------------------------------------------ writing

func _season(day: int) -> String:
	return ChronicleManager.date_for(day).get_slice(" of ", 1).get_slice(",", 0)

func _fmt(t: String, v: Dictionary) -> String:
	return t.format(v)

## Your Chronicle in a mythic voice: {name, epithet, race, cls, rank, years, crowns, deepest, story: [lines], companions, rival, relic}.
func write(player: CharacterData) -> Dictionary:
	var c = cfg()
	var ep = ChronicleManager.player_epithet(player)
	var day = WorldClock.day(player)
	var base := {"name": player.name, "race": player.race, "class": player.character_class, "rank": RankManager.display(RankManager.get_rank(player)),
		"birthplace": Regions.describe(Regions.player_birthplace(player)) if Regions.player_birthplace(player) != "" else "a place no one remembers",
		"youth": Backgrounds.youth(player) if Backgrounds.youth(player) != "" else ("born in %s" % (Regions.describe(Regions.player_birthplace(player)) if Regions.player_birthplace(player) != "" else "a place no one remembers")),
		"epithet": ep, "epithet_sp": (" " + ep) if ep != "" else "", "epithet_or_famous": ep if ep != "" else "famous across the land"}
	var story: Array = []
	var joined = int(player.town_state.get("joined_day", 1))
	story.append(_fmt(String(c.get("origin", "")), base.merged({"year": ChronicleManager.year_of(joined), "season": _season(joined)})))
	# the deeds that mattered most, in order
	var mine = ChronicleManager.about(player, "you").duplicate()
	mine.sort_custom(func(a, b): return int(a.imp) > int(b.imp))
	mine = mine.slice(0, int(c.get("max_beats", 8)))
	mine.sort_custom(func(a, b): return int(a.day) < int(b.day))
	for e in mine:
		var text = String(e.text).replace("You are", "%s was" % player.name).replace("You keep", "%s kept" % player.name) \
			.replace("Your ", "%s's " % player.name).replace("You ", "%s " % player.name).replace(" you", " %s" % player.name)
		story.append(_fmt(String(c.get("deed", "{text}")), base.merged({"year": ChronicleManager.year_of(int(e.day)), "season": _season(int(e.day)), "text": text})))
	# a bond and a rival
	var act = AdventurerManager.all_adventurers(player)
	var friend := {}
	var rival := {}
	for n in act:
		if friend.is_empty() or int(n.get("rapport", 0)) > int(friend.get("rapport", 0)):
			friend = n
		if int(n.get("rivalry", 0)) > int(rival.get("rivalry", 0)):
			rival = n
	if not friend.is_empty() and int(friend.get("rapport", 0)) >= 40:
		story.append(_fmt(String(c.get("bond", "")), base.merged({"friend": friend.name})))
	if not rival.is_empty() and int(rival.get("rivalry", 0)) >= 3:
		story.append(_fmt(String(c.get("rival", "")), base.merged({"rival": rival.name})))
	var m = ChronicleManager.metrics_player(player)
	if int(m.crowns) > 0:
		story.append(_fmt(String(c.get("crowns", "")), base.merged({"count": int(m.crowns)})))
	story.append(_fmt(String(c.get("end", "")), base.merged({"year": ChronicleManager.year_of(day)})))
	var relic := {}
	var w = player.equipment.get("main_hand")
	if w is Equipment and String(w.key) != "":
		relic = {"base": String(w.key), "name": "%s's %s" % [String(player.name).get_slice(" ", 0), ItemManager.get_equipment_template(String(w.key)).get("name", w.display_name)]}
	return {"name": player.name, "birthplace": Regions.player_birthplace(player), "epithet": ep, "race": player.race, "class": player.character_class, "rank": base.rank,
		"crowns": int(m.crowns), "deepest": int(m.deepest), "years": ChronicleManager.year_of(day), "story": story,
		"companions": PartyManager.members(player).map(func(n): return {"name": n.name, "race": n.race, "class": n.cls}) + ([{"name": friend.name, "race": friend.race, "class": friend.cls}] if not friend.is_empty() and int(friend.get("rapport", 0)) >= 40 else []),
		"rival": {"name": rival.name, "race": rival.race, "class": rival.cls} if not rival.is_empty() and int(rival.get("rivalry", 0)) >= 3 else {},
		"relic": relic, "written": Time.get_datetime_string_from_system(false, true)}

## Retire: write and keep the Legend, close this story. Returns the Legend.
func retire(player: CharacterData) -> Dictionary:
	var leg = write(player)
	all().append(leg)
	_save()
	player.town_state["retired"] = true
	ChronicleManager.record(player, "%s retired from adventuring. Their Legend is written." % player.name, "chronicle", 10)
	return leg

## Permadeath: you fell. The Legend ends with your death.
func fall(player: CharacterData, location_id := "") -> Dictionary:
	var leg = write(player)
	var ep = String(leg.get("epithet", ""))
	var place = LocationManager.get_display_name(location_id) if location_id != "" else "the depths"
	if not leg.story.is_empty():
		leg.story[leg.story.size() - 1] = String(cfg().get("end_death", "{name} fell in {place}.")).format({"name": player.name,
			"epithet_sp": (" " + ep) if ep != "" else "", "place": place, "rank": leg.rank, "year": ChronicleManager.year_of(WorldClock.day(player))})
	leg["fell"] = true
	all().append(leg)
	_save()
	player.town_state["dead"] = true
	return leg

func legend_text(leg: Dictionary) -> String:
	var t := "[b][font_size=20][color=#ffd166]%s%s[/color][/font_size][/b]\n[color=gray]%s %s, %s. %d year(s) with the Guild.[/color]\n\n" % [
		leg.get("name", "?"), (" " + String(leg.epithet)) if String(leg.get("epithet", "")) != "" else "", leg.get("race", ""), leg.get("class", ""), leg.get("rank", ""), int(leg.get("years", 1))]
	for l in leg.get("story", []):
		t += "%s\n\n" % l
	return t

## The Hall of Legends.
func legends_text() -> String:
	if all().is_empty():
		return "[i]The Hall of Legends is empty. Retire a character (Guild) to write the first Legend - it will be told in every world after.[/i]"
	var t := "[b][font_size=20]The Hall of Legends[/font_size][/b]\n\n"
	var list = all().duplicate()
	list.reverse()
	for leg in list:
		t += legend_text(leg) + "[color=#4a434e]──────────[/color]\n\n"
	return t

# ------------------------------------------------------------------ in later worlds

## A bard's telling (BBCode), or "" if there are no Legends.
func bard_song() -> String:
	if all().is_empty():
		return ""
	var leg: Dictionary = all()[RandomManager.randi() % all().size()]
	var intros: Array = cfg().get("bard_intro", ["Have you heard of {name}{epithet_sp}?"])
	var ep = String(leg.get("epithet", ""))
	var t = "[i]%s[/i]\n\n" % String(intros[RandomManager.randi() % intros.size()]).format({"name": leg.name, "epithet_sp": (" " + ep) if ep != "" else ""})
	var story: Array = leg.get("story", [])
	for l in story.slice(0, min(5, story.size())):
		t += "%s\n\n" % l
	return t

## Maybe make a newly generated adventurer the heir of a legend (or of a legend's companion).
func maybe_heir(npc: Dictionary, player: CharacterData = null) -> void:
	if all().is_empty() or RandomManager.randf() >= float(cfg().get("heir_chance", 0.05)):
		return
	var leg: Dictionary = all()[RandomManager.randi() % all().size()]
	var who: Array = [{"name": leg.name, "race": leg.get("race", "")}] + leg.get("companions", [])
	var anc: Dictionary = who[RandomManager.randi() % who.size()]
	var fam = String(anc.name).get_slice(" ", 1)
	var new_name = "%s %s" % [String(npc.name).get_slice(" ", 0), fam]
	var taken = player != null and AdventurerManager.all_adventurers(player).any(func(n): return String(n.name) == new_name)
	if fam != "" and not taken:
		npc.name = new_name
	if String(anc.get("race", "")) != "":
		npc.race = anc.race
	npc["heir_of"] = String(anc.name)
	npc["heir_legend"] = String(leg.name)
	npc.history.append({"day": 1, "text": "Grew up on stories of %s." % anc.name})

## A relic of a past legend on a boss floor (once per legend per world).
func _on_floor_cleared(_loc: String, fl: int) -> void:
	var p = CharacterManager.get_current_character()
	if p == null or all().is_empty() or RandomManager.randf() >= float(cfg().get("relic_chance", 0.04)):
		return
	var found: Array = p.town_state.get("relics_found", [])
	var open_legs = all().filter(func(l): return not l.get("relic", {}).is_empty() and not String(l.name) in found)
	if open_legs.is_empty():
		return
	var leg: Dictionary = open_legs[RandomManager.randi() % open_legs.size()]
	var item = make_relic(leg, fl)
	if item == null:
		return
	p.inventory.add_item(item, 1)
	found.append(String(leg.name))
	p.town_state["relics_found"] = found
	WorldClock.add_news(p, "Among the boss's hoard you found %s - a relic of %s." % [item.display_name, leg.name], "chronicle")

func make_relic(leg: Dictionary, fl: int) -> Equipment:
	var r: Dictionary = leg.get("relic", {})
	if r.is_empty():
		return null
	var item: Equipment = ItemManager.create_equipment_for_floor(String(r.base), max(1, fl), int(cfg().get("relic_rarity", 4)))
	if item:
		item.display_name = String(r.name)
		item.flavor_text = "Carried by %s%s, long ago." % [leg.name, (" " + String(leg.epithet)) if String(leg.get("epithet", "")) != "" else ""]
	return item

## Something an adventurer might say about the Legends of past worlds ("" if
## nothing this time). Heirs talk about their ancestor more often.
func quote(npc: Dictionary, player: CharacterData = null) -> String:
	if all().is_empty():
		return ""
	var c = cfg()
	var heir = npc.has("heir_of")
	if RandomManager.randf() >= float(c.get("heir_quote_chance" if heir else "quote_chance", 0.2)):
		return ""
	var leg: Dictionary = all()[RandomManager.randi() % all().size()]
	if heir:
		for l in all():
			if String(l.name) == String(npc.get("heir_legend", "")):
				leg = l
	var pool: Array = []
	if heir:
		pool = c.get("heir_quotes", [])
	elif player and String(leg.get("class", "")) == player.character_class:
		pool = c.get("same_class_quotes", [])
	if pool.is_empty():
		pool = c.get("quotes", [])
		if leg.get("relic", {}).is_empty():
			pool = pool.filter(func(q): return not String(q).contains("{relic}"))
	if pool.is_empty():
		return ""
	var ep = String(leg.get("epithet", ""))
	var line = String(pool[RandomManager.randi() % pool.size()]).format({"legend": leg.name, "epithet_sp": (" " + ep) if ep != "" else "",
		"rank": leg.get("rank", ""), "class": leg.get("class", ""), "relic": leg.get("relic", {}).get("name", ""), "ancestor": npc.get("heir_of", "")})
	return "%s: \"%s\"" % [String(npc.name).get_slice(" ", 0), line]

