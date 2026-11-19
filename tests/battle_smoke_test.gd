# res://tests/battle_smoke_test.gd
# Headless smoke test for the battle system: unit checks for past bugs plus
# full auto-played battles through Battle.tscn.
# Run:  godot --headless res://tests/battle_smoke_test.tscn   (exit code 0 = pass)
extends Node
# Headless smoke test for the refactored battle system.
# 1) Unit-style checks for each bug fix.
# 2) Plays full battles through Battle.tscn with an auto-pilot player.

var failures: Array[String] = []
var passes := 0
var kills_seen := 0  # GameEvents.enemy_killed count

func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("PASS: ", label)
	else:
		failures.append(label)
		print("FAIL: ", label)

func make_player(hp_override: int = -1) -> CharacterData:
	var p = CharacterFactory.create_character("Hero", "Hume", "Paladin", true)
	if hp_override == -2:  # strong hero for victory runs
		p.vitality += 200; p.strength += 400; p.dexterity += 100; p.agility += 200
		p.calculate_secondary_attributes()
		hp_override = -1
	p.current_hp = p.max_hp if hp_override < 0 else hp_override
	p.current_mp = p.max_mp
	p.current_sp = p.max_sp
	return p

func _ready():
	Engine.time_scale = 25.0
	await get_tree().process_frame
	_unit_checks()
	_phase0_checks()
	GameEvents.enemy_killed.connect(func(_e, _loc, _f, _b): kills_seen += 1)
	await _battle_run("single enemy", 1, false, -1)
	await _battle_run("three enemies", 3, false, -1)
	await _battle_run("boss", 1, true, -1)
	await _battle_run("forced defeat", 2, false, 1)
	await _battle_run("victory vs three", 3, false, -2)
	await _battle_run("victory vs boss", 1, true, -2)
	print("SMOKE RESULT: %d passed, %d failed" % [passes, failures.size()])
	for f in failures:
		print("  FAILED -> ", f)
	get_tree().quit(1 if failures.size() > 0 else 0)

# ------------------------------------------------------------------ unit checks

func _unit_checks() -> void:
	# Reflection applied exactly once
	var a = make_player(); var d = make_player()
	a.name = "Attacker"; d.name = "Defender"
	d.apply_status_effect(Skill.StatusEffect.REFLECT, 3)
	var refl = d.status_manager.get_total_reflection()
	var hp_before = a.current_hp
	var engine = CombatEngine.new()
	var info = engine._track_reflection_damage(a, d, 100.0)
	check(a.current_hp == hp_before, "reflection prediction does not apply damage")
	d.take_damage(100.0, a)
	check(hp_before - a.current_hp == int(100 * refl) and info.amount == int(100 * refl),
		"reflection applied exactly once (%d expected %d)" % [hp_before - a.current_hp, int(100 * refl)])
	# Status damage (no attacker) must not reflect to stale last_attacker
	hp_before = a.current_hp
	d.take_damage(50.0)
	check(a.current_hp == hp_before, "attacker-less damage does not reflect to last_attacker")

	# Skill costs stay 0 for unused resource
	var any_bad := false
	for skill_name in a.skills:
		var s: Skill = a.get_skill_instance(skill_name)
		if (s.base_mp_cost == 0 and s.mp_cost != 0) or (s.base_sp_cost == 0 and s.sp_cost != 0):
			any_bad = true
	check(not any_bad and a.skills.size() > 0, "skill costs not forced to 1 when base cost is 0")

	# TurnQueue does not leak metadata, rounds advance
	var p = make_player()
	var e1 = EnemyFactory.create_enemy(1, 1, 1)
	var e2 = EnemyFactory.create_enemy(1, 1, 1)
	var q = TurnQueue.new()
	var enemies: Array[CharacterData] = [e1, e2]
	q.initialize(p, enemies)
	for i in range(7):
		q.advance()
	check(not p.has_meta("_turn_this_round"), "TurnQueue keeps round state off CharacterData")
	check(q.round_number == 3, "TurnQueue rounds advance after everyone acts (round=%d)" % q.round_number)
	e1.current_hp = 0
	check(q.current_actor() != e1 and q.queue.size() == 2, "TurnQueue drops dead combatants")

	# Breather clears status for real
	p.apply_status_effect(Skill.StatusEffect.POISON, 3)
	p.status_manager.clear_all_effects()
	check(p.status_effects.is_empty(), "status_manager.clear_all_effects clears effects")

	# BossAI phase 3 keeps its buff
	var boss = EnemyFactory.create_boss(1, 1, 0)
	var ai = BossAI.new()
	ai.initialize(boss, p, 1)
	boss.apply_debuff(Skill.AttributeTarget.STRENGTH, 5, 3)
	boss.current_hp = int(boss.max_hp * 0.2)
	ai._check_phase_transition()
	check(boss.buff_manager.has_buffs() and not boss.buff_manager.has_debuffs(),
		"BossAI phase 3 clears debuffs and keeps its new buff")

	# Enemy AI uses the enemy's own skill instances
	var e3 = EnemyFactory.create_enemy(1, 1, 1)
	var ai2 = EnemyAI.new(); ai2.initialize(e3, p, 1)
	var uses_instances := true
	for s in ai2._get_damage_skills():
		if s != e3.get_skill_instance(s.name):
			uses_instances = false
	check(uses_instances, "EnemyAI picks the enemy's own skill instances")

	# Party prep: AI picks a target from a hero list (works with 1..N heroes)
	var h1 = make_player(); var h2 = make_player(); var h3 = make_player()
	h2.current_hp = 5
	var ai3 = EnemyAI.new(); ai3.initialize(e3, [h1, h2, h3], 1)
	ai3.intelligence = 1.0
	check(ai3.choose_target() == h2, "smart enemy focuses the most wounded hero")
	h2.current_hp = 0
	var picks := {}
	ai3.intelligence = 0.0
	for i in range(30): picks[ai3.choose_target()] = true
	check(not picks.has(h2) and picks.size() == 2, "AI never targets a dead hero and spreads attacks when not focusing")
	var ai_solo = EnemyAI.new(); ai_solo.initialize(e3, func(): return [p], 1)
	var solo_action = ai_solo.decide_action()
	check(solo_action != null and (solo_action.targets.is_empty() or p in solo_action.targets or e3 in solo_action.targets),
		"single-hero behaviour unchanged (targets the player)")
	
	# Defend wears off at the start of the defender's next turn
	var ctx = BattleContext.new(); ctx.player = p; ctx.enemies = enemies
	var tsp = TurnStartProcessor.new()
	p.defend()
	tsp.context = ctx
	tsp.combat_engine = CombatEngine.new()
	check(p.is_defending, "defend sets stance")
	p.reset_defense()
	check(not p.is_defending, "reset_defense clears stance (called by TurnStartProcessor.run)")

# ------------------------------------------------------------------ phase 0 (locations, drops, carry limit, saves)

func _phase0_checks() -> void:
	# Gear "spell_power" bonuses (cloth armor) actually raise spell power
	var caster = make_player()
	var sp_before = caster.spell_power
	var robe = Equipment.new({"id": "test_robe", "name": "Test Robe", "type": "cloth", "slot": "chest",
		"armor_value": 1, "rarity": "common", "effects": {"spell_power": 5}})
	robe.effects = {"spell_power": 5}   # strip any rolled extras so the check is exact
	robe.stat_modifiers = {}
	robe.attribute_target = ""
	caster.equipment["chest"] = robe
	caster.calculate_secondary_attributes()
	check(is_equal_approx(caster.spell_power, sp_before + 5), "gear spell_power bonus applies (%.1f -> %.1f)" % [sp_before, caster.spell_power])
	caster.equipment["chest"] = null
	caster.calculate_secondary_attributes()
	check(is_equal_approx(caster.spell_power, sp_before), "gear spell_power bonus removed on unequip")

	# Armor penetration: gear sets it, recalculation doesn't stack it, physical hits ignore that much defense
	var striker = make_player(); var wall = make_player()
	wall.toughness = 100.0
	var axe = Equipment.new({"id": "test_axe", "name": "Test Axe", "type": "two_handed", "slot": "main_hand",
		"damage": 10, "rarity": "common"})
	axe.effects = {"armor_penetration": 0.2}
	axe.stat_modifiers = {}
	axe.attribute_target = ""
	var plain_hit = BattleFormulas.hit_damage(striker, wall, true)
	striker.equipment["main_hand"] = axe
	striker.calculate_secondary_attributes()
	striker.calculate_secondary_attributes()
	check(is_equal_approx(striker.armor_penetration, 0.2), "armor penetration from gear, not stacked by recalcs (%.2f)" % striker.armor_penetration)
	var expected = (BattleFormulas.physical_offense(striker) * BattleFormulas.BASE_SCALE) * BattleFormulas.mitigation(BattleFormulas.physical_defense(wall) * 0.8)
	check(is_equal_approx(BattleFormulas.hit_damage(striker, wall, true), expected), "physical hit ignores 20 percent of defense")
	check(is_equal_approx(BattleFormulas.hit_damage(striker, wall, false), BattleFormulas.magical_offense(striker) * BattleFormulas.BASE_SCALE * BattleFormulas.mitigation(BattleFormulas.magical_defense(wall))), "armor penetration doesn't affect magic")
	striker.armor_penetration = 5.0
	check(is_equal_approx(BattleFormulas.get_armor_penetration(striker), BattleFormulas.MAX_ARMOR_PENETRATION), "armor penetration capped")
	striker.equipment["main_hand"] = null
	striker.calculate_secondary_attributes()
	check(striker.armor_penetration == 0.0 and plain_hit > 0.0, "armor penetration removed on unequip")
	# Themed location: only that race (regular enemies and boss)
	EnemyFactory.set_location("goblin_forest")
	var all_goblin := true
	for i in range(15):
		if EnemyFactory.create_enemy(1, 1, 1).race != "Goblin": all_goblin = false
	check(all_goblin and EnemyFactory.create_boss(1, 6, 0).race == "Goblin", "Goblin Forest spawns only Goblins (incl. boss)")
	
	# Mixed location: several races
	EnemyFactory.set_location("the_dungeon")
	var seen := {}
	for i in range(40):
		seen[EnemyFactory.create_enemy(1, 1, 1).race] = true
	check(seen.size() >= 3, "The Dungeon mixes races (%s)" % str(seen.keys()))
	
	# Per-location progress
	var p = make_player()
	check(p.get_max_floor("orc_plains") == 1, "new location starts at floor 1")
	p.unlock_floor("orc_plains", 4)
	p.unlock_floor("orc_plains", 2)  # never lowers
	check(p.get_max_floor("orc_plains") == 4 and p.get_max_floor("troll_caves") == 1 and p.max_floor_cleared >= 4,
		"floor progress is tracked per location")
	
	# v1 save migration
	var v1 := {"max_floor_cleared": 7}
	SaveManager._migrate(v1)
	check(v1.location_progress == {"the_dungeon": 7} and v1.save_version == SaveManager.SAVE_VERSION,
		"v1 save progress migrates to The Dungeon")
	
	# Carry limit: pack holds 5 of each consumable, rest to stash; materials unlimited
	var potion = ItemManager.get_item("health_potion")
	var res = p.add_to_pack(potion, 8)
	check(res.pack == 5 and res.stash == 3 and p.inventory.get_quantity("health_potion") == 5 and p.stash.get_quantity("health_potion") >= 3,
		"carry limit: 8 potions -> 5 pack + 3 stash")
	check(p.withdraw_from_stash("health_potion", 2) == 0, "can't withdraw past the carry limit")
	p.add_to_pack(ItemManager.get_item("iron_ore"), 12)
	check(p.inventory.get_quantity("iron_ore") == 12, "materials are not carry-limited")
	p.inventory.add_item(potion, 4)  # simulate an old save with 9 in the pack
	check(p.enforce_carry_limit() == 4 and p.inventory.get_quantity("health_potion") == 5, "enforce_carry_limit moves excess to stash")
	
	# Material drops follow the defeated enemies' race
	EnemyFactory.set_location("troll_caves")
	var trolls: Array[CharacterData] = [EnemyFactory.create_enemy(1, 1, 1), EnemyFactory.create_enemy(1, 1, 1)]
	var troll_mats = ["frostroot_chunk", "wood", "voltslate_pebble"]
	var only_troll := true
	var total := 0
	for i in range(30):
		var drops = RewardsManager.roll_material_drops({"current_floor": 1, "is_boss_fight": false, "enemies": trolls})
		for id in drops:
			total += drops[id]
			if id not in troll_mats: only_troll = false
	check(only_troll and total >= 30 and total <= 60, "Troll waves drop 1-2 Troll materials each (%d over 30 waves)" % total)
	var boss_total := 0
	for i in range(20):
		var drops = RewardsManager.roll_material_drops({"current_floor": 1, "is_boss_fight": true, "enemies": trolls})
		for id in drops: boss_total += drops[id]
	check(boss_total >= 60, "boss waves drop 3+ materials (%d over 20)" % boss_total)
	
	# Save round trip keeps v2 fields
	p.name = "ZZ_SmokeTest_Save"
	p.last_location = "fairy_circles"
	SaveManager.save_game(p)
	var loaded = SaveManager.load_game(p.name)
	SaveManager.delete_character(p.name)
	check(loaded != null and loaded.get_max_floor("orc_plains") == 4 and loaded.last_location == "fairy_circles"
		and loaded.carry_limit == 5 and loaded.inventory.get_quantity("health_potion") == 5,
		"save v2 round trip keeps location progress, last location, carry limit, pack")
	EnemyFactory.set_location("the_dungeon")
	_reward_checks()
	_buff_checks()
	_alchemy_checks()
	_status_modifier_checks()
	_blacksmith_checks()
	_guild_checks()

# ------------------------------------------------------------------ momentum + gear drops

func _reward_checks() -> void:
	# Bonus grows +10% per momentum level and caps at +50%
	check(MomentumSystem.get_reward_bonus(0) == 0.0 and is_equal_approx(MomentumSystem.get_reward_bonus(3), 0.3)
		and MomentumSystem.get_reward_bonus(5) == 0.5 and MomentumSystem.get_reward_bonus(9) == 0.5,
		"momentum reward bonus: +10%/level, capped at +50%")
	
	# Press-On waves are banked and paid out at the Breather with the bonus
	EnemyFactory.set_location("orc_plains")
	var foes: Array[CharacterData] = [EnemyFactory.create_enemy(1, 1, 1)]
	MomentumSystem.clear_accumulated_loot()
	MomentumSystem.bank_rewards({"currency": 100, "equipment_instances": [], "iron_ore": 4})
	MomentumSystem.bank_rewards({"currency": 100, "equipment_instances": [], "iron_ore": 4})
	var data = {"current_wave": 3, "current_floor": 1, "is_boss_fight": false, "enemies": foes, "momentum_level": 5}
	var payout = RewardsManager.calculate_battle_rewards(data)
	var wave_gold = (50 + 3 * 10) * 1
	check(payout.currency == int(round((200 + wave_gold) * 1.5)),
		"Breather pays banked + current gold with +50%% (%d)" % payout.currency)
	check(payout.get("iron_ore", 0) >= 12, "banked materials paid out with bonus (%d iron ore from 8 banked)" % payout.get("iron_ore", 0))
	check(MomentumSystem.momentum_loot_accumulated.currency == 0, "bank is empty after the payout")
	
	# No bonus without momentum
	var plain = RewardsManager.calculate_battle_rewards({"current_wave": 3, "current_floor": 1, "is_boss_fight": false, "enemies": foes, "momentum_level": 0})
	check(plain.currency == wave_gold and RewardsManager.last_momentum_bonus == 0.0, "no momentum = no bonus")
	
	# Enemy gear drops again (multi-enemy waves)
	var gear = ItemManager.create_equipment_for_floor(ItemManager.get_random_weapon(), 1)
	gear.rarity = "rare"
	var wearer = EnemyFactory.create_enemy(1, 1, 1)
	wearer.set_meta("equipped_items", [gear])
	var crowd: Array[CharacterData] = [EnemyFactory.create_enemy(1, 1, 1), wearer]
	var drops := 0
	for i in range(40):
		var r = RewardsManager.roll_wave_rewards({"current_wave": 1, "current_floor": 1, "is_boss_fight": false, "enemies": crowd, "momentum_level": 0})
		if gear in r.equipment_instances: drops += 1
	check(drops >= 20 and drops <= 39, "rare enemy gear drops ~75%% of the time (%d/40)" % drops)
	EnemyFactory.set_location("the_dungeon")

# ------------------------------------------------------------------ buff / debuff rework

func _buff_checks() -> void:
	var p = make_player()
	var clarity: Skill = SkillManager.get_skill("Arcane Clarity").duplicate()
	clarity.use(p, [p])
	var int_buff = p.buff_manager.buffs.get(Skill.AttributeTarget.INTELLIGENCE, {})
	var expected = max(1, int(round(p.intelligence * clarity.power * BattleFormulas.BUFF_PERCENT_PER_POWER)))
	check(int_buff.get("value", 0) == expected, "buff size = power x %.1f%% of base stat (+%d INT)" % [BattleFormulas.BUFF_PERCENT_PER_POWER * 100, expected])
	check(int_buff.get("duration", 0) == clarity.duration + BattleFormulas.BUFF_DURATION_BONUS, "buff duration covers the full listed turns")
	# Each owner turn ticks durations first, then acts: a duration-N buff must
	# still be active when acting on each of the next N turns, then expire.
	var active_turns := 0
	for turn in range(clarity.duration):
		p.buff_manager.update_buffs_and_debuffs()
		if p.buff_manager.buffs.has(Skill.AttributeTarget.INTELLIGENCE): active_turns += 1
	p.buff_manager.update_buffs_and_debuffs()
	check(active_turns == clarity.duration and not p.buff_manager.buffs.has(Skill.AttributeTarget.INTELLIGENCE),
		"a %d-turn buff boosts exactly %d of the owner's turns" % [clarity.duration, active_turns])
	
	var foe = EnemyFactory.create_enemy(1, 1, 1)
	var curse: Skill = SkillManager.get_skill("Curse of Weakness").duplicate()
	var hp_before = foe.current_hp
	var r = curse.use(p, [foe])
	check(foe.current_hp < hp_before and r.damage > 0 and foe.buff_manager.has_debuffs(), "debuff skills also land a hit (%d dmg) and debuff" % r.damage)

# ------------------------------------------------------------------ alchemist

func _alchemy_checks() -> void:
	var p = make_player()
	p.currency.copper = 100
	check(AlchemyManager.is_known(p, "health_potion") and not AlchemyManager.is_known(p, "flame_flask")
		and not AlchemyManager.is_known(p, "ether"), "default recipes known; bought/floor recipes locked")
	
	# Ingredients come from pack first, then stash
	p.inventory.add_item(ItemManager.get_item("glowcap_mushroom"), 3)
	p.stash.add_item(ItemManager.get_item("glowcap_mushroom"), 2)
	p.stash.add_item(ItemManager.get_item("bloodvine_fiber"), 4)
	check(AlchemyManager.max_craftable(p, "health_potion") == 4, "max craftable counts pack + stash")
	var r = AlchemyManager.craft(p, "health_potion", 4)
	check(r.ok and p.inventory.get_quantity("health_potion") == 4 and p.currency.copper == 80
		and p.inventory.get_quantity("glowcap_mushroom") == 0 and p.stash.get_quantity("glowcap_mushroom") == 1
		and p.stash.get_quantity("bloodvine_fiber") == 0, "craft uses pack then stash, charges the fee")
	check(not AlchemyManager.craft(p, "health_potion", 1).ok, "can't craft without materials")
	
	# Output over the carry limit goes to the stash
	p.inventory.add_item(ItemManager.get_item("bogblossom_petal"), 8)
	r = AlchemyManager.craft(p, "antidote_herb", 4)
	check(r.ok and r.made == 8 and p.inventory.get_quantity("antidote_herb") == 5 and p.stash.get_quantity("antidote_herb") == 3,
		"crafted output respects the carry limit (8 -> 5 pack + 3 stash)")
	
	# Fee limits crafting too
	p.currency.copper = 0
	p.inventory.add_item(ItemManager.get_item("glowcap_mushroom"), 1)
	p.inventory.add_item(ItemManager.get_item("bloodvine_fiber"), 1)
	check(AlchemyManager.max_craftable(p, "health_potion") == 0, "no money for the fee = can't craft")
	
	# Buying a recipe book, and it persists through save/load
	check(not AlchemyManager.buy_recipe(p, "flame_flask").ok, "can't buy a recipe without money")
	p.currency.copper = 300
	r = AlchemyManager.buy_recipe(p, "flame_flask")
	check(r.ok and AlchemyManager.is_known(p, "flame_flask") and p.currency.copper == 0, "buy Flame Flask recipe for 300")
	check(not AlchemyManager.buy_recipe(p, "flame_flask").ok, "can't buy a known recipe twice")
	p.max_floor_cleared = 5
	check(AlchemyManager.is_known(p, "ether"), "floor-gated recipe unlocks at floor 5")
	p.name = "ZZ_SmokeTest_Alchemy"
	SaveManager.save_game(p)
	var loaded = SaveManager.load_game(p.name)
	SaveManager.delete_character(p.name)
	check(loaded != null and AlchemyManager.is_known(loaded, "flame_flask") and not AlchemyManager.is_known(loaded, "venom_vial"),
		"known recipes survive save/load")
	
	# Mana potion restores MP only, Stamina SP only, Ether both
	var q = make_player()
	q.current_mp = 0; q.current_sp = 0
	ItemManager.get_item("mana_potion").use(q, [q])
	check(q.current_mp > 0 and q.current_sp == 0, "Mana Potion restores MP only")
	ItemManager.get_item("stamina_potion").use(q, [q])
	check(q.current_sp > 0, "Stamina Potion restores SP")
	q.current_mp = 0; q.current_sp = 0
	ItemManager.get_item("ether").use(q, [q])
	check(q.current_mp > 0 and q.current_sp > 0, "Ether restores MP and SP")
	
	# Craft-only items never drop as random loot
	var dropped_exclusive := false
	for i in range(400):
		if ItemManager.get_random_consumable() in ["greater_health_potion", "ether"]:
			dropped_exclusive = true
	check(not dropped_exclusive, "craft-only potions never drop as random loot")

# ------------------------------------------------------------------ status accuracy/dodge modifiers

func _status_modifier_checks() -> void:
	var p = make_player()
	var acc0 = p.accuracy
	var dodge0 = p.dodge
	p.apply_status_effect(Skill.StatusEffect.BLIND, 3)
	# Blind also has -3 DEX, so accuracy ends up a little under half
	check(p.accuracy <= acc0 * 0.5 + 0.001 and p.accuracy > acc0 * 0.45 and p.dodge < dodge0,
		"Blind halves accuracy and lowers dodge (%.2f -> %.2f; was never applied)" % [acc0, p.accuracy])
	p.remove_status_effect(Skill.StatusEffect.BLIND)
	check(is_equal_approx(p.accuracy, acc0), "accuracy restored when Blind ends")
	p.apply_status_effect(Skill.StatusEffect.EVASIVE, 3)
	check(is_equal_approx(p.dodge, dodge0 + 0.25), "Evasive adds +25% dodge")
	p.remove_status_effect(Skill.StatusEffect.EVASIVE)
	check(is_equal_approx(p.dodge, dodge0), "dodge restored when Evasive ends")
	var evasion: Skill = SkillManager.get_skill("Evasion").duplicate()
	evasion.use(p, [p])
	check(p.has_status_effect(Skill.StatusEffect.EVASIVE), "Myrmidon's Evasion grants Evasive")

# ------------------------------------------------------------------ blacksmith

func _give(p: CharacterData, id: String, qty: int) -> void:
	p.stash.add_item(ItemManager.get_item(id), qty)

func _make_gear(rarity: String, weapon := true) -> Equipment:
	var id = ItemManager.get_random_weapon() if weapon else ItemManager.get_random_armor()
	var e: Equipment = ItemManager.create_equipment_for_floor(id, 1)
	e.rarity = rarity
	e.item_level = 3
	if weapon and e.damage <= 0: e.damage = 12
	if not weapon and e.armor_value <= 0: e.armor_value = 6
	return e

func _blacksmith_checks() -> void:
	var p = make_player()
	var sword = _make_gear("rare")
	var base_dmg = sword.damage
	var base_name = sword.display_name
	sword.set_upgrade_level(3)
	check(sword.damage == int(round(base_dmg * 1.24)) and sword.display_name == "+3 " + base_name,
		"+3 = +24%% damage and '+3' name (%d -> %d)" % [base_dmg, sword.damage])
	sword.set_upgrade_level(0)
	check(sword.damage == base_dmg and sword.display_name == base_name, "upgrade math never compounds (back to base at +0)")
	
	# Cost: gold = value x 0.25 x L, ore x L, +wood for weapons; reinforcement +25%/step
	var c1 = BlacksmithManager.get_upgrade_cost(sword, 0)
	check(c1.gold == max(10, int(round(sword.value * 0.25))) and c1.materials.get("iron_ore", 0) == 1 and c1.materials.get("wood", 0) == 1,
		"+1 costs value x 25%%, 1 iron ore, 1 wood (%s)" % str(c1))
	var c2 = BlacksmithManager.get_upgrade_cost(sword, 2)
	check(c2.gold == int(ceil(c1.gold * 1.5)) and c2.materials.iron_ore == 2, "2 reinforcement steps = +50%% cost (%s)" % str(c2))
	check(BlacksmithManager.get_success_chance(sword, 0) == 1.0, "+1..+3 always succeed")
	sword.set_upgrade_level(3)
	check(is_equal_approx(BlacksmithManager.get_success_chance(sword, 0), 0.9) and BlacksmithManager.steps_to_guarantee(sword) == 1,
		"+4 is 90%, one reinforcement step guarantees it")
	sword.set_upgrade_level(5)
	check(BlacksmithManager.get_upgrade_cost(sword, 0).materials.has("monster_core"), "+6 needs a Monster Core")
	
	# A guaranteed upgrade spends the payment (pack/stash) and levels up
	var armor = _make_gear("uncommon", false)
	p.inventory.add_item(armor, 1)
	p.currency.copper = 1000
	_give(p, "iron_ore", 10)
	var r = BlacksmithManager.upgrade(p, armor, 0)
	check(r.ok and r.success and armor.upgrade_level == 1 and p.count_owned("iron_ore") == 9 and p.currency.copper < 1000,
		"successful upgrade spends ore/gold and gives +1")
	
	# Failure below +7: item kept, Tempered stacks, payment lost
	var mid = _make_gear("legendary")
	mid.set_upgrade_level(4)
	p.currency.copper = 1000000
	_give(p, "mithril_ore", 500); _give(p, "adamant_ore", 500); _give(p, "wood", 500); _give(p, "monster_core", 200)
	var failed_mid := false
	for i in range(60):
		mid.set_upgrade_level(4); mid.tempered = 0
		r = BlacksmithManager.upgrade(p, mid, 0)
		if not r.success:
			failed_mid = mid.upgrade_level == 4 and mid.tempered == 1
			break
	check(failed_mid, "failing +4 -> +5 keeps the item at +4 and adds Tempered")
	check(is_equal_approx(BlacksmithManager.get_success_chance(mid, 0), 0.85), "Tempered adds +5% to the next try")
	
	# Failure at +7 or higher drops a level
	var high = _make_gear("legendary")
	var dropped := false
	for i in range(80):
		high.set_upgrade_level(9); high.tempered = 0
		r = BlacksmithManager.upgrade(p, high, 0)
		if not r.success:
			dropped = high.upgrade_level == 8
			break
	check(dropped, "failing at +9 drops the item to +8")
	high.tempered = 3
	high.set_upgrade_level(1)
	r = BlacksmithManager.upgrade(p, high, 0)
	check(r.success and high.tempered == 0, "Tempered resets after a success")
	var capped = _make_gear("common"); capped.set_upgrade_level(3)
	check(not BlacksmithManager.can_upgrade(capped) and not BlacksmithManager.upgrade(p, capped, 0).ok, "common gear caps at +3")
	
	# Salvage: pack item -> ore by item level; equipped items refused
	var junk = _make_gear("magic")
	p.inventory.add_item(junk, 1)
	var iron_before = p.count_owned("iron_ore")
	r = BlacksmithManager.salvage(p, junk)
	check(r.ok and r.materials.get("iron_ore", 0) >= 3 and p.count_owned("iron_ore") >= iron_before + 3
		and not p.inventory.items.has(junk.inventory_key), "salvaging a magic item gives 3-4 iron ore and removes it")
	var worn = _make_gear("rare")
	p.equipment["main_hand"] = worn
	check(not BlacksmithManager.salvage(p, worn).ok, "can't salvage equipped gear")
	
	# Caster off-hand bonuses now apply, survive recalculation, and scale with upgrades
	var mage = make_player()
	var ward0 = mage.spell_ward
	var tome: Equipment = ItemManager.create_equipment_for_floor("tome", 1)
	mage.equipment["off_hand"] = tome
	tome.apply_effects(mage)
	var tome_ward = tome.get_flat_bonuses().get("spell_ward", 0.0)
	check(tome_ward > 0 and is_equal_approx(mage.spell_ward, ward0 + tome_ward), "equipped Tome adds its Spell Ward (+%.1f) - was never applied" % tome_ward)
	mage.apply_buff(Skill.AttributeTarget.STRENGTH, 2, 3)  # triggers a full recalculation
	check(is_equal_approx(mage.spell_ward, ward0 + tome_ward), "equipment bonus survives stat recalculation")
	tome.set_upgrade_level(3)
	mage.calculate_secondary_attributes()
	check(is_equal_approx(mage.spell_ward, ward0 + tome_ward * 1.24), "upgrading the Tome +3 scales its bonuses by +24%")
	
	# Upgrades survive save/load (pack and equipped), with item level and value
	worn.set_upgrade_level(2)
	worn.tempered = 1
	var worn_dmg = worn.damage
	armor.item_level = 7
	p.name = "ZZ_SmokeTest_Smith"
	SaveManager.save_game(p)
	var loaded = SaveManager.load_game(p.name)
	SaveManager.delete_character(p.name)
	var lw: Equipment = loaded.equipment.get("main_hand") if loaded else null
	var la: Equipment = null
	if loaded:
		for key in loaded.inventory.items:
			if loaded.inventory.items[key].item is Equipment and loaded.inventory.items[key].item.upgrade_level == 1:
				la = loaded.inventory.items[key].item
	check(lw != null and lw.upgrade_level == 2 and lw.damage == worn_dmg and lw.tempered == 1 and lw.display_name.begins_with("+2 "),
		"equipped +2 item survives save/load")
	check(la != null and la.item_level == 7, "pack item keeps upgrade and item level through save/load")
	# One more upgrade after load uses the saved base (no compounding)
	if lw:
		lw.set_upgrade_level(3)
		check(lw.damage == int(round(lw.base_damage * 1.24)), "upgrades after reload use the original base stats")

# ------------------------------------------------------------------ guild bounties

func _bounty(p: CharacterData, tid: String, type: String, target: Dictionary, count: int) -> Dictionary:
	var b = GuildManager._instantiate(tid, p)
	b.type = type; b.target = target; b.count = count; b.progress = 0; b.deadline = 3
	GuildManager.state(p).active.append(b)
	return b

func _guild_checks() -> void:
	var p = make_player()
	p.name = "ZZ_SmokeTest_Guild"
	p.max_floor_cleared = 3
	DungeonStateManager.active_player = p
	var messages: Array = []
	var on_msg = func(t): messages.append(t)
	GuildManager.progress_message.connect(on_msg)
	
	var board = GuildManager.get_board(p)
	var resolved := true
	for b in board:
		if "{" in b.title or b.title == "" or (b.target.has("location") and not LocationManager.has_location(b.target.location)):
			resolved = false
	check(board.size() == 3 and resolved, "board rolls 3 bounties with resolved placeholders (%s)" % ", ".join(board.map(func(b): return b.title)))
	var first_uid = int(board[0].uid)
	check(GuildManager.accept(p, first_uid).ok and GuildManager.get_active(p).size() == 1 and GuildManager.state(p).board.size() == 2,
		"accepting moves a bounty from the board to active")
	GuildManager.state(p).active.clear()
	
	# KILL filters: location + race; class (bosses count for their minion class)
	EnemyFactory.set_location("troll_caves")
	var troll = EnemyFactory.create_enemy(1, 1, 1)
	EnemyFactory.set_location("goblin_forest")
	var goblin = EnemyFactory.create_enemy(1, 1, 1)
	var purge = _bounty(p, "race_purge", "KILL", {"location": "troll_caves", "race": "Troll"}, 2)
	GameEvents.enemy_killed.emit(troll, "troll_caves", 1, false)
	GameEvents.enemy_killed.emit(troll, "the_dungeon", 1, false)   # wrong location
	GameEvents.enemy_killed.emit(goblin, "troll_caves", 1, false)  # wrong race
	check(int(purge.progress) == 1, "KILL counts only the right race at the right location")
	GameEvents.enemy_killed.emit(troll, "troll_caves", 1, false)
	check(GuildManager.is_complete(p, purge) and messages.any(func(m): return "complete" in m), "bounty completes and announces it in the combat log")
	
	var brutes = _bounty(p, "hunt_class", "KILL", {"location": "orc_plains", "class": "Brute"}, 5)
	var king = EnemyFactory.create_enemy(1, 1, 1); king.character_class = "King (Brute)"
	var mage = EnemyFactory.create_enemy(1, 1, 1); mage.character_class = "Mage"
	GameEvents.enemy_killed.emit(king, "orc_plains", 2, true)
	GameEvents.enemy_killed.emit(mage, "orc_plains", 2, false)
	check(int(brutes.progress) == 1, "a Brute King counts for a Brute bounty; a Mage doesn't")
	
	var boss = _bounty(p, "boss_hunt", "KILL_BOSS", {"location": "fairy_circles"}, 1)
	GameEvents.enemy_killed.emit(goblin, "fairy_circles", 2, false)
	check(int(boss.progress) == 0, "KILL_BOSS ignores regular enemies")
	GameEvents.enemy_killed.emit(king, "fairy_circles", 2, true)
	check(GuildManager.is_complete(p, boss), "KILL_BOSS completes on a boss kill at the location")
	
	var depth = _bounty(p, "depth_charge", "CLEAR_FLOOR", {"location": "orc_plains"}, 1)
	depth.floor = 2
	GameEvents.floor_cleared.emit("orc_plains", 1)
	check(int(depth.progress) == 0, "clearing a lower floor doesn't count")
	GameEvents.floor_cleared.emit("orc_plains", 2)
	check(GuildManager.is_complete(p, depth), "CLEAR_FLOOR completes when that floor is cleared")
	
	# Win streak; a Breather (momentum -> 0) resets it
	var streak = _bounty(p, "streak", "WIN_STREAK", {}, 3)
	GameEvents.expedition_started.emit("the_dungeon", 1)
	MomentumSystem.reset_momentum()
	GameEvents.battle_won.emit("the_dungeon", 1, 1, false)
	GameEvents.battle_won.emit("the_dungeon", 1, 2, false)
	MomentumSystem.gain_momentum(); MomentumSystem.reset_momentum()  # Breather
	GameEvents.battle_won.emit("the_dungeon", 1, 3, false)
	check(int(streak.progress) == 2 and not GuildManager.is_complete(p, streak), "a Breather resets the win streak (best %d/3)" % int(streak.progress))
	GameEvents.battle_won.emit("the_dungeon", 1, 4, false)
	GameEvents.battle_won.emit("the_dungeon", 1, 5, false)
	check(GuildManager.is_complete(p, streak), "3 wins in a row completes WIN_STREAK")
	
	# Turn in: gold + GP; DELIVER consumes items from pack/stash
	var gold0 = p.currency.copper
	var gp0 = GuildManager.get_points(p)
	var r = GuildManager.turn_in(p, int(purge.uid))
	check(r.ok and p.currency.copper == gold0 + int(purge.rewards.gold) and GuildManager.get_points(p) == gp0 + int(purge.rewards.points),
		"turn-in pays gold and Guild Points")
	check(not GuildManager.turn_in(p, int(brutes.uid)).ok, "unfinished bounties can't be turned in")
	var deliver = _bounty(p, "supply_run", "DELIVER", {}, 4)
	deliver.item = "wood"
	check(not GuildManager.is_complete(p, deliver), "DELIVER isn't complete without the items")
	p.stash.add_item(ItemManager.get_item("wood"), 5)
	check(GuildManager.turn_in(p, int(deliver.uid)).ok and p.count_owned("wood") == 1, "DELIVER turn-in takes 4 wood from the stash")
	
	# Abandon: fee (no demerit) or demerit
	p.currency.copper = 100000
	var fee = GuildManager.get_abandon_fee(brutes)
	var dem0 = GuildManager.get_demerits(p)
	r = GuildManager.abandon(p, int(brutes.uid), true)
	check(r.ok and p.currency.copper == 100000 - fee and GuildManager.get_demerits(p) == dem0, "abandon with fee: pay 25%% of the gold, no demerit (%d)" % fee)
	var quit_me = _bounty(p, "hunt_class", "KILL", {"location": "orc_plains", "class": "Mage"}, 5)
	GuildManager.state(p).points = 30
	r = GuildManager.abandon(p, int(quit_me.uid), false)
	check(r.ok and GuildManager.get_demerits(p) == dem0 + 1 and GuildManager.get_points(p) == 30 - GuildManager.get_point_penalty(quit_me),
		"abandon without paying: demerit and -50% of its GP")
	
	# Deadlines: 3 expeditions, unfinished bounties fail; finished ones wait
	var late = _bounty(p, "hunt_class", "KILL", {"location": "orc_plains", "class": "Shaman"}, 9)
	var dem1 = GuildManager.get_demerits(p)
	for i in range(3):
		GameEvents.expedition_ended.emit("the_dungeon", true)
	check(not GuildManager.get_active(p).has(late) and GuildManager.get_demerits(p) == dem1 + 1, "missing the 3-expedition deadline fails the bounty with a demerit")
	check(GuildManager.get_active(p).has(boss) and GuildManager.get_active(p).has(depth), "finished bounties don't expire before turn-in")
	check(GuildManager.state(p).board.size() == 3, "the board refreshes after an expedition")
	
	var fee_r = GuildManager.get_reroll_fee(p)
	var c0 = p.currency.copper
	check(GuildManager.reroll_board(p).ok and p.currency.copper == c0 - fee_r, "paid reroll (%d)" % fee_r)
	
	# Save/load keeps guild state
	SaveManager.save_game(p)
	var loaded = SaveManager.load_game(p.name)
	SaveManager.delete_character(p.name)
	check(loaded != null and GuildManager.get_points(loaded) == GuildManager.get_points(p) and GuildManager.get_demerits(loaded) == GuildManager.get_demerits(p)
		and GuildManager.get_active(loaded).size() == GuildManager.get_active(p).size() and GuildManager.state(loaded).board.size() == 3,
		"guild state survives save/load")
	if loaded:
		var lb = GuildManager.get_active(loaded)[0]
		DungeonStateManager.active_player = loaded
		check(GuildManager.is_complete(loaded, lb), "loaded bounties keep their progress")
	
	GuildManager.progress_message.disconnect(on_msg)
	DungeonStateManager.active_player = null
	EnemyFactory.set_location("the_dungeon")

# ------------------------------------------------------------------ full battles

func _battle_run(label: String, enemy_count: int, boss: bool, player_hp: int) -> void:
	print("=== BATTLE: ", label)
	var player = make_player(player_hp)
	var enemies: Array[CharacterData] = []
	if boss:
		enemies.append(EnemyFactory.create_boss(1, 1, 0))
	else:
		for i in range(enemy_count):
			enemies.append(EnemyFactory.create_enemy(1, 1, 1))

	var kills_seen_before := kills_seen
	var battle = load("res://scenes/battle/Battle.tscn").instantiate()
	get_tree().root.add_child(battle)

	var completed := [false, false, 0, 0]  # done, won, xp, count
	battle.battle_completed.connect(func(won, xp):
		completed[0] = true; completed[1] = won; completed[2] = xp; completed[3] += 1)

	battle.set_player(player)
	battle.set_enemies(enemies)
	battle.set_dungeon_info(boss, 1, 1, 5, "Smoke test")

	var defended_turns := 0
	var stale_defense := false
	var actions := 0
	var frames := 0
	while not completed[0] and frames < 60000:
		frames += 1
		await get_tree().process_frame

		# Auto-click the post-battle dialog
		for child in battle.get_children():
			if child.has_signal("take_breather_selected") and not child.has_meta("clicked"):
				child.set_meta("clicked", true)
				child.take_breather_selected.emit()

		if battle.get("_awaiting_player_action") and not battle.get("_action_in_progress") and not battle.context.main_action_taken:
			if player.is_defending:
				stale_defense = true  # defend should have been reset at turn start
			var living = battle.context.get_living_enemies()
			if living.is_empty():
				continue
			var action: BattleAction
			var skill_to_use: Skill = null
			for sn in player.skills:
				var sk: Skill = player.get_skill_instance(sn)
				if sk.type == Skill.SkillType.DAMAGE and player.get_skill_cooldown(sn) == 0 and player.current_sp >= sk.sp_cost and player.current_mp >= sk.mp_cost:
					skill_to_use = sk
			if actions % 4 == 3:
				action = BattleAction.defend(player)
				defended_turns += 1
			elif actions % 4 == 1 and skill_to_use:
				var tg: Array = living if skill_to_use.target == Skill.TargetType.ALL_ENEMIES else [living[0]]
				action = BattleAction.skill(player, skill_to_use, tg)
			else:
				action = BattleAction.attack(player, living[0])
			actions += 1
			battle.ui_controller.action_selected.emit(action)

	check(completed[0], "%s: battle completed (frames=%d, player actions=%d)" % [label, frames, actions])
	check(completed[3] == 1, "%s: battle_completed emitted exactly once (%d)" % [label, completed[3]])
	if player_hp == -2:
		check(completed[1] and completed[2] > 0, "%s: player won with XP reward via breather (xp=%d)" % [label, completed[2]])
	if player_hp == 1:
		check(not completed[1], "%s: player lost" % label)
	else:
		check(completed[1] == player.is_alive(), "%s: result matches player state (won=%s)" % [label, completed[1]])
	check(not stale_defense, "%s: defend stance never carried into the next player turn" % label)
	if completed[1]:
		check(kills_seen_before + enemies.size() == kills_seen,
			"%s: GameEvents.enemy_killed fired once per enemy (%d)" % [label, kills_seen - kills_seen_before])
	battle.queue_free()
	await get_tree().process_frame
