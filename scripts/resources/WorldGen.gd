# res://scripts/resources/WorldGen.gd
# World generation for a new character (data/world.json "prehistory"): before
# you arrive, the Guild lives through its own history - adventurers join,
# level, take jobs, form companies, feud, die, retire, and champions are
# crowned - with the real daily simulation. Nothing in it is about you: while
# town_state.prehistory is set you're left out of the Ledger, invitations,
# scenes that involve you and the Chronicle's "you". Your rivals sign up the
# day you do.
class_name WorldGen
extends RefCounted

static func cfg() -> Dictionary:
	var d = DataRegistry.get_data("world")
	return d.get("prehistory", {}) if d is Dictionary else {}

static func is_prehistory(player: CharacterData) -> bool:
	return player != null and bool(player.town_state.get("prehistory", false))

static func days() -> int:
	return int(cfg().get("days", 224))

## Run the prehistory. `tree` (optional) is awaited every few days so a UI can
## stay responsive; `progress` (optional) gets (day, total, date_text).
static func run(player: CharacterData, tree: SceneTree = null, progress: Callable = Callable(), days_override := -1) -> void:
	var total = days() if days_override < 0 else days_override
	if total <= 0:
		_finish(player)
		return
	player.town_state["prehistory"] = true
	AdventurerManager.state(player)   # the founding roster
	var step = max(1, int(cfg().get("frame_every", 4)))
	for d in range(total):
		WorldClock.advance(player, 1)
		if tree and d % step == 0:
			if progress.is_valid():
				progress.call(d + 1, total, WorldClock.date_text(player))
			await tree.process_frame
	_finish(player)

static func _finish(player: CharacterData) -> void:
	player.town_state.erase("prehistory")
	var day = WorldClock.day(player)
	player.town_state["joined_day"] = day
	# your rivals sign up the same day you do (a returning veteran draws
	# rivals of their own standing)
	var st: Dictionary = AdventurerManager._s("settings")
	var returning = player.town_state.has("returning")
	var lv = st.get("newcomer_level", [1, 3])
	if player.level > int(lv[1]):
		lv = [max(1, player.level - 2), player.level + 1]
	for i in range(int(st.get("rivals_at_start", 2))):
		var npc = AdventurerManager._add(player, AdventurerManager.generate(player, lv, true))
		npc.joined_day = day
		AdventurerManager._history(npc, day, ("Took notice of %s the day they came back to the Guild." if returning else "Signed up with the Guild the same day as %s.") % player.name)
	if returning:
		WorldClock.add_news(player, "%s returned to the Guild after a long time away. Few remember the name." % player.name, "chronicle")
	else:
		WorldClock.add_news(player, "%s signed their name in the Guild's ledger." % player.name, "chronicle")
