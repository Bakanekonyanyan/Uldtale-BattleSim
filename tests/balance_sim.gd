extends Node
# res://tests/balance_sim.gd
# Balance simulator: plays thousands of battles synchronously through the real
# CombatEngine, TurnQueue, EnemyAI and EnemyGroup generation (no animations),
# with a sensible auto-pilot player. Use it to check any change to
# BattleFormulas / EnemyFactory / status_effects.json before playtesting.
#
# Run:   godot --headless res://tests/balance_sim.tscn -- <label>
# Output: user://balance_<label>.txt (path is printed). Labels starting with
#         "diag" print a detailed boss-fight breakdown instead; "classes..." is
#         the fast class report; "tool" is the content manager's mode (see
#         tool_report for its options).

const CLASSES = ["Paladin", "Necromancer", "Myrmidon", "Cleric", "Samurai", "Elementalist", "Druid", "Monk",
	"Berserker", "Shinobi", "Kannagi", "Beastmaster"]
const N = 150

var out := []
var sim_location := "the_dungeon"  # expedition location used by make_enemies()
var start_potions := 0             # health + mana potions each hero starts a run with
var use_setup := true              # auto-pilot casts buffs/debuffs (false = damage only)
var sim_party := 0                 # companions (0-2) fighting beside the hero (tool --party=N)
const PARTY_CLASSES := ["Cleric", "Berserker", "Elementalist", "Samurai", "Druid", "Shinobi"]
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
	if mode == "tool":
		tool_report(args)
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

## Mode used by the content manager's "Balance sim" button. Options:
##   --classes=Paladin,Monk  --location=goblin_forest  --setup=both|on|off
##   --potions=5  --runs=150  --floor=1
## Prints (parsed by DevTools/cm/godot.py):
##   SIM PROGRESS|<done>|<total>
##   SIM ROW|<class>|<dmg-only %>|<set-up %>|<best %>|<best style>   (-1 = not run)
##   SIM DONE
func tool_report(args: Array) -> void:
	var opts := {"classes": ",".join(CLASSES), "location": "the_dungeon", "setup": "both", "potions": "0", "runs": "150", "floor": "1"}
	for a in args.slice(1):
		var kv = String(a).trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	var classes = Array(String(opts.classes).split(",", false))
	sim_location = String(opts.location)
	var runs = max(1, int(opts.runs))
	var potions = int(opts.potions)
	var floor_num = max(1, int(opts.floor))
	EnemyFactory.force_archetype = String(opts.get("archetype", ""))
	sim_party = clamp(int(opts.get("party", "0")), 0, 2)
	sim_policy = String(opts.get("policy", "smart"))
	var styles: Array = [false, true] if opts.setup == "both" else ([true] if opts.setup == "on" else [false])
	var total = classes.size() * styles.size()
	var done := 0
	print("SIM PROGRESS|0|%d" % total)
	for cls in classes:
		var rates := {false: -1, true: -1}
		for setup in styles:
			use_setup = setup
			start_potions = potions
			var clears := 0
			var died := {}
			for i in range(runs):
				MomentumSystem.reset_momentum()
				var r = sim_run(cls, floor_num)
				if r.cleared: clears += 1
				else: died[r.wave] = died.get(r.wave, 0) + 1
			rates[setup] = int(round(100.0 * clears / runs))
			if opts.has("deaths"):
				print("SIM DEATHS|%s|%s|%s" % [cls, "set-up" if setup else "damage-only", str(died)])
			done += 1
			print("SIM PROGRESS|%d|%d" % [done, total])
		var best_setup = rates[true] >= rates[false]
		print("SIM ROW|%s|%d|%d|%d|%s" % [cls, rates[false], rates[true], max(rates[false], rates[true]), "set-up" if best_setup else "damage-only"])
	use_setup = true
	start_potions = 0
	sim_location = "the_dungeon"
	EnemyFactory.force_archetype = ""
	print("SIM DONE")

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
				spend_talents(p)
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
	g.ally_count = sim_party
	g.initialize(floor_num, wave, wave == 6)
	return g.enemies

## Companions for a run: random classes, the hero's level, matching gear.
func make_allies(p: CharacterData, floor_num: int) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for i in range(sim_party):
		var cls = PARTY_CLASSES[RandomManager.randi() % PARTY_CLASSES.size()]
		var a = AutoBattler.build_hero({"name": "Ally %d" % (i + 1), "race": "Hume", "cls": cls, "level": p.level, "gear_floor": max(1, floor_num - 1), "branch": 0})
		a.inventory = p.inventory
		out.append(a)
	return out

func sim_run(cls: String, floor_num: int, p: CharacterData = null) -> Dictionary:
	# Mirrors the real loop: XP + level-ups after each win, Breather (full heal,
	# momentum reset) when HP < 50%, otherwise Press On (momentum +1, no heal).
	if p == null:
		p = make_player(cls)
		MomentumSystem.reset_momentum()
	var allies = make_allies(p, floor_num)
	for wave in range(1, 7):
		var enemies = make_enemies(floor_num, wave)
		var xp := 0
		for e in enemies: xp += e.level * 50 * floor_num
		var r = fight(p, enemies, floor_num, wave == 6, allies)
		for a in ([p] + allies if not allies.is_empty() else []):   # knocked-out heroes get back up after a win
			if r.won and not a.is_alive():
				a.current_hp = max(1, int(a.max_hp * 0.1))
		if not r.won:
			return {"cleared": false, "wave": wave, "player": p}
		p.gain_xp(xp)
		while p.attribute_points > 0:
			spend_point(p)
		spend_talents(p)
		# Breather below 50% HP, or below 80% right before the boss
		var threshold = 0.8 if wave == 5 else 0.5
		if p.current_hp < p.max_hp * threshold:
			MomentumSystem.reset_momentum()
			p.current_hp = p.max_hp; p.current_mp = p.max_mp; p.current_sp = p.max_sp
			p.status_manager.clear_all_effects()
			for a in allies:
				a.current_hp = a.max_hp; a.current_mp = a.max_mp; a.current_sp = a.max_sp
				a.status_manager.clear_all_effects()
		else:
			MomentumSystem.gain_momentum()
	# floor cleared -> next floor starts fresh
	p.reset_for_new_battle()
	MomentumSystem.reset_momentum()
	return {"cleared": true, "wave": 7, "player": p}

## Talent policy for the sim: fill the first branch tier by tier, then the next.
var talent_branch_order := []   # empty = class order
func spend_talents(p: CharacterData) -> void:
	var branches = TalentManager.branches_for(p.character_class)
	for b in branches:
		for nd in TalentManager.nodes_for(p.character_class, b.id):
			while p.talents.can_learn(nd.key):
				p.talents.learn(nd.key)
			if p.talents.available_points() <= 0:
				return

func spend_point(p: CharacterData) -> void:
	var main = p.attack_power_type if p.attack_power_type != "" else "strength"
	if p.spell_power > p.attack_power:
		main = p.spell_power_type if p.spell_power_type in ["intelligence", "arcane", "faith"] else "intelligence"
	var choice = main if p.attribute_points % 3 != 0 else "vitality"
	p.spend_attribute_point(choice)

func sim_fight(cls: String, floor_num: int, wave: int) -> Dictionary:
	return fight(make_player(cls), make_enemies(floor_num, wave), floor_num, wave == 6)

## Every sim fight uses the game's headless battle (AutoBattler.fight) with the
## full combat rules. sim_policy: "smart" or "naive" (tool --policy=naive).
var sim_policy := "smart"
func fight(p: CharacterData, enemies: Array[CharacterData], floor_num: int, boss: bool, allies: Array[CharacterData] = []) -> Dictionary:
	var r = AutoBattler.fight(p, enemies, floor_num, boss, allies, {"potions": true, "setup": use_setup, "policy": sim_policy})
	r["direct"] = 0.0
	r["status"] = 0.0
	return r
