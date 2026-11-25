# res://scripts/resources/Backgrounds.gd
# Backgrounds (data/backgrounds.json): who you were before the Guild, chosen at
# character creation. Light, flavourful effects: attributes (once), starting
# money and items, better sale prices, cheaper crafting, how adventurers of
# some traits first take to you, a nudge to your reputation, armour training,
# and how your Legend remembers your youth.
class_name Backgrounds
extends RefCounted

static func cfg() -> Dictionary:
	var d = DataRegistry.get_data("backgrounds")
	return d.get("backgrounds", {}) if d is Dictionary else {}

static func get_bg(id: String) -> Dictionary:
	return cfg().get(id, {})

static func of(player: CharacterData) -> Dictionary:
	return get_bg(String(player.town_state.get("background", ""))) if player else {}

static func fill(text: String, player: CharacterData) -> String:
	var born = Regions.player_birthplace(player) if player else ""
	return text.replace("{birthplace}", born if born != "" else "a nameless town")

## At creation: remember the background, raise attributes, then the start.
static func apply_creation(player: CharacterData, id: String) -> void:
	if get_bg(id).is_empty():
		return
	player.town_state["background"] = id
	var b = get_bg(id)
	for a in b.get("attributes", {}):
		player.set(String(a), int(player.get(String(a))) + int(b.attributes[a]))
	player.calculate_secondary_attributes()
	apply_start(player)

## The start of every game with this character: money, items, reputation, training.
static func apply_start(player: CharacterData) -> void:
	var b = of(player)
	if b.is_empty():
		return
	player.currency.copper = max(0, player.currency.copper + int(b.get("start_copper", 0)))
	for it in b.get("start_items", []):
		var item = ItemManager.get_item(String(it.id))
		if item:
			player.add_to_pack(item, int(it.get("qty", 1)))
	var pts: Dictionary = PersonalityManager._voice_state(player).points
	for a in b.get("reputation", {}):
		pts[a] = int(pts.get(a, 0)) + int(b.reputation[a])
	if int(b.get("training_points", 0)) > 0:
		ArmorTraining.grant_point(player, int(b.training_points))

static func sell_mult(player: CharacterData) -> float:
	return 1.0 + float(of(player).get("sell_bonus", 0.0))

static func craft_mult(player: CharacterData, shop: String) -> float:
	return 1.0 - float(of(player).get("craft_discount", {}).get(shop, 0.0))

## Starting rapport from your background with an adventurer's traits.
static func rapport_for(player: CharacterData, npc: Dictionary) -> int:
	var r := 0
	var rt: Dictionary = of(player).get("rapport_traits", {})
	for t in npc.get("traits", []):
		r += int(rt.get(t, 0))
	return r

## How your Legend remembers your youth ("" if none chosen).
static func youth(player: CharacterData) -> String:
	var b = of(player)
	return fill(String(b.get("legend", "")), player) if not b.is_empty() else ""
