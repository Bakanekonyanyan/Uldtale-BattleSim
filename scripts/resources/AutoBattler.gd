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
	_spend_talents(p, int(npc.get("branch", 0)))
	var floor_num = max(1, int(npc.get("gear_floor", 1)))
	var main = ClassEquipmentBias.get_biased_equipment_id(p.character_class, "main_hand")
	if main != "":
		_equip(p, main, floor_num)
	for i in range(4):
		var armor = ClassEquipmentBias.get_biased_equipment_id(p.character_class, "armors")
		if armor != "":
			_equip(p, armor, floor_num)
	p.calculate_secondary_attributes()
	p.reset_for_new_battle()
	return p

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

static func _spend_talents(p: CharacterData, start_branch: int) -> void:
	var branches = TalentManager.branches_for(p.character_class)
	if branches.is_empty():
		return
	for i in range(branches.size()):
		var b = branches[(start_branch + i) % branches.size()]
		for nd in TalentManager.nodes_for(p.character_class, b.id):
			while p.talents.can_learn(nd.key):
				p.talents.learn(nd.key)
			if p.talents.available_points() <= 0:
				return

## Fight a floor's boss (or a wave) at `location_id`. Returns
## {won, turns, hp_frac} where hp_frac is the hero's HP left (0..1).
static func fight_floor(hero: CharacterData, location_id: String, floor_num: int, boss := true) -> Dictionary:
	# EnemyFactory and MomentumSystem are global: leave them as we found them
	var saved_loc = EnemyFactory.current_location
	var saved_race = EnemyFactory.current_dungeon_race
	var saved_momentum = MomentumSystem.current_momentum
	MomentumSystem.current_momentum = 0
	EnemyFactory.set_location(location_id)
	var g = EnemyGroup.new()
	g.initialize(floor_num, 6 if boss else 3, boss)
	var r = fight(hero, g.enemies, floor_num, boss)
	EnemyFactory.current_location = saved_loc
	EnemyFactory.current_dungeon_race = saved_race
	MomentumSystem.current_momentum = saved_momentum
	return r

static func fight(p: CharacterData, enemies: Array[CharacterData], floor_num: int, boss: bool) -> Dictionary:
	var ctx = BattleContext.new()
	ctx.player = p
	ctx.enemies = enemies
	ctx.set_dungeon_info(boss, 1, floor_num, 5, "")
	var engine = CombatEngine.new()
	engine.initialize_multi(p, enemies)
	var q = TurnQueue.new()
	q.initialize(p, enemies)
	var planner = EnemyTurnPlanner.new()
	planner.initialize(ctx)
	var turns := 0
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
		if actor.is_stunned:
			actor.is_stunned = false
			q.advance()
			continue
		var action: BattleAction = hero_policy(p, ctx) if actor == p else planner.plan_action(actor)
		if action:
			engine.execute_action(action)
		for c in [p] + enemies:
			if not c.is_alive():
				q.remove(c)
		q.advance()
	return {"won": ctx.did_player_win(), "turns": turns, "hp_frac": float(max(0, p.current_hp)) / max(1, p.max_hp)}

## Heal when low -> pay off a combo -> buff early -> debuff a fresh enemy ->
## strongest damage skill -> attack the weakest enemy.
static func hero_policy(p: CharacterData, ctx: BattleContext) -> BattleAction:
	var living = ctx.get_living_enemies()
	if living.is_empty():
		return null
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
		match s.type:
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
	if buff and fight_young and not p.buff_manager.has_buffs():
		return BattleAction.skill(p, buff, [p])
	if debuff and fight_young:
		var fresh = living.filter(func(e): return not e.buff_manager.has_debuffs())
		if not fresh.is_empty():
			return BattleAction.skill(p, debuff, living if debuff.target == Skill.TargetType.ALL_ENEMIES else [fresh[-1]])
	if best:
		return BattleAction.skill(p, best, living if best.target == Skill.TargetType.ALL_ENEMIES else [living[0]])
	return BattleAction.attack(p, living[0])
