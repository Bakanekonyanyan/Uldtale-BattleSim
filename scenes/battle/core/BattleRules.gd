# res://scenes/battle/core/BattleRules.gd
# Combat rules on top of the engine (data/combat.json, data/elites.json),
# shared by the battle scene (BattleOrchestrator) and headless battles
# (AutoBattler: NPC fights, the balance sim):
#   - Break: weakness hits fill a break meter (enemies AND heroes); full = Broken
#   - Link: the party gauge (ultimates spend it, Unison Strike empties it)
#   - Turn order: skills with turn_delay push enemies back / pull allies forward
#   - Elite affixes: enrage, splitting
# Usage per action:  var snap = rules.before_action(action)
#                    engine.execute_action(action)
#                    var lines = rules.after_action(action, snap)
# and at each actor's turn start: rules.on_turn_start(actor) (before the stun check).
class_name BattleRules
extends RefCounted

var ctx: BattleContext
var queue: TurnQueue
## Enemies spawned by rules (Splitting elites) waiting to join: the battle
## loop adds them (turn order, AI, UI) and clears this list.
var pending_spawns: Array[CharacterData] = []
## What happened this battle (wave challenges): breaks, combos, weak_hits,
## guards, items, unison, setbacks (heroes Broken or knocked out).
var stats: Dictionary = {"breaks": 0, "combos": 0, "weak_hits": 0, "guards": 0, "items": 0, "unison": 0, "setbacks": 0}
## This wave's challenge (WaveChallenges.pick) or {}.
var challenge: Dictionary = {}

func _init(p_ctx: BattleContext, p_queue: TurnQueue) -> void:
	ctx = p_ctx
	queue = p_queue
	ctx.rules = self
	for h in ctx.get_heroes():   # hero poise starts fresh every battle
		clear_break(h)
	ctx.link_gauge = min(link_max(), MomentumSystem.get_momentum() * int(_link().get("start_per_momentum", 10)) + int(RunState.add("start_link")))

static func cfg() -> Dictionary:
	var d = DataRegistry.get_data("combat")
	return d if d is Dictionary else {}

func _brk() -> Dictionary:
	return cfg().get("break", {})

func _guard() -> Dictionary:
	return cfg().get("guard", {})

func _link() -> Dictionary:
	return cfg().get("link", {})

func link_max() -> int:
	return int(_link().get("max", 100))

# ------------------------------------------------------------------ link

func add_link(amount: float) -> void:
	if amount > 0:
		amount *= RunState.mult("link_gain_mult")   # Omen: Discord
	ctx.link_gauge = clamp(ctx.link_gauge + int(round(amount)), 0, link_max())

## Gauge a hero skill costs (ultimates), 0 for anything else.
func link_cost(skill: Skill) -> int:
	if skill and skill.category == "ULTIMATE":
		return int(_link().get("ultimate_cost", 50))
	return 0

## Heroes can only use what the gauge allows (ultimates).
func link_ok(actor: CharacterData, skill: Skill) -> bool:
	return not ctx.is_hero(actor) or ctx.link_gauge >= link_cost(skill)

func unison_ready() -> bool:
	return ctx.link_gauge >= int(_link().get("unison_cost", 100))

# ------------------------------------------------------------------ action hooks

func before_action(action: BattleAction) -> Dictionary:
	var hp := {}
	for c in ctx.get_heroes() + ctx.enemies:
		hp[c] = c.current_hp
	Combos.recent.clear()
	return {"hp": hp}

## Apply break, link, turn-order and affix rules. Returns combat-log lines.
func after_action(action: BattleAction, snap: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if action == null or action.actor == null:
		return lines
	var actor = action.actor
	var hero = ctx.is_hero(actor)
	var was_charged = actor.get_meta("charged_strike", false)
	if actor.has_meta("charged_strike"):
		actor.remove_meta("charged_strike")
	var hp: Dictionary = snap.get("hp", {})
	var combo_targets := {}
	for r in Combos.recent:
		combo_targets[r.target] = true
	Combos.recent.clear()
	# --- damage: break points (weakness hits, combos) on the other side, both ways
	var hit_any := false
	var tracking = Bestiary.tracks(ctx)
	for t in ctx.get_heroes() + ctx.enemies:
		if t == null or ctx.is_hero(t) == hero:
			continue
		var before = int(hp.get(t, t.current_hp))
		var dealt = before - max(0, t.current_hp)
		if dealt <= 0:
			continue
		hit_any = true
		if not hero and not t.is_alive() and int(hp.get(t, 0)) > 0:
			stats.setbacks += 1
		if hero and _weak_hit(action, t):
			stats.weak_hits += 1
		if not hero and t.is_defending and t.get_meta("perfect_guard", false):
			lines.append_array(_perfect_guard(t, actor, was_charged))
			continue
		if hero and tracking:
			var fresh = Bestiary.reveal(t, _weak_names(action, t))
			if not fresh.is_empty():
				lines.append("[color=#c77dff]Weakness found: %s is weak to %s![/color]" % [t.name, ", ".join(fresh)])
			if not t.is_alive():
				Bestiary.add_kill(t)
		if t.is_alive() and not t.get_meta("broken", false):
			var pts := 0
			if _weak_hit(action, t):
				pts += 1
				if combo_targets.has(t):
					pts += int(_brk().get("combo_bonus", 1))
			if pts > 0:
				var meter = int(t.get_meta("break_meter", 0)) + pts
				t.set_meta("break_meter", meter)
				if meter >= break_max(t, not hero):
					lines.append(break_unit(t))
	if hero:
		if hit_any:   # split across the party so the gauge fills at a similar pace
			add_link(float(_link().get("gain_per_hit", 4)) / max(1, ctx.get_heroes().size()))
		add_link(float(_link().get("gain_combo", 15)) * combo_targets.size())
		stats.combos += combo_targets.size()
		if action.type == BattleAction.ActionType.ITEM:
			stats.items += 1
	# --- Defend against an attack you can see coming: Perfect Guard
	if hero and action.type == BattleAction.ActionType.DEFEND and _guard().get("enabled", true):
		if is_threatened(actor):
			actor.set_meta("perfect_guard", true)
			lines.append("[color=#90e0ef]%s reads the attack and braces - Perfect Guard![/color]" % actor.name)
	# --- skills: link costs, LINK skills, turn order
	if action.type == BattleAction.ActionType.SKILL and action.skill_data:
		var s = action.skill_data
		if hero and link_cost(s) > 0:
			add_link(-link_cost(s))
		if hero and s.category == "LINK":
			add_link(_link().get("gain_link_skill", 15))
			var nxt = _next_hero_after(actor)
			if nxt:
				queue.haste(nxt)
				lines.append("%s's opening lets %s act next!" % [actor.name, nxt.name])
		if s.turn_delay != 0:
			for t in action.targets:
				if t == null or not t.is_alive():
					continue
				if s.turn_delay > 0 and not ctx.is_hero(t):
					queue.delay(t, s.turn_delay)
					lines.append("%s is knocked back in the turn order." % t.name)
				elif s.turn_delay < 0 and ctx.is_hero(t) and t != actor:
					queue.haste(t)
					lines.append("%s is spurred forward!" % t.name)
	elif action.type == BattleAction.ActionType.UNISON:
		add_link(-int(_link().get("unison_cost", 100)))
		stats.unison += 1
	# --- elite affixes
	for e in ctx.enemies.duplicate():
		lines.append_array(_affix_checks(e, int(hp.get(e, e.current_hp))))
	return lines.filter(func(l): return l != "")

## Does an enemy's shown intent (or a charge-up) threaten `hero` this round?
func is_threatened(hero_c: CharacterData) -> bool:
	for e in ctx.get_living_enemies():
		if e.has_meta("charging"):
			return true
		var a = ctx.intents.get(e, null)
		if not (a is BattleAction):
			continue
		if a.type == BattleAction.ActionType.ATTACK and a.targets.has(hero_c):
			return true
		if a.type == BattleAction.ActionType.SKILL and a.skill_data \
				and a.skill_data.type in [Skill.SkillType.DAMAGE, Skill.SkillType.DRAIN, Skill.SkillType.DEBUFF] \
				and (a.targets.has(hero_c) or a.skill_data.target == Skill.TargetType.ALL_ENEMIES):
			return true
	return false

## A Perfect Guard absorbed `attacker`'s hit on `guard`: no Break pips for the
## hero, the attacker is staggered, and a charged strike is countered.
func _perfect_guard(guard: CharacterData, attacker: CharacterData, charged: bool) -> Array[String]:
	var out: Array[String] = []
	var g = _guard()
	out.append("[color=#90e0ef][b]PERFECT GUARD![/b] %s turns the blow aside.[/color]" % guard.name)
	stats.guards += 1
	if attacker.is_alive() and not attacker.get_meta("broken", false):
		var meter = int(attacker.get_meta("break_meter", 0)) + int(g.get("attacker_pips", 1)) + int(RunState.add("guard_pips"))
		attacker.set_meta("break_meter", meter)
		if meter >= break_max(attacker, false):
			out.append(break_unit(attacker))
	if charged and attacker.is_alive() and guard.is_alive():
		var dmg = int(round(BattleFormulas.hit_damage(guard, attacker, true) * float(g.get("counter_mult", 0.75))))
		if dmg > 0:
			attacker.take_damage(dmg, guard)
			out.append("[color=#90e0ef]%s counters the charged strike for %d![/color]" % [guard.name, dmg])
	return out

## Weakness hits needed to Break `e` (grows each time it is broken).
## Heroes and companions use hero_hits: the same rule as enemies, own threshold.
static func break_max(e: CharacterData, hero := false) -> int:
	var b: Dictionary = cfg().get("break", {})
	var base = int(b.get("regular_hits", 2))
	if hero:
		base = int(b.get("hero_hits", 3))
	elif e.character_class.begins_with("King") or e.has_meta("boss_signature"):
		base = int(b.get("boss_hits", 4))
	elif e.has_meta("elite_affix") or e.has_meta("encounter"):
		base = int(b.get("elite_hits", 3))
	base += int(RunState.add("break_hits_delta"))   # Omen: Brittle
	base += int(RunState.add("hero_break_delta" if hero else "enemy_break_delta"))   # boons: Steadfast, Ruthless
	return max(1, base + int(e.get_meta("times_broken", 0)) * int(b.get("growth_per_break", 1)))

func _is_boss(e: CharacterData) -> bool:
	return e.character_class.begins_with("King") or e.has_meta("boss_signature")

## Did this action hit a weakness of `e` (damage type or element)?
func _weak_hit(action: BattleAction, e: CharacterData) -> bool:
	return not _weak_names(action, e).is_empty()

## Which of `e`'s weaknesses this action hits: ["Blunt", "Fire"].
func _weak_names(action: BattleAction, e: CharacterData) -> Array:
	var out: Array = []
	var physical := true
	var dt := -1
	var elements: Array = []
	if action.type == BattleAction.ActionType.SKILL and action.skill_data:
		physical = action.skill_data.ability_type == Skill.AbilityType.PHYSICAL
		dt = action.skill_data.damage_type
		for el in action.skill_data.elements:
			elements.append(Skill.ElementType.keys()[el])
	if physical:
		var t = DamageTypes.attack_type(action.actor, dt)
		if DamageTypes.multiplier(e, t) > 1.05:
			out.append(DamageTypes.Type.keys()[t].capitalize())
	if e.elemental_resistances:
		for n in elements:
			if ElementalDamage.Element.has(n) and e.elemental_resistances.get_total_weakness(ElementalDamage.Element[n]) > 0.0:
				out.append(String(n).capitalize())
	return out

## Break `e` (enemy or hero): it loses its next turn and takes extra damage
## until then. Breaking an enemy also fills the party's Link gauge.
func break_unit(e: CharacterData) -> String:
	var is_hero = ctx.is_hero(e)
	e.set_meta("broken", true)
	e.set_meta("break_meter", 0)
	e.set_meta("times_broken", int(e.get_meta("times_broken", 0)) + 1)
	e.is_stunned = true            # loses its next turn
	var extra = ""
	if e.has_meta("charging"):
		e.remove_meta("charging")
		extra = " Its charge is broken!"
	if int(e.get_meta("barrier", 0)) > 0:
		e.set_meta("barrier", 0)
		extra += " The barrier shatters!"
	ctx.intents.erase(e)
	if is_hero:
		stats.setbacks += 1
	else:
		stats.breaks += 1
		var heal = RunState.add("break_heal")   # boon: Vigor
		if heal > 0.0:
			for h in ctx.get_living_heroes():
				h.heal(int(round(h.max_hp * heal)))
			extra += " [color=#7bd389]Vigor: your party recovers %d%% HP.[/color]" % int(round(heal * 100))
	if not is_hero and Bestiary.tracks(ctx):
		Bestiary.add_break(e)
		var learned = Bestiary.study(e)
		if not learned.is_empty():
			extra += " [color=#c77dff]Studied: weak to %s.[/color]" % ", ".join(learned)
	if is_hero:
		return "[color=#ff6b6b][b]BREAK![/b] %s is staggered and loses the next turn.%s[/color]" % [e.name, extra.replace("Its", "The")]
	add_link(_brk().get("link_gain", 25))
	return "[b]BREAK![/b] %s is staggered and loses its next turn.%s" % [e.name, extra]

## Kept for older callers: Break an enemy.
func break_enemy(e: CharacterData) -> String:
	return break_unit(e)

static func clear_break(c: CharacterData) -> void:
	if c == null:
		return
	for m in ["broken", "break_meter", "times_broken", "perfect_guard"]:
		if c.has_meta(m):
			c.remove_meta(m)

func _next_hero_after(actor: CharacterData) -> CharacterData:
	for c in queue.queue:
		if c != actor and ctx.is_hero(c) and c.is_alive():
			return c
	return null

## Stats including rounds (from the turn queue), for challenge checks.
func battle_stats() -> Dictionary:
	var out = stats.duplicate()
	out["rounds"] = queue.round_number if queue else 1
	return out

# ------------------------------------------------------------------ turn start

## Call at the start of `actor`'s turn, before the stun check. Returns a log line.
func on_turn_start(actor: CharacterData) -> String:
	if actor.has_meta("perfect_guard"):
		actor.remove_meta("perfect_guard")
	if actor.get_meta("broken", false):
		actor.set_meta("broken", false)   # this skipped turn is the recovery
		return "%s recovers from the break." % actor.name
	return ""

# ------------------------------------------------------------------ elites

func _affix_checks(e: CharacterData, hp_before: int) -> Array[String]:
	var out: Array[String] = []
	var aff = String(e.get_meta("elite_affix", ""))
	if aff == "":
		return out
	var a: Dictionary = EliteAffixes.affix(aff)
	match aff:
		"enraged":
			if e.is_alive() and not e.get_meta("enraged_done", false) and float(e.current_hp) / max(1, e.max_hp) < float(a.get("threshold", 0.5)):
				e.set_meta("enraged_done", true)
				e.damage_multiplier *= float(a.get("damage_mult", 1.35))
				e.apply_status_effect(Skill.StatusEffect.ENRAGED, 99)
				out.append("[color=orange]%s flies into a rage![/color]" % e.name)
		"splitting":
			if not e.is_alive() and hp_before > 0 and not e.get_meta("split_done", false):
				e.set_meta("split_done", true)
				for i in range(int(a.get("count", 2))):
					var child = EliteAffixes.make_fragment(e, float(a.get("hp_frac", 0.35)), i + 1, ctx.current_floor)
					if child:
						pending_spawns.append(child)
				out.append("[color=orange]%s splits apart![/color]" % e.name)
	return out

## Hand spawned enemies to the battle: adds them to the context and the turn
## order, and returns them so the caller can wire AI and UI.
func take_spawns() -> Array[CharacterData]:
	var out: Array[CharacterData] = pending_spawns.duplicate()
	pending_spawns.clear()
	for c in out:
		ctx.enemies.append(c)
		queue.join(c, false)
	return out

## Damage types and elements `e` is weak to: ["Blunt", "Fire"].
static func weaknesses(e: CharacterData) -> Array:
	var out: Array = []
	for t in DamageTypes.Type.values():
		if DamageTypes.multiplier(e, t) > 1.05:
			out.append(DamageTypes.Type.keys()[t].capitalize())
	if e.elemental_resistances:
		for n in ElementalDamage.Element.keys():
			if n in ["NONE", "PHYSICAL"]:
				continue
			if e.elemental_resistances.get_total_weakness(ElementalDamage.Element[n]) > 0.0:
				out.append(n.capitalize())
	return out

# ------------------------------------------------------------------ descriptions

## "Fireball → Mira", "⚠ CHARGING Avalanche Slam (everyone)", "" when unknown.
static func describe_intent(e: CharacterData, intents: Dictionary = {}) -> String:
	if not e.is_alive():
		return ""
	if e.get_meta("broken", false):
		return "[color=#ffd166]BROKEN - loses its turn[/color]"
	if e.has_meta("charging"):
		return "[color=#ff6b6b]⚠ CHARGING %s[/color]" % e.get_meta("charging")
	var a = intents.get(e, null)
	if not (a is BattleAction):
		return ""
	var who = ""
	if not a.targets.is_empty() and a.targets[0] != null:
		who = a.targets[0].name.get_slice(" ", 0)
	match a.type:
		BattleAction.ActionType.ATTACK:
			return "Attack → %s" % who
		BattleAction.ActionType.DEFEND:
			return "Defend"
		BattleAction.ActionType.CHARGE:
			return "[color=#ff6b6b]⚠ Gathering power[/color]"
		BattleAction.ActionType.ITEM:
			return "Item: %s" % a.item_data.display_name
		BattleAction.ActionType.SKILL:
			var s: Skill = a.skill_data
			var tgt = who
			if s.target == Skill.TargetType.ALL_ENEMIES:
				tgt = "everyone"
			elif s.target in [Skill.TargetType.SELF, Skill.TargetType.ALL_ALLIES, Skill.TargetType.ALLY]:
				tgt = "allies" if s.target == Skill.TargetType.ALL_ALLIES else (who if who != "" else "self")
			var col = "#ff9f6b" if s.type in [Skill.SkillType.DAMAGE, Skill.SkillType.DRAIN] else "#b8c0ff"
			return "[color=%s]%s → %s[/color]" % [col, s.name, tgt]
	return ""
