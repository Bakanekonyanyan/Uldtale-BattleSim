extends Node
# res://tests/balance_sim.gd
# Balance simulator: plays thousands of battles synchronously through the real
# CombatEngine, TurnQueue, EnemyAI and EnemyGroup generation (no animations),
# with a sensible auto-pilot player. Use it to check any change to
# BattleFormulas / EnemyFactory / status_effects.json before playtesting.
#
# Run:   godot --headless res://tests/balance_sim.tscn -- <label>
# Output: user://balance_<label>.txt (path is printed). Labels starting with
#         "diag" print a detailed boss-fight breakdown instead.

const CLASSES = ["Paladin", "Necromancer", "Myrmidon", "Cleric", "Samurai", "Elementalist", "Druid", "Monk"]
const N = 150

var out := []
var sim_location := "the_dungeon"  # expedition location used by make_enemies()
var start_potions := 0             # health + mana potions each hero starts a run with
var use_setup := true              # auto-pilot casts buffs/debuffs (false = damage only)
var t := {}  # tallies

func log_line(s: String) -> void:
	out.append(s)

func _ready():
	var args = OS.get_cmdline_user_args()
	var mode = args[0] if args.size() > 0 else "baseline"
	log_line("MODE " + mode)
	if mode.begins_with("classes"):
		class_report()
		var f3 = FileAccess.open("user://balance_%s.txt" % mode, FileAccess.WRITE)
		f3.store_string("\n".join(out)); f3.close()
		get_tree().quit(); return
	if mode.begins_with("diag"):
		diag_boss()
		var f2 = FileAccess.open("user://balance_%s.txt" % mode, FileAccess.WRITE)
		f2.store_string("\n".join(out)); f2.close()
		get_tree().quit(); return

	# --- 1. Single fights at full HP, floor 1, per class and wave ---
	log_line("\n== Floor 1, level 1, no gear: win% per single battle (full HP each fight) ==")
	log_line("class         w1   w3   w5   boss | dmgTaken: direct  status | avg turns")
	for cls in CLASSES:
		var row = "%-12s" % cls
		var direct := 0.0; var status := 0.0; var turns := 0.0; var fights := 0
		for wave in [1, 3, 5, 6]:
			var wins := 0
			for i in range(N):
				var r = sim_fight(cls, 1, wave)
				wins += 1 if r.won else 0
				direct += r.direct; status += r.status; turns += r.turns; fights += 1
			row += " %4d" % int(100.0 * wins / N)
		row += " | %6.0f%% %6.0f%% | %.1f" % [100 * direct / max(1, direct + status), 100 * status / max(1, direct + status), turns / fights]
		log_line(row)

	# --- 2. Full floor-1 run (5 waves + boss), HP carries over (Press On) ---
	log_line("\n== Floor 1 full run (XP/levels, Breather <50% HP, <80% before boss): clear % ==")
	for cls in CLASSES:
		var clears := 0
		var reached := {}
		for i in range(N):
			MomentumSystem.reset_momentum()
			var r = sim_run(cls, 1)
			if r.cleared: clears += 1
			reached[r.wave] = reached.get(r.wave, 0) + 1
		log_line("%-12s clear %3d%%   died at wave: %s" % [cls, int(100.0 * clears / N), str(reached)])

	# --- 2c. Same run, carrying 5 Health + 5 Mana potions (the carry limit) ---
	log_line("\n== Floor 1 full run carrying 5 Health + 5 Mana potions: clear % ==")
	start_potions = 5
	for cls in CLASSES:
		var clears := 0
		for i in range(N):
			MomentumSystem.reset_momentum()
			if sim_run(cls, 1).cleared: clears += 1
		log_line("%-12s clear %3d%%" % [cls, int(100.0 * clears / N)])
	start_potions = 0
	
	# --- 2d. Floor 1 full run by expedition location ---
	log_line("\n== Floor 1 full run by location (no potions): clear % ==")
	var loc_header = "%-12s" % "class"
	for loc in LocationManager.get_ids():
		loc_header += " %14s" % LocationManager.get_display_name(loc)
	log_line(loc_header)
	for cls in ["Paladin", "Samurai", "Cleric", "Elementalist", "Druid"]:
		var row = "%-12s" % cls
		for loc in LocationManager.get_ids():
			sim_location = loc
			var clears := 0
			for i in range(N):
				MomentumSystem.reset_momentum()
				if sim_run(cls, 1).cleared: clears += 1
			row += " %13d%%" % int(100.0 * clears / N)
		log_line(row)
	sim_location = "the_dungeon"
	
	# --- 2b. Campaign: floors 1..4 back to back, same character ---
	log_line("\n== Campaign: floors 1-4 back-to-back, leveling up (clear % of each floor | avg level reached) ==")
	for cls in CLASSES:
		var row = "%-12s" % cls
		var alive := N
		var levels := 0.0
		var players: Array = []
		for i in range(N): players.append(null)
		for floor_num in range(1, 5):
			var cleared := 0
			for i in range(N):
				if players[i] is String: continue
				MomentumSystem.reset_momentum()
				var pl = players[i] if players[i] != null else make_player(cls)
				var r = sim_run(cls, floor_num, pl)
				if r.cleared:
					cleared += 1; players[i] = r.player
				else:
					players[i] = "dead"
			var lv := 0.0; var cnt := 0
			for pp in players:
				if pp is CharacterData: lv += pp.level; cnt += 1
			row += "  F%d %3d%% (L%.1f)" % [floor_num, int(100.0 * cleared / N), lv / max(1, cnt)]
		log_line(row)
	
	# --- 3. Damage profile for one representative matchup ---
	log_line("\n== Per-hit damage, floor 1 (Paladin vs regular enemies) ==")
	t.clear()
	for i in range(N):
		sim_fight("Paladin", 1, 1)
	for k in t.keys():
		var v = t[k]
		log_line("%-34s n=%4d avg=%6.1f" % [k, v[1], v[0] / max(1, v[1])])

	var f = FileAccess.open("user://balance_%s.txt" % mode, FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	print("BALANCE REPORT WRITTEN: ", ProjectSettings.globalize_path("user://balance_%s.txt" % mode))
	get_tree().quit()

## Fast class-balance report: floor-1 full runs. Each class is judged by its
## better play style (damage-only vs buff/debuff set-up), without and with potions.
func class_report() -> void:
	var n = 200
	log_line("== Class balance: floor-1 full run clear %% (N=%d, The Dungeon) ==" % n)
	log_line("class        dmg-only   set-up  | best, no potions   best, 5+5 potions")
	for cls in CLASSES:
		var rates := {}
		for setup in [false, true]:
			use_setup = setup
			rates[setup] = _clear_rate(cls, n, 0)
		var best_setup = rates[true] > rates[false]
		use_setup = best_setup
		var with_potions = _clear_rate(cls, n, 5)
		log_line("%-12s %7d%%  %7d%%  | %10d%% (%s)  %12d%%" % [cls, rates[false], rates[true],
			max(rates[false], rates[true]), "set-up" if best_setup else "dmg", with_potions])
	use_setup = true
	start_potions = 0

func _clear_rate(cls: String, n: int, potions: int) -> int:
	start_potions = potions
	var clears := 0
	for i in range(n):
		MomentumSystem.reset_momentum()
		if sim_run(cls, 1).cleared: clears += 1
	start_potions = 0
	return int(100.0 * clears / n)

func diag_boss() -> void:
	# Play waves 1-5 as a run, then log the boss fight in detail
	for cls in ["Paladin", "Elementalist"]:
		for i in range(4):
			MomentumSystem.reset_momentum()
			var p = make_player(cls)
			var ok = true
			for wave in range(1, 6):
				var en = make_enemies(1, wave)
				var xp := 0
				for e in en: xp += e.level * 50
				var r = fight(p, en, 1, false)
				log_line("  %s wave %d: won=%s L%d HP %d/%d MP %d SP %d momentum %d status=%s" % [cls, wave, r.won, p.level, p.current_hp, p.max_hp, p.current_mp, p.current_sp, MomentumSystem.get_momentum(), p.get_status_effects_string()])
				if not r.won: ok = false; break
				p.gain_xp(xp)
				while p.attribute_points > 0: spend_point(p)
				if p.current_hp < p.max_hp * 0.5:
					MomentumSystem.reset_momentum()
					p.current_hp = p.max_hp; p.current_mp = p.max_mp; p.current_sp = p.max_sp
					p.status_manager.clear_all_effects()
				else:
					MomentumSystem.gain_momentum()
			if not ok: continue
			var bosses = make_enemies(1, 6)
			var b = bosses[0]
			log_line("%s L%d HP %d/%d AP %.0f SP %.0f pdef %.0f | BOSS %s HP %d AP %.0f SP %.0f pdef %.0f mdef %.0f dodge %.2f momentum %d" % [cls, p.level, p.current_hp, p.max_hp, p.attack_power, p.spell_power, BattleFormulas.physical_defense(p), b.name, b.max_hp, b.attack_power, b.spell_power, BattleFormulas.physical_defense(b), BattleFormulas.magical_defense(b), b.dodge, MomentumSystem.get_momentum()])
			t.clear()
			var r = fight(p, bosses, 1, true)
			log_line("   -> won=%s turns=%d boss HP left %d" % [r.won, r.turns, b.current_hp])
			for k in t.keys():
				log_line("      %-30s n=%3d avg=%5.1f" % [k, t[k][1], t[k][0] / max(1, t[k][1])])

func tally(key: String, amount: float) -> void:
	if not t.has(key): t[key] = [0.0, 0]
	t[key][0] += amount; t[key][1] += 1

func make_player(cls: String) -> CharacterData:
	var p = CharacterFactory.create_character("Hero", "Hume", cls, true)
	p.reset_for_new_battle()
	if start_potions > 0:
		p.add_to_pack(ItemManager.get_item("health_potion"), start_potions)
		p.add_to_pack(ItemManager.get_item("mana_potion"), start_potions)
	return p

func make_enemies(floor_num: int, wave: int) -> Array[CharacterData]:
	EnemyFactory.set_location(sim_location)
	var g = EnemyGroup.new()
	g.initialize(floor_num, wave, wave == 6)
	return g.enemies

func sim_run(cls: String, floor_num: int, p: CharacterData = null) -> Dictionary:
	# Mirrors the real loop: XP + level-ups after each win, Breather (full heal,
	# momentum reset) when HP < 50%, otherwise Press On (momentum +1, no heal).
	if p == null:
		p = make_player(cls)
		MomentumSystem.reset_momentum()
	for wave in range(1, 7):
		var enemies = make_enemies(floor_num, wave)
		var xp := 0
		for e in enemies: xp += e.level * 50 * floor_num
		var r = fight(p, enemies, floor_num, wave == 6)
		if not r.won:
			return {"cleared": false, "wave": wave, "player": p}
		p.gain_xp(xp)
		while p.attribute_points > 0:
			spend_point(p)
		# Breather below 50% HP, or below 80% right before the boss
		var threshold = 0.8 if wave == 5 else 0.5
		if p.current_hp < p.max_hp * threshold:
			MomentumSystem.reset_momentum()
			p.current_hp = p.max_hp; p.current_mp = p.max_mp; p.current_sp = p.max_sp
			p.status_manager.clear_all_effects()
		else:
			MomentumSystem.gain_momentum()
	# floor cleared -> next floor starts fresh
	p.reset_for_new_battle()
	MomentumSystem.reset_momentum()
	return {"cleared": true, "wave": 7, "player": p}

func spend_point(p: CharacterData) -> void:
	var main = p.attack_power_type if p.attack_power_type != "" else "strength"
	if p.spell_power > p.attack_power:
		main = p.spell_power_type if p.spell_power_type in ["intelligence", "arcane", "faith"] else "intelligence"
	var choice = main if p.attribute_points % 3 != 0 else "vitality"
	p.spend_attribute_point(choice)

func sim_fight(cls: String, floor_num: int, wave: int) -> Dictionary:
	return fight(make_player(cls), make_enemies(floor_num, wave), floor_num, wave == 6)

func fight(p: CharacterData, enemies: Array[CharacterData], floor_num: int, boss: bool) -> Dictionary:
	var ctx = BattleContext.new()
	ctx.player = p; ctx.enemies = enemies
	ctx.set_dungeon_info(boss, 1, floor_num, 5, "")
	var engine = CombatEngine.new(); engine.initialize_multi(p, enemies)
	var q = TurnQueue.new(); q.initialize(p, enemies)
	var planner = EnemyTurnPlanner.new(); planner.initialize(ctx)
	var direct := 0.0; var status := 0.0; var turns := 0

	while not ctx.is_battle_decided() and turns < 300:
		var actor = q.current_actor()
		if actor == null: break
		turns += 1
		actor.reset_defense()

		var hp0 = p.current_hp
		engine.process_status_effects(actor)
		if actor == p: status += hp0 - p.current_hp
		if not actor.is_alive():
			q.remove(actor); q.advance(); continue
		if actor.is_stunned:
			actor.is_stunned = false; q.advance(); continue

		# Items are a free action (one per turn) before the main action
		if actor == p:
			var potion = potion_policy(p)
			if potion:
				engine.execute_action(potion)
				tally("player item " + potion.item_data.id, 1)
		
		var action: BattleAction = player_policy(p, ctx) if actor == p else planner.plan_action(actor)
		if action:
			var hp_before = p.current_hp
			var tgt_hp := {}
			for e in enemies: tgt_hp[e] = e.current_hp
			var res = engine.execute_action(action)
			if actor != p:
				var lost = hp_before - p.current_hp
				direct += max(0, lost)
				if lost > 0:
					tally("enemy %s" % ("skill " + action.skill_data.name if action.skill_data else "attack"), lost)
			else:
				var dealt := 0
				for e in enemies: dealt += tgt_hp[e] - e.current_hp
				tally("player %s" % ("skill " + action.skill_data.name if action.skill_data else BattleAction.ActionType.keys()[action.type].to_lower()), dealt)
		for c in [p] + enemies:
			if not c.is_alive(): q.remove(c)
		q.advance()

	return {"won": ctx.did_player_win(), "direct": direct, "status": status, "turns": turns}

# Drink a health potion below 40% HP, or a mana potion below 25% MP (casters).
func potion_policy(p: CharacterData) -> BattleAction:
	if p.current_hp < p.max_hp * 0.4 and p.inventory.get_quantity("health_potion") > 0:
		return BattleAction.item(p, p.inventory.get_item("health_potion"), [p])
	if p.spell_power > p.attack_power and p.current_mp < p.max_mp * 0.25 and p.inventory.get_quantity("mana_potion") > 0:
		return BattleAction.item(p, p.inventory.get_item("mana_potion"), [p])
	return null

# A sensible human-like policy:
#   heal when low -> buff self early -> debuff a fresh enemy -> best damage skill -> attack weakest
func player_policy(p: CharacterData, ctx: BattleContext) -> BattleAction:
	var living = ctx.get_living_enemies()
	living.sort_custom(func(a, b): return a.current_hp < b.current_hp)
	var enemy_hp := 0.0
	var enemy_max := 0.0
	for e in ctx.enemies:
		enemy_hp += e.current_hp; enemy_max += e.max_hp
	var fight_young = enemy_hp > enemy_max * 0.5  # set-up skills only pay off early
	
	var best: Skill = null
	var buff: Skill = null
	var debuff: Skill = null
	for sn in p.skills:
		var s: Skill = p.get_skill_instance(sn)
		if p.get_skill_cooldown(sn) > 0: continue
		var cost_ok = (p.current_sp >= s.sp_cost) if s.ability_type == Skill.AbilityType.PHYSICAL else (p.current_mp >= s.mp_cost)
		if not cost_ok: continue
		match s.type:
			Skill.SkillType.HEAL:
				if p.current_hp < p.max_hp * 0.4:
					return BattleAction.skill(p, s, [p])
			Skill.SkillType.BUFF:
				buff = s
			Skill.SkillType.DEBUFF, Skill.SkillType.INFLICT_STATUS:
				debuff = s
			Skill.SkillType.DAMAGE, Skill.SkillType.DRAIN:
				# MP/SP drains deal no HP damage - don't treat them as attacks
				if s.type == Skill.SkillType.DRAIN and s.drain_source != Skill.DrainTarget.HP:
					continue
				if best == null or s.power > best.power:
					best = s
	
	if use_setup and buff and fight_young and not p.buff_manager.has_buffs():
		return BattleAction.skill(p, buff, [p])
	if use_setup and debuff and fight_young:
		var fresh = living.filter(func(e): return not e.buff_manager.has_debuffs())
		if not fresh.is_empty():
			var tg: Array = living if debuff.target == Skill.TargetType.ALL_ENEMIES else [fresh[-1]]
			return BattleAction.skill(p, debuff, tg)
	if best:
		var tg: Array = living if best.target == Skill.TargetType.ALL_ENEMIES else [living[0]]
		return BattleAction.skill(p, best, tg)
	return BattleAction.attack(p, living[0])
