# res://scripts/autoload/EnchantManager.gd
# Enchanter rules (no UI): raise an item one rarity tier and add an
# enchantment's bonus, paid for in gold, materials and (higher tiers) cores.
# Tuning lives in data/enchanting.json. Design: docs/design/TOWN_SERVICES.md.
#
# Enchant attempt (item at rarity R -> next tier T, up to max_rarity):
#   cost      gold = max(min_gold, value x gold_per_value) x tier (uncommon 1 .. epic 4), the enchant's
#             material x cost_by_target[T].materials, monster cores x .cores
#   chance    cost_by_target[T].chance + fail_bonus per earlier failure (Attuned)
#   success   rarity -> T; damage/armor/value rescale like a dropped T item;
#             + the enchant's stat (rolled in the item level's range);
#             weapons with no status effect gain the enchant's weapon_status
#   failure   payment lost, item unchanged, Attuned +1
extends Node

func cfg() -> Dictionary:
	var d = DataRegistry.get_data("enchanting")
	return d if d is Dictionary else {}

func enchants() -> Dictionary:
	var out: Dictionary = {}
	var all: Dictionary = cfg().get("enchants", {})
	for id in all:
		if not String(id).begins_with("_"):
			out[id] = all[id]
	return out

# === RULES ===

func _order() -> Array:
	return cfg().get("rarity_order", ["common", "uncommon", "magic", "rare", "epic", "legendary"])

## The rarity an enchant would raise `item` to, or "" when it can't go higher.
func next_rarity(item: Equipment) -> String:
	var order = _order()
	var i = order.find(item.rarity)
	var cap = order.find(String(cfg().get("max_rarity", "epic")))
	if i < 0 or i >= cap or i + 1 >= order.size():
		return ""
	return order[i + 1]

func can_enchant(item: Equipment) -> bool:
	return item != null and next_rarity(item) != ""

## {"gold": int, "materials": {id: qty}} for enchanting `item` with `enchant_id`.
func get_cost(item: Equipment, enchant_id: String) -> Dictionary:
	var target = next_rarity(item)
	var tier: Dictionary = cfg().get("cost_by_target", {}).get(target, {})
	var e: Dictionary = enchants().get(enchant_id, {})
	var mats := {}
	if e.has("material") and int(tier.get("materials", 0)) > 0:
		mats[String(e.material)] = int(tier.materials)
	if int(tier.get("cores", 0)) > 0:
		mats["monster_core"] = mats.get("monster_core", 0) + int(tier.cores)
	var tier_no = max(1, _order().find(target))   # uncommon 1 ... epic 4
	var gold = max(int(cfg().get("min_gold", 50)) * tier_no, int(round(item.value * float(cfg().get("gold_per_value", 0.5)) * tier_no)))
	gold = int(round(gold * (1.0 - CommissionManager.perk(CharacterManager.get_current_character(), "enchanter", "discount"))
		* Backgrounds.craft_mult(CharacterManager.get_current_character(), "enchanter")))
	return {"gold": gold, "materials": mats}

func get_success_chance(item: Equipment) -> float:
	var tier: Dictionary = cfg().get("cost_by_target", {}).get(next_rarity(item), {})
	var standing = CommissionManager.perk(CharacterManager.get_current_character(), "enchanter", "success")
	return clamp(float(tier.get("chance", 0.5)) + item.enchant_fails * float(cfg().get("fail_bonus", 0.1)) + standing, 0.0, 1.0)

## Stat range the enchant's bonus is rolled in (same as dropped gear).
func stat_range(item: Equipment) -> Vector2i:
	return Vector2i(max(1, int(1 + item.item_level * 0.15)), max(3, int(3 + item.item_level * 0.25)))

## Status a weapon would gain from this enchant (NONE if it already has one).
func weapon_status_for(item: Equipment, enchant_id: String) -> int:
	var st = String(enchants().get(enchant_id, {}).get("weapon_status", ""))
	if not item.is_weapon() or item.status_effect_type != Skill.StatusEffect.NONE or not Skill.StatusEffect.has(st):
		return Skill.StatusEffect.NONE
	return Skill.StatusEffect[st]

## Damage/armor/value multiplier from raising the rarity (EquipmentScaler table).
func rarity_mult(from: String, to: String) -> float:
	var m = EquipmentScaler.RARITY_MULTIPLIERS
	return float(m.get(to, 1.0)) / max(0.01, float(m.get(from, 1.0)))

func can_afford(player: CharacterData, cost: Dictionary) -> bool:
	return BlacksmithManager.can_afford(player, cost)

# === ACTION ===

## One enchant attempt. Returns {"ok", "success", "reason", "chance"}.
func enchant(player: CharacterData, item: Equipment, enchant_id: String) -> Dictionary:
	if not can_enchant(item):
		return {"ok": false, "success": false, "reason": "%s can't be enchanted further." % item.get_base_name()}
	var e: Dictionary = enchants().get(enchant_id, {})
	if e.is_empty():
		return {"ok": false, "success": false, "reason": "Unknown enchantment."}
	var cost = get_cost(item, enchant_id)
	if not can_afford(player, cost):
		return {"ok": false, "success": false, "reason": "Not enough money or materials."}
	var chance = get_success_chance(item)
	player.currency.subtract(cost.gold)
	for id in cost.materials:
		player.take_owned(id, cost.materials[id])
	if RandomManager.randf() >= chance:
		item.enchant_fails += 1
		var msg = "The enchantment fizzled (%d%% chance). The materials are lost, the item is unharmed. Attuned: +%d%% on the next try." % [
			int(round(chance * 100)), int(round(item.enchant_fails * float(cfg().get("fail_bonus", 0.1)) * 100))]
		GameEvents.item_enchanted.emit(item, item.rarity, false)
		return {"ok": true, "success": false, "reason": msg, "chance": chance}
	_apply(player, item, enchant_id)
	GameEvents.item_enchanted.emit(item, item.rarity, true)
	return {"ok": true, "success": true, "chance": chance,
		"reason": "Success! %s is now %s with %s." % [item.get_base_name(), item.rarity.capitalize(), String(e.get("name", enchant_id))]}

func _apply(player: CharacterData, item: Equipment, enchant_id: String) -> void:
	var e: Dictionary = enchants().get(enchant_id, {})
	var worn = player != null and item in player.equipment.values()
	if worn:
		item.remove_stat_modifiers(player)
	var from = item.rarity
	var to = next_rarity(item)
	var mult = rarity_mult(from, to)
	item.ensure_upgrade_base()
	item.base_damage = int(round(item.base_damage * mult))
	item.base_armor = int(round(item.base_armor * mult))
	item.value = int(round(item.value * mult))
	item.rarity = to
	item.set_upgrade_level(item.upgrade_level)   # recompute damage/armor from the new base
	var stat_name = String(e.get("stat", ""))
	if Skill.AttributeTarget.has(stat_name):
		var stat = Skill.AttributeTarget[stat_name]
		var r = stat_range(item)
		item.stat_modifiers[stat] = int(item.stat_modifiers.get(stat, 0)) + RandomManager.randi_range(r.x, r.y)
	var st = weapon_status_for(item, enchant_id)
	if st != Skill.StatusEffect.NONE:
		item.status_effect_type = st
		item.status_effect_chance = min(0.5, 0.1 + item.item_level * 0.005 + 0.05 * _order().find(to))
	item.enchants.append(String(e.get("name", enchant_id)))
	item.enchant_fails = 0
	if worn:
		item.apply_stat_modifiers(player)
		player.calculate_secondary_attributes()
