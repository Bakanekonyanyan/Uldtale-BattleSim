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
