# res://scripts/resources/WorldShare.gd
# A new character can start in a new world (WorldGen writes its history) or
# join the world another character lives in. Joining copies that world as it
# stands in their save - the clock, the Guild's adventurers and their bonds,
# the Ledger, the Chronicle, rumours - and leaves behind everything that was
# about *them*: what people remember of them, rapport and rivalries with them,
# their bounties, party, bestiary and so on. Their deeds stay in the
# Chronicle and the Ledger under their name.
#
# It's a copy, not a live link: the two saves go on separately from here.
class_name WorldShare
extends RefCounted

## The parts of town_state that are the world itself.
const WORLD_KEYS := ["world", "adventurers", "ledger", "chronicle", "rumours"]

## Characters whose world can be joined: [{name, level, race, cls, day, date, adventurers}].
static func joinable(exclude := "") -> Array:
	var out: Array = []
	var dir = DirAccess.open(SaveManager.SAVE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var data = _read(f.get_basename())
		var ts: Dictionary = data.get("town", {})
		if String(data.get("name", "")) == exclude or not ts.has("adventurers") or not ts.has("world"):
			continue
		out.append({
			"name": String(data.get("name", f.get_basename())), "level": int(data.get("level", 1)),
			"race": String(data.get("race", "")), "cls": String(data.get("character_class", "")),
			"day": int(ts.world.get("day", 1)), "adventurers": ts.adventurers.get("list", []).size(),
			"fallen": bool(ts.get("dead", false)), "retired": bool(ts.get("retired", false)),
		})
	out.sort_custom(func(a, b): return a.name < b.name)
	return out

static func _read(save_name: String) -> Dictionary:
	var path = SaveManager.get_save_file_path(save_name)
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

## Move `player` into `from_name`'s world. Returns false if there's no such world.
static func join(player: CharacterData, from_name: String) -> bool:
	var src: Dictionary = _read(from_name).get("town", {})
	if not src.has("adventurers") or not src.has("world"):
		return false
	for k in WORLD_KEYS:
		if src.has(k):
			player.town_state[k] = (src[k] as Variant).duplicate(true) if src[k] is Dictionary or src[k] is Array else src[k]
		else:
			player.town_state.erase(k)
	_strip(player, from_name)
	player.town_state["world_from"] = from_name
	player.town_state.erase("world_pending")
	player.town_state["world_ready"] = true
	WorldGen._finish(player)   # your rivals sign up the day you do
	WorldClock.add_news(player, "%s's name is still spoken in the Guild hall." % from_name, "chronicle")
	return true

## Forget what this world knew about its previous "you".
static func _strip(player: CharacterData, old_name: String) -> void:
	var soc: Dictionary = AdventurerManager._s("social")
	var st: Dictionary = player.town_state.get("adventurers", {})
	for key in ["list", "departed"]:
		for npc in st.get(key, []):
			if not npc is Dictionary:
				continue
			# memories of the old you go; memories of each other stay
			if npc.has("memories"):
				npc.memories = npc.memories.filter(func(m): return String(m.get("about", "")) != "you")
			var heart = int(npc.get("heart", 0))
			npc["rapport"] = clamp(AdventurerManager._range(soc.get("start_rapport", [-10, 15])) + heart / 10, -100, 100)
			npc["rivalry"] = 0
			npc["rival"] = false
			npc["nemesis"] = false
			npc["ahead_of_player"] = false
			npc["known_traits"] = []
			npc["chats"] = 0
			npc["bond_seen"] = 0
			for d in ["drank_day", "chat_day", "gift_day"]:
				npc[d] = 0
			if npc.has("personality") and npc.personality is Dictionary:
				npc.personality["stage"] = 0   # arcs were about the old you
	# the Ledger: their deeds keep their name; the standings start you at zero
	var led: Dictionary = player.town_state.get("ledger", {})
	for k in ["bosses", "firsts", "crowns"]:
		led[k] = 0
	led["last"] = {}
	for rec in led.get("crownings", []):
		if String(rec.get("key", "")) == "you":
			rec["key"] = "pc:" + old_name
			rec["is_player"] = false
	# the Chronicle: lines about the old you become lines about them
	for e in player.town_state.get("chronicle", []):
		var who: Array = e.get("who", [])
		if who.has("you"):
			who.erase("you")
			who.append("pc:" + old_name)
			e["text"] = "%s: %s" % [old_name, e.text]
	# town news about the old you would read as news about you
	var news: Array = player.town_state.get("world", {}).get("news", [])
	player.town_state.world["news"] = news.filter(func(n): return not (String(n.get("text", "")).begins_with("You") or String(n.get("text", "")).contains(" you")))
	player.town_state["world"]["event"] = player.town_state.world.get("event", {})
