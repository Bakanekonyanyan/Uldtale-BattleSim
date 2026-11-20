# res://tests/economy_sim.gd
# Economy model: money and materials in vs out across a career, using the real
# reward and cost functions (RewardsManager, BlacksmithManager, EnchantManager,
# WaveChallenges, RumorManager, CommissionManager, shop prices).
#
#   godot --headless res://tests/economy_sim.tscn -- [--runs=40] [--floors_per_band=5]
#
# For each floor band it rolls `runs` expeditions (2 floors x 6 waves, Press On
# twice then a Breather) and prints:
#   income per expedition and per day, by source
#   the cost of "keeping your gear current" for the band (upgrades to the
#   band's target level on 6 slots + one enchant tier on 3 slots, expected
#   attempts included), potions and other running costs
#   how many expeditions the band's upgrades take, and material in vs needed.
# Assumptions are constants below - change them to model a different player.
extends Node

const BANDS := [1, 4, 8, 12, 16, 20, 25]
const FLOORS_PER_EXPEDITION := 2
const EXPEDITIONS_PER_BAND := 6          # how long a player spends per band
const UPGRADE_TARGET := {1: 3, 4: 3, 8: 5, 12: 6, 16: 7, 20: 8, 25: 8}
const GEAR_SLOTS := 6                    # weapon + 5 armor pieces kept current
const ENCHANT_SLOTS := 3
const POTIONS_PER_EXPEDITION := {"health_potion": 4, "mana_potion": 2}
const CHALLENGE_SUCCESS := 0.5           # share of offered challenges met
const RUMOURS_PER_DAY := 0.25            # rumours acted on
const COMMISSIONS_PER_WEEK := 2.0        # deliveries
const DEFEAT_RATE := 0.15                # expeditions ending in defeat
const CARRIED_GOLD_SHARE := 0.6          # of band income carried when defeated
const PARTY_SHARE := 0.0                 # companions' cut (0 = solo)

var runs := 40

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = String(a).trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and kv[0] == "runs":
			runs = int(kv[1])
	RunState.clear()
	MomentumSystem.reset_momentum()
	print("ECON|band|gold/exp waves|gear sold|mats sold|challenges|rumours|commissions|TOTAL/exp|per day|band income|upgrade cost|enchant cost|running|band cost|ratio|mats in/out")
	for f in BANDS:
		_band(f)
	print("ECON DONE")
	get_tree().quit()

func _band(f: int) -> void:
	var src := {"waves": 0.0, "gear": 0.0, "mats": 0.0, "challenges": 0.0}
	var mat_in := {}
	for r in range(runs):
		for fl in range(f, f + FLOORS_PER_EXPEDITION):
			var momentum := 0
			for wave in range(1, 7):
				EnemyFactory.set_location("the_dungeon")
				var g = EnemyGroup.new()
				g.initialize(fl, wave, wave == 6)
				var rw = RewardsManager.roll_wave_rewards({"current_wave": wave, "current_floor": fl, "is_boss_fight": wave == 6,
					"enemies": g.enemies, "momentum_level": momentum, "player_class": "Paladin"})
				var bonus = 1.0 + MomentumSystem.get_reward_bonus(momentum)
				src.waves += rw.currency * bonus
				for e in rw.equipment_instances:
					src.gear += ShopManager.sell_price(e)
				for k in rw:
					if k in ["currency", "equipment_instances", "xp"]:
						continue
					var it = ItemManager.get_item(k)
					if it and it.item_type == Item.ItemType.MATERIAL:
						mat_in[k] = mat_in.get(k, 0.0) + rw[k] * bonus
					elif it:
						src.mats += int(it.value / 2) * rw[k]   # consumables found: sold
				momentum = 0 if wave == 3 else momentum + 1
				# challenges: offered, met half the time
				var ch_chance = float(WaveChallenges.cfg().get("boss_chance" if wave == 6 else "chance", 0.6))
				var cr = WaveChallenges.roll_reward(fl, wave == 6, g.enemies)
				src.challenges += cr.currency * ch_chance * CHALLENGE_SUCCESS
				for k in cr:
					if not k in ["currency", "equipment_instances"]:
						mat_in[k] = mat_in.get(k, 0.0) + cr[k] * ch_chance * CHALLENGE_SUCCESS
	for k in src:
		src[k] /= runs
	for k in mat_in:
		mat_in[k] /= runs
	# materials beyond what upgrades use are sold (value / 2)
	var days = float(WorldClock.expedition_days("goblin_forest", FLOORS_PER_EXPEDITION, false))
	var rumour = float(RumorManager.cfg().get("reward", {}).get("gold_base", 300)) * RewardsManager.floor_scale(f) * RUMOURS_PER_DAY * days
	var commission = _commission_value(f) * RewardsManager.floor_scale(f) * COMMISSIONS_PER_WEEK / 7.0 * days
	var per_exp = src.waves + src.gear + src.challenges + rumour + commission + src.mats
	per_exp *= 1.0 - PARTY_SHARE
	var band_income = per_exp * EXPEDITIONS_PER_BAND
	# --- costs
	var up = _upgrade_cost(f)
	var en = _enchant_cost(f)
	var potions := 0.0
	var prices: Dictionary = DataRegistry.get_data("shop").get("consumables", {})
	for id in POTIONS_PER_EXPEDITION:
		potions += float(prices.get(id, 25)) * POTIONS_PER_EXPEDITION[id]
	var defeat = DEFEAT_RATE * float(DataRegistry.get_data("defeat").get("gold_fee_fraction", 0.15)) * band_income * CARRIED_GOLD_SHARE
	var running = potions * EXPEDITIONS_PER_BAND + defeat
	var band_cost = up.gold + en.gold + running
	# materials: inflow over the band vs what the band's upgrades/enchants need
	var need: Dictionary = up.materials.duplicate()
	for k in en.materials:
		need[k] = need.get(k, 0.0) + en.materials[k]
	var mat_line: Array = []
	for k in need:
		mat_line.append("%s %d/%d" % [k, int(mat_in.get(k, 0.0) * EXPEDITIONS_PER_BAND), int(need[k])])
	var spare := 0.0
	for k in mat_in:
		var it = ItemManager.get_item(k)
		var left = mat_in[k] * EXPEDITIONS_PER_BAND - need.get(k, 0.0)
		if it and left > 0:
			spare += left * int(it.value / 2)
	print("ECON|F%d-%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%.2f|%s" % [f, f + FLOORS_PER_EXPEDITION * EXPEDITIONS_PER_BAND / 2, src.waves, src.gear, src.mats, src.challenges, rumour, commission,
		per_exp, per_exp / days, band_income, up.gold, en.gold, running, band_cost, band_income / max(1.0, band_cost), ", ".join(mat_line)])
	print("ECON SPARE|F%d|unused materials worth %d if sold" % [f, spare])

func _rep_item(f: int, weapon: bool, armor_type := "") -> Equipment:
	var id = ItemManager.get_random_weapon() if weapon else ItemManager.get_random_armor(armor_type)
	var e: Equipment = ItemManager.create_equipment_for_floor(id, f, 2)
	e.rarity = "rare" if f >= 8 else ("magic" if f >= 4 else "uncommon")
	return e

## Expected gold and materials to take GEAR_SLOTS items from +0 to the band's
## target (1 / success chance attempts per level; no reinforcement).
func _upgrade_cost(f: int) -> Dictionary:
	var gold := 0.0
	var mats := {}
	var target = UPGRADE_TARGET.get(f, 3)
	var kinds = [[true, ""], [false, "plate"], [false, "mail"], [false, "leather"], [false, "cloth"], [false, "leather"]]
	for i in range(GEAR_SLOTS):
		var k = kinds[i % kinds.size()]
		var e = _rep_item(f, k[0], k[1])
		var cap = min(target, BlacksmithManager.get_max_level(e))
		for lvl in range(cap):
			e.upgrade_level = lvl
			var tries = 1.0 / max(0.05, BlacksmithManager.get_success_chance(e, 0))
			var c = BlacksmithManager.get_upgrade_cost(e, 0)
			gold += c.gold * tries
			for m in c.materials:
				mats[m] = mats.get(m, 0.0) + c.materials[m] * tries
	return {"gold": gold, "materials": mats}

## One enchant tier on ENCHANT_SLOTS items (expected attempts included).
func _enchant_cost(f: int) -> Dictionary:
	var gold := 0.0
	var mats := {}
	for i in range(ENCHANT_SLOTS):
		var e = _rep_item(f, i == 0)
		if not EnchantManager.can_enchant(e):
			continue
		var tries = 1.0 / max(0.05, EnchantManager.get_success_chance(e))
		var c = EnchantManager.get_cost(e, "ember")
		gold += c.gold * tries
		for m in c.materials:
			mats[m] = mats.get(m, 0.0) + c.materials[m] * tries
	return {"gold": gold, "materials": mats}

func _commission_value(f: int) -> float:
	var cfg = CommissionManager.cfg()
	var total := 0.0
	var n := 0
	for shop in cfg.get("shops", {}):
		for id in cfg.shops[shop].get("materials", {}):
			var m: Dictionary = cfg.shops[shop].materials[id]
			if f + 1 < int(m.get("min_floor", 1)):
				continue
			var q: Array = m.get("qty", [3, 5])
			var it = ItemManager.get_item(id)
			var val = int(it.value) if it else 10
			total += max(float(cfg.get("min_reward", 60)), val * (q[0] + q[1]) / 2.0 * float(cfg.get("reward_per_value", 2.5)))
			n += 1
	return total / max(1, n)
