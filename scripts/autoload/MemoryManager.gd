# res://scripts/autoload/MemoryManager.gd
# Consequential memory (data/social.json; docs/design/LIVING_WORLD.md B, G).
# Adventurers - and you - remember what others did:
#   npc.memories / player.town_state["memories"] =
#     [{day, kind, about, w, core, heard_from?}]
#   about: "you" (the player) or "npc:<id>".
# Same kind about the same person adds up (to a cap); non-core memories fade
# each day; the strongest `max_per_holder` are kept. Gossip copies strong
# memories to others at a fraction of their weight, so reputations spread.
# Behaviour hooks: grudges (won't join you, may ambush you), debts (help more,
# carry you home once after a defeat), a nemesis who studies you.
extends Node

func _ready() -> void:
	GameEvents.day_passed.connect(daily)

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("social")
	return d if d is Dictionary else {}

func _m() -> Dictionary:
	return cfg().get("memory", {})

func kind(k: String) -> Dictionary:
	return cfg().get("kinds", {}).get(k, {})

func key_npc(npc: Dictionary) -> String:
	return "npc:%d" % int(npc.get("id", -1))

# ------------------------------------------------------------------ storage

func list(holder) -> Array:
	if holder is CharacterData:
		if not holder.town_state.has("memories"):
			holder.town_state["memories"] = []
		return holder.town_state["memories"]
	if holder is Dictionary:
		if not holder.has("memories"):
			holder["memories"] = []
		return holder["memories"]
	return []

## Remember `k` about `about` ("you" or "npc:<id>"). Returns the memory.
func add(holder, k: String, about: String, day: int = -1, weight_override = null, heard_from := "") -> Dictionary:
	var kd = kind(k)
	if kd.is_empty() or about == "":
		return {}
	var w = float(weight_override) if weight_override != null else float(kd.get("weight", 0))
	# honour: an Honorable adventurer respects the one who beat them fairly
	if k == "beat_me" and holder is Dictionary and "honorable" in holder.get("traits", []):
		w = float(kd.get("honorable_weight", w))
	if day < 0:
		var pl = CharacterManager.get_current_character()
		day = WorldClock.day(pl) if pl else 1
	var mems = list(holder)
	for m in mems:
		if m.kind == k and m.about == about and String(m.get("heard_from", "")) == heard_from:
			var cap = float(kd.get("cap", w * 2))
			m.w = clamp(float(m.w) + w, min(cap, 0.0), max(cap, 0.0)) if cap != 0.0 else float(m.w)
			m.day = day
			m["n"] = int(m.get("n", 1)) + 1
			return m
	var mem := {"day": day, "kind": k, "about": about, "w": w, "core": bool(kd.get("core", false)), "n": 1}
	if heard_from != "":
		mem["heard_from"] = heard_from
	mems.append(mem)
	_trim(mems)
	return mem

func _trim(mems: Array) -> void:
	var cap = int(_m().get("max_per_holder", 20))
	if mems.size() <= cap:
		return
	mems.sort_custom(func(a, b): return (1 if a.core else 0) * 1000 + abs(float(a.w)) > (1 if b.core else 0) * 1000 + abs(float(b.w)))
	mems.resize(cap)

## Sum of memory weights about someone (heard_of included).
func opinion(holder, about: String) -> float:
	var s := 0.0
	for m in list(holder):
		if m.about == about:
			s += float(m.w)
	return s

func about_of(holder, about: String) -> Array:
	return list(holder).filter(func(m): return m.about == about)

# ------------------------------------------------------------------ daily: fading and gossip

func daily(player: CharacterData, day: int) -> void:
	if player == null:
		return
	var fade = 1.0 - float(_m().get("fade_per_day", 0.02))
	var floor_w = float(_m().get("forget_below", 1.0))
	var holders: Array = [player]
	holders.append_array(AdventurerManager.active(player))
	for h in holders:
		var mems = list(h)
		for i in range(mems.size() - 1, -1, -1):
			var m = mems[i]
			if m.core:
				continue
			m.w = float(m.w) * fade
			if abs(float(m.w)) < floor_w:
				mems.remove_at(i)
	gossip(player, day)

## Each day a few adventurers in town pass on a strong memory to someone.
func gossip(player: CharacterData, day: int) -> Array:
	var out: Array = []
	var town = AdventurerManager.active(player).filter(func(n): return AdventurerManager.in_town(n))
	if town.size() < 2:
		return out
	var min_w = float(_m().get("gossip_min_weight", 15))
	for i in range(int(_m().get("gossip_per_day", 2))):
		var teller: Dictionary = town[RandomManager.randi() % town.size()]
		var strong = list(teller).filter(func(m): return abs(float(m.w)) >= min_w and not m.has("heard_from") and m.about != key_npc(teller))
		if strong.is_empty():
			continue
		var mem = strong[RandomManager.randi() % strong.size()]
		var listeners = gossip_listeners(player, teller).filter(func(n): return key_npc(n) != mem.about)
		if listeners.is_empty():
			continue
		var ear: Dictionary = listeners[RandomManager.randi() % listeners.size()]
		var w = float(mem.w) * float(_m().get("gossip_share", 0.3))
		add(ear, mem.kind, mem.about, day, w, key_npc(teller))
		if mem.about == "you":
			AdventurerManager._set_rapport(ear, int(round(w * float(_m().get("heard_rapport_factor", 0.5)))))
		out.append({"teller": teller, "listener": ear, "memory": mem})
	return out

## Who an adventurer gossips with: usually their friends in town, otherwise
## anyone in town.
func gossip_listeners(player: CharacterData, teller: Dictionary) -> Array:
	var friends = RelationsManager.friends(player, teller).filter(func(n): return AdventurerManager.in_town(n))
	if not friends.is_empty() and RandomManager.randf() < 0.75:
		return friends
	return AdventurerManager.active(player).filter(func(n): return AdventurerManager.in_town(n) and n != teller)

# ------------------------------------------------------------------ behaviour hooks

## The strongest grudge memory about you (weight at or below grudge_at), or {}.
func grudge(npc: Dictionary) -> Dictionary:
	var best := {}
	for m in about_of(npc, "you"):
		if kind(m.kind).get("grudge", false) and float(m.w) <= float(_m().get("grudge_at", -20)):
			if best.is_empty() or float(m.w) < float(best.w):
				best = m
	return best

## They owe you (a saved_me / helped_me memory at debt_at, not yet repaid).
func owes_you(npc: Dictionary) -> bool:
	for m in about_of(npc, "you"):
		if m.kind in ["saved_me", "avenged_me"] and float(m.w) >= float(_m().get("debt_at", 20)) and not m.has("heard_from") and not m.get("repaid", false):
			return true
	return false

## Call in a debt: the first adventurer in town who owes you. Marks it repaid.
func call_in_debt(player: CharacterData) -> Dictionary:
	for n in AdventurerManager.active(player):
		if owes_you(n) and String(n.status) in ["idle", "party"]:
			for m in about_of(n, "you"):
				if m.kind in ["saved_me", "avenged_me"] and not m.has("heard_from"):
					m["repaid"] = true
			return n
	return {}

## How many times this adventurer has lost to you (for a nemesis that learns).
func losses_to_you(npc: Dictionary) -> int:
	for m in about_of(npc, "you"):
		if m.kind == "beat_me" and not m.has("heard_from"):
			return int(m.get("n", 1))
	return 0

# ------------------------------------------------------------------ text

func _who(about: String, player: CharacterData) -> String:
	if about == "you":
		return player.name if player else "you"
	if about.begins_with("npc:") and player:
		var n = AdventurerManager.get_npc(player, int(about.substr(4)))
		return String(n.get("name", "someone")) if not n.is_empty() else "someone"
	return about

## One line for a memory ("Kara left them to die - day 34").
func text(m: Dictionary, player: CharacterData, holder_is_player := false) -> String:
	var kd = kind(m.kind)
	var who = _who(m.about, player)
	var t: String
	if holder_is_player:   # your memory of someone: "Kara robbed you"
		t = String(kd.get("text", m.kind)).format({"about": who}).replace("them", "you")
		t = t.substr(0, 1).to_upper() + t.substr(1)
	elif m.about == "you":
		t = String(kd.get("you_text", ""))
	else:
		t = String(kd.get("text", m.kind)).format({"about": who})
	if m.has("heard_from"):
		t = "Heard from %s: %s" % [_who(String(m.heard_from), player), t.substr(0, 1).to_lower() + t.substr(1)]
	return "%s - day %d" % [t, int(m.day)]

## What the Tavern shows about how they remember you: full once you're
## friends, otherwise one hint.
func tavern_text(npc: Dictionary, player: CharacterData) -> String:
	var mems = about_of(npc, "you")
	if mems.is_empty():
		return ""
	if int(npc.get("rapport", 0)) >= int(_m().get("full_view_rapport", 40)):
		mems.sort_custom(func(a, b): return abs(float(a.w)) > abs(float(b.w)))
		var t = "[b]Remembers about you:[/b]\n"
		for m in mems.slice(0, 5):
			t += "  [color=%s]• %s[/color]\n" % ["#7bd389" if float(m.w) > 0 else "#ff9f6b", text(m, player)]
		return t
	var strongest = mems[0]
	for m in mems:
		if abs(float(m.w)) > abs(float(strongest.w)):
			strongest = m
	var hint = String(kind(strongest.kind).get("hint", "")) if not strongest.has("heard_from") else String(cfg().get("heard_hint", ""))
	return ("[i]%s %s.[/i]\n" % [String(npc.name).get_slice(" ", 0), hint]) if hint != "" else ""
