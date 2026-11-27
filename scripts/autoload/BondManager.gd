# res://scripts/autoload/BondManager.gd
# Bonds and companion opinions (data/bonds.json).
#   Bonds: each rapport tier a companion reaches unlocks a short scene, played
#   the next time you visit the Tavern (npc.bond_seen counts scenes seen). The
#   last tier makes them Bonded and unlocks a duo tech: a Link skill you can use
#   while they fight beside you.
#   Opinions: party members react to your choices by trait (rapport).
extends Node

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("bonds")
	return d if d is Dictionary else {}

func tiers() -> Array:
	return cfg().get("tiers", [])

# === BONDS ===

## Highest tier index `npc`'s rapport reaches (-1 = none).
func tier_reached(npc: Dictionary) -> int:
	var t = tiers()
	var best := -1
	for i in range(t.size()):
		if int(npc.get("rapport", 0)) >= int(t[i].get("rapport", 999)):
			best = i
	return best

func tier_name(npc: Dictionary) -> String:
	var seen = int(npc.get("bond_seen", 0))
	return String(tiers()[seen - 1].get("name", "")) if seen > 0 and seen <= tiers().size() else ""

func is_bonded(npc: Dictionary) -> bool:
	return int(npc.get("bond_seen", 0)) >= tiers().size() and not tiers().is_empty()

## Companions (party members and adventurers in town) with an unseen scene.
func pending(player: CharacterData) -> Array:
	return AdventurerManager.active(player).filter(func(n):
		return tier_reached(n) >= int(n.get("bond_seen", 0)) and (PartyManager.is_member(player, int(n.id)) or AdventurerManager.in_town(n)))

## Play the next scene for `npc`. Returns {"title", "text", "bonded"}.
func play_scene(player: CharacterData, npc: Dictionary) -> Dictionary:
	var seen = int(npc.get("bond_seen", 0))
	if seen > tier_reached(npc) or seen >= tiers().size():
		return {}
	var lines: Array = _scene_lines(npc)
	var text = String(lines[min(seen, lines.size() - 1)]).replace("{name}", String(npc.name))
	npc["bond_seen"] = seen + 1
	var tier = String(tiers()[seen].get("name", ""))
	var bonded = is_bonded(npc)
	AdventurerManager._history(npc, WorldClock.day(player), "Became %s with %s." % [tier.to_lower(), player.name])
	if bonded:
		var duo = duo_data(npc)
		text += "\n\n[color=#ffd166]Duo tech unlocked: %s[/color] - %s" % [duo.get("name", "?"), duo.get("description", "")]
		WorldClock.add_news(player, "%s and %s are now inseparable." % [player.name, npc.name], "adventurer")
	return {"title": "%s - %s" % [npc.name, tier], "text": text, "bonded": bonded}

func _scene_lines(npc: Dictionary) -> Array:
	var scenes: Dictionary = cfg().get("scenes", {})
	for t in npc.get("traits", []):
		if scenes.has(t):
			return scenes[t]
	return scenes.get("default", ["{name} nods at you."])

# === DUO TECHS ===

func duo_data(npc: Dictionary) -> Dictionary:
	return cfg().get("duo_techs", {}).get(String(npc.get("cls", "")), {})

## The duo tech as a Skill the player uses (Link cost via category ULTIMATE).
func duo_skill(npc: Dictionary) -> Skill:
	var d: Dictionary = duo_data(npc).duplicate()
	if d.is_empty():
		return null
	d["category"] = "ULTIMATE"
	d["mp_cost"] = 0
	d["sp_cost"] = 0
	d["cooldown"] = 0
	var s = Skill.create_from_dict(d)
	s.set_meta("duo_partner_id", int(npc.get("id", -1)))
	return s

## Duo techs available in this battle: [{"skill", "partner"}] for each Bonded
## companion fighting (and standing) beside `player`.
func battle_duos(player: CharacterData, heroes: Array) -> Array:
	var out: Array = []
	for h in heroes:
		if h == null or h == player or not h.is_alive():
			continue
		var npc = PartyManager.npc_of(h, player)
		if not npc.is_empty() and is_bonded(npc):
			var s = duo_skill(npc)
			if s:
				out.append({"skill": s, "partner": h})
	return out

# === OPINIONS ===

## React and put the result in the town news (for choices made outside battle).
func react_to_news(player: CharacterData, event: String, times: int = 1) -> void:
	var lines = react(player, event, times)
	if not lines.is_empty():
		WorldClock.add_news(player, " ".join(lines), "party")

## Party members react to `event` (data opinions). Returns log lines.
func react(player: CharacterData, event: String, times: int = 1) -> Array:
	var lines: Array = []
	if player == null or times <= 0:
		return lines
	PersonalityManager.player_event(player, event, times)   # your choices shape how you're seen
	if event in ["boss_win", "challenge_done"]:
		for n in PartyManager.members(player):
			MemoryManager.add(n, "fought_beside", "you")
			MemoryManager.add(player, "fought_beside", MemoryManager.key_npc(n))
	var table: Dictionary = cfg().get("opinions", {}).get(event, {})
	if table.is_empty():
		return lines
	var words: Dictionary = cfg().get("opinion_lines", {})
	for npc in PartyManager.members(player):
		var delta := 0
		for t in npc.get("traits", []):
			delta += int(table.get(t, 0))
		delta *= times
		if delta == 0:
			continue
		AdventurerManager._set_rapport(npc, delta)
		var w = String(words.get("up" if delta > 0 else "down", "{name}"))
		lines.append("%s (%+d rapport)" % [w.replace("{name}", String(npc.name)), delta])
	return lines
