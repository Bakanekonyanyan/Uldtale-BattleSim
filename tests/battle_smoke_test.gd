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
	await _party_battle_run()
	await _encounter_battle_run("saboteur", "mid")
	await _encounter_battle_run("saboteur", "after")
	await _encounter_battle_run("helper", "mid")
	await _levelup_on_breather_check()
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

## Defeat: fee, injury, Lost & Found buy-back, Infirmary (DefeatManager, data/defeat.json)
func _defeat_checks() -> void:
	var p = CharacterFactory.create_character("D", "Hume", "Paladin", true)
	p.level = 5
	p.currency.copper = 10000
	var sword = ItemManager.create_equipment_for_floor("short_sword", 3)
	p.inventory.add_item(sword, 1)
	p.equip_item(sword)
	var hp_full = p.max_hp
	var gear_in_pack = func(id): return p.inventory.items.values().filter(func(e): return e.item is Equipment and e.item.id == id).size()
	var s = DefeatManager.apply_defeat(p, false)
	check(s.gold_lost == 1500 and p.currency.copper == 8500, "defeat costs 15%% of carried money (%d)" % s.gold_lost)
	check(s.items.size() == 1 and p.equipment["main_hand"] == null and gear_in_pack.call("short_sword") == 0, "the equipped item goes to Lost & Found (not the pack)")
	check(not s.injury.is_empty() and DefeatManager.get_injuries(p).size() == 1, "defeat inflicts an injury (%s)" % s.injury.get("name", ""))
	check(p.current_hp > 0 and p.current_hp <= p.max_hp, "you wake in town with HP")
	var price = int(DefeatManager.get_lost_found(p)[0].price)
	check(price > 0 and price == DefeatManager.buyback_price(sword), "buy-back price scales with the item (%d)" % price)
	var r = DefeatManager.buy_back(p, 0)
	check(r.ok and gear_in_pack.call("short_sword") == 1 and DefeatManager.get_lost_found(p).is_empty(), "buy back returns the item to the pack")
	var cost = DefeatManager.treatment_cost(p)
	check(DefeatManager.treat(p).ok and DefeatManager.get_injuries(p).is_empty() and p.currency.copper == 8500 - price - cost, "the Infirmary treats injuries for gold")
	# injuries apply stats and heal over expeditions; unbought gear expires
	DefeatManager.get_injuries(p).append({"id": "cracked_ribs", "remaining": 2})
	p.calculate_secondary_attributes()
	check(p.max_hp < hp_full, "Cracked Ribs lowers max HP (%d -> %d)" % [hp_full, p.max_hp])
	DefeatManager.get_lost_found(p).append({"item": SaveManager.equipment_to_save(sword), "price": 10, "expires_in": 1})
	DefeatManager.tick(p)
	check(DefeatManager.get_injuries(p)[0].remaining == 1 and DefeatManager.get_lost_found(p).is_empty(), "expeditions heal injuries and expire Lost & Found items")
	DefeatManager.tick(p)
	check(DefeatManager.get_injuries(p).is_empty() and p.max_hp == hp_full, "healed: max HP back to normal")
	var boss = CharacterFactory.create_character("D2", "Hume", "Paladin", true)
	for id in ["short_sword", "buckler"]:
		var it = ItemManager.create_equipment_for_floor(id, 1); boss.inventory.add_item(it, 1); boss.equip_item(it)
	check(DefeatManager.apply_defeat(boss, true).items.size() == 2, "boss defeats cost two items")

## Enemy and boss archetypes (data/enemy_archetypes.json, EnemyArchetypes.gd)
func _archetype_checks() -> void:
	EnemyFactory.set_location("troll_caves")
	var arch_ids = EnemyArchetypes.archetypes().keys()
	var all_ok := true
	var seen := {}
	for i in range(30):
		var e = EnemyFactory.create_enemy(1, 4, 1, 0)
		var a = String(e.get_meta("archetype", ""))
		seen[a] = true
		var pools: Dictionary = EnemyArchetypes.get_archetype(a).get("skill_pools", {})
		var allowed: Array = []
		for p in pools: allowed.append_array(pools[p])
		for p in EnemyArchetypes.data().races.Troll.skills: allowed.append_array(EnemyArchetypes.data().races.Troll.skills[p])
		var rolled = e.skills.filter(func(s): return not s in e.talents.talent_skills())
		if not (a in arch_ids and e.character_class == a and rolled.size() >= 2 and rolled.all(func(s): return s in allowed)):
			all_ok = false
			print("  bad archetype enemy: ", a, " ", e.skills)
	check(all_ok, "enemies roll an archetype and skills from its pools (%s)" % ", ".join(seen.keys()))
	check(seen.has("Brute") and not seen.has("Fairy"), "Troll Caves favour Brutes")
	var e2 = EnemyFactory.create_enemy(1, 4, 1, 0)
	check(e2.talents.spent_points() == EnemyArchetypes.enemy_points(4) and e2.talents.tree() != "", "floor-4 enemies spend %d talent points in their hero branch (%s)" % [EnemyArchetypes.enemy_points(4), e2.talents.tree()])
	var shamans = 0
	for i in range(40):
		var s = EnemyFactory.create_enemy(1, 1, 1, 0)
		if s.get_meta("archetype", "") == "Shaman":
			shamans += 1
			check(s.skills.any(func(n): return s.get_skill_instance(n) and s.get_skill_instance(n).type == Skill.SkillType.HEAL), "a Shaman always has a heal")
			break
	var b = EnemyFactory.create_boss(1, 6, 0)
	var sig = String(b.get_meta("boss_signature", ""))
	var ult = String(b.get_meta("boss_ultimate", ""))
	check(b.character_class.begins_with("King (") and sig == "Avalanche Slam" and b.skills.has(sig), "a Troll boss is a King archetype with the Troll signature (%s)" % b.name)
	check(ult != "" and b.skills.has(ult), "bosses learn their branch ultimate (%s)" % ult)
	# HP triggers: signature below 60%, ultimate below 35% (each once)
	var bai = BossAI.new()
	bai.initialize(b, make_player(), 6)
	b.current_hp = int(b.max_hp * 0.5)
	var t1 = bai._try_hp_trigger(0.5)
	check(t1 != null and t1.type == BattleAction.ActionType.CHARGE and String(t1.get_meta("charge_skill", "")) == sig, "below 60% HP the boss charges its signature (a telegraph)")
	check(bai._try_hp_trigger(0.5) == null, "each HP trigger fires once")
	# the charge shows as an intent, then the signature comes out next turn
	var bctx = BattleContext.new()
	var hero_t = make_player()
	bctx.player = hero_t
	bctx.enemies.append(b)
	bctx.is_boss_battle = true
	var beng = CombatEngine.new()
	beng.initialize_multi(hero_t, bctx.enemies)
	beng.execute_action(t1)
	var bplan = EnemyTurnPlanner.new()
	bplan.initialize(bctx)
	bplan.plan_intent(b)
	check(BattleRules.describe_intent(b, bctx.intents).contains("CHARGING"), "the charge is shown as the boss's intent")
	var unleash = bplan.take_intent(b)
	check(unleash != null and unleash.skill_data and unleash.skill_data.name == sig and not b.has_meta("charging"), "next turn the boss unleashes %s" % sig)
	# a Break cancels a charge
	var bq = TurnQueue.new()
	bq.initialize(hero_t, bctx.enemies)
	var brules = BattleRules.new(bctx, bq)
	b.set_meta("charging", sig)
	brules.break_enemy(b)
	check(not b.has_meta("charging") and b.is_stunned and b.get_meta("broken", false), "breaking a charging boss cancels the charge and costs it a turn")
	b.is_stunned = false
	b.set_meta("broken", false)
	b.current_hp = int(b.max_hp * 0.3)
	var t2 = bai._try_hp_trigger(0.3)
	check(t2 != null and String(t2.get_meta("charge_skill", "")) == ult, "below 35%% the boss charges its ultimate (%s)" % ult)
	# AI role: healers mend a hurt ally
	EnemyFactory.force_archetype = "Shaman"
	var healer = EnemyFactory.create_enemy(1, 1, 1, 0)
	EnemyFactory.force_archetype = ""
	healer.set_meta("ai_role", "healer")
	healer.add_skills(["Ancestral Mending"])
	var ally = EnemyFactory.create_enemy(1, 1, 1, 0)
	ally.current_hp = int(ally.max_hp * 0.2)
	var hero = make_player()
	var ai = EnemyAI.new()
	ai.initialize(healer, hero, 1)
	ai.set_allies_source(func(): return [healer, ally])
	ai.target = hero
	var act = ai._try_heal_ally()
	check(act != null and act.skill_data.type == Skill.SkillType.HEAL and (act.targets.is_empty() or act.targets[0] == ally or act.skill_data.target == Skill.TargetType.ALL_ALLIES), "a healer-role enemy heals its wounded ally")
	EnemyFactory.set_location(LocationManager.DEFAULT_LOCATION)

## Adventurer ranks (data/ranks.json, RankManager.gd)
func _rank_checks() -> void:
	var p = make_player()
	p.name = "ZZ_SmokeTest_Rank"
	var prev_active = DungeonStateManager.active_player
	DungeonStateManager.active_player = p
	check(RankManager.get_rank(p) == "F" and RankManager.floor_cap(p) == 5, "new adventurers are F-Rank, floors capped at 5")
	p.location_progress["goblin_forest"] = 9
	check(RankManager.start_floor_limit(p, "goblin_forest") == 5, "the rank cap limits the starting floor (unlocked 9, start <= 5)")
	check(not AlchemyManager.is_known(p, "smoke_bomb"), "rank-gated recipe unknown at F")
	check(not RankManager.start_trial(p).ok, "no promotion trial without the Guild Points")
	var gs = GuildManager.state(p)
	gs.points = 40
	gs.demerits = 3
	check(RankManager.promotion_status(p).trial_state == "demerits" and not RankManager.start_trial(p).ok, "3 demerits block promotion")
	var work = _bounty(p, "hunt_class", "KILL", {}, 1)
	work.progress = 1
	check(GuildManager.turn_in(p, int(work.uid)).ok and GuildManager.get_demerits(p) == 2, "completing a bounty works off a demerit")
	gs.demerits = 0
	gs.points = 40
	check(RankManager.start_trial(p).ok and not RankManager.get_trial(p).is_empty(), "with 40 GP the E-Rank trial can be taken")
	check(GuildManager.active_count(p) == 0, "the trial doesn't use an active-bounty slot")
	var trial = RankManager.get_trial(p)
	for b in GuildManager.get_active(p):   # trials skip the deadline tick
		if b.get("trial", false):
			check(int(b.deadline) == 0, "trials have no deadline")
	EnemyFactory.set_location("goblin_forest")
	var boss = EnemyFactory.create_boss(2, 6, 0)
	GameEvents.enemy_killed.emit(boss, "goblin_forest", 2, true)
	check(not GuildManager.is_complete(p, trial), "a floor-2 boss doesn't satisfy a floor-3+ trial")
	GameEvents.enemy_killed.emit(boss, "orc_plains", 4, true)
	check(not GuildManager.is_complete(p, trial), "a boss elsewhere doesn't count")
	GameEvents.enemy_killed.emit(boss, "goblin_forest", 3, true)
	check(GuildManager.is_complete(p, trial), "the Goblin Forest floor-3 boss completes the trial")
	var money = p.currency.copper
	var r = GuildManager.turn_in(p, int(trial.uid))
	check(r.ok and RankManager.get_rank(p) == "E" and p.currency.copper > money, "turning in the trial promotes to E (%s)" % r.reason)
	check(RankManager.floor_cap(p) == 8 and AlchemyManager.is_known(p, "smoke_bomb"), "E-Rank: floors to 8 and the Smoke Bomb recipe")
	RankManager.promote(p, "D")
	check(p.carry_limit == 10 and GuildManager.board_size(p) == 4, "D-Rank: carry limit 10, 4 bounties on the board")
	GuildManager.refresh_board(p)
	check(GuildManager.get_board(p).size() == 4, "the board posts 4 bounties at D")
	check(not GuildManager.get_board(p).any(func(b): return b.template == "royal_writ"), "C-Rank bounties don't show at D")
	RankManager.promote(p, "A")
	check(RankManager.floor_cap(p) == 0 and not RankManager.is_floor_capped(p, 25), "A-Rank: no floor cap")
	check(not RankManager.promote(p, "C").begins_with("Promoted"), "promotion never lowers your rank")
	DungeonStateManager.active_player = prev_active
	EnemyFactory.set_location(LocationManager.DEFAULT_LOCATION)

## World clock (data/world.json, WorldClock.gd)
func _world_checks() -> void:
	var p = make_player()
	p.name = "ZZ_SmokeTest_World"
	var prev_active = DungeonStateManager.active_player
	DungeonStateManager.active_player = p
	check(WorldClock.day(p) == 1 and "Day 1" in WorldClock.date_text(p), "a new adventurer starts on day 1 (%s)" % WorldClock.date_text(p))
	check(WorldClock.expedition_days("the_dungeon", 1, false) == 1 and WorldClock.expedition_days("goblin_forest", 3, false) == 3
		and WorldClock.expedition_days("goblin_forest", 3, true) == 4, "expeditions cost travel + floors (+1 day after a defeat)")
	# an expedition through the real lifecycle
	DungeonStateManager.start_dungeon(p, 1, "goblin_forest")
	DungeonStateManager.advance_floor()
	DungeonStateManager.end_dungeon(true)
	check(WorldClock.day(p) == 3, "Goblin Forest, 2 floors: 2 days pass (day %d)" % WorldClock.day(p))
	DungeonStateManager.active_player = p
	# daily ticks
	var b = _bounty(p, "hunt_class", "KILL", {"location": "orc_plains", "class": "Brute"}, 9)
	b.deadline = 2
	DefeatManager.get_injuries(p).append({"id": "cracked_ribs", "remaining": 3})
	WorldClock.advance(p, 2, "test")
	check(not GuildManager.get_active(p).has(b), "a 2-day deadline fails after 2 days")
	check(int(DefeatManager.get_injuries(p)[0].remaining) == 1, "injuries heal a day at a time")
	check(WorldClock.get_news(p, 20).any(func(n): return "Bounty failed" in n.text), "failed bounties make the news")
	# Inn
	p.currency.copper = 1000
	p.current_hp = 1
	var day0 = WorldClock.day(p)
	var cost = WorldClock.inn_price(p, 1)
	check(WorldClock.rest(p, 1).ok and WorldClock.day(p) == day0 + 1 and p.currency.copper == 1000 - cost and p.current_hp == p.max_hp,
		"a night at the Inn costs %d copper, passes a day and restores HP" % cost)
	p.currency.copper = 0
	check(not WorldClock.rest(p, 1).ok and WorldClock.day(p) == day0 + 1, "no money, no room")
	# events
	WorldClock.start_event(p, "monster_surge", "troll_caves")
	check(WorldClock.modifier(p, "enemy_power", "troll_caves") > 1.0 and WorldClock.modifier(p, "enemy_power", "orc_plains") == 1.0
		and WorldClock.modifier(p, "reward_mult", "troll_caves") > 1.0, "a Monster Surge strengthens one location and its rewards")
	var before = ShopManager.get_consumable_price("health_potion")
	WorldClock.start_event(p, "harvest_festival")
	check(ShopManager.get_consumable_price("health_potion") < before, "the Harvest Festival lowers potion prices (%d -> %d)" % [before, ShopManager.get_consumable_price("health_potion")])
	WorldClock.advance(p, 5, "test")
	check(WorldClock.current_event(p).is_empty(), "events end after their duration")
	# weekly restock
	ShopManager.equipment_inventory.clear()
	while (WorldClock.day(p) - 1) % WorldClock.days_per_week() != 0:
		WorldClock.advance(p, 1, "")
	check(not ShopManager.equipment_inventory.is_empty(), "the shop restocks at the start of each week (day %d)" % WorldClock.day(p))
	# old-save migration: timers were in expeditions
	var old = make_player()
	old.town_state = {"guild": {"active": [{"uid": 1, "deadline": 3}]}, "injuries": [{"id": "deep_gash", "remaining": 2}]}
	WorldClock.migrate_old_save(old)
	check(int(old.town_state.guild.active[0].deadline) == 6 and int(old.town_state.injuries[0].remaining) == 4, "old saves: expedition timers become days (x2)")
	DungeonStateManager.active_player = prev_active

## NPC adventurers (data/adventurers.json, AdventurerManager.gd, AutoBattler.gd)
func _adventurer_checks() -> void:
	var p = make_player()
	p.name = "ZZ_SmokeTest_Npc"
	var prev_active = DungeonStateManager.active_player
	DungeonStateManager.active_player = p
	var roster = AdventurerManager.active(p)
	var names := {}
	var traits_ok := true
	for n in roster:
		names[n.name] = true
		for a in n.traits:
			for b in n.traits:
				if a != b and b in AdventurerManager.trait_data(a).get("exclusive", []):
					traits_ok = false
		if n.traits.size() < 2 or abs(int(n.honor)) > 100 or abs(int(n.heart)) > 100:
			traits_ok = false
	check(roster.size() >= 15 and roster.size() <= 17 and names.size() == roster.size(), "a fresh guild of %d uniquely named adventurers" % roster.size())
	check(traits_ok, "every adventurer has 2-3 compatible traits and Honor/Heart in range")
	check(roster.filter(func(n): return "Rival" in AdventurerManager.tags(n)).size() == 2, "two rivals at the start")
	# social
	var npc: Dictionary = roster[0]
	npc.status = "idle"
	var r0 = int(npc.rapport)
	var c = AdventurerManager.chat(p, int(npc.id))
	check(c.ok and int(npc.rapport) > r0 and npc.known_traits.size() == 1, "chatting raises rapport and reveals a trait (%s)" % c.reason)
	check(not AdventurerManager.chat(p, int(npc.id)).ok, "one chat per adventurer per day")
	p.currency.copper = 1000
	var r1 = int(npc.rapport)
	check(AdventurerManager.drink(p, int(npc.id)).ok and p.currency.copper == 1000 - AdventurerManager.drink_price(p) and int(npc.rapport) > r1, "buying a drink costs money and raises rapport")
	p.add_to_pack(ItemManager.get_item("health_potion"), 2)
	var key = ""
	for k in p.inventory.items:
		if p.inventory.items[k].item.id == "health_potion":
			key = k
	var r2 = int(npc.rapport)
	check(AdventurerManager.gift(p, int(npc.id), key).ok and p.inventory.get_quantity("health_potion") == 1 and int(npc.rapport) > r2, "a gift leaves your pack and raises rapport")
	var away: Dictionary = roster[1]
	away.status = "job"
	away.job = {"kind": "job", "location": "the_dungeon", "floor": 1, "ends": 99}
	check(not AdventurerManager.chat(p, int(away.id)).ok, "you can't chat with someone out on a job")
	# a real battle (big moment) leaves the global state as it was
	EnemyFactory.set_location("orc_plains")
	var hero = AutoBattler.build_hero({"name": "Test", "race": "Hume", "cls": "Paladin", "level": 8, "gear_floor": 4, "branch": 0})
	check(hero.level == 8 and hero.equipment["main_hand"] != null and hero.talents.spent_points() > 0, "NPC heroes are built with level, gear and talents")
	var fr = AutoBattler.fight_floor(hero, "troll_caves", 2, true)
	check(fr.has("won") and int(fr.turns) > 0 and EnemyFactory.current_location == "orc_plains", "a real boss battle runs headless (won=%s, %d turns) and restores the location" % [fr.won, int(fr.turns)])
	EnemyFactory.set_location(LocationManager.DEFAULT_LOCATION)
	# fates
	var saved_f = AdventurerManager.cfg.fates.duplicate()
	AdventurerManager.cfg.fates.death_chance = 100.0   # certain, whatever their traits
	var doomed: Dictionary = roster[2]
	AdventurerManager._fate(p, doomed, WorldClock.day(p), false, "The Dungeon", 1)
	check(doomed.status == "dead" and not AdventurerManager.is_active(doomed), "a fatal failure kills the adventurer")
	AdventurerManager.cfg.fates.death_chance = 0.0
	AdventurerManager.cfg.fates.retire_chance = 0.0
	var hurt: Dictionary = roster[3]
	AdventurerManager._fate(p, hurt, WorldClock.day(p), false, "The Dungeon", 1)
	check(hurt.status == "injured" and int(hurt.injured_until) > WorldClock.day(p), "otherwise they come back injured")
	AdventurerManager.cfg.fates = saved_f
	# competition: never takes the last bounty
	GuildManager.refresh_board(p)
	var saved_j = AdventurerManager.cfg.jobs.duplicate()
	AdventurerManager.cfg.jobs.take_chance = 1.0
	AdventurerManager.cfg.jobs.compete_chance = 100.0
	AdventurerManager.cfg.jobs.trial_chance = 0.0
	for n in AdventurerManager.active(p):
		if n.status == "idle":
			AdventurerManager._maybe_start(p, n, WorldClock.day(p))
	check(GuildManager.state(p).board.size() == 1, "adventurers take bounties off your board but leave the last one")
	AdventurerManager.cfg.jobs = saved_j
	# days pass: jobs resolve, the roster stays in range
	WorldClock.advance(p, 20, "test")
	var n_active = AdventurerManager.active(p).size()
	var did = AdventurerManager.all_adventurers(p).reduce(func(acc, n): return acc + int(n.record.jobs), 0)
	check(did > 0 and n_active >= 14 and n_active <= 20, "20 days later: %d jobs done, %d adventurers active" % [did, n_active])
	# your promotion makes rivals jealous
	var rival = AdventurerManager.active(p).filter(func(n): return n.get("rival", false) and AdventurerManager.has_trait_flag(n, "rival"))
	if not rival.is_empty():
		var rv0 = int(rival[0].rivalry)
		RankManager.promote(p, "B")
		check(int(rival[0].rivalry) > rv0 or RankManager.rank_index(String(rival[0].rank)) > RankManager.rank_index("B"), "your promotion deepens a rivalry")
	DungeonStateManager.active_player = prev_active

## Party and recruiting (PartyManager.gd)
func _party_checks() -> void:
	var p = make_player()
	p.name = "ZZ_SmokeTest_Party"
	p.level = 6
	var prev_active = DungeonStateManager.active_player
	DungeonStateManager.active_player = p
	var pool = AdventurerManager.active(p)
	var a: Dictionary = pool[0]
	var b: Dictionary = pool[1]
	var c: Dictionary = pool[2]
	for n in [a, b, c]:
		n.status = "idle"
		n.rapport = 50
	check(PartyManager.slots(p) == 0 and not PartyManager.recruit(p, int(a.id)).ok, "F-Rank: no companions yet")
	RankManager.promote(p, "D")
	check(PartyManager.slots(p) == 1, "D-Rank opens one party slot")
	b.rapport = 10
	check(not PartyManager.recruit(p, int(b.id)).ok, "strangers won't join (rapport below Friend)")
	var r = PartyManager.recruit(p, int(a.id))
	check(r.ok and a.status == "party" and int(a.level) >= 6, "a Friend joins and levels with you (%s)" % r.reason)
	check(not PartyManager.recruit(p, int(c.id)).ok, "the party is full at D-Rank")
	RankManager.promote(p, "B")
	check(PartyManager.recruit(p, int(c.id)).ok and PartyManager.members(p).size() == 2, "B-Rank: two companions")
	# expedition: built as battle characters sharing your pack
	DungeonStateManager.start_dungeon(p, 1, "the_dungeon")
	check(PartyManager.allies.size() == 2 and PartyManager.allies[0].inventory == p.inventory and PartyManager.allies[0].level >= 6, "companions come along with your level and share your pack")
	var rewards = {"currency": 1000, "equipment_instances": []}
	var cut = PartyManager.take_share(p, rewards)
	check(cut > 0 and int(rewards.currency) == 1000 - cut, "they take their share of the gold (%d of 1000)" % cut)
	# a knock-out costs rapport and leaves them hurt
	var rap_a = int(a.rapport)
	var rap_c = int(c.rapport)
	PartyManager.on_hero_knocked_out(PartyManager.allies[0])
	DungeonStateManager.end_dungeon(true)
	check(int(a.injured_until) > WorldClock.day(p) and int(a.rapport) < rap_a + 3, "a knocked-out companion comes back hurt and less happy")
	check(int(c.rapport) > rap_c, "a good expedition raises rapport (%d -> %d)" % [rap_c, int(c.rapport)])
	# unhappy companions may leave
	var saved = PartyManager.cfg.duplicate()
	PartyManager.cfg.leave_chance = 100.0
	c.rapport = 5
	DungeonStateManager.active_player = p
	DungeonStateManager.start_dungeon(p, 1, "the_dungeon")
	DungeonStateManager.end_dungeon(false)
	check(not PartyManager.is_member(p, int(c.id)) or c.status == "dead", "an unhappy companion walks away")
	PartyManager.cfg = saved
	check(PartyManager.dismiss(p, int(a.id)).ok and a.status == "idle" and PartyManager.members(p).is_empty() or PartyManager.members(p).size() <= 1, "dismissing sends them back to the Guild")
	DungeonStateManager.active_player = prev_active

## Revival skills and encounter rules
func _revive_and_encounter_checks() -> void:
	for pair in [["Cleric", "Dawn's Return"], ["Druid", "Rebirth"], ["Kannagi", "Spirit Recall"]]:
		var m = CharacterFactory.create_character("M", "Hume", pair[0], true)
		check(m.skills.has(pair[1]), "%s starts with %s" % pair)
	var healer = CharacterFactory.create_character("Healer", "Hume", "Cleric", true)
	healer.current_mp = healer.max_mp
	var fallen = CharacterFactory.create_character("Fallen", "Hume", "Berserker", true)
	var foe = EnemyFactory.create_enemy(1, 1, 1)
	var engine = CombatEngine.new()
	var foes: Array[CharacterData] = [foe]
	var mates: Array[CharacterData] = [fallen]
	engine.initialize_multi(healer, foes, mates)
	var q = TurnQueue.new()
	q.initialize(healer, foes, mates)
	fallen.current_hp = 0
	q.remove(fallen)
	var res = engine.execute_action(BattleAction.skill(healer, healer.get_skill_instance("Dawn's Return"), [fallen]))
	check(res.success and fallen.current_hp > 0 and fallen.current_hp <= int(fallen.max_hp * 0.5), "Dawn's Return raises a knocked-out ally (%d HP)" % fallen.current_hp)
	check(q.rejoin_revived().has(fallen) and fallen in q.all_combatants, "the revived ally rejoins the turn order")
	var ctx = BattleContext.new()
	ctx.player = healer; ctx.allies = mates; ctx.enemies = foes
	fallen.current_hp = 0
	healer.skill_manager.clear_cooldowns()
	healer.current_mp = 999   # a level-1 Cleric can't yet afford Dawn's Return
	var ai_act = AutoBattler.hero_policy(healer, ctx)
	check(ai_act != null and ai_act.skill_data and ai_act.skill_data.type == Skill.SkillType.REVIVE, "the hero AI revives a fallen ally")
	# encounter rolls pick the right people
	var p = make_player()
	p.name = "ZZ_SmokeTest_Enc"
	DungeonStateManager.active_player = p
	var roster = AdventurerManager.active(p)
	for n in roster:
		n.status = "idle"; n.rapport = 0
	roster[0].rapport = 60
	roster[1].rapport = -50
	if not roster[1].traits.has("greedy"):
		roster[1].traits.append("greedy")
	var bd = {"player_character": p, "current_wave": 3, "is_boss_fight": false}
	var h = EncounterManager.roll(bd, "helper")
	check(h.get("type", "") == "helper" and AdventurerManager.get_npc(p, int(h.npc_id)).rapport >= 20, "helpers are friends (rapport 20+)")
	var sab = EncounterManager.roll(bd, "saboteur")
	var sab_npc = AdventurerManager.get_npc(p, int(sab.get("npc_id", -1)))
	check(sab.get("type", "") == "saboteur" and (int(sab_npc.rapport) <= -10 or "Rival" in AdventurerManager.tags(sab_npc)), "saboteurs are schemers who dislike you, or rivals")
	MomentumSystem.momentum_loot_accumulated.currency = 0
	check(EncounterManager.roll(bd, "rival_theft").is_empty(), "no theft without banked loot")
	# wounded: give a potion
	p.add_to_pack(ItemManager.get_item("health_potion"), 1)
	EncounterManager.auto_choice = "give"
	var w = {"type": "wounded", "npc_id": int(roster[2].id), "location": "the_dungeon"}
	var r0 = int(roster[2].rapport)
	await EncounterManager.begin(w, p, self)
	check(p.inventory.get_quantity("health_potion") == 0 and int(roster[2].rapport) > r0, "giving a wounded adventurer a potion earns rapport")
	# theft: let it go loses the loot
	MomentumSystem.momentum_loot_accumulated.currency = 1000
	EncounterManager.auto_choice = "let_go"
	await EncounterManager.begin({"type": "rival_theft", "npc_id": int(roster[1].id), "location": "the_dungeon"}, p, self)
	check(int(MomentumSystem.momentum_loot_accumulated.currency) < 1000 and int(MomentumSystem.momentum_loot_accumulated.currency) >= 500, "a rival steals part of your banked loot (%d left)" % int(MomentumSystem.momentum_loot_accumulated.currency))
	MomentumSystem.clear_accumulated_loot()
	EncounterManager.auto_choice = ""

## A real Battle.tscn wave with an encounter: someone joins mid-battle or
## after the wave's enemies fall.
func _encounter_battle_run(type: String, mode: String) -> void:
	print("=== BATTLE: encounter ", type, " ", mode)
	var player = make_player(-2)
	player.name = "ZZ_SmokeTest_EncB"
	DungeonStateManager.active_player = player
	var npc: Dictionary = AdventurerManager.active(player)[0]
	npc.status = "idle"
	var enemies: Array[CharacterData] = [EnemyFactory.create_enemy(1, 1, 2), EnemyFactory.create_enemy(1, 1, 2)]
	var battle = load("res://scenes/battle/Battle.tscn").instantiate()
	get_tree().root.add_child(battle)
	var done := [false, false]
	battle.battle_completed.connect(func(won, _xp): done[0] = true; done[1] = won)
	battle.set_player(player)
	battle.set_enemies(enemies)
	battle.set_encounter({"type": type, "npc_id": int(npc.id), "location": "the_dungeon", "mode": mode, "round": 2})
	battle.set_dungeon_info(false, 2, 1, 5, "Encounter smoke test")
	var frames := 0
	var joined_at_round := -1
	var n0 = enemies.size()
	while not done[0] and frames < 90000:
		frames += 1
		await get_tree().process_frame
		for child in battle.get_children():
			if child.has_signal("take_breather_selected") and not child.has_meta("clicked"):
				child.set_meta("clicked", true)
				child.take_breather_selected.emit()
		if joined_at_round < 0 and battle.get("_encounter_joined") and not battle._encounter_joined.is_empty():
			joined_at_round = battle.turn_queue.round_number
		if battle.get("_awaiting_player_action") and not battle.get("_action_in_progress") and not battle.context.main_action_taken:
			var living = battle.context.get_living_enemies()
			if living.is_empty():
				continue
			battle.ui_controller.action_selected.emit(BattleAction.attack(battle.ui_controller.player, living[0]))
	check(done[0], "%s/%s: battle completed (frames=%d)" % [type, mode, frames])
	check(joined_at_round >= 0, "%s/%s: they joined the fight (round %d)" % [type, mode, joined_at_round])
	if type == "saboteur":
		check(battle.context.enemies.size() == n0 + 1, "%s/%s: the saboteur fought on the enemy side" % [type, mode])
		if done[1]:
			check(npc.status == "injured" and int(npc.rivalry) > 0, "%s/%s: a beaten saboteur limps off injured" % [type, mode])
	else:
		check(battle.context.allies.size() == 1 and battle.context.allies[0].has_meta("npc_id"), "helper/mid: they fought on your side")
	battle.queue_free()
	await get_tree().process_frame

## The Breather reward screen shows the level-up screen when XP levels you.
func _levelup_on_breather_check() -> void:
	var p = make_player(-2)
	p.name = "ZZ_SmokeTest_Lvl"
	var lv = p.level
	var rs = load("res://scenes/RewardScene.tscn").instantiate()
	rs.set_player_character(p)
	rs.set_rewards({"currency": 10, "equipment_instances": []})
	rs.set_xp_gained(LevelSystem.calculate_xp_for_level(p.level) + 5)
	get_tree().root.add_child(rs)
	await get_tree().process_frame
	var watcher := [false]
	var timer = get_tree().create_timer(0.5)
	timer.timeout.connect(func():
		for n in rs.find_children("*", "Control", true, false):
			if n.has_signal("level_up_complete"):
				watcher[0] = true
				n.level_up_complete.emit())
	await rs._add_auto_rewards()
	check(p.level > lv and watcher[0], "a Breather level-up shows the level-up screen (level %d -> %d)" % [lv, p.level])
	rs.queue_free()
	await get_tree().process_frame

## Characters must be freed once nothing uses them (docs/CODE_AUDIT.md L1/L2).
func _leak_checks() -> void:
	var refs: Array = []
	for i in 20:
		refs.append(weakref(EnemyFactory.create_enemy(1, 3, 2)))
	for i in 5:
		refs.append(weakref(AutoBattler.build_hero({"name": "T", "race": "Hume", "cls": "Cleric", "level": 6, "gear_floor": 3, "branch": 0})))
	var a = EnemyFactory.create_enemy(1, 2, 1)
	var b = CharacterFactory.create_character("B", "Hume", "Paladin", true)
	a.last_attacker = b
	b.last_attacker = a
	refs.append(weakref(a)); refs.append(weakref(b))
	a = null; b = null
	var alive = refs.filter(func(w): return w.get_ref() != null).size()
	check(alive == 0, "released enemies, heroes and duelling pairs are freed (%d of %d still alive)" % [alive, refs.size()])
	var hb = AutoBattler.build_hero({"name": "T", "race": "Hume", "cls": "Paladin", "level": 6, "gear_floor": 3, "branch": 0})
	var foes: Array[CharacterData] = [EnemyFactory.create_enemy(1, 2, 3), EnemyFactory.create_enemy(1, 2, 3)]
	var wrefs = [weakref(hb), weakref(foes[0]), weakref(foes[1])]
	AutoBattler.fight(hb, foes, 2, false)
	hb = null
	foes = []
	check(wrefs.all(func(w): return w.get_ref() == null), "a full battle with intents, breaks and Link leaves nothing behind")
	var e = EnemyFactory.create_enemy(1, 1, 1)
	check(e.status_manager.character == e and e.talents.character == e, "managers still reach their character through the weak reference")

## DataRegistry: each data file parsed once and shared; reload re-reads it.
func _data_registry_checks() -> void:
	var a = DataRegistry.get_data("classes")
	check(a is Dictionary and a.has("playable") and is_same(a, DataRegistry.get_data("classes")) and is_same(a, EnemyFactory.classes), "classes.json is parsed once and shared")
	DataRegistry.reload("combos")
	check(Combos.all().size() > 0, "a reloaded file is read again on next use")
	var src = ""
	for f in ["res://scripts/autoload/EnemyFactory.gd", "res://scripts/factories/CharacterFactory.gd", "res://scripts/autoload/ItemManager.gd", "res://scripts/resources/TalentManager.gd"]:
		src += FileAccess.get_file_as_string(f)
	check(not src.contains("FileAccess.open(\"res://data"), "core systems load data only through DataRegistry")

## Combat rules: Break, Link, turn order, intents, elites (BattleRules.gd)
func _combat_rules_checks() -> void:
	MomentumSystem.reset_momentum()
	var hero = CharacterFactory.create_character("Rules", "Hume", "Monk", true)   # Monk hits Blunt
	EnemyFactory.set_location("fairy_circles")                                       # Fairies are weak to Blunt
	var f1 = EnemyFactory.create_enemy(1, 2, 1)
	var f2 = EnemyFactory.create_enemy(1, 2, 1)
	for f in [f1, f2]:
		f.hp_multiplier = 20.0
		f.calculate_secondary_attributes()
		f.current_hp = f.max_hp
	var ctx = BattleContext.new()
	ctx.player = hero
	ctx.enemies.append(f1); ctx.enemies.append(f2)
	var eng = CombatEngine.new()
	eng.initialize_multi(hero, ctx.enemies)
	var q = TurnQueue.new()
	q.initialize(hero, ctx.enemies)
	var rules = BattleRules.new(ctx, q)
	check(BattleRules.weaknesses(f1).has("Blunt"), "Fairies show Blunt as a weakness (%s)" % ", ".join(BattleRules.weaknesses(f1)))
	# Bestiary: weaknesses are hidden until found (only the current player's battles count)
	var prev_cur = CharacterManager.get_current_character()
	CharacterManager.current_character_resource.set_meta("current_character", hero)
	hero.town_state.erase("bestiary")
	check(Bestiary.shown_weaknesses(f1).has("???") and not Bestiary.shown_weaknesses(f1).has("Blunt"), "unknown weaknesses show as ??? (%s)" % str(Bestiary.shown_weaknesses(f1)))
	var run = func(a: BattleAction) -> Array:
		var snap = rules.before_action(a)
		eng.execute_action(a)
		return rules.after_action(a, snap)
	var lines: Array = []
	var need = BattleRules.break_max(f1)
	var tries := 0
	while not f1.get_meta("broken", false) and tries < 12:   # attacks can miss
		tries += 1
		hero.current_sp = hero.max_sp
		lines.append_array(run.call(BattleAction.attack(hero, f1)))
	check(f1.get_meta("broken", false) and f1.is_stunned and lines.any(func(l): return l.contains("BREAK")), "%d weakness hits Break an enemy (it loses its next turn)" % need)
	check(lines.any(func(l): return l.contains("Weakness found")) and Bestiary.shown_weaknesses(f1).has("Blunt"), "a weakness hit reveals it")
	check(Bestiary.entry("Fairy").get("studied", false) and not Bestiary.shown_weaknesses(f1).has("???") and int(Bestiary.entry("Fairy").breaks) == 1,
		"a Break studies the race: all of its weaknesses are known")
	CharacterManager.current_character_resource.set_meta("current_character", prev_cur)
	check(ctx.link_gauge >= int(BattleRules.cfg().link.get("gain_per_hit", 4)) + int(BattleRules.cfg().get("break", {}).get("link_gain", 25)), "hits and Breaks fill the Link gauge (%d)" % ctx.link_gauge)
	var hp_before = f1.current_hp
	var dmg_broken = BattleFormulas.hit_damage(hero, f1, true)
	f1.set_meta("broken", false)
	var dmg_normal = BattleFormulas.hit_damage(hero, f1, true)
	check(dmg_broken > dmg_normal * 1.2, "Broken enemies take extra damage (%.0f vs %.0f)" % [dmg_broken, dmg_normal])
	f1.set_meta("broken", true)
	check(rules.on_turn_start(f1).contains("recovers") and not f1.get_meta("broken", false), "a Broken enemy recovers after its skipped turn")
	check(BattleRules.break_max(f1) == int(BattleRules.cfg().break.regular_hits) + 1, "each Break raises the threshold")
	# heroes have the same poise: enemies hitting their weakness Break them
	var old_race = hero.race
	hero.race = "Fairy"   # weak to Blunt
	var club = Skill.create_from_dict({"name": "Test Club", "description": "", "ability_type": "PHYSICAL", "type": "DAMAGE", "target": "ENEMY", "power": 5, "cooldown": 0, "duration": 0, "damage_type": "BLUNT"})
	var hlines: Array = []
	var htries := 0
	while not hero.get_meta("broken", false) and htries < 20:   # hits can miss
		htries += 1
		hero.current_hp = hero.max_hp
		f2.current_mp = f2.max_mp; f2.current_sp = f2.max_sp
		hlines.append_array(run.call(BattleAction.skill(f2, club, [hero])))
	check(hero.get_meta("broken", false) and hero.is_stunned and hlines.any(func(l): return l.contains("BREAK")),
		"%d weakness hits Break a hero too" % BattleRules.break_max(hero, true))
	var link_now = ctx.link_gauge
	check(rules.on_turn_start(hero).contains("recovers") and not hero.get_meta("broken", false), "a Broken hero recovers after the skipped turn")
	check(ctx.link_gauge == link_now, "enemies breaking a hero don't fill the party's Link")
	hero.is_stunned = false
	BattleRules.new(ctx, q)
	check(not hero.has_meta("times_broken") and not hero.has_meta("break_meter"), "hero poise resets at the next battle")
	ctx.rules = rules
	# Perfect Guard: Defend while an enemy's intent targets you
	hero.reset_defense()
	ctx.intents.clear()
	check(not rules.is_threatened(hero), "no intent on you = no Perfect Guard")
	ctx.intents[f2] = BattleAction.attack(f2, hero)
	check(rules.is_threatened(hero), "an enemy's shown attack on you readies Perfect Guard")
	var glines = run.call(BattleAction.defend(hero))
	check(hero.get_meta("perfect_guard", false) and glines.any(func(l): return l.contains("Perfect Guard")), "Defending then sets Perfect Guard")
	f2.set_meta("broken", false); f2.is_stunned = false; f2.set_meta("break_meter", 0)
	hero.set_meta("break_meter", 0)
	var guard_hits := 0
	var plines: Array = []
	while guard_hits < 12 and not plines.any(func(l): return l.contains("PERFECT GUARD")):
		guard_hits += 1
		hero.current_hp = hero.max_hp
		plines = run.call(BattleAction.skill(f2, club, [hero]))
	check(plines.any(func(l): return l.contains("PERFECT GUARD")) and int(hero.get_meta("break_meter", 0)) == 0 and int(f2.get_meta("break_meter", 0)) >= 1,
		"a guarded weakness hit gives the hero no pips and staggers the attacker")
	rules.on_turn_start(hero)
	check(not hero.has_meta("perfect_guard"), "Perfect Guard ends at the hero's next turn")
	# Wave challenges: BattleRules counts what happened
	var st = rules.battle_stats()
	check(st.breaks >= 1 and st.weak_hits >= 2 and st.guards >= 1 and st.setbacks >= 1, "battle stats count Breaks, weakness hits, guards and setbacks (%s)" % str(st))
	var breaker = {"name": "Breaker", "description": "Break 2 enemies.", "stat": "breaks", "at_least": 2}
	check(WaveChallenges.met(breaker, {"breaks": 2}) and not WaveChallenges.met(breaker, {"breaks": 1}), "at_least challenges need the count")
	check(WaveChallenges.met({"stat": "items", "at_most": 0}, {"items": 0}) and not WaveChallenges.met({"stat": "items", "at_most": 0}, {"items": 1}), "at_most challenges fail when exceeded")
	check(WaveChallenges.progress(breaker, {"breaks": 1}).ends_with("(1/2)"), "challenge progress text")
	var creward = WaveChallenges.roll_reward(3, false, ctx.enemies)
	check(int(creward.currency) == int(round(float(WaveChallenges.cfg().reward.gold_base) * RewardsManager.floor_scale(3))) and creward.size() > 2, "a met challenge rewards gold and materials (%s)" % str(creward.keys()))
	var picked := 0
	var bad := 0
	for i in range(50):
		var ch = WaveChallenges.pick(true, 1, 1)
		if not ch.is_empty():
			picked += 1
			if ch.get("id", "") in ["breaker", "together"]:
				bad += 1
	check(bad == 0, "challenges respect min_enemies / min_party")
	check(picked == 50, "boss waves always offer a challenge")
	hero.reset_defense()
	ctx.intents.clear()
	hero.race = old_race
	# ultimates wait for the Link gauge
	var ult = Skill.create_from_dict({"name": "Test Ult", "description": "", "ability_type": "PHYSICAL", "type": "DAMAGE", "target": "ENEMY", "category": "ULTIMATE", "power": 80, "cooldown": 0, "duration": 0})
	ctx.link_gauge = 10
	check(not rules.link_ok(hero, ult), "ultimates need %d Link" % rules.link_cost(ult))
	ctx.link_gauge = 60
	check(rules.link_ok(hero, ult), "with enough Link they are available")
	# Unison Strike
	ctx.link_gauge = 100
	check(rules.unison_ready(), "a full gauge readies Unison Strike")
	var hp_u = f2.current_hp
	run.call(BattleAction.unison(hero, f2))
	check(f2.current_hp < hp_u and ctx.link_gauge < 100, "Unison Strike hits and empties the gauge")
	# turn order: delay and haste
	var ox = Skill.create_from_dict({"name": "Shove", "description": "", "ability_type": "PHYSICAL", "type": "DAMAGE", "target": "ENEMY", "power": 10, "cooldown": 0, "duration": 0, "turn_delay": 2})
	var q2 = TurnQueue.new()
	var ally = CharacterFactory.create_character("Ally", "Hume", "Cleric", true)
	var mates: Array[CharacterData] = [ally]
	q2.initialize(hero, ctx.enemies, mates)
	q2.queue.clear()
	for c in [hero, f2, ally, f1]:
		q2.queue.append(c)
	q2.delay(f2, 2)
	check(q2.queue.find(f2) == 3, "a turn_delay skill knocks an enemy back in the order")
	q2.haste(f1)
	check(q2.queue[1] == f1, "haste pulls someone forward to act next")
	check(q2.upcoming(4).size() == 4, "the timeline previews the next turns")
	# elites
	EnemyFactory.set_location("the_dungeon")
	var ok_all := true
	for aff in EliteAffixes.data().affixes:
		var el = EnemyFactory.create_enemy(1, 3, 1)
		var hp0 = el.max_hp
		EliteAffixes.apply(el, aff)
		ok_all = ok_all and el.get_meta("elite_affix", "") == aff and el.max_hp > hp0 and el.name.begins_with(String(EliteAffixes.affix(aff).name))
	check(ok_all, "every elite affix applies (tougher, renamed)")
	var sh = EnemyFactory.create_enemy(1, 3, 1)
	EliteAffixes.apply(sh, "shielded")
	var b0 = int(sh.get_meta("barrier", 0))
	var hp_s = sh.current_hp
	sh.take_damage(5, hero)
	check(b0 > 0 and sh.current_hp == hp_s and int(sh.get_meta("barrier", 0)) == b0 - 5, "a Shielded elite's barrier soaks damage first")
	var sp = EnemyFactory.create_enemy(1, 3, 1)
	EliteAffixes.apply(sp, "splitting")
	ctx.enemies.append(sp)
	var hp_sp = sp.current_hp
	sp.current_hp = 0
	rules._affix_checks(sp, hp_sp)
	var spawned = rules.take_spawns()
	check(spawned.size() == 2 and spawned.all(func(c): return c.max_hp < sp.max_hp and c in ctx.enemies), "a Splitting elite splits into two smaller enemies")
	var rg = EnemyFactory.create_enemy(1, 3, 1)
	EliteAffixes.apply(rg, "enraged")
	var dm = rg.damage_multiplier
	rg.current_hp = int(rg.max_hp * 0.4)
	rules._affix_checks(rg, rg.max_hp)
	check(rg.damage_multiplier > dm, "a Raging elite hits harder below half HP")
	# intents: a planned action is what the enemy does
	var ictx = BattleContext.new()
	ictx.player = hero
	var foe = EnemyFactory.create_enemy(1, 1, 1)
	ictx.enemies.append(foe)
	var plan = EnemyTurnPlanner.new()
	plan.initialize(ictx)
	plan.plan_intent(foe)
	var shown = ictx.intents.get(foe)
	check(shown is BattleAction and BattleRules.describe_intent(foe, ictx.intents) != "", "each enemy shows its next action (%s)" % BattleRules.describe_intent(foe, ictx.intents))
	check(plan.take_intent(foe) == shown, "on its turn the enemy does what its intent showed")
	EnemyFactory.set_location(LocationManager.DEFAULT_LOCATION)

## Talent trees (data/talents.json, TalentManager.gd)
func _talent_checks() -> void:
	# skills charge every cost they list
	var sam0 = CharacterFactory.create_character("C", "Hume", "Samurai", true)
	var iaido0 = sam0.get_skill_instance("Iaido")
	var dummy0 = make_player(); dummy0.vitality += 200; dummy0.calculate_secondary_attributes(); dummy0.current_hp = dummy0.max_hp
	var mp0 = sam0.current_mp; var sp0 = sam0.current_sp
	CombatEngine.new().execute_action(BattleAction.skill(sam0, iaido0, [dummy0]))
	check(sam0.current_mp == mp0 - iaido0.mp_cost and sam0.current_sp == sp0 - iaido0.sp_cost and iaido0.mp_cost > 0 and iaido0.sp_cost > 0,
		"Iaido charges both MP (%d) and SP (%d)" % [iaido0.mp_cost, iaido0.sp_cost])
	sam0.current_mp = 0
	check(not iaido0.can_afford(sam0), "a skill can't be used without its secondary resource")

	var p = CharacterFactory.create_character("T", "Hume", "Paladin", true)
	p.currency.copper = 100000
	var t: TalentManager = p.talents
	check(t.total_points() == 0 and not t.can_learn("bulwark/shield_discipline"), "level 1: no talent points")
	p.level = 6
	check(t.total_points() == 5, "1 point per level from level 2 (L6 = 5)")
	check(not t.can_learn("bulwark/shield_bash"), "tier 2 locked until 2 points are in the branch")
	var tough_before = p.toughness
	check(t.learn("bulwark/shield_discipline") and t.learn("bulwark/shield_discipline"), "learn a passive twice")
	check(is_equal_approx(p.toughness, tough_before + 6.0), "Shield Discipline: +3 toughness per rank (%.1f -> %.1f)" % [tough_before, p.toughness])
	check(t.learn("bulwark/shield_bash") and "Shield Bash" in p.skills and "Shield Bash" in p.get_battle_skills(), "tier-2 node unlocks Shield Bash and equips it")
	check("Holy Strike" in p.get_battle_skills() and p.get_battle_skills().size() == 4, "starting skills stay equipped alongside it")
	check(not t.can_learn("bulwark/aegis_of_dawn"), "ultimate needs 8 points in the branch")
	
	# defense with a shield
	var dummy = make_player()
	var plain = BattleFormulas.hit_damage(dummy, p, true)
	p.equipment["off_hand"] = Equipment.new(ItemManager.get_equipment_template("buckler").duplicate(true))
	check(BattleFormulas.hit_damage(dummy, p, true) < plain, "Shield Discipline reduces damage taken with a shield")
	
	# skill upgrade: Samurai Iai Mastery adds Iaido power
	var sam = CharacterFactory.create_character("S", "Hume", "Samurai", true)
	sam.level = 10
	var iaido_before = sam.get_skill_instance("Iaido").power
	for k in ["iai/swift_draw", "iai/swift_draw", "iai/swift_draw", "iai/flash_draw", "iai/iai_mastery"]:
		sam.talents.learn(k)
	check(sam.get_skill_instance("Iaido").power == iaido_before + 10, "Iai Mastery: Iaido +10 power (%d -> %d)" % [iaido_before, sam.get_skill_instance("Iaido").power])
	
	# loadout cap and respec
	sam.set_equipped_skills(sam.skills + ["Nonexistent"])
	check(sam.get_battle_skills().size() <= TalentManager.loadout_size(), "loadout capped at %d skills" % TalentManager.loadout_size())
	var gold = sam.currency.copper
	sam.currency.copper = 5000
	check(sam.talents.respec() and sam.talents.spent_points() == 0 and not "Flash Draw" in sam.skills and sam.get_skill_instance("Iaido").power == iaido_before,
		"respec refunds points, removes talent skills and upgrades")
	check(sam.currency.copper == 5000 - sam.talents.respec_cost(), "respec costs %d copper at level 10" % sam.talents.respec_cost())
	
	# lifesteal + combo bonus + hp cost
	var zerk = CharacterFactory.create_character("B", "Hume", "Berserker", true)
	zerk.level = 5
	for i in 3: zerk.talents.learn("bloodlust/thirst")
	zerk.current_hp = int(zerk.max_hp * 0.5)
	var hp0 = zerk.current_hp
	var foe = make_player(); foe.vitality += 200; foe.calculate_secondary_attributes(); foe.current_hp = foe.max_hp
	zerk.accuracy = 10.0; zerk.critical_hit_rate = 0.0; foe.dodge = 0.0
	CombatEngine.new()._execute_attack(BattleAction.attack(zerk, foe))
	check(zerk.current_hp > hp0, "Thirst: basic attacks heal the Berserker (%d -> %d)" % [hp0, zerk.current_hp])
	var nec = CharacterFactory.create_character("N", "Hume", "Necromancer", true)
	nec.level = 8
	for k in ["curses/malediction", "curses/malediction", "curses/crippling_hex", "curses/malediction", "curses/lingering_curse", "curses/lingering_curse", "curses/blight_mastery"]:
		nec.talents.learn(k)
	foe.apply_status_effect(Skill.StatusEffect.POISON, 3)
	var c = Combos.preview(nec, nec.get_skill_instance("Dark Bolt"), foe)
	check(c.get("name", "") == "Blight" and c.multiplier > 1.5, "Blight Mastery raises Blight above x1.5 (%.2f)" % c.get("multiplier", 0))
	for k in ["life_drinker/dark_pact", "life_drinker/dark_pact"]:
		nec.talents.learn(k)
	check("Crippling Hex" in nec.skills, "reused skill unlocked by a talent (Crippling Hex)")
	
	# every class: 3 branches x 5 tiers, every skill node's skill exists
	var ok := true
	for cls in TalentManager.data().get("nodes", {}):
		var branches = TalentManager.branches_for(cls)
		if branches.size() != 3:
			ok = false
		for b in branches:
			for n in TalentManager.nodes_for(cls, b.id):
				if n.has("skill") and SkillManager.get_skill(n.skill) == null:
					ok = false
					print("  missing skill ", n.skill)
	check(ok, "12 classes x 3 branches, every talent skill exists")

## Classes follow their philosophies (docs/lore/CLASS_PHILOSOPHIES.md)
func _philosophy_checks() -> void:
	var monk = CharacterFactory.create_character("M", "Hume", "Monk", true)
	check("Tiger Claw" in monk.skills and "Crane Stance" in monk.skills and "Mantis Strike" in monk.skills, "Monk has animal-style skills")
	
	# weapon_bonus: Berserker Cleave x1.25 with a two-hander
	var zerk = CharacterFactory.create_character("B", "Hume", "Berserker", true)
	var cleave = zerk.get_skill_instance("Cleave")
	check(is_equal_approx(cleave.weapon_multiplier(zerk), 1.0), "Cleave: no bonus unarmed")
	var axe = Equipment.new(ItemManager.get_equipment_template("great_axe").duplicate(true))
	zerk.equipment["main_hand"] = axe
	check(is_equal_approx(cleave.weapon_multiplier(zerk), 1.25), "Cleave: x1.25 with a great axe (two-handed)")
	var pal = CharacterFactory.create_character("P", "Hume", "Paladin", true)
	pal.equipment["off_hand"] = Equipment.new(ItemManager.get_equipment_template("buckler").duplicate(true))
	check(is_equal_approx(pal.get_skill_instance("Holy Strike").weapon_multiplier(pal), 1.2), "Holy Strike: x1.2 with a shield")
	
	# off-hand sources' spell_power is applied
	var necro = CharacterFactory.create_character("N", "Hume", "Necromancer", true)
	var sp_before = necro.spell_power
	var tome = Equipment.new(ItemManager.get_equipment_template("tome").duplicate(true))
	necro.equipment["off_hand"] = tome
	necro.calculate_secondary_attributes()
	check(necro.spell_power >= sp_before + tome.spell_power_bonus - 0.01 and tome.spell_power_bonus > 0, "tome spell power applies (%.0f -> %.0f)" % [sp_before, necro.spell_power])
	
	# Cleric wears mail, not plate
	var cleric = CharacterFactory.create_character("C", "Hume", "Cleric", true)
	var mail_ok := false
	var plate_ok := false
	for id in ItemManager.armors:
		var t = ItemManager.get_equipment_template(id)
		if t.type == "mail" and cleric.character_class in t.class_restriction: mail_ok = true
		if t.type == "plate" and cleric.character_class in t.class_restriction: plate_ok = true
	check(mail_ok and not plate_ok, "Cleric: mail yes, plate no")
	
	# every class can use at least two main-hand weapon types
	var classes = JSON.parse_string(FileAccess.open("res://data/classes.json", FileAccess.READ).get_as_text())["playable"]
	var all_ok := true
	for cls in classes:
		var count := 0
		for id in ItemManager.weapons:
			var t = ItemManager.get_equipment_template(id)
			if t.slot == "main_hand" and cls in t.class_restriction: count += 1
		if count < 2:
			all_ok = false
			print("  %s can only use %d weapon types" % [cls, count])
	check(all_ok, "every class can use 2+ weapon types")
	
	# preferred weapons bias drops: Paladin mostly sword and board
	var sword_board := 0
	for i in 200:
		var id = ClassEquipmentBias.get_biased_equipment_id("Paladin", "weapons")
		if id in ["short_sword", "mace", "buckler", "great_shield"]: sword_board += 1
	check(sword_board > 90, "Paladin weapon drops lean sword and board (%d/200)" % sword_board)

## Water element, status elements, Soaked combos, the four new classes
func _element_and_class_checks() -> void:
	check(ElementalDamage.Element.has("WATER") and Skill.ElementType.has("WATER"), "Water element exists")
	var jutsu = SkillManager.get_skill("Water Dragon Jutsu")
	check(jutsu != null and Skill.ElementType.WATER in jutsu.elements, "Water Dragon Jutsu is a Water skill")
	var bushido = SkillManager.get_skill("Bushido")
	check(bushido != null and bushido.elements.is_empty(), "Bushido has no element")
	
	# Conduction: Soaked + Lightning; Water Dragon Jutsu (debuff) always soaks
	var ninja = CharacterFactory.create_character("N", "Hume", "Shinobi", true)
	var dummy = make_player(); dummy.name = "Dummy"
	dummy.vitality += 300; dummy.calculate_secondary_attributes(); dummy.current_hp = dummy.max_hp
	ninja.get_skill_instance("Water Dragon Jutsu").use(ninja, [dummy])
	check(dummy.status_manager.has_effect(Skill.StatusEffect.SOAKED), "Water Dragon Jutsu soaks the target")
	var kunai = ninja.get_skill_instance("Lightning Kunai")
	check(Combos.preview(ninja, kunai, dummy).get("name", "") == "Conduction", "Lightning Kunai on a soaked target = Conduction")
	
	# Status ticks use the status's element: Poison is Earth
	var earthy = make_player(); earthy.name = "Earthy"
	var plain = make_player(); plain.name = "Plain"
	earthy.add_temp_elemental_resistance(ElementalDamage.Element.EARTH, 0.5)
	for c in [earthy, plain]:
		c.vitality += 200; c.calculate_secondary_attributes(); c.current_hp = c.max_hp
		c.apply_status_effect(Skill.StatusEffect.POISON, 3)
	var hp_e = earthy.current_hp; var hp_p = plain.current_hp
	earthy.status_manager.update_effects(); plain.status_manager.update_effects()
	var lost_e = hp_e - earthy.current_hp; var lost_p = hp_p - plain.current_hp
	check(lost_p > 0 and abs(float(lost_e) / lost_p - 0.5) < 0.05, "Poison ticks are Earth: 50%% Earth resist halves them (%d vs %d)" % [lost_e, lost_p])
	
	# the four new classes
	for cls in ["Berserker", "Shinobi", "Kannagi", "Beastmaster"]:
		var c = CharacterFactory.create_character("T", "Hume", cls, true)
		var ok = c != null and c.skills.size() >= 3   # Kannagi also starts with Spirit Recall
		for sn in (c.skills if c else []):
			ok = ok and c.get_skill_instance(sn) != null
		check(ok and c.attack_power > 0 and c.spell_power > 0, "%s: created with working starting skills" % cls)
		check(not c.proficiency_manager.get_available_weapon_types().is_empty(), "%s: can use some weapons" % cls)

## Set-up / payoff combos (data/combos.json, scripts/resources/Combos.gd)
func _combo_checks() -> void:
	check(Combos.all().size() >= 7, "combos load (%d)" % Combos.all().size())
	var spear_data = {"name": "T", "description": "", "ability_type": "MAGICAL", "type": "DAMAGE", "target": "ENEMY",
		"element": ["FIRE", "ICE"], "power": 10, "cooldown": 0, "duration": 0}
	var spear = Skill.create_from_dict(spear_data)
	check(spear.elements.size() == 2, "a skill's element list is read (was ignored)")
	
	# deterministic attacker/target: always hit, never crit, never dodge
	var make_pair = func():
		var a = make_player(); var d = make_player()
		a.name = "Striker"; d.name = "Target"
		for c in [a, d]:
			c.equipment["main_hand"] = null
			c.calculate_secondary_attributes()
		a.accuracy = 10.0; a.critical_hit_rate = 0.0; d.dodge = 0.0
		d.vitality += 300; d.calculate_secondary_attributes(); d.current_hp = d.max_hp; d.dodge = 0.0
		return [a, d]
	var smash = Skill.create_from_dict({"name": "Smash Test", "description": "", "ability_type": "PHYSICAL", "type": "DAMAGE",
		"target": "ENEMY", "damage_type": "BLUNT", "power": 30, "cooldown": 0, "duration": 0})
	var pair = make_pair.call()
	var plain = smash.use(pair[0], [pair[1]]).damage
	pair = make_pair.call()
	pair[1].apply_status_effect(Skill.StatusEffect.FREEZE, 3)
	pair[0].accuracy = 10.0; pair[0].critical_hit_rate = 0.0; pair[1].dodge = 0.0
	var res = smash.use(pair[0], [pair[1]])
	check(abs(float(res.damage) / plain - 1.5) < 0.05, "Shatter: Blunt hit on a frozen target x1.5 (%d vs %d)" % [res.damage, plain])
	check("Shatter" in res.message, "combo shows in the combat log")
	check(not pair[1].status_manager.has_effect(Skill.StatusEffect.FREEZE), "the combo consumes Freeze")
	
	pair = make_pair.call()
	pair[1].apply_status_effect(Skill.StatusEffect.BLEED, 3)
	var fireball = Skill.create_from_dict({"name": "Fire Test", "description": "", "ability_type": "MAGICAL", "type": "DAMAGE",
		"target": "ENEMY", "elements": ["FIRE"], "power": 30, "cooldown": 0, "duration": 0})
	check(Combos.preview(pair[0], fireball, pair[1]).is_empty(), "no combo when the payoff doesn't match (Fire on Bleed)")
	check(Combos.preview(pair[0], smash, pair[1]).is_empty(), "Blunt is not an Open Wound payoff")
	var dagger = Equipment.new(ItemManager.get_equipment_template("dagger").duplicate(true))
	pair[0].equipment["main_hand"] = dagger
	check(Combos.find(pair[1], Combos.hit_from_attack(pair[0])).get("name", "") == "Open Wound", "basic attack with a dagger pays off Bleed")
	
	# basic attack through the combat engine: Sucker Punch on a confused target
	pair = make_pair.call()
	pair[1].apply_status_effect(Skill.StatusEffect.CONFUSED, 3)
	pair[0].accuracy = 10.0; pair[0].critical_hit_rate = 0.0; pair[1].dodge = 0.0
	var engine = CombatEngine.new()
	var r = engine._execute_attack(BattleAction.attack(pair[0], pair[1]))
	check("Sucker Punch" in r.message and not pair[1].status_manager.has_effect(Skill.StatusEffect.CONFUSED), "basic attack triggers and consumes Sucker Punch")
	
	# enemy AI spots the combo (players = enemies)
	var shaman = CharacterData.new()
	shaman.name = "Shaman"
	shaman.add_skills(["Lightning Bolt"])
	shaman.current_mp = 999; shaman.current_sp = 999
	var hero = make_player()
	hero.apply_status_effect(Skill.StatusEffect.SHOCK, 3)
	var ai = EnemyAI.new()
	ai.initialize(shaman, [hero], 1)
	ai.target = hero
	var act = ai._try_combo()
	check(act != null and act.skill_data != null and act.skill_data.name == "Lightning Bolt", "enemy AI uses Lightning Bolt on a shocked hero (Overload)")

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

	_combo_checks()
	_element_and_class_checks()
	_philosophy_checks()
	_talent_checks()
	_defeat_checks()
	_archetype_checks()
	_rank_checks()
	_world_checks()
	_adventurer_checks()
	_party_checks()
	_revive_and_encounter_checks()
	_leak_checks()
	_data_registry_checks()
	_combat_rules_checks()
	
	# Class-biased loot rolls (Breather drops pass the player's class)
	var biased_ok := true
	for i in 40:
		for cls in ["Paladin", "Elementalist", "NotAClass"]:
			var w = ItemManager.get_random_weapon_biased(cls)
			var ar = ItemManager.get_random_armor_biased(cls)
			var ar_head = ItemManager.get_random_armor_biased(cls, "head")
			var any = ItemManager.get_random_equipment_biased(cls)
			if w == "" or ar == "" or any == "" or ItemManager.get_equipment_template(ar_head).get("slot", "") != "head":
				biased_ok = false
	check(biased_ok, "class-biased weapon/armor/slot rolls return valid items")
	var drop_rewards = {"equipment_instances": []}
	for i in 30:
		RewardsManager.add_random_item_to_rewards(drop_rewards, "weapon", 1.0, 1, "Paladin")
		RewardsManager.add_random_item_to_rewards(drop_rewards, "armor", 1.0, 1, "Paladin")
	check(drop_rewards.equipment_instances.size() == 60, "Breather gear drops with a player class (%d/60)" % drop_rewards.equipment_instances.size())
	# The real Breather payout path, boss and regular waves, with a player class
	var breather_gear := 0
	for i in 60:
		var r = RewardsManager.calculate_battle_rewards({"current_wave": 1 + i % 6, "current_floor": 3, "is_boss_fight": i % 6 == 5,
			"momentum_level": i % 4, "player_class": "Paladin", "enemies": [], "xp_gained": 10})
		breather_gear += r.equipment_instances.size()
	check(breather_gear > 0, "Breather reward calculation runs with a player class (%d gear drops in 60)" % breather_gear)
	
	# Physical damage types: weapon/skill/unarmed source, race + armor affinities, clamp
	var troll = make_player(); troll.race = "Troll"
	for slot in DamageTypes.ARMOR_SLOTS: troll.equipment[slot] = null
	check(is_equal_approx(DamageTypes.multiplier(troll, DamageTypes.Type.SLASH), 1.2), "Troll takes +20% Slash")
	check(is_equal_approx(DamageTypes.multiplier(troll, DamageTypes.Type.BLUNT), 0.8), "Troll resists Blunt")
	var monk = CharacterFactory.create_character("M", "Hume", "Monk", true); monk.equipment["main_hand"] = null
	check(DamageTypes.attack_type(monk) == DamageTypes.Type.BLUNT, "Monk fists are Blunt (unarmed_by_class)")
	var brawler = make_player(); brawler.equipment["main_hand"] = null
	check(DamageTypes.attack_type(brawler) == DamageTypes.FROM_WEAPON and DamageTypes.multiplier(troll, DamageTypes.attack_type(brawler)) == 1.0, "unarmed hits are untyped (neutral)")
	check(DamageTypes.attack_type(brawler, DamageTypes.Type.PIERCE) == DamageTypes.Type.PIERCE, "skill damage_type overrides the weapon")
	var mace = Equipment.new(ItemManager.get_equipment_template("mace").duplicate(true))
	check(mace.key == "mace" and DamageTypes.weapon_type(mace) == DamageTypes.Type.BLUNT, "Mace deals Blunt")
	var knight = make_player(); knight.race = "Hume"
	for slot in DamageTypes.ARMOR_SLOTS:
		var piece = Equipment.new({"id": "test_plate_" + slot, "name": "Test Plate", "type": "plate", "slot": slot, "armor_value": 1, "rarity": "common"})
		knight.equipment[slot] = piece
	check(is_equal_approx(DamageTypes.multiplier(knight, DamageTypes.Type.BLUNT), 1.2) and is_equal_approx(DamageTypes.multiplier(knight, DamageTypes.Type.SLASH), 0.8), "full plate: weak to Blunt, resists Slash")
	knight.equipment["head"] = null
	check(is_equal_approx(DamageTypes.multiplier(knight, DamageTypes.Type.BLUNT), 1.16), "partial plate gives a partial effect")
	var crusher = make_player(); crusher.equipment["main_hand"] = null
	var slash_hit = BattleFormulas.hit_damage(crusher, troll, true, 0.0, DamageTypes.Type.SLASH)
	var blunt_hit = BattleFormulas.hit_damage(crusher, troll, true, 0.0, DamageTypes.Type.BLUNT)
	var wb = 1.0 + float(BattleRules.cfg().get("weakness_bonus", 0.0))
	check(is_equal_approx(slash_hit / blunt_hit, 1.5 * wb), "hit_damage applies the type multiplier and the weakness bonus (Slash/Blunt on Troll = 1.2/0.8 x %.1f)" % wb)
	check(is_equal_approx(BattleFormulas.hit_damage(crusher, troll, false, 0.0, DamageTypes.Type.SLASH), BattleFormulas.hit_damage(crusher, troll, false)), "magic ignores damage types")
	var iaido = Skill.create_from_dict({"name": "T", "description": "", "ability_type": "PHYSICAL", "type": "DAMAGE", "target": "ENEMY", "power": 10, "cooldown": 0, "duration": 0, "damage_type": "slash"})
	check(iaido.damage_type == DamageTypes.Type.SLASH, "skills read damage_type from data")
	
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
	check(p.get_max_floor("orc_plains") == 4 and p.get_max_floor("troll_caves") == 1 and p.max_floor_unlocked >= 4,
		"floor progress is tracked per location")
	check(p.deepest_floor_cleared() == 3, "deepest floor cleared = highest unlocked - 1 (%d)" % p.deepest_floor_cleared())
	var old_save := {"max_floor_cleared": 6}
	var p_old = make_player()
	p_old.max_floor_unlocked = int(old_save.get("max_floor_unlocked", old_save.get("max_floor_cleared", 0)))
	check(p_old.max_floor_unlocked == 6, "old saves' max_floor_cleared loads as max_floor_unlocked")
	
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
	var troll_mats = ["frostroot_chunk", "wood", "rawhide", "voltslate_pebble"]
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
	_material_checks()
	_enchant_checks()
	_run_state_checks()
	_bond_checks()
	_personality_checks()
	_memory_checks()
	_relations_checks()
	_drama_checks()
	_town_life_checks()
	_ledger_checks()
	_journal_checks()
	_compendium_checks()
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
	var wave_gold = int(round((40.0 + 3 * 6.0) * RewardsManager.floor_scale(1)))   # data/loot/gold.json
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
	for i in range(200):
		var r = RewardsManager.roll_wave_rewards({"current_wave": 1, "current_floor": 1, "is_boss_fight": false, "enemies": crowd, "momentum_level": 0})
		if gear in r.equipment_instances: drops += 1
	var rare_chance = RewardsManager.get_equipment_drop_chance("rare", false)
	check(drops >= int(200 * rare_chance * 0.4) and drops <= int(200 * rare_chance * 1.8) + 2, "rare enemy gear drops only sometimes (~%d%%: %d/200)" % [int(rare_chance * 100), drops])
	# at most one piece per enemy, and a boss always drops one
	var kit: Array = []
	for i in range(4):
		var piece = ItemManager.create_equipment_for_floor(ItemManager.get_random_weapon(), 1)
		piece.rarity = "legendary"
		kit.append(piece)
	var champ = EnemyFactory.create_enemy(1, 1, 1)
	champ.set_meta("equipped_items", kit)
	var most := 0
	for i in range(100):
		most = max(most, RewardsManager.roll_enemy_gear([champ], false, 3.0).size())
	check(most == 1, "an enemy drops at most one piece of its gear")
	var boss_ok := true
	for i in range(30):
		if RewardsManager.roll_enemy_gear([champ], true).size() != 1:
			boss_ok = false
	check(boss_ok, "a boss always drops one piece")
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
	p.max_floor_unlocked = 5
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

## Cloth and leather armor use cloth and hide at the Blacksmith.
func _material_checks() -> void:
	for id in ["linen_cloth", "silk_cloth", "spellweave_cloth", "rawhide", "thick_hide", "drake_hide"]:
		check(ItemManager.get_item(id) != null, "material %s exists" % id)
	var robe = _make_gear("rare", false)
	robe.type = "cloth"
	var vest = _make_gear("rare", false)
	vest.type = "leather"
	var plate = _make_gear("rare", false)
	plate.type = "plate"
	check(BlacksmithManager.get_upgrade_cost(robe).materials.has("linen_cloth") and BlacksmithManager.get_upgrade_cost(vest).materials.has("rawhide")
		and BlacksmithManager.get_upgrade_cost(plate).materials.has("iron_ore"), "cloth armor upgrades with cloth, leather with hide, plate with ore")
	robe.set_upgrade_level(5)
	check(BlacksmithManager.get_upgrade_cost(robe).materials.has("silk_cloth"), "higher cloth upgrades need Silk")
	check(BlacksmithManager.get_salvage_preview(vest).ore_id == "rawhide", "salvaging leather armor gives hide")

## Every Compendium topic renders with live values and no broken placeholders.
func _compendium_checks() -> void:
	var topics = CompendiumScreen.all_topics()
	check(topics.size() >= 15, "the Compendium has %d topics" % topics.size())
	var bad: Array = []
	for t in topics:
		var txt = CompendiumScreen.render(String(t.text))
		if txt.contains("{") or txt.contains("?") and not txt.contains("??? until") and txt.find(" ?") >= 0:
			bad.append(String(t.id))
	check(bad.is_empty(), "every placeholder resolves (%s)" % ", ".join(bad))
	var g = CompendiumScreen.render("{x:combat:intents.charge_power_mult} {pct:combat:weakness_bonus} {num:combat:break.hero_hits}")
	check(g == "×%s %d%% %d" % [CompendiumScreen._fmt(float(BattleRules.cfg().intents.charge_power_mult)), int(round(float(BattleRules.cfg().weakness_bonus) * 100)), int(BattleRules.cfg().break.hero_hits)], "placeholders read live data (%s)" % g)
	var st = CompendiumScreen.render("{list:status_effects}")
	check(st.contains("Burn") and st.contains("4% of max HP") and st.contains("Marked"), "status effects are described from their data")
	var names = CompendiumScreen.render("{list:item_names}")
	check(names.contains("Brilliant") and names.contains("Intelligence") and names.contains("Toxic") and names.contains("Elandria"), "item name words are explained from the namer's tables")
	check(CompendiumScreen.render("{list:classes}").contains("Wardens") and CompendiumScreen.render("{list:ranks}").contains("Wayfarer"), "classes and ranks lists are generated")

## The Journal reads every system's open objectives.
func _journal_checks() -> void:
	var p = make_player()
	AdventurerManager.state(p)
	var empty = JournalScreen.build_text(p)
	check(empty.contains("Standing") and empty.contains("None accepted") and empty.contains("Recovery"), "the Journal shows every section, with empty states")
	CommissionManager.refresh(p)
	RumorManager.refresh(p, true)
	DefeatManager.get_injuries(p).append({"id": "cracked_ribs", "remaining": 2})
	RumorManager.list(p)[0].expires = WorldClock.day(p) + 1
	var t = JournalScreen.build_text(p)
	var a = CommissionManager.active(p, "blacksmith")
	check(t.contains(ItemManager.get_item(String(a.item)).display_name) and t.contains(RumorManager.text(RumorManager.list(p)[0])), "commissions and rumours appear in the Journal")
	check(t.contains("heals in 2 days") and t.contains("due soon"), "injuries show, and anything due within 2 days is flagged")
	check(t.contains("The Crowning in"), "the Crowning countdown is in the Journal")

## The Guild Ledger: renown standings for you and every adventurer.
func _ledger_checks() -> void:
	var p = make_player()
	AdventurerManager.state(p)
	var st = LedgerManager.standings(p)
	check(st.size() == AdventurerManager.active(p).size() + 1 and st.any(func(x): return x.is_player), "the Ledger lists you and every active adventurer (%d)" % st.size())
	var sorted_ok := true
	for i in range(st.size() - 1):
		if st[i].renown < st[i + 1].renown:
			sorted_ok = false
	check(sorted_ok and int(st[0].pos) == 1, "standings are sorted by renown")
	var r0 = LedgerManager.profile_player(p).renown
	var keep = DungeonStateManager.active_player
	DungeonStateManager.active_player = p
	GameEvents.floor_cleared.emit("goblin_forest", 3)
	DungeonStateManager.active_player = keep
	p.unlock_floor("goblin_forest", 4)
	var pr = LedgerManager.profile_player(p)
	check(pr.bosses == 1 and pr.deepest == 3 and pr.renown > r0, "a boss kill and a deeper floor raise your renown (%d -> %d)" % [r0, pr.renown])
	var npc = AdventurerManager.active(p)[0]
	var nr = LedgerManager.profile_npc(npc).renown
	LedgerManager.record_npc_job(npc, 9, true, true)
	check(LedgerManager.profile_npc(npc).renown > nr and int(npc.deeds.deepest) >= 9, "NPC boss kills count the same way")
	# weekly movers: snapshot at a new week, arrows after
	LedgerManager._on_day(p, 1)
	npc.points = int(npc.points) + 100000
	var moved = LedgerManager.standings(p).filter(func(x): return x.key == "npc_%d" % int(npc.id))[0]
	check(moved.pos == 1 and moved.move > 0, "climbers show their weekly movement (#%d, +%d)" % [moved.pos, moved.move])
	LedgerManager._on_day(p, 8)
	check(WorldClock.get_news(p, 20).any(func(n): return String(n.text).contains("tops the Guild Ledger")), "a new #1 makes the news")
	check(LedgerManager.summary(p).begins_with("#"), "summary line: %s" % LedgerManager.summary(p))
	# the yearly crowning
	var dpy = LedgerManager.days_per_year()
	check(dpy == 112 and LedgerManager.year_of(1) == 1 and LedgerManager.year_of(113) == 2, "a year is %d days" % dpy)
	LedgerManager._crowning_tick(p, 50)
	check(LedgerManager.champion(p).is_empty() and LedgerManager.days_to_crowning(p) > 0, "no Champion before the first crowning")
	var lead = LedgerManager.standings(p)[0]
	LedgerManager._crowning_tick(p, 113)
	var ch = LedgerManager.champion(p)
	check(ch.get("key", "") == lead.key and int(ch.year) == 1 and WorldClock.get_news(p, 20).any(func(n): return String(n.text).contains("crowned Champion of Year 1")),
		"at the turn of the year the Ledger's #1 is crowned (%s)" % ch.get("name", "?"))
	check(not lead.is_player and "Champion" in AdventurerManager.tags(lead.npc) and LedgerManager.profile_npc(lead.npc).renown > int(lead.renown), "an NPC Champion gets the title and the crown's renown")
	# the player at #1 takes the crown and its purse
	GuildManager.state(p).points = 1000000
	var gold0 = p.currency.copper
	LedgerManager._crowning_tick(p, 113 + dpy)
	check(LedgerManager.champion(p).get("is_player", false) and p.currency.copper > gold0 and int(LedgerManager.profile_player(p).crowns) == 1,
		"you can take the crown (gold, Guild points, renown)")
	check(WorldClock.get_news(p, 20).any(func(n): return String(n.text).contains("You are crowned Champion of Year 2")), "your crowning makes the news")

## Memory: what adventurers (and you) remember, fading, gossip, grudges, debts.
func _memory_checks() -> void:
	var p = make_player()
	AdventurerManager.state(p)
	var prev_cur = CharacterManager.get_current_character()
	CharacterManager.current_character_resource.set_meta("current_character", p)
	var a = AdventurerManager._add(p, AdventurerManager.generate(p))
	a.status = "idle"
	a.memories = []
	MemoryManager.add(a, "abandoned_me", "you", 1)
	check(MemoryManager.opinion(a, "you") == -30 and not MemoryManager.grudge(a).is_empty(), "leaving someone to die is remembered as a grudge")
	a.rapport = 90
	check(PartyManager.why_not_recruit(p, int(a.id)).contains("won't travel with you"), "a grudge blocks recruiting even at high rapport")
	MemoryManager.add(a, "abandoned_me", "you", 2)
	check(MemoryManager.about_of(a, "you").size() == 1 and int(MemoryManager.opinion(a, "you")) == -60, "the same memory adds up (to its cap) instead of duplicating")
	# fading
	var b = AdventurerManager._add(p, AdventurerManager.generate(p))
	b.memories = []
	b.status = "idle"
	MemoryManager.add(b, "gifted_me", "you", 1)
	MemoryManager.add(b, "killed_my_friend", "npc:9999", 1)
	for i in range(40):
		MemoryManager.daily(p, 2 + i)
	var w_gift = MemoryManager.opinion(b, "you")
	check(w_gift < 5.0 and MemoryManager.opinion(b, "npc:9999") == -60, "ordinary memories fade; core ones never do (%.1f left of a gift)" % w_gift)
	# gossip spreads a strong memory to someone else in town
	for n in AdventurerManager.active(p):
		if n != a:
			n.memories = []
	var spread := 0
	for i in range(40):
		for g in MemoryManager.gossip(p, 50 + i):
			if g.memory.about == "you" and g.teller == a:
				spread += 1
	var heard = AdventurerManager.active(p).filter(func(n): return n != a and MemoryManager.about_of(n, "you").any(func(m): return m.has("heard_from")))
	check(spread > 0 and not heard.is_empty(), "gossip spreads your reputation (%d people heard)" % heard.size())
	# visibility: hints, then full
	b.rapport = 0
	MemoryManager.add(b, "saved_me", "you", 60)
	check(MemoryManager.tavern_text(b, p).contains("gratefully"), "strangers only show a hint")
	b.rapport = 50
	check(MemoryManager.tavern_text(b, p).contains("Remembers about you"), "friends show the full memory list")
	# debts: carried home after a defeat
	check(MemoryManager.owes_you(b), "saving someone puts them in your debt")
	p.currency.copper = 1000
	var summary = DefeatManager.apply_defeat(p, false)
	check(String(summary.get("rescued_by", "")) == String(b.name) and p.currency.copper == 1000 and not MemoryManager.owes_you(b), "a debtor carries you home: no fee, no lost gear, debt repaid")
	# your own memories
	MemoryManager.add(p, "robbed_me", MemoryManager.key_npc(a), 70)
	check(MemoryManager.text(MemoryManager.list(p)[-1], p, true).begins_with(String(a.name) + " robbed you"), "you remember who wronged you (%s)" % MemoryManager.text(MemoryManager.list(p)[-1], p, true))
	check(JournalScreen.build_text(p).contains("People") and JournalScreen.build_text(p).contains("robbed you"), "the Journal lists your people")
	# a nemesis who lost to you twice studies you
	var nem = AdventurerManager._add(p, AdventurerManager.generate(p, [3, 3], true))
	nem.memories = []
	MemoryManager.add(nem, "beat_me", "you", 1)
	MemoryManager.add(nem, "beat_me", "you", 2)
	var sword = ItemManager.create_equipment_for_floor("short_sword", 1) if ItemManager.get_item("short_sword") else ItemManager.create_equipment_for_floor(ItemManager.get_random_weapon("sword"), 1)
	p.equipment["main_hand"] = sword
	var foe = EncounterManager.build_nemesis(p, nem)
	check(MemoryManager.losses_to_you(nem) == 2 and foe.get_meta("studied_you", false) and DamageTypes.multiplier(foe, DamageTypes.attack_type(p)) < 1.0, "a nemesis who lost twice comes back armored against you")
	CharacterManager.current_character_resource.set_meta("current_character", prev_cur)

## NPC-to-NPC relationships: chemistry, shared jobs, rescues, ripples.
func _relations_checks() -> void:
	var p = make_player()
	AdventurerManager.state(p)
	var prev_cur = CharacterManager.get_current_character()
	CharacterManager.current_character_resource.set_meta("current_character", p)
	var x = AdventurerManager._add(p, AdventurerManager.generate(p))
	var y = AdventurerManager._add(p, AdventurerManager.generate(p))
	var z = AdventurerManager._add(p, AdventurerManager.generate(p))
	x.traits = ["kind", "loyal"]
	y.traits = ["kind", "honorable"]
	z.traits = ["cruel"]
	check(RelationsManager.chemistry(x, y) == 2 and RelationsManager.chemistry(y, z) == -2, "trait chemistry: kindred spirits click, the cruel grate (%d / %d)" % [RelationsManager.chemistry(x, y), RelationsManager.chemistry(y, z)])
	check(RelationsManager.change(p, x, y, 45, 1) == "friends" and RelationsManager.status(p, y, x) == "friends", "affinity crosses into friendship (symmetric)")
	RelationsManager.change(p, x, y, 30, 2)
	check(RelationsManager.status(p, x, y) == "sworn" and x.history.any(func(h): return String(h.text).contains("Swore")), "sworn companions are written into their histories")
	RelationsManager.change(p, y, z, -75, 2)
	check(RelationsManager.status(p, y, z) == "feud", "a feud at -70")
	# cap: weakest relations are forgotten
	var others: Array = []
	for i in range(12):
		var o = AdventurerManager._add(p, AdventurerManager.generate(p))
		others.append(o)
		RelationsManager.change(p, x, o, 5 + i, 3)
	check(RelationsManager.relations_of(p, x).size() <= int(RelationsManager.cfg().max_per_npc) and RelationsManager.status(p, x, y) == "sworn", "each adventurer keeps their strongest %d relations" % int(RelationsManager.cfg().max_per_npc))
	# partners: a sworn companion comes along and the job binds them
	for n in AdventurerManager.active(p):
		if n.status == "job":
			n.status = "idle"
	x.status = "idle"
	y.status = "idle"
	var paired := 0
	for i in range(20):
		if RelationsManager.pick_partner(p, x) == y:
			paired += 1
	check(paired >= 14, "sworn companions go on jobs together (%d / 20)" % paired)
	var solo = AdventurerManager.job_success_chance(x, 3)
	var duo = AdventurerManager.group_success_chance([x, y], 3)
	check(duo > min(solo, AdventurerManager.job_success_chance(y, 3)), "two together do better than the weaker alone (%.2f vs %.2f)" % [duo, solo])
	var before = RelationsManager.affinity(p, x, y)
	RelationsManager.after_group_job(p, [x, y], true, 4)
	check(RelationsManager.affinity(p, x, y) > before and MemoryManager.about_of(x, MemoryManager.key_npc(y)).any(func(m): return m.kind == "fought_beside"), "a shared success brings them closer and is remembered")
	# blame: the cruel blame partners for failures
	var w = AdventurerManager._add(p, AdventurerManager.generate(p))
	w.traits = ["boastful"]
	RelationsManager.after_group_job(p, [w, z], false, 5)
	check(RelationsManager.affinity(p, w, z) < 0, "a failure with a blamer sours things")
	# a full job with a partner, resolved by the sim
	x.status = "idle"
	y.status = "idle"
	AdventurerManager._start_job(x, 10, "job", "the_dungeon" if LocationManager.get_ids().has("the_dungeon") else LocationManager.get_ids()[0], 1)
	x.job["partners"] = [int(y.id)]
	y.status = "job"
	y.job = x.job.duplicate()
	y.job.erase("partners")
	y.job["lead"] = int(x.id)
	var jobs_before = int(y.record.jobs)
	AdventurerManager.simulate_day(p, int(x.job.ends))
	check(int(y.record.jobs) == jobs_before + 1 and y.status != "job", "the partner's job is resolved with the leader's (%d -> %d, %s, leader %s)" % [jobs_before, int(y.record.jobs), y.status, x.status])
	# rescue
	RelationsManager.on_rescue(p, x, y, 12)
	check(MemoryManager.about_of(y, MemoryManager.key_npc(x)).any(func(m): return m.kind == "saved_me"), "being dragged out alive is remembered")
	# ripple: your rapport spreads to friends, the other way to rivals
	y.rapport = 0
	z.rapport = 0
	x.rapport = 0
	AdventurerManager._set_rapport(x, 20)
	check(int(y.rapport) > 0, "doing right by someone warms their friends to you (%+d)" % int(y.rapport))
	AdventurerManager._set_rapport(y, 20)
	check(int(z.rapport) < 0, "and cools their rivals (%+d)" % int(z.rapport))
	check(RelationsManager.describe(p, y).contains("Sworn companion of") and RelationsManager.describe(p, y).contains("Feuding with"), "the Tavern shows their bonds")
	# promotion resentment
	var amb = AdventurerManager._add(p, AdventurerManager.generate(p))
	amb.traits = ["ambitious"]
	amb.rank = x.rank
	AdventurerManager._promote(p, x, 20)
	check(RelationsManager.affinity(p, amb, x) < 0, "the ambitious resent a peer's promotion")
	# the dead are mourned by their friends
	AdventurerManager._fate(p, y, 30, false, "test", 1)   # may or may not die; force it
	y.status = "dead"
	RelationsManager.prune(p)
	check(RelationsManager.affinity(p, x, y) > 0, "relations to the dead are kept (for grief)")
	CharacterManager.current_character_resource.set_meta("current_character", prev_cur)

## Drama: companies, invitations, romance, grief, feuds, jealousy.
func _drama_checks() -> void:
	var p = make_player()
	AdventurerManager.state(p)
	var prev_cur = CharacterManager.get_current_character()
	CharacterManager.current_character_resource.set_meta("current_character", p)
	var mk = func(traits: Array) -> Dictionary:
		var n = AdventurerManager._add(p, AdventurerManager.generate(p, [6, 6]))
		n.traits = traits
		n.status = "idle"
		n.rapport = 0
		return n
	var a = mk.call(["loyal"])
	var b = mk.call(["honorable"])
	var c = mk.call(["kind"])
	# companies
	RelationsManager.change(p, a, b, 80, 1)
	DramaManager._form_companies(p, 7)
	var co = DramaManager.company_of(p, a)
	check(not co.is_empty() and DramaManager.company_of(p, b) == co and String(co.name).begins_with("The "), "sworn companions found a company (%s)" % co.get("name", "?"))
	RelationsManager.change(p, b, c, 80, 2)
	RelationsManager.change(p, a, c, 45, 2)
	DramaManager._form_companies(p, 14)
	check(DramaManager.company_members(p, co).size() == 3, "a third sworn friend joins the company")
	check(DramaManager.job_partners(p, a).size() == 2, "a company takes jobs together")
	RelationsManager.change(p, a, c, -100, 15)
	DramaManager._tidy_companies(p, 15)
	check(DramaManager.company_members(p, co).size() == 2 and (DramaManager.company_of(p, a).is_empty() or DramaManager.company_of(p, c).is_empty()), "a falling-out inside splits the company")
	# romance
	var x = mk.call(["kind"])
	var y = mk.call(["kind"])
	var z = mk.call(["aloof"])
	RelationsManager.change(p, x, y, 80, 3)
	RelationsManager.change(p, x, z, 0, 3)
	var w = mk.call(["kind"])
	RelationsManager.change(p, w, z, 80, 3)
	for i in range(40):
		DramaManager._romance_week(p, 21 + i * 7)
	check(int(x.get("partner", -1)) == int(y.id) and int(y.get("partner", -1)) == int(x.id), "sworn companions fall for each other in time")
	check(not w.has("partner") and not z.has("partner"), "one Aloof heart stops it")
	RelationsManager.change(p, x, y, -200, 400)
	DramaManager._romance_week(p, 406)
	check(not x.has("partner"), "partners who fall out split up")
	# death and grief
	RelationsManager.change(p, x, y, 200, 410)
	DramaManager.pair_up(p, x, y, 410)
	y.status = "dead"
	y["died_at"] = {"location": LocationManager.get_ids()[0], "floor": 3}
	DramaManager.on_death(p, y, 411)
	check(DramaManager.is_grieving(x) and x.grief.partner and DramaManager.job_chance_mult(x) < 1.0 and not x.has("partner"), "a partner's death: grief (fewer jobs)")
	check(MemoryManager.about_of(x, MemoryManager.key_npc(y)).any(func(m): return m.kind == "lost_companion" and m.core), "the loss is a core memory")
	var counts := {}
	var coward = AdventurerManager.generate(p)
	coward.traits = ["cowardly", "cautious"]
	var hothead = AdventurerManager.generate(p)
	hothead.traits = ["reckless", "loyal"]
	for i in range(300):
		var oc = "c_" + DramaManager.grief_outcome(coward)
		var oh = "h_" + DramaManager.grief_outcome(hothead)
		counts[oc] = int(counts.get(oc, 0)) + 1
		counts[oh] = int(counts.get(oh, 0)) + 1
	check(int(counts.get("c_withdraws", 0)) > int(counts.get("h_withdraws", 0)) and int(counts.get("h_vengeance", 0)) > int(counts.get("c_vengeance", 0)), "grief paths follow traits (%s)" % counts)
	DramaManager._apply_grief(p, x, "vengeance", y, 430)
	check(x.has("vengeance") and String(x.vengeance.location) == String(y.died_at.location), "vengeance: they swear to kill the boss where their partner fell")
	check(DramaManager.describe(p, x).contains("sworn to slay"), "the Tavern shows it")
	x.rapport = 0
	DramaManager._on_player_floor_cleared(String(y.died_at.location), 3)
	check(not x.has("vengeance") and int(x.rapport) >= 25 and MemoryManager.about_of(x, "you").any(func(m): return m.kind == "avenged_me"), "you killing that boss is never forgotten")
	DramaManager._apply_grief(p, x, "hardens", y, 440)
	check(x.traits.any(func(t): return t in ["aloof", "cruel"]), "or grief hardens them")
	# lethal feuds
	var k = mk.call(["cruel"])
	var v = mk.call(["kind"])
	var vf = mk.call(["loyal"])
	k.rank = RankManager.rank_ids()[2]
	RelationsManager.change(p, v, vf, 60, 450)
	RelationsManager.change(p, k, v, -90, 450)
	var res = DramaManager.confront(p, k, v, 451, true)
	var killer: Dictionary = res.winner
	var victim: Dictionary = res.loser
	check(String(victim.status) == "dead" and int(killer.get("demerits", 0)) >= 3, "a lethal feud: a death, and the Guild punishes the killer")
	if victim == v:
		check(RankManager.rank_index(String(killer.rank)) == 1 and MemoryManager.about_of(vf, MemoryManager.key_npc(killer)).any(func(m): return m.kind == "killed_my_friend"), "the killer drops a rank; the victim's friends remember who did it")
	var res2 = DramaManager.confront(p, mk.call(["kind"]), mk.call(["kind"]), 452, false)
	check(String(res2.loser.status) == "injured", "a non-lethal brawl leaves the loser injured")
	# invitations
	var i1 = mk.call(["kind"])
	var i2 = mk.call(["cheerful"])
	RelationsManager.change(p, i1, i2, 80, 460)
	var ic = DramaManager._new_company(p, i1, i2, 460)
	i1.rapport = 50
	p.town_state["party"] = []
	var day = WorldClock.day(p)
	p.town_state["invitation"] = {"company": int(ic.id), "expires": day + 3}
	check(JournalScreen.build_text(p).contains("invited you along"), "the Journal shows an invitation")
	var acc = DramaManager.accept_invitation(p)
	check(acc.ok and PartyManager.members(p).size() == 2 and DramaManager.is_guest(i1), "accepting brings the company along as guests")
	DramaManager.on_expedition_end(p, true)
	check(PartyManager.members(p).is_empty() and String(i1.status) == "idle" and MemoryManager.about_of(i2, "you").any(func(m): return m.kind == "shared_victory"), "after the expedition they go home remembering it")
	for j in range(3):
		p.town_state["invitation"] = {"company": int(ic.id), "expires": day + 3}
		DramaManager.decline_invitation(p)
	check(int(i1.rapport) < 55, "decline them three times and they cool a little")
	# jealousy
	var yan = mk.call(["loyal"])
	yan.personality.archetype = "yandere"
	yan.personality.stage = 1
	yan.rapport = 70
	var fav = mk.call(["kind"])
	fav.rapport = 85
	var did: Array = []
	for j in range(12):
		fav.status = "idle"
		did.append(DramaManager.jealousy_step(p, yan, 470 + j * 7))
	check("gossip" in did and MemoryManager.opinion(yan, MemoryManager.key_npc(fav)) <= -40, "a jealous Yandere resents your favourite, then spreads poison (%s)" % ", ".join(did.slice(0, 6)))
	check(AdventurerManager.active(p).any(func(n): return MemoryManager.about_of(n, MemoryManager.key_npc(fav)).any(func(m): return m.kind == "slandered")), "others heard the gossip")
	yan.rapport = 10
	DramaManager._jealousy_week(p, 560)
	check(yan.get("broken", false) and int(yan.rivalry) >= 5, "let their devotion sour and they break: a nemesis")
	CharacterManager.current_character_resource.set_meta("current_character", prev_cur)

## Personalities: archetypes, drives, flaws, quirks, voices, arcs, your voice.
func _personality_checks() -> void:
	var p = make_player()
	AdventurerManager.state(p)
	var roster = AdventurerManager.active(p)
	check(roster.all(func(n): return n.has("personality") and PersonalityManager.archetypes().has(String(n.personality.archetype))), "every adventurer has an archetype")
	var seen := {}
	for i in range(60):
		seen[String(AdventurerManager.generate(p).personality.archetype)] = true
	check(seen.size() >= 8, "archetypes vary (%d kinds in 60)" % seen.size())
	var lazy = AdventurerManager.generate(p)
	lazy.traits = ["lazy"]
	lazy.personality.archetype = "lazy_genius"
	lazy.personality.drive = "family_name"
	lazy.personality.flaw = "greed"
	check(AdventurerManager.trait_sum(lazy, "success") >= 0.1 and AdventurerManager.trait_sum(lazy, "job_chance") < 0.0, "archetype mods feed the simulation (Lazy Genius: fewer jobs, better odds)")
	var ts = AdventurerManager._add(p, AdventurerManager.generate(p))
	ts.personality.archetype = "tsundere"
	ts.personality.stage = 0
	ts.rapport = 50
	check(PersonalityManager.mood(ts) == "friendly", "a Tsundere seems colder than they are (%s at rapport 50)" % PersonalityManager.mood(ts))
	var l = PersonalityManager.line(ts, "greeting")
	check(l != "" and not l.contains("{"), "voice lines fill in ({you} -> name): %s" % l)
	AdventurerManager._set_rapport(ts, 25)
	check(String(PersonalityManager.stage_data(ts).id) == "honest" and PersonalityManager.mood(ts) == "devoted", "rapport moves them along their arc (Tsundere: honest at 70+)")
	ts.chats = 0
	ts.rapport = 0
	check(not PersonalityManager.drive_known(ts) and not PersonalityManager.flaw_known(ts), "drives and flaws start hidden")
	ts.chats = 5
	ts.rapport = 55
	check(PersonalityManager.drive_known(ts) and PersonalityManager.flaw_known(ts) and PersonalityManager.describe(ts).contains("Drive:"), "they reveal with chats and rapport")
	var ph = AdventurerManager.generate(p)
	ph.personality.flaw = "phobia"
	check(PersonalityManager.avoids(ph, String(ph.personality.place)) and not PersonalityManager.avoids(ph, "nowhere"), "a phobia makes them avoid one place")
	var av = AdventurerManager._add(p, AdventurerManager.generate(p))
	av.personality.drive = "avenge"
	av.personality.drive_done = false
	PersonalityManager.on_boss(p, av, String(av.personality.place))
	check(av.personality.drive_done, "an avenger's drive is fulfilled by a boss at that place")
	# your voice drifts with your choices
	p.town_state.erase("voice")
	check(PersonalityManager.player_archetype(p) == "", "your reputation starts neutral")
	for i in range(6):
		PersonalityManager.player_event(p, "help_wounded")
	check(PersonalityManager.player_archetype(p) == "big_sibling" and PersonalityManager.player_reputation(p).contains("Big Sibling"), "helping the wounded makes the Guild see you as a Big Sibling")

## Commissions, rumours and nemesis rivals.
func _town_life_checks() -> void:
	var p = make_player()
	var prev_cur = CharacterManager.get_current_character()
	CharacterManager.current_character_resource.set_meta("current_character", p)
	# --- commissions
	CommissionManager.refresh(p)
	for shop in ["blacksmith", "alchemist", "enchanter"]:
		check(not CommissionManager.active(p, shop).is_empty(), "the %s posts a commission" % shop)
	var a = CommissionManager.active(p, "blacksmith")
	check(not CommissionManager.deliver(p, "blacksmith").ok, "can't deliver without the materials")
	var sword = _make_gear("rare")
	var cost0 = BlacksmithManager.get_upgrade_cost(sword).gold
	var gold0 = p.currency.copper
	for i in range(2):
		a = CommissionManager.active(p, "blacksmith")
		_give(p, String(a.item), int(a.qty))
		var r = CommissionManager.deliver(p, "blacksmith")
		if i == 0:
			check(r.ok, "delivering pays (%s)" % r.reason)
	check(p.currency.copper > gold0 and CommissionManager.done(p, "blacksmith") == 2 and CommissionManager.tier_name(p, "blacksmith") == "Known", "two deliveries: Known standing")
	check(BlacksmithManager.get_upgrade_cost(sword).gold < cost0 or cost0 <= 10, "standing makes the Blacksmith cheaper (%d -> %d)" % [cost0, BlacksmithManager.get_upgrade_cost(sword).gold])
	# --- rumours
	p.town_state.erase("rumours")
	RumorManager.refresh(p, true)
	var rl = RumorManager.list(p)
	check(rl.size() == int(RumorManager.cfg().max_active), "the Tavern has %d rumours" % rl.size())
	var rum = rl[0]
	rum.type = "elite"
	rum.affix = "swift"
	for other in rl.slice(1):   # random rumours could share the floor
		other.type = "cache"
	var got = RumorManager.take_elite(p, String(rum.location), int(rum.floor))
	check(not got.is_empty() and RumorManager.take_elite(p, String(rum.location), int(rum.floor)).is_empty(), "a rumoured elite appears once")
	MomentumSystem.clear_accumulated_loot()
	var line = RumorManager.claim(p, int(rum.id))
	check(line.contains("rumour was true") and int(MomentumSystem.momentum_loot_accumulated.currency) > 0 and RumorManager.list(p).size() == rl.size(), "beating it banks the bonus and ends the rumour")
	var cache = RumorManager.list(p)[0]
	cache.type = "cache"
	var keep_active = DungeonStateManager.active_player
	DungeonStateManager.active_player = p
	var before_bank = int(MomentumSystem.momentum_loot_accumulated.currency)
	GameEvents.floor_cleared.emit(String(cache.location), int(cache.floor))
	check(int(MomentumSystem.momentum_loot_accumulated.currency) > before_bank and not RumorManager.list(p).has(cache), "clearing a rumoured floor finds the cache")
	DungeonStateManager.active_player = keep_active
	MomentumSystem.clear_accumulated_loot()
	# --- nemesis rivals
	AdventurerManager.state(p)
	var npc = AdventurerManager._add(p, AdventurerManager.generate(p, [2, 2], true))
	npc.status = "idle"
	npc.rivalry = 3
	npc.traits = ["cruel"]
	check(not EncounterManager.candidates(p, "nemesis").has(npc), "a fresh rival (rivalry 3) isn't a nemesis yet")
	npc.rivalry = 5
	check(EncounterManager.candidates(p, "nemesis").has(npc) and not EncounterManager.candidates(p, "saboteur").has(npc), "rivalry 5 makes a nemesis (not a mere saboteur)")
	var foe = EncounterManager.build_nemesis(p, npc)
	check(foe.level >= p.level + 2 and foe.name.contains("Nemesis") and not foe.is_player, "a nemesis returns stronger (level %d)" % foe.level)
	var enc = {"type": "nemesis", "npc_id": int(npc.id), "location": "the_dungeon"}
	var lines = EncounterManager.finish(enc, p, true, [foe])
	var banked: Array = MomentumSystem.momentum_loot_accumulated.equipment_instances
	check(not banked.is_empty() and banked[0].display_name.begins_with(String(npc.name).get_slice(" ", 0)) and int(npc.rivalry) == 0 and not npc.get("nemesis", false),
		"beating a nemesis wins their signature item (%s)" % (banked[0].display_name if not banked.is_empty() else "none"))
	MomentumSystem.clear_accumulated_loot()
	# --- new recipes
	for id in ["field_dressing", "healing_mist", "ironbark_tonic", "sages_draught", "prayer_incense", "hide_ward", "hunters_focus",
			"firestorm_bomb", "shock_net", "tidal_flask", "marking_dye", "stagger_stone", "elixir_of_dawn", "grand_panacea"]:
		check(AlchemyManager.get_recipe(id).has("output") and ItemManager.get_item(String(AlchemyManager.get_recipe(id).output)) != null, "recipe %s makes a real item" % id)
	_give(p, "linen_cloth", 2)
	_give(p, "glowcap_mushroom", 2)
	var cr = AlchemyManager.craft(p, "field_dressing", 1)
	check(cr.ok and p.count_owned("field_dressing") == 2, "Field Dressing: linen + glowcap make two (%s)" % cr.reason)
	var tonic: Item = ItemManager.get_item("ironbark_tonic")
	tonic.use(p, [p])
	check(p.buff_manager.buffs.has(Skill.AttributeTarget.ENDURANCE), "Ironbark Tonic raises Endurance (new buff types)")
	var foe2 = EnemyFactory.create_enemy(1, 1, 1)
	ItemManager.get_item("marking_dye").use(p, [foe2])
	check(foe2.status_manager.has_effect(Skill.StatusEffect.MARKED), "Marking Dye sets up a combo (Marked)")
	check(ItemTips.effect_line(ItemManager.get_item("marking_dye")).begins_with("Inflicts Marked"), "status-only items read 'Inflicts ...'")
	check(not AlchemyManager.is_known(p, "grand_panacea"), "the Grand Panacea needs Valued standing with the Alchemist")
	var ast = CommissionManager._state(p)["alchemist"]
	ast.done = 5
	check(AlchemyManager.is_known(p, "elixir_of_dawn") and AlchemyManager.is_known(p, "grand_panacea"), "Alchemist standing teaches the special recipes")
	CharacterManager.current_character_resource.set_meta("current_character", prev_cur)

## Bonds (scenes per rapport tier, duo techs) and companion opinions.
func _bond_checks() -> void:
	var p = make_player()
	AdventurerManager.state(p)
	var npc = AdventurerManager._add(p, AdventurerManager.generate(p, [3, 3]))
	npc.traits = ["reckless"]
	npc.cls = "Samurai"
	npc.status = "idle"
	npc.rapport = 10
	check(BondManager.pending(p).is_empty(), "no bond scene below the first tier")
	npc.rapport = 80
	check(BondManager.pending(p).size() == 1, "reaching a tier queues a bond scene")
	var sc1 = BondManager.play_scene(p, npc)
	check(sc1.title.contains("Acquainted") and sc1.text.contains(String(npc.name)) and not sc1.bonded, "the first scene uses the companion's trait lines (%s)" % sc1.title)
	BondManager.play_scene(p, npc)
	var sc3 = BondManager.play_scene(p, npc)
	check(sc3.bonded and BondManager.is_bonded(npc) and sc3.text.contains("Twin Moon Cut"), "the last tier bonds you and unlocks their class's duo tech")
	check(BondManager.play_scene(p, npc).is_empty() and BondManager.pending(p).is_empty(), "each scene plays once")
	var duo = BondManager.duo_skill(npc)
	check(duo != null and duo.category == "ULTIMATE" and duo.mp_cost == 0 and duo.power > 0, "a duo tech is a Link skill with no MP/SP cost")
	# in battle: only with the bonded companion standing beside you
	var partner = AutoBattler.build_hero(npc)
	partner.set_meta("npc_id", int(npc.id))
	check(BondManager.battle_duos(p, [p, partner]).size() == 1, "the duo tech is offered while your Bonded companion fights")
	partner.current_hp = 0
	check(BondManager.battle_duos(p, [p, partner]).is_empty(), "not while they're down")
	# opinions: party members react by trait
	PartyManager.party_ids(p).append(int(npc.id))
	var r0 = int(npc.rapport)
	var lines = BondManager.react(p, "press_on")
	check(int(npc.rapport) == r0 + 2 and lines.size() == 1 and lines[0].contains("approves"), "a Reckless companion approves of pressing on (%s)" % str(lines))
	BondManager.react(p, "omens", 2)
	check(int(npc.rapport) == min(100, r0 + 2 + 4), "reactions scale with how many Omens you take")
	BondManager.react(p, "breather")
	check(int(npc.rapport) == min(100, r0 + 5), "and frowns at a Breather")
	PartyManager.party_ids(p).clear()

## Omens (and boons) modify the current expedition only.
func _run_state_checks() -> void:
	RunState.clear()
	var foe = EnemyFactory.create_enemy(1, 2, 1)
	var dmg = foe.damage_multiplier
	var hp = foe.max_hp
	var need = BattleRules.break_max(foe, false)
	RunState.set_omens(["bloodmoon", "ironhide", "brittle", "discord"])
	check(RunState.omens.size() == int(RunState.omen_data().get("max_omens", 3)), "Omens are capped (%d)" % RunState.omens.size())
	check(is_equal_approx(RunState.reward_bonus(), 0.5), "Omen loot bonus adds up (+%d%%)" % int(RunState.reward_bonus() * 100))
	RunState.apply_to_enemies([foe])
	check(foe.damage_multiplier > dmg * 1.15 and foe.max_hp > hp and foe.current_hp == foe.max_hp, "Bloodmoon + Ironhide: harder-hitting, tougher enemies")
	RunState.apply_to_enemies([foe])
	check(is_equal_approx(foe.damage_multiplier, dmg * 1.2), "Omens apply to an enemy only once")
	check(BattleRules.break_max(foe, false) == max(1, need - 1) and BattleRules.break_max(foe, true) == max(1, int(BattleRules.cfg().break.hero_hits) - 1), "Brittle: one fewer hit to Break, for heroes too")
	var w = RewardsManager.roll_wave_rewards({"current_wave": 1, "current_floor": 1, "is_boss_fight": false, "enemies": [], "momentum_level": 0})
	RunState.clear()
	var w0 = RewardsManager.roll_wave_rewards({"current_wave": 1, "current_floor": 1, "is_boss_fight": false, "enemies": [], "momentum_level": 0})
	check(w.currency == int(round(w0.currency * 1.5)), "Omens boost wave gold (%d vs %d)" % [w.currency, w0.currency])
	RunState.set_omens(["dim_sight"])
	check(Bestiary.shown_weaknesses(foe) == ["???"], "Dim Sight hides every weakness")
	RunState.clear()
	# Boons: picked after bosses, also run-long
	var offer = BoonPicker.offer()
	check(offer.size() == int(RunState.boon_data().get("offer_count", 3)), "a boss offers %d boons" % offer.size())
	RunState.add_boon("ruthless")
	RunState.add_boon("steadfast")
	check(not BoonPicker.offer(99).has("ruthless"), "boons you hold aren't offered again")
	check(BattleRules.break_max(foe, false) == max(1, need - 1) and BattleRules.break_max(foe, true) == int(BattleRules.cfg().break.hero_hits) + 1, "Ruthless and Steadfast shift Break thresholds")
	RunState.add_boon("keen_eye")
	check(not Bestiary.shown_weaknesses(foe).has("???") or BattleRules.weaknesses(foe).is_empty(), "Keen Eye shows every weakness")
	RunState.add_boon("plunder")
	var wp = RewardsManager.roll_wave_rewards({"current_wave": 1, "current_floor": 1, "is_boss_fight": false, "enemies": [], "momentum_level": 0})
	check(wp.currency == int(round(w0.currency * 1.25)), "Plunder: +25% wave gold")
	GameEvents.expedition_ended.emit("the_dungeon", true)
	check(RunState.omens.is_empty() and RunState.boons.is_empty(), "Omens and boons end with the expedition")

func _enchant_checks() -> void:
	var p = make_player()
	var sword = _make_gear("common")
	sword.status_effect_type = Skill.StatusEffect.NONE
	sword.stat_modifiers = {}
	p.inventory.add_item(sword, 1)
	p.currency.copper = 100000
	check(EnchantManager.next_rarity(sword) == "uncommon", "an enchant raises common to uncommon")
	var cost = EnchantManager.get_cost(sword, "ember")
	check(cost.materials.get("embershard_fragment", 0) == 3 and not cost.materials.has("monster_core"), "the enchant's material pays for it (%s)" % str(cost))
	check(not EnchantManager.can_afford(p, cost), "no materials = can't enchant")
	_give(p, "embershard_fragment", 40)
	_give(p, "monster_core", 5)
	var dmg = sword.damage
	sword.enchant_fails = 99   # force success for the effect check
	var r = EnchantManager.enchant(p, sword, "ember")
	check(r.ok and r.success and sword.rarity == "uncommon" and sword.enchants == ["Ember"], "a successful enchant raises the rarity and records the enchant (%s)" % r.reason)
	check(sword.damage > dmg and sword.stat_modifiers.get(Skill.AttributeTarget.STRENGTH, 0) > 0, "it rescales damage (%d -> %d) and adds Strength" % [dmg, sword.damage])
	check(sword.status_effect_type == Skill.StatusEffect.BURN and sword.status_effect_chance > 0.0, "an Ember weapon can Burn")
	check(p.count_owned("embershard_fragment") == 37 and sword.enchant_fails == 0, "materials spent, Attuned reset")
	# failure: payment lost, item unchanged, Attuned grows
	var helm = _make_gear("magic", false)
	p.inventory.add_item(helm, 1)
	var before = [helm.rarity, helm.armor_value, helm.stat_modifiers.duplicate()]
	var base_chance = EnchantManager.get_success_chance(helm)
	_give(p, "frostroot_chunk", 20)
	helm.enchant_fails = -20   # forces a 0% chance
	var frost_before = p.count_owned("frostroot_chunk")
	var res = EnchantManager.enchant(p, helm, "frost")
	check(res.ok and not res.success and helm.rarity == before[0] and helm.armor_value == before[1] and helm.stat_modifiers == before[2],
		"a failed enchant leaves the item unharmed")
	check(p.count_owned("frostroot_chunk") < frost_before and helm.enchant_fails == -19, "a failed enchant loses the materials and adds Attuned")
	helm.enchant_fails = 2
	check(is_equal_approx(EnchantManager.get_success_chance(helm), min(1.0, base_chance + 0.2)), "each earlier failure adds +10%% (Attuned x2: %d%%)" % int(EnchantManager.get_success_chance(helm) * 100))
	helm.enchant_fails = 99
	EnchantManager.enchant(p, helm, "frost")
	check(helm.rarity == "rare" and helm.enchants == ["Frost"], "magic -> rare with Frost")
	# cap: nothing above Epic
	var epic = _make_gear("epic")
	check(not EnchantManager.can_enchant(epic) and not EnchantManager.can_enchant(_make_gear("legendary")), "enchanting stops at Epic")
	# equipped items keep the character's bonuses in sync
	var ring = _make_gear("common", false)
	ring.stat_modifiers = {}
	ring.enchant_fails = 99
	p.equipment[ring.slot] = ring
	ring.apply_stat_modifiers(p)
	_give(p, "glowcap_mushroom", 5)
	var faith_before = int(p.equipment_bonuses.get("faith", 0))
	EnchantManager.enchant(p, ring, "glow")
	check(int(p.equipment_bonuses.get("faith", 0)) == faith_before + int(ring.stat_modifiers.get(Skill.AttributeTarget.FAITH, 0)), "enchanting worn gear updates the character's bonuses")
	p.equipment[ring.slot] = null
	# save round trip
	var d = sword.get_upgrade_save_data()
	var copy = _make_gear("common")
	copy.apply_upgrade_save_data(d)
	check(copy.enchants == ["Ember"], "enchants survive a save")

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
	var gpl = float(BlacksmithManager.cfg.get("gold_per_level", 0.5))
	check(c1.gold == max(10, int(round(sword.value * gpl))) and c1.materials.get("iron_ore", 0) == 1 and c1.materials.get("wood", 0) == 1,
		"+1 costs value x %d%%, 1 iron ore, 1 wood (%s)" % [int(gpl * 100), str(c1)])
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
	armor.type = "mail"   # mail takes ore (cloth and leather are checked below)
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
	p.max_floor_unlocked = 3
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
	p.take_owned("wood", p.count_owned("wood"))   # earlier random rewards may have paid out wood
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
	check(not GuildManager.get_active(p).has(late) and GuildManager.get_demerits(p) == dem1 + 1, "missing the deadline (3 one-day expeditions) fails the bounty with a demerit")
	check(GuildManager.get_active(p).has(boss) and GuildManager.get_active(p).has(depth), "finished bounties don't expire before turn-in")
	check(GuildManager.state(p).board.size() == 3, "the board refreshes after 3 days")
	
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

## A real Battle.tscn fight with two companions: one you control, one on Auto.
func _party_battle_run() -> void:
	print("=== BATTLE: party of 3")
	var player = make_player(-2)
	var manual = AutoBattler.build_hero({"name": "Ally Manual", "race": "Hume", "cls": "Cleric", "level": 5, "gear_floor": 3, "branch": 0})
	var auto = AutoBattler.build_hero({"name": "Ally Auto", "race": "Durgar", "cls": "Berserker", "level": 5, "gear_floor": 3, "branch": 0})
	auto.set_meta("auto", true)
	for a in [manual, auto]:
		a.inventory = player.inventory
	var g = EnemyGroup.new()
	g.ally_count = 2
	EnemyFactory.set_location("the_dungeon")
	g.initialize(1, 3, false)
	var enemies: Array[CharacterData] = g.enemies
	var kills_before := kills_seen
	var battle = load("res://scenes/battle/Battle.tscn").instantiate()
	get_tree().root.add_child(battle)
	var done := [false, false]
	battle.battle_completed.connect(func(won, _xp): done[0] = true; done[1] = won)
	battle.set_player(player)
	battle.set_allies([manual, auto])
	battle.set_enemies(enemies)
	battle.set_dungeon_info(false, 3, 1, 5, "Party smoke test")
	var acted := {}
	var frames := 0
	var auto_mine := false
	while not done[0] and frames < 90000:
		frames += 1
		await get_tree().process_frame
		for child in battle.get_children():
			if child.has_signal("take_breather_selected") and not child.has_meta("clicked"):
				child.set_meta("clicked", true)
				child.take_breather_selected.emit()
		if battle.get("_awaiting_player_action") and not battle.get("_action_in_progress") and not battle.context.main_action_taken:
			var who: CharacterData = battle.ui_controller.player
			if who == auto:
				auto_mine = true   # an Auto ally should never wait for input
			var living = battle.context.get_living_enemies()
			if living.is_empty():
				continue
			acted[who.name] = acted.get(who.name, 0) + 1
			battle.ui_controller.action_selected.emit(BattleAction.attack(who, living[0]))
		elif battle.get("turn_queue") and battle.turn_queue.current_actor() == auto:
			acted["auto"] = 1
	check(done[0], "party battle completed (frames=%d)" % frames)
	check(acted.get(player.name, 0) > 0 and acted.get("Ally Manual", 0) > 0, "you act for yourself and for the manual companion (%s)" % str(acted))
	check(not auto_mine and acted.has("auto"), "the Auto companion acts on its own")
	check(enemies.size() == 4 or enemies.size() >= 3, "a party of 3 faces a bigger wave (%d enemies)" % enemies.size())
	var heroes_alive = [player, manual, auto].any(func(h): return h.is_alive())
	check(done[1] == heroes_alive, "party result matches the heroes' state (won=%s)" % done[1])
	if done[1]:
		check(kills_seen - kills_before == enemies.size(), "only enemies count as kills (%d)" % (kills_seen - kills_before))
		check([player, manual, auto].all(func(h): return h.current_hp > 0), "knocked-out heroes get back up after a win")
	battle.queue_free()
	await get_tree().process_frame

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
