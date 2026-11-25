# res://scripts/resources/AutoBattler.gd
# Headless battles with the real engine (CombatEngine, TurnQueue, EnemyAI):
# NPC adventurers' "big moments" (boss hunts, promotion trials) are fought, not
# rolled. Mirrors the balance sim's driver and hero policy (tests/balance_sim.gd).
# No GameEvents fire, so NPC kills never count toward the player's bounties.
class_name AutoBattler
extends RefCounted

## Build a hero for an NPC adventurer: class, level, attribute points, talents
## (from `branch_index` onward) and class-appropriate gear for `gear_floor`.
static func build_hero(npc: Dictionary) -> CharacterData:
	var p = CharacterFactory.create_character(String(npc.name), String(npc.race), String(npc.cls), true)
	for i in range(int(npc.level) - 1):
		p.level_up()
	while p.attribute_points > 0:
		_spend_point(p)
	_spend_talents(p, int(npc.get("branch", 0)), npc)
	if not npc.get("traits", []).is_empty():
		p.set_meta("traits", npc.get("traits", []).duplicate())   # temperament in battle
	var floor_num = max(1, int(npc.get("gear_floor", 1)))
	for attempt in range(6):   # a rolled weapon may not suit the class: reroll
		var main = ClassEquipmentBias.get_biased_equipment_id(p.character_class, "main_hand")
		if main != "":
			_equip(p, main, floor_num)
		if p.equipment["main_hand"] != null:
			break
	if p.equipment["main_hand"] == null:   # never go to a fight empty-handed
		for wid in EnemyFactory.classes.get("playable", {}).get(p.character_class, {}).get("preferred_weapons", []):
			var tpl = ItemManager.get_equipment_template(String(wid))
			if String(tpl.get("slot", "")) == "main_hand":
				_equip(p, String(wid), floor_num)
				if p.equipment["main_hand"] != null:
					break
	for i in range(4):
		# armour they're trained in (ArmorTraining): reroll a few times before settling
		var armor := ""
		for attempt in range(6):
			armor = ClassEquipmentBias.get_biased_equipment_id(p.character_class, "armors")
			var tpl = ItemManager.get_equipment_template(armor) if armor != "" else {}
			var tier = ArmorTraining.weights().find(String(tpl.get("type", "")))
			if armor != "" and (tier < 0 or tier <= ArmorTraining.trained_tier(p)):
				break
		if armor != "":
			_equip(p, armor, floor_num)
	WeaponArts.grant_npc(p)   # their weapon arts, by level
	p.calculate_secondary_attributes()
	p.reset_for_new_battle()
	return p

const _BOLD_TRAITS := ["reckless", "ambitious", "cruel", "boastful", "greedy"]
const _CAREFUL_TRAITS := ["kind", "loyal", "cautious", "devout", "cowardly", "honorable"]

## Which option of fork `choice` an adventurer takes: the bold favour raw
## power (focused or harder hits), the careful favour protection and the party.
## Ties fall to a stable per-adventurer coin, so builds vary.
static func fork_pick(nodes: Array, choice: String, npc: Dictionary) -> String:
	var opts = nodes.filter(func(n): return String(n.get("choice", "")) == choice)
	if opts.is_empty():
		return ""
	# the balance sim can force a side: "a" = first option, "b" = second
	var pref = String(npc.get("fork_pref", ""))
	if pref in ["a", "b"]:
		return String(opts[0 if pref == "a" or opts.size() < 2 else 1].key)
	var tr: Array = npc.get("traits", [])
	var lean = tr.filter(func(t): return t in _BOLD_TRAITS).size() - tr.filter(func(t): return t in _CAREFUL_TRAITS).size()
	var best: Dictionary = opts[abs(hash("%s|%s" % [npc.get("id", npc.get("name", "")), choice])) % opts.size()]
	if lean != 0:
		var best_score = -INF
		for o in opts:
			var sc = _fork_score(o) * sign(lean)
			if sc > best_score:
				best_score = sc
				best = o
	return String(best.key)

## + for offence, - for protection (party reach, healing, defence, sustain).
static func _fork_score(n: Dictionary) -> float:
	var s := 0.0
	for e in n.get("effects", []):
		match String(e.get("type", "")):
			"damage", "lifesteal": s += 1.0
			"defense", "heal_bonus", "regen": s -= 1.0
			"mutate":
				if String(e.get("target", "")) == "ALL_ALLIES": s -= 1.5
				if float(e.get("power_mult", 1.0)) > 1.0: s += 1.0
				if e.get("after_use", {}).has("heal_pct") or e.get("after_use", {}).has("self_status"): s -= 0.5
	return s

static func _equip(p: CharacterData, id: String, floor_num: int) -> void:
	var item = ItemManager.create_equipment_for_floor(id, floor_num)
	if item and item.can_equip(p):
		p.inventory.add_item(item, 1)
		p.equip_item(item)

static func _spend_point(p: CharacterData) -> void:
	var main = p.attack_power_type if p.attack_power_type != "" else "strength"
	if p.spell_power > p.attack_power:
		main = p.spell_power_type if p.spell_power_type in ["intelligence", "arcane", "faith"] else "intelligence"
	p.spend_attribute_point(main if p.attribute_points % 3 != 0 else "vitality")

static func _spend_talents(p: CharacterData, start_branch: int, npc: Dictionary = {}) -> void:
	var branches = TalentManager.branches_for(p.character_class)
	if branches.is_empty():
		return
	for i in range(branches.size()):
		var b = branches[(start_branch + i) % branches.size()]
		var nodes = TalentManager.nodes_for(p.character_class, b.id)
		for nd in nodes:
			if nd.has("choice") and nd.key != fork_pick(nodes, String(nd.choice), npc):
				continue   # their temperament picked the other option
			while p.talents.can_learn(nd.key):
				p.talents.learn(nd.key)
			if p.talents.available_points() <= 0:
				return

## Fight a floor's boss (or a wave) at `location_id`. Returns
## {won, turns, hp_frac} where hp_frac is the hero's HP left (0..1).
static func fight_floor(hero: CharacterData, location_id: String, floor_num: int, boss := true, allies: Array[CharacterData] = []) -> Dictionary:
	# EnemyFactory and MomentumSystem are global: leave them as we found them
	var saved_loc = EnemyFactory.current_location
	var saved_race = EnemyFactory.current_dungeon_race
	var saved_momentum = MomentumSystem.current_momentum
	MomentumSystem.current_momentum = 0
	EnemyFactory.set_location(location_id)
	var g = EnemyGroup.new()
	g.ally_count = allies.size()
	g.initialize(floor_num, 6 if boss else 3, boss)
	var r = fight(hero, g.enemies, floor_num, boss, allies)
	EnemyFactory.current_location = saved_loc
	EnemyFactory.current_dungeon_race = saved_race
	MomentumSystem.current_momentum = saved_momentum
	return r

## `allies` fight beside `p` on the same hero policy.
## A headless battle with the full rules (BattleRules: break, Link, intents,
## turn order, elite affixes). opts:
##   potions: true  - heroes drink a potion (free action) when low
##   policy: "smart" (default) | "naive" - naive ignores intents, breaks and
##           the Link gauge: always the strongest skill (to measure how much
##           playing well is worth)
##   setup: true    - use buffs/debuffs (false = damage only)
static func fight(p: CharacterData, enemies: Array[CharacterData], floor_num: int, boss: bool, allies: Array[CharacterData] = [], opts: Dictionary = {}) -> Dictionary:
	var ctx = BattleContext.new()
	ctx.player = p
	ctx.allies = allies
	ctx.enemies = enemies
	ctx.set_dungeon_info(boss, 1, floor_num, 5, "")
	var engine = CombatEngine.new()
	engine.initialize_multi(p, enemies, allies)
	var q = TurnQueue.new()
	q.initialize(p, enemies, allies)
	var rules = BattleRules.new(ctx, q)
	var planner = EnemyTurnPlanner.new()
	planner.initialize(ctx)
	planner.plan_all_intents()
	var turns := 0
	var breaks := 0
	while not ctx.is_battle_decided() and turns < 300:
		var actor = q.current_actor()
		if actor == null:
			break
		turns += 1
		actor.reset_defense()
		engine.process_status_effects(actor)
		if not actor.is_alive():
			q.remove(actor)
			q.advance()
			continue
		rules.on_turn_start(actor)
		if actor.is_stunned:
			actor.is_stunned = false
			if not ctx.is_hero(actor):
				planner.plan_intent(actor)
			q.advance()
			continue
		if ctx.is_hero(actor) and opts.get("potions", false):
			var potion = potion_policy(actor)
			if potion:
				var ps = rules.before_action(potion)
				engine.execute_action(potion)
				rules.after_action(potion, ps)
		var action: BattleAction
		if ctx.is_hero(actor):
			ctx.set_meta("sim_no_guard", not bool(opts.get("guard", true)))
			action = hero_policy(actor, ctx, bool(opts.get("setup", true)), String(opts.get("policy", "smart")))
		else:
			action = planner.take_intent(actor)
		if action:
			var snap = rules.before_action(action)
			engine.execute_action(action)
			for line in rules.after_action(action, snap):
				if line.contains("BREAK"):
					breaks += 1
		if not ctx.is_hero(actor):
			planner.plan_intent(actor)
		for c in rules.take_spawns():
			planner.add_enemy(c)
			planner.plan_intent(c)
		for c in ctx.get_heroes() + ctx.enemies:
			if not c.is_alive():
				q.remove(c)
		q.rejoin_revived()
		q.advance()
	return {"won": ctx.did_player_win(), "turns": turns, "breaks": breaks, "hp_frac": float(max(0, p.current_hp)) / max(1, p.max_hp)}

## Drink a health potion below 40% HP, or a mana potion below 25% MP (casters).
static func potion_policy(p: CharacterData) -> BattleAction:
	if p.current_hp < p.max_hp * 0.4 and p.inventory.get_quantity("health_potion") > 0:
		return BattleAction.item(p, p.inventory.get_item("health_potion"), [p])
	if p.spell_power > p.attack_power and p.current_mp < p.max_mp * 0.25 and p.inventory.get_quantity("mana_potion") > 0:
		return BattleAction.item(p, p.inventory.get_item("mana_potion"), [p])
	return null

## Heal when low -> pay off a combo -> buff early -> debuff a fresh enemy ->
## strongest damage skill -> attack the weakest enemy.
## use_setup = false plays "damage only" (no buffs/debuffs) - the balance sim
## compares both styles. Companions on Auto and NPC battles use set-ups.
## A hero's move. Adventurers (meta "traits") fight by temperament
## (data/temperament.json "battle"): a hook before and after the usual policy.
static func hero_policy(p: CharacterData, ctx: BattleContext, use_setup := true, policy := "smart") -> BattleAction:
	var traits: Array = p.get_meta("traits", []) if p.has_meta("traits") else []
	if not traits.is_empty():
		var pre = _temperament_pre(p, ctx, traits)
		if pre:
			return pre
	var act = _hero_policy_core(p, ctx, use_setup, policy)
	if act and not traits.is_empty():
		act = _temperament_post(p, ctx, traits, act)
	return act

static func _tcfg(t: String) -> Dictionary:
	var d = DataRegistry.get_data("temperament")
	return d.get("battle", {}).get(t, {}) if d is Dictionary else {}

## Usable healing skill that can target an ally (or null).
static func _ally_heal(p: CharacterData) -> Skill:
	for sn in p.get_battle_skills():
		var s: Skill = p.get_skill_instance(sn)
		if s and s.type == Skill.SkillType.HEAL and s.target in [Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES] \
				and p.get_skill_cooldown(sn) == 0 and s.can_afford(p):
			return s
	return null

static func _temperament_pre(p: CharacterData, ctx: BattleContext, traits: Array) -> BattleAction:
	var hp = float(p.current_hp) / max(1, p.max_hp)
	if "cowardly" in traits:
		var c = _tcfg("cowardly")
		if hp < float(c.get("freeze_below", 0.3)) and RandomManager.randf() < float(c.get("chance", 0.35)):
			p.set_meta("temperament_bark", "%s freezes up and cowers!" % p.name)
			return BattleAction.defend(p)
	# the loyal and the kind look after others first
	for t in ["loyal", "kind"]:
		if not t in traits:
			continue
		var below = float(_tcfg(t).get("protect_below" if t == "loyal" else "heal_below", 0.5))
		var heal = _ally_heal(p)
		if heal == null:
			continue
		var hurt = ctx.get_heroes().filter(func(h): return h != p and h.is_alive() and float(h.current_hp) / max(1, h.max_hp) < below)
		if t == "loyal":
			hurt = hurt.filter(func(h): return h == ctx.player)
		if not hurt.is_empty():
			hurt.sort_custom(func(a, b): return float(a.current_hp) / max(1, a.max_hp) < float(b.current_hp) / max(1, b.max_hp))
			return BattleAction.skill(p, heal, ctx.get_heroes().filter(func(h): return h.is_alive()) if heal.target == Skill.TargetType.ALL_ALLIES else [hurt[0]])
	if "cautious" in traits:
		var c2 = _tcfg("cautious")
		if hp < float(c2.get("guard_below", 0.35)) and RandomManager.randf() < float(c2.get("chance", 0.5)):
			return BattleAction.defend(p)
	return null

static func _temperament_post(p: CharacterData, ctx: BattleContext, traits: Array, act: BattleAction) -> BattleAction:
	var living = ctx.get_living_enemies()
	if living.is_empty():
		return act
	living.sort_custom(func(a, b): return a.current_hp < b.current_hp)
	if "reckless" in traits and act.type == BattleAction.ActionType.DEFEND:
		return BattleAction.attack(p, living[0])   # the reckless never guard
	if "lazy" in traits and act.type == BattleAction.ActionType.SKILL and RandomManager.randf() < float(_tcfg("lazy").get("basic_chance", 0.15)):
		return BattleAction.attack(p, living[0])
	if "cruel" in traits and act.targets.size() == 1 and act.targets[0] in living and act.type in [BattleAction.ActionType.ATTACK, BattleAction.ActionType.SKILL]:
		act.targets.clear()
		act.targets.append(living[0])   # finish the weakest
	return act

static func _hero_policy_core(p: CharacterData, ctx: BattleContext, use_setup := true, policy := "smart") -> BattleAction:
	var living = ctx.get_living_enemies()
	if living.is_empty():
		return null
	var rules: BattleRules = ctx.rules
	if policy == "simple":
		return _simple_move(p, ctx, living)
	var smart = policy != "naive"
	if smart and policy != "hit":
		var plan = _smart_moves(p, ctx, living, rules)
		if plan:
			return plan
	living.sort_custom(func(a, b): return a.current_hp < b.current_hp)
	var enemy_hp := 0.0
	var enemy_max := 0.0
	for e in ctx.enemies:
		enemy_hp += e.current_hp
		enemy_max += e.max_hp
	var fight_young = enemy_hp > enemy_max * 0.5
	var best: Skill = null
	var buff: Skill = null
	var debuff: Skill = null
	for sn in p.get_battle_skills():
		var s: Skill = p.get_skill_instance(sn)
		if s == null or p.get_skill_cooldown(sn) > 0 or not s.can_afford(p):
			continue
		if rules and not rules.link_ok(p, s):
			continue   # ultimates wait for the Link gauge
		match s.type:
			Skill.SkillType.REVIVE:
				var fallen = ctx.get_heroes().filter(func(h): return not h.is_alive())
				if not fallen.is_empty():
					return BattleAction.skill(p, s, [fallen[0]])
				continue
			Skill.SkillType.HEAL:
				if p.current_hp < p.max_hp * 0.4:
					return BattleAction.skill(p, s, [p])
			Skill.SkillType.BUFF:
				buff = s
			Skill.SkillType.DEBUFF, Skill.SkillType.INFLICT_STATUS:
				debuff = s
			Skill.SkillType.DAMAGE, Skill.SkillType.DRAIN:
				if s.type == Skill.SkillType.DRAIN and s.drain_source != Skill.DrainTarget.HP:
					continue
				if best == null or s.power > best.power:
					best = s
	# combos
	var combo_pick: Skill = null
	var combo_target: CharacterData = null
	var combo_mult := 1.0
	for sn in p.get_battle_skills():
		var s: Skill = p.get_skill_instance(sn)
		if s == null or p.get_skill_cooldown(sn) > 0 or not s.can_afford(p):
			continue
		if rules and not rules.link_ok(p, s):
			continue
		if s.type == Skill.SkillType.DRAIN and s.drain_source != Skill.DrainTarget.HP:
			continue
		for e in living:
			var c = Combos.preview(p, s, e)
			if not c.is_empty() and c.multiplier > combo_mult:
				combo_pick = s
				combo_target = e
				combo_mult = c.multiplier
	if combo_pick:
		return BattleAction.skill(p, combo_pick, living if combo_pick.target == Skill.TargetType.ALL_ENEMIES else [combo_target])
	# a basic attack that triggers a combo beats a weak skill
	for e in living:
		if not Combos.find(e, Combos.hit_from_attack(p)).is_empty() and (best == null or best.power < 40):
			return BattleAction.attack(p, e)
	if not use_setup:
		buff = null
		debuff = null
	# A skilled player only spends turns on set-ups when the fight is long
	# enough for them to pay back (bosses, elites, big waves)
	if smart and policy != "moves" and (buff or debuff) and hero_actions_left(p, ctx, best) < 4.0:
		buff = null
		debuff = null
	if buff and fight_young and not p.buff_manager.has_buffs():
		return BattleAction.skill(p, buff, [p])
	if debuff and fight_young:
		var fresh = living.filter(func(e): return not e.buff_manager.has_debuffs())
		if not fresh.is_empty():
			return BattleAction.skill(p, debuff, living if debuff.target == Skill.TargetType.ALL_ENEMIES else [fresh[-1]])
	if smart and policy != "moves":
		# same skill choice, smarter aim: weakness, near-Break, kills
		var aim = _best_target(p, best, living, rules)
		if aim:
			return BattleAction.skill(p, best, living if best and best.target == Skill.TargetType.ALL_ENEMIES else [aim]) if best else BattleAction.attack(p, aim)
	if best:
		return BattleAction.skill(p, best, living if best.target == Skill.TargetType.ALL_ENEMIES else [living[0]])
	return BattleAction.attack(p, living[0])


## The baseline a casual player plays: the strongest damage skill it can
## afford (else a basic attack) on the first enemy in the list. No focus fire,
## combos, buffs, Defend or Link play. Heals itself when low.
static func _simple_move(p: CharacterData, ctx: BattleContext, living: Array) -> BattleAction:
	var rules: BattleRules = ctx.rules
	var best: Skill = null
	for sn in p.get_battle_skills():
		var s: Skill = p.get_skill_instance(sn)
		if s == null or p.get_skill_cooldown(sn) > 0 or not s.can_afford(p) or (rules and not rules.link_ok(p, s)):
			continue
		if s.type == Skill.SkillType.HEAL and p.current_hp < p.max_hp * 0.4:
			return BattleAction.skill(p, s, [p])
		if s.type == Skill.SkillType.DAMAGE and (best == null or s.power > best.power):
			best = s
	if best:
		return BattleAction.skill(p, best, living if best.target == Skill.TargetType.ALL_ENEMIES else [living[0]])
	return BattleAction.attack(p, living[0])

## Rough number of actions `p` (with the party's help) needs to finish the
## fight with its best skill: total enemy HP / (damage per action x heroes).
static func hero_actions_left(p: CharacterData, ctx: BattleContext, best: Skill) -> float:
	var living = ctx.get_living_enemies()
	if living.is_empty():
		return 0.0
	var hp := 0.0
	for e in living:
		hp += e.current_hp
	var physical = best == null or best.ability_type == Skill.AbilityType.PHYSICAL
	var per = BattleFormulas.hit_damage(p, living[0], physical, 0.0 if best == null else best.power, -1 if best == null else best.damage_type, best)
	return hp / max(1.0, per * max(1, ctx.get_living_heroes().size()))

## Expected damage `p` takes this round from intents aimed at it (a rough
## read of the panels: basic hits, skill power, charged strikes).
static func incoming_damage(p: CharacterData, ctx: BattleContext) -> float:
	var total := 0.0
	var charge = float(BattleRules.cfg().get("intents", {}).get("charge_power_mult", 1.5))
	for e in ctx.get_living_enemies():
		if e.get_meta("broken", false) or e.is_stunned:
			continue
		var a = ctx.intents.get(e, null)
		if e.has_meta("charging"):
			total += BattleFormulas.hit_damage(e, p, e.attack_power >= e.spell_power, 60.0) * charge / max(1, ctx.get_living_heroes().size())
			continue
		if not (a is BattleAction):
			continue
		if a.type == BattleAction.ActionType.ATTACK and a.targets.has(p):
			total += BattleFormulas.hit_damage(e, p, true)
		elif a.type == BattleAction.ActionType.SKILL and a.skill_data and a.skill_data.type in [Skill.SkillType.DAMAGE, Skill.SkillType.DRAIN] \
				and (a.targets.has(p) or a.skill_data.target == Skill.TargetType.ALL_ENEMIES):
			total += BattleFormulas.hit_damage(e, p, a.skill_data.ability_type == Skill.AbilityType.PHYSICAL, a.skill_data.power, a.skill_data.damage_type, a.skill_data)
	return total

## The "reads the fight" layer on top of the basic policy:
##   Unison Strike when the gauge is full -> brace for a telegraphed big hit ->
##   break the enemy that is charging -> otherwise null (basic policy decides).
static func _smart_moves(p: CharacterData, ctx: BattleContext, living: Array, rules: BattleRules) -> BattleAction:
	var charging = living.filter(func(e): return e.has_meta("charging"))
	# Unison at full gauge: on a charging enemy, else the toughest one
	if rules and rules.unison_ready():
		var tgt = charging[0] if not charging.is_empty() else living.reduce(func(a, b): return a if a.current_hp > b.current_hp else b)
		return BattleAction.unison(p, tgt)
	# A wounded ally: heal them before they drop (party play)
	var heroes = ctx.get_living_heroes()
	if heroes.size() > 1:
		var hurt = heroes.filter(func(h): return h != p and h.current_hp < h.max_hp * 0.35)
		if not hurt.is_empty():
			for sn in p.get_battle_skills():
				var s: Skill = p.get_skill_instance(sn)
				if s and s.type == Skill.SkillType.HEAL and s.target in [Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES] \
						and p.get_skill_cooldown(sn) == 0 and s.can_afford(p):
					return BattleAction.skill(p, s, [hurt[0]] if s.target == Skill.TargetType.ALLY else heroes)
	# Read the intents: a big hit coming at us is worth a Perfect Guard
	# (a quarter of the damage, no Break pips, the attacker staggered)
	if rules and rules.is_threatened(p) and BattleRules.cfg().get("guard", {}).get("enabled", true) and not ctx.get_meta("sim_no_guard", false):
		var incoming = incoming_damage(p, ctx)
		var weak_to_it = int(p.get_meta("break_meter", 0)) + 1 >= BattleRules.break_max(p, true)
		# Guarding saves ~3/4 of the hit but costs an attack: worth it against a
		# big or charged blow, a hit that would Break us, or one that would drop us
		var charged = living.any(func(e): return e.has_meta("charging"))
		if charged or incoming >= p.current_hp * 0.45 or (weak_to_it and incoming >= p.max_hp * 0.1):
			# unless a quick kill removes the threat instead
			var killable = living.filter(func(e): return e.current_hp <= BattleFormulas.hit_damage(p, e, p.attack_power >= p.spell_power) and ctx.intents.get(e, null) is BattleAction and ctx.intents[e].targets.has(p))
			if killable.is_empty():
				return BattleAction.defend(p)
	# Something big is coming at us: heal up or brace
	var threatened = not charging.is_empty() or living.any(func(e):
		var a = ctx.intents.get(e, null)
		return a is BattleAction and a.type == BattleAction.ActionType.SKILL and a.skill_data.power >= 50 and (a.skill_data.target == Skill.TargetType.ALL_ENEMIES or a.primary_target == p))
	if threatened and p.current_hp < p.max_hp * 0.45:
		for sn in p.get_battle_skills():
			var s: Skill = p.get_skill_instance(sn)
			if s and s.type == Skill.SkillType.HEAL and p.get_skill_cooldown(sn) == 0 and s.can_afford(p):
				return BattleAction.skill(p, s, [p])
	# Something is charging: Break it this turn if we can, else brace for it
	if not charging.is_empty():
		var target = charging[0]
		var best: Skill = null
		var best_power := -1.0
		for sn in p.get_battle_skills():
			var s: Skill = p.get_skill_instance(sn)
			if s == null or s.type != Skill.SkillType.DAMAGE or p.get_skill_cooldown(sn) > 0 or not s.can_afford(p):
				continue
			if rules and not rules.link_ok(p, s):
				continue
			if rules and rules._weak_hit(BattleAction.skill(p, s, [target]), target) and s.power > best_power:
				best = s
				best_power = s.power
		var weak_attack = rules and rules._weak_hit(BattleAction.attack(p, target), target)
		var meter = int(target.get_meta("break_meter", 0))
		if meter + 1 >= BattleRules.break_max(target):
			if best:
				return BattleAction.skill(p, best, living if best.target == Skill.TargetType.ALL_ENEMIES else [target])
			if weak_attack:
				return BattleAction.attack(p, target)
		if p.current_hp < p.max_hp * 0.75:
			return BattleAction.defend(p)     # halves the charged hit
		if best:   # chip in a weakness hit toward the Break
			return BattleAction.skill(p, best, living if best.target == Skill.TargetType.ALL_ENEMIES else [target])
		if weak_attack:
			return BattleAction.attack(p, target)
	# Build a Break on the big threats (bosses, elites): a weakness skill nearly
	# as strong as our best is worth more, because Breaks cost them turns
	if rules:
		var bigs = living.filter(func(e): return not e.get_meta("broken", false) and BattleRules.break_max(e) >= 3 - int(e.get_meta("times_broken", 0)) and (e.character_class.begins_with("King") or e.has_meta("elite_affix")))
		if not bigs.is_empty():
			var t = bigs[0]
			var top := 0.0
			for sn in p.get_battle_skills():
				var s: Skill = p.get_skill_instance(sn)
				if s and s.type == Skill.SkillType.DAMAGE and p.get_skill_cooldown(sn) == 0 and s.can_afford(p) and rules.link_ok(p, s):
					top = max(top, s.power)
			for sn in p.get_battle_skills():
				var s: Skill = p.get_skill_instance(sn)
				if s and s.type == Skill.SkillType.DAMAGE and p.get_skill_cooldown(sn) == 0 and s.can_afford(p) and rules.link_ok(p, s) \
						and s.power >= top * 0.6 and rules._weak_hit(BattleAction.skill(p, s, [t]), t):
					return BattleAction.skill(p, s, living if s.target == Skill.TargetType.ALL_ENEMIES else [t])
			if rules._weak_hit(BattleAction.attack(p, t), t) and top < 35:
				return BattleAction.attack(p, t)
	# Finish a Break that is one weakness hit away (most dangerous enemy first)
	if rules:
		var ready = living.filter(func(e): return not e.get_meta("broken", false) and int(e.get_meta("break_meter", 0)) + 1 >= BattleRules.break_max(e))
		ready.sort_custom(func(a, b): return max(a.attack_power, a.spell_power) > max(b.attack_power, b.spell_power))
		for t in ready:
			for sn in p.get_battle_skills():
				var s: Skill = p.get_skill_instance(sn)
				if s and s.type == Skill.SkillType.DAMAGE and p.get_skill_cooldown(sn) == 0 and s.can_afford(p) and rules.link_ok(p, s) \
						and rules._weak_hit(BattleAction.skill(p, s, [t]), t):
					return BattleAction.skill(p, s, living if s.target == Skill.TargetType.ALL_ENEMIES else [t])
			if rules._weak_hit(BattleAction.attack(p, t), t):
				return BattleAction.attack(p, t)
	return null

## The best target for `s` (null = basic attack): share of the target removed
## x its threat, more for a hit that Breaks it or a weakness hit, a kill bonus.
static func _best_target(p: CharacterData, s: Skill, living: Array, rules: BattleRules) -> CharacterData:
	if rules == null or living.is_empty():
		return null
	var brk: Dictionary = BattleRules.cfg().get("break", {})
	var focus: CharacterData = null
	var focus_score := -1.0
	var physical = s == null or s.ability_type == Skill.AbilityType.PHYSICAL
	for t in living:
		var act = BattleAction.attack(p, t) if s == null else BattleAction.skill(p, s, [t])
		var dmg = BattleFormulas.hit_damage(p, t, physical, 0.0 if s == null else s.power, -1 if s == null else s.damage_type, s)
		var threat = max(t.attack_power, t.spell_power) * t.damage_multiplier
		var value = min(dmg, t.current_hp) / max(1.0, float(t.current_hp)) * threat
		if dmg >= t.current_hp:
			value *= 1.5
		if rules._weak_hit(act, t) and not t.get_meta("broken", false):
			value *= 1.8 if int(t.get_meta("break_meter", 0)) + 1 >= BattleRules.break_max(t) else 1.25
		if value > focus_score:
			focus_score = value
			focus = t
	return focus

