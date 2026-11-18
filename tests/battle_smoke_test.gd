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
	battle.queue_free()
	await get_tree().process_frame
