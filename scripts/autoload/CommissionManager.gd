# res://scripts/autoload/CommissionManager.gd
# Shop commissions (data/commissions.json): the Blacksmith, Alchemist and
# Enchanter each keep one open request for materials. Delivering pays gold and
# raises your standing with that shop; standing tiers give its perks.
# State: player.town_state["commissions"] = {shop: {"active": {...}, "done": n}}
extends Node

func _ready() -> void:
	GameEvents.day_passed.connect(func(p, _d): refresh(p))

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("commissions")
	return d if d is Dictionary else {}

func shops() -> Dictionary:
	return cfg().get("shops", {})

func _state(player: CharacterData) -> Dictionary:
	if not player.town_state.has("commissions"):
		player.town_state["commissions"] = {}
	var s: Dictionary = player.town_state["commissions"]
	for shop in shops():
		if not s.has(shop):
			s[shop] = {"active": {}, "done": 0}
	return s

# === STANDING ===

func done(player: CharacterData, shop: String) -> int:
	return int(_state(player).get(shop, {}).get("done", 0)) if player else 0

## Standing tier index (-1 = none yet).
func tier(player: CharacterData, shop: String) -> int:
	var t: Array = cfg().get("standing_tiers", [])
	var n = done(player, shop)
	var best := -1
	for i in range(t.size()):
		if n >= int(t[i].get("done", 999)):
			best = i
	return best

func tier_name(player: CharacterData, shop: String) -> String:
	var i = tier(player, shop)
	return String(cfg().get("standing_tiers", [])[i].get("name", "")) if i >= 0 else "Stranger"

func perk(player: CharacterData, shop: String, key: String) -> float:
	var i = tier(player, shop)
	return float(cfg().get("standing_tiers", [])[i].get(key, 0.0)) if i >= 0 and player else 0.0

# === REQUESTS ===

## Open new requests where none is active, and expire overdue ones.
func refresh(player: CharacterData) -> void:
	if player == null:
		return
	var today = WorldClock.day(player)
	for shop in shops():
		var st: Dictionary = _state(player)[shop]
		var a: Dictionary = st.active
		if not a.is_empty() and today > int(a.get("due", 0)):
			WorldClock.add_news(player, "The %s gave up waiting for %d %s." % [shops()[shop].get("name", shop), int(a.qty), _item_name(a.item)], "info")
			st.active = {}
		if st.active.is_empty():
			st.active = _new_request(player, shop, today)

func _new_request(player: CharacterData, shop: String, today: int) -> Dictionary:
	var mats: Dictionary = shops()[shop].get("materials", {})
	var deepest = player.max_floor_cleared
	var pool = mats.keys().filter(func(id): return deepest + 1 >= int(mats[id].get("min_floor", 1)))
	if pool.is_empty():
		return {}
	var id = String(pool[RandomManager.randi() % pool.size()])
	var q: Array = mats[id].get("qty", [3, 5])
	var qty = RandomManager.randi_range(int(q[0]), int(q[1]))
	var item = ItemManager.get_item(id)
	var value = int(item.value) if item else 10
	var reward = int(round(max(float(cfg().get("min_reward", 60)), value * qty * float(cfg().get("reward_per_value", 2.5))) * RewardsManager.floor_scale(deepest + 1)))
	return {"item": id, "qty": qty, "due": today + int(cfg().get("deadline_days", 7)), "reward": reward}

func active(player: CharacterData, shop: String) -> Dictionary:
	refresh(player)
	return _state(player)[shop].active

func describe(player: CharacterData, shop: String) -> String:
	var a = active(player, shop)
	if a.is_empty():
		return "No request right now."
	return String(shops()[shop].get("line", "{qty} {item} by day {due}")).format({"qty": int(a.qty), "item": _item_name(a.item), "due": int(a.due)})

func _item_name(id) -> String:
	var it = ItemManager.get_item(String(id))
	return it.display_name if it else String(id)

## Hand in the active request. Returns {"ok", "reason", "tier_up"}.
func deliver(player: CharacterData, shop: String) -> Dictionary:
	var a = active(player, shop)
	if a.is_empty():
		return {"ok": false, "reason": "There's nothing to deliver."}
	if player.count_owned(String(a.item)) < int(a.qty):
		return {"ok": false, "reason": "You need %d %s (you have %d)." % [int(a.qty), _item_name(a.item), player.count_owned(String(a.item))]}
	var before = tier(player, shop)
	player.take_owned(String(a.item), int(a.qty))
	player.currency.add(int(a.reward))
	var st: Dictionary = _state(player)[shop]
	st.done = int(st.done) + 1
	st.active = {}
	var name = String(shops()[shop].get("name", shop))
	var msg = "Delivered! The %s pays you %s." % [name, Currency.format_copper(int(a.reward))]
	var up = tier(player, shop) > before
	if up:
		msg += " Your standing rises to %s." % tier_name(player, shop)
		WorldClock.add_news(player, "You are now %s with the %s." % [tier_name(player, shop).to_lower(), name], "info")
	GameEvents.commission_completed.emit(shop)
	refresh(player)
	return {"ok": true, "reason": msg, "tier_up": up}
