# res://scripts/autoload/Bestiary.gd
# What the player has learned about each enemy race: which weaknesses are known,
# kills and Breaks. Enemy weaknesses show as "???" until discovered:
#   - a weakness hit reveals that weakness for the race
#   - Breaking an enemy reveals all of its weaknesses ("studied")
#   - Inspect reveals them when the party has a scholar (class or companion
#     trait; data/combat.json "bestiary")
# Only battles the current player fights count (not NPC sims).
# State: player.town_state["bestiary"] = {race: {"weak": [...], "kills": n,
#   "breaks": n, "studied": bool}}
extends Node

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("combat")
	return d.get("bestiary", {}) if d is Dictionary else {}

func enabled() -> bool:
	return bool(cfg().get("enabled", true))

func _player() -> CharacterData:
	return CharacterManager.get_current_character()

## The bestiary dictionary of `player` (current character by default).
func book(player: CharacterData = null) -> Dictionary:
	var p = player if player else _player()
	if p == null:
		return {}
	if not p.town_state.has("bestiary"):
		p.town_state["bestiary"] = {}
	return p.town_state["bestiary"]

func entry(race: String, player: CharacterData = null) -> Dictionary:
	var b = book(player)
	if b.is_empty() and (player if player else _player()) == null:
		return {}
	if not b.has(race):
		b[race] = {"weak": [], "kills": 0, "breaks": 0, "studied": false}
	return b[race]

## Does this battle belong to the player (so discoveries count)?
func tracks(ctx: BattleContext) -> bool:
	return enabled() and ctx != null and ctx.player != null and ctx.player == _player()

# === DISCOVERY ===

func reveal(e: CharacterData, names: Array) -> Array:
	var en = entry(String(e.race))
	var fresh: Array = []
	for n in names:
		if not n in en.weak:
			en.weak.append(n)
			fresh.append(n)
	return fresh

## Reveal everything about `e` (Break, scholar Inspect).
func study(e: CharacterData) -> Array:
	var fresh = reveal(e, BattleRules.weaknesses(e))
	entry(String(e.race)).studied = true
	return fresh

func add_kill(e: CharacterData) -> void:
	entry(String(e.race)).kills += 1

func add_break(e: CharacterData) -> void:
	entry(String(e.race)).breaks += 1

# === DISPLAY ===

## Weaknesses of `e` as shown to the player: known ones, plus "???" while
## any remain unknown. Everything is known when the bestiary is off.
func shown_weaknesses(e: CharacterData) -> Array:
	var all = BattleRules.weaknesses(e)
	if RunState.flag("hide_weaknesses"):   # Omen: Dim Sight
		return ["???"]
	if not enabled() or _player() == null:
		return all
	var en: Dictionary = book().get(String(e.race), {})
	var known: Array = en.get("weak", [])
	var out = all.filter(func(n): return n in known)
	var hidden = all.size() - out.size()
	if hidden > 0 or (all.is_empty() and not en.get("studied", false)):
		out.append("???")
	return out

## Can this party learn an enemy's weaknesses by inspecting it?
func party_can_study(heroes: Array) -> bool:
	var classes: Array = cfg().get("scholar_classes", [])
	var traits: Array = cfg().get("scholar_traits", [])
	var p = _player()
	for h in heroes:
		if h == null:
			continue
		if String(h.character_class) in classes:
			return true
		if p and h != p:
			var npc = PartyManager.npc_of(h, p)
			for t in npc.get("traits", []):
				if String(t) in traits:
					return true
	return false
