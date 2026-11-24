# res://scripts/autoload/DefeatManager.gd
# Losing a battle (decided in docs/design/GAME_ROADMAP.md section 7): the Guild
# recovers you, and you pay for it.
#   - a gold fee (gold_fee_fraction of the money you carry)
#   - an injury: stat penalties for a few days (Infirmary can treat it)
#   - equipped gear lost to the Guild's Lost & Found (more on a boss fight),
#     bought back for a price scaling with rarity, item level and upgrades,
#     before it expires
# Tuning: data/defeat.json. State lives in player.town_state ("injuries",
# "lost_found") so it saves with the character. Timers count days (WorldClock).
extends Node

var cfg: Dictionary = {}

func _ready():
	var d = DataRegistry.get_data("defeat")
	cfg = d if d is Dictionary else {}
	GameEvents.day_passed.connect(func(player, _day): tick(player))

# ------------------------------------------------------------------ defeat

## Apply every defeat penalty. Returns a summary for the Defeat screen:
## {gold_lost, injury: {id, name, description, expeditions}, items: [{name, rarity, price}]}
func apply_defeat(player: CharacterData, is_boss: bool = false) -> Dictionary:
	var summary := {"gold_lost": 0, "injury": {}, "items": []}
	if player == null:
		return summary
	# someone who owes you carries you home: no fee, no lost gear (MemoryManager debts)
	var saver = MemoryManager.call_in_debt(player)
	if not saver.is_empty():
		summary["rescued_by"] = String(saver.name)
		WorldClock.add_news(player, "%s carried %s home from the depths, repaying an old debt." % [saver.name, player.name], "adventurer")
		AdventurerManager._history(saver, WorldClock.day(player), "Carried %s home, repaying a debt." % player.name)
		summary.injury = add_random_injury(player, is_boss)
		player.status_manager.clear_all_effects() if player.status_manager else null
		player.current_hp = max(1, int(player.max_hp * float(cfg.get("wake_hp_fraction", 0.5))))
		player.current_mp = player.max_mp
		player.current_sp = player.max_sp
		player.calculate_secondary_attributes()
		return summary
	# gold fee
	var fee = int(floor(player.currency.copper * float(cfg.get("gold_fee_fraction", 0.15))))
	if fee > 0:
		player.currency.subtract(fee)
	summary.gold_lost = fee
	# lost gear
	var n = int(cfg.get("items_lost_boss" if is_boss else "items_lost", 1))
	var slots: Array = []
	for slot in player.equipment:
		if player.equipment[slot] is Equipment:
			slots.append(slot)
	for i in range(min(n, slots.size())):
		var slot = slots.pop_at(RandomManager.randi() % slots.size())
		var item: Equipment = player.equipment[slot]
		player.unequip_item(slot)                  # back into the pack...
		_remove_from_pack(player, item)            # ...and out of it: the Guild has it now
		var entry = {"item": SaveManager.equipment_to_save(item), "price": buyback_price(item),
			"expires_in": int(cfg.get("lost_found", {}).get("expires_after_days", 10))}
		_lost_found(player).append(entry)
		summary.items.append({"name": item.display_name, "rarity": item.rarity, "price": entry.price})
	# injury
	summary.injury = add_random_injury(player, is_boss)
	# wake up in town
	player.status_manager.clear_all_effects() if player.status_manager else null
	player.current_hp = max(1, int(player.max_hp * float(cfg.get("wake_hp_fraction", 0.5))))
	player.current_mp = player.max_mp
	player.current_sp = player.max_sp
	player.calculate_secondary_attributes()
	return summary

func _remove_from_pack(player: CharacterData, item: Equipment) -> void:
	for key in player.inventory.items.keys():
		if player.inventory.items[key].item == item:
			player.inventory.remove_item(key, 1)
			return

# ------------------------------------------------------------------ lost & found

func _lost_found(player: CharacterData) -> Array:
	if not player.town_state.has("lost_found"):
		player.town_state["lost_found"] = []
	return player.town_state["lost_found"]

func get_lost_found(player: CharacterData) -> Array:
	return _lost_found(player)

## Buy-back price: value x rarity multiplier x (1 + level_step x item level)
## x (1 + upgrade_step x upgrade level) x price_fraction.
func buyback_price(item: Equipment) -> int:
	var lf: Dictionary = cfg.get("lost_found", {})
	var rarity = float(lf.get("rarity_mult", {}).get(item.rarity, 1.0))
	var lvl = 1.0 + float(lf.get("level_step", 0.08)) * item.item_level
	var upg = 1.0 + float(lf.get("upgrade_step", 0.15)) * item.upgrade_level
	return max(1, int(round(item.value * rarity * lvl * upg * float(lf.get("price_fraction", 0.6)))))

## Buy back entry `index`. Returns {"ok", "reason"}.
func buy_back(player: CharacterData, index: int) -> Dictionary:
	var lf = _lost_found(player)
	if index < 0 or index >= lf.size():
		return {"ok": false, "reason": "That item is no longer here."}
	var entry: Dictionary = lf[index]
	if player.currency.copper < int(entry.price):
		return {"ok": false, "reason": "Buying it back costs %s." % Currency.format_copper(int(entry.price))}
	var item = SaveManager.equipment_from_save(entry.item)
	if item == null:
		return {"ok": false, "reason": "The Guild can't find that item."}
	player.currency.subtract(int(entry.price))
	player.add_to_pack(item, 1)
	lf.remove_at(index)
	return {"ok": true, "reason": "Bought back %s for %s. It's in your pack." % [item.display_name, Currency.format_copper(int(entry.price))]}

# ------------------------------------------------------------------ injuries

func _injuries(player: CharacterData) -> Array:
	if not player.town_state.has("injuries"):
		player.town_state["injuries"] = []
	return player.town_state["injuries"]

func get_injuries(player: CharacterData) -> Array:
	return _injuries(player)

func injury_info(id: String) -> Dictionary:
	return cfg.get("injuries", {}).get(id, {})

func add_random_injury(player: CharacterData, is_boss: bool = false) -> Dictionary:
	var table: Dictionary = cfg.get("injuries", {})
	if table.is_empty():
		return {}
	var total := 0.0
	for id in table:
		total += float(table[id].get("weight", 1))
	var roll = RandomManager.randf() * total
	var pick: String = table.keys()[0]
	for id in table:
		roll -= float(table[id].get("weight", 1))
		if roll <= 0.0:
			pick = id
			break
	var ic: Dictionary = cfg.get("injury", {})
	var exps = int(ic.get("days", 4)) + (int(ic.get("extra_days_boss", 2)) if is_boss else 0)
	var list = _injuries(player)
	for inj in list:
		if inj.id == pick:          # same injury again: it lasts longer
			inj.remaining = int(inj.remaining) + exps
			player.calculate_secondary_attributes()
			return {"id": pick, "name": table[pick].name, "description": table[pick].get("description", ""), "days": inj.remaining}
	list.append({"id": pick, "remaining": exps})
	player.calculate_secondary_attributes()
	return {"id": pick, "name": table[pick].name, "description": table[pick].get("description", ""), "days": exps}

## Summed stat penalties of current injuries ({stat: amount}), read by
## CharacterData.get_all_flat_bonuses.
func injury_stats(player: CharacterData) -> Dictionary:
	var out := {}
	for inj in player.town_state.get("injuries", []):
		var s: Dictionary = injury_info(String(inj.get("id", ""))).get("stats", {})
		for k in s:
			out[k] = out.get(k, 0.0) + float(s[k])
	return out

func treatment_cost(player: CharacterData) -> int:
	return int(cfg.get("injury", {}).get("treatment_copper_per_level", 40)) * player.level * _injuries(player).size()

## Infirmary: cure all injuries for treatment_cost.
func treat(player: CharacterData) -> Dictionary:
	if _injuries(player).is_empty():
		return {"ok": false, "reason": "You have no injuries."}
	var cost = treatment_cost(player)
	if player.currency.copper < cost:
		return {"ok": false, "reason": "Treatment costs %s." % Currency.format_copper(cost)}
	player.currency.subtract(cost)
	_injuries(player).clear()
	player.calculate_secondary_attributes()
	return {"ok": true, "reason": "The Infirmary patches you up for %s." % Currency.format_copper(cost)}

# ------------------------------------------------------------------ time

## Each day (WorldClock): injuries heal a step, Lost & Found items age out.
func tick(player: CharacterData) -> void:
	var inj = _injuries(player)
	for i in range(inj.size() - 1, -1, -1):
		inj[i].remaining = int(inj[i].remaining) - 1
		if int(inj[i].remaining) <= 0:
			inj.remove_at(i)
	var lf = _lost_found(player)
	for i in range(lf.size() - 1, -1, -1):
		lf[i].expires_in = int(lf[i].expires_in) - 1
		if int(lf[i].expires_in) <= 0:
			lf.remove_at(i)            # sold off by the Guild
	player.calculate_secondary_attributes()
