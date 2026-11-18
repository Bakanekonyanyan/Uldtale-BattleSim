# res://scripts/autoload/BlacksmithManager.gd
# Blacksmith rules (no UI): upgrading gear and salvaging it for ore.
# Tuning lives in data/blacksmith.json; the per-level stat gain is
# Equipment.UPGRADE_STEP. Design: docs/design/TOWN_SERVICES.md section 5.
#
# Upgrade attempt to level L:
#   base cost   gold = max(min_gold, value x gold_per_level x L)
#               ore x L (tier by L) + wood (weapons) + monster core (L >= core_from_level)
#   reinforce   each step pays +25% of the base cost (gold and materials) for +10% success
#   success     table by L (100% up to +3), + Tempered bonus, capped at 100%
#   failure     payment lost; Tempered +1; items at +7 or higher drop one level
extends Node

var cfg: Dictionary = {}

func _ready():
	_load()

func _load() -> void:
	var file = FileAccess.open("res://data/blacksmith.json", FileAccess.READ)
	if file == null:
		push_error("BlacksmithManager: data/blacksmith.json not found")
		return
	var data = JSON.parse_string(file.get_as_text())
	cfg = data if data is Dictionary else {}

# === GEAR LISTING ===

## All gear the player owns: [{item, where: "equipped"/"pack"/"stash", slot}]
func list_gear(player: CharacterData) -> Array:
	var gear: Array = []
	for slot in player.equipment:
		var item = player.equipment[slot]
		if item is Equipment:
			gear.append({"item": item, "where": "equipped", "slot": slot})
	for container in [["pack", player.inventory], ["stash", player.stash]]:
		for key in container[1].items:
			var item = container[1].items[key].item
			if item is Equipment:
				gear.append({"item": item, "where": container[0], "slot": key})
	return gear

func is_equipped(player: CharacterData, item: Equipment) -> bool:
	return item in player.equipment.values()

# === UPGRADES ===

func get_max_level(item: Equipment) -> int:
	return int(cfg.get("max_level", {}).get(item.rarity, 3))

func can_upgrade(item: Equipment) -> bool:
	return item.upgrade_level < get_max_level(item)

## Base success chance for reaching `target_level` (no reinforcement/tempered).
func get_base_chance(target_level: int) -> float:
	return float(cfg.get("success_chance", {}).get(str(target_level), 1.0))

func get_success_chance(item: Equipment, steps: int = 0) -> float:
	var target = item.upgrade_level + 1
	var chance = get_base_chance(target)
	chance += steps * float(cfg.get("reinforce_step_bonus", 0.10))
	chance += item.tempered * float(cfg.get("tempered_bonus", 0.05))
	return min(1.0, chance)

## Fewest reinforcement steps that make the next attempt certain.
func steps_to_guarantee(item: Equipment) -> int:
	var steps := 0
	while get_success_chance(item, steps) < 1.0 and steps < 20:
		steps += 1
	return steps

## Cost of one attempt at the next level with `steps` reinforcement steps.
## Returns {"gold": int, "materials": {id: qty}}.
func get_upgrade_cost(item: Equipment, steps: int = 0) -> Dictionary:
	var target = item.upgrade_level + 1
	var mult = 1.0 + steps * float(cfg.get("reinforce_step_cost", 0.25))
	var base_gold = max(int(cfg.get("min_gold", 10)), int(round(item.value * float(cfg.get("gold_per_level", 0.25)) * target)))
	var mats := {}
	mats[_ore_for_level(target)] = target
	if item.is_weapon():
		for id in cfg.get("weapon_extra_materials", {}):
			mats[id] = mats.get(id, 0) + int(cfg.weapon_extra_materials[id])
	if target >= int(cfg.get("core_from_level", 6)):
		mats["monster_core"] = mats.get("monster_core", 0) + 1
	for id in mats:
		mats[id] = int(ceil(mats[id] * mult))
	return {"gold": int(ceil(base_gold * mult)), "materials": mats}

func can_afford(player: CharacterData, cost: Dictionary) -> bool:
	if player.currency.copper < cost.gold:
		return false
	for id in cost.materials:
		if player.count_owned(id) < cost.materials[id]:
			return false
	return true

## One upgrade attempt. Returns {"ok", "success", "reason", "level", "chance"}.
func upgrade(player: CharacterData, item: Equipment, steps: int = 0) -> Dictionary:
	if not can_upgrade(item):
		return {"ok": false, "success": false, "reason": "%s is already at its maximum (+%d)." % [item.get_base_name(), get_max_level(item)], "level": item.upgrade_level}
	var cost = get_upgrade_cost(item, steps)
	if not can_afford(player, cost):
		return {"ok": false, "success": false, "reason": "Not enough money or materials.", "level": item.upgrade_level}

	var chance = get_success_chance(item, steps)
	player.currency.subtract(cost.gold)
	for id in cost.materials:
		player.take_owned(id, cost.materials[id])

	var success = RandomManager.randf() < chance
	var reason: String
	if success:
		item.tempered = 0
		item.set_upgrade_level(item.upgrade_level + 1)
		reason = "Success! %s is now +%d." % [item.get_base_name(), item.upgrade_level]
	else:
		item.tempered += 1
		reason = "The upgrade failed (%d%% chance). The materials are lost." % int(round(chance * 100))
		if item.upgrade_level >= int(cfg.get("downgrade_from_level", 7)):
			item.set_upgrade_level(item.upgrade_level - 1)
			reason += " The item weakened to +%d." % item.upgrade_level
		reason += " Tempered: +%d%% on the next try." % int(round(item.tempered * float(cfg.get("tempered_bonus", 0.05)) * 100))

	GameEvents.item_upgraded.emit(item, item.upgrade_level, success)
	return {"ok": true, "success": success, "reason": reason, "level": item.upgrade_level, "chance": chance}

# === SALVAGE ===

## What salvaging would give: {"ore_id", "ore_min", "ore_max", "core_chance"}
func get_salvage_preview(item: Equipment) -> Dictionary:
	var table: Dictionary = cfg.get("salvage", {}).get(item.rarity, {"ore": [1, 1], "core_chance": 0.0})
	return {
		"ore_id": _ore_for_item_level(item.item_level),
		"ore_min": int(table.ore[0]),
		"ore_max": int(table.ore[1]),
		"core_chance": float(table.get("core_chance", 0.0))
	}

## Destroy an unequipped item (pack or stash) for materials.
## Returns {"ok", "reason", "materials": {id: qty}}.
func salvage(player: CharacterData, item: Equipment) -> Dictionary:
	if is_equipped(player, item):
		return {"ok": false, "reason": "Unequip %s before salvaging it." % item.display_name, "materials": {}}
	var container: Inventory = null
	if player.inventory.items.has(item.inventory_key) and player.inventory.items[item.inventory_key].item == item:
		container = player.inventory
	elif player.stash.items.has(item.inventory_key) and player.stash.items[item.inventory_key].item == item:
		container = player.stash
	if container == null:
		return {"ok": false, "reason": "That item isn't in your pack or stash.", "materials": {}}

	var preview = get_salvage_preview(item)
	var mats := {}
	mats[preview.ore_id] = RandomManager.randi_range(preview.ore_min, preview.ore_max)
	if preview.core_chance > 0.0 and RandomManager.randf() < preview.core_chance:
		mats["monster_core"] = 1

	container.remove_item(item.inventory_key, 1)
	var parts: PackedStringArray = []
	for id in mats:
		player.add_to_pack(ItemManager.get_item(id), mats[id])
		parts.append("%d x %s" % [mats[id], ItemManager.get_item(id).display_name])
	return {"ok": true, "reason": "Salvaged %s into %s." % [item.display_name, ", ".join(parts)], "materials": mats}

# === INTERNAL ===

func _ore_for_level(target_level: int) -> String:
	for tier in cfg.get("ore_by_target_level", []):
		if target_level <= int(tier.max_level):
			return tier.ore
	return "iron_ore"

func _ore_for_item_level(item_level: int) -> String:
	for tier in cfg.get("salvage_ore_by_item_level", []):
		if item_level <= int(tier.max_item_level):
			return tier.ore
	return "iron_ore"
